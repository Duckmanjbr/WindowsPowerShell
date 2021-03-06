function Get-ProcessModules {
<#
.SYNOPSIS
Retrieves information about currently loaded modules in process(es).

.DESCRIPTION
This commandlet uses Windows Remote Management to retrieve information about currently loaded modules of specified process(es).

.PARAMETER TargetList 
Specify host(s) to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections.

.PARAMETER Name 
Specify name of process who's modules should be enumerated.

.PARAMETER Id 
Specify process Id of process who's modules should be enumerated.

.PARAMETER WhiteList 
Specify path to Whitelist file to compare retrieved data against.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example gets a list of computers from the pipeline and writes output to the console.

PS C:\> $Targs = New-TargetList -Cidr 10.10.20.0/24
PS C:\> Get-ProcessModules -TargetList $Targs -Name svchost

.EXAMPLE
The following example specifies a list of computers and sends output to a csv file.

PS C:\> $Targs = New-TargetList -Cidr 10.10.20.0/24
PS C:\> Get-ProcessModules -TargetList $Targs -Name svchost -CSV C:\pathto\output.csv

.NOTES
Version: 0.1
Author : RBOT

.INPUTS

.OUTPUTS

.LINK
#>
[CmdLetBinding(SupportsShouldProcess = $false)]
    Param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$TargetList,

        [Parameter()]
        [Switch]$ConfirmTargets,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int]$ThrottleLimit = 10,

        [Parameter(ParameterSetName = "Name")]
        [ValidateNotNullOrEmpty()]
        [String]$Name = "",

        [Parameter(ParameterSetName = "Id")]
        [ValidateNotNullOrEmpty()]
        [Int]$Id = -1,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$WhiteList,

        [Parameter()]
        [ValidateSet('MD5','SHA1','SHA256','SHA384','SHA512')]
        [String]$Hash = "",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$CSV,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TXT
    ) #End Param
    
    if($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Get-ProcessModules
        
    $Global:Error.Clear()
    $RemoteScriptBlock = {
        Param([String]$ProcessName, [Int]$ProcessId, [String]$Hash)
            
            #region WinAPI
            function local:func {
            # A helper function used to reduce typing while defining function prototypes for Add-Win32Type.
                Param
                (
                    [Parameter(Position = 0, Mandatory = $true)]
                    [String]
                    $DllName,

                    [Parameter(Position = 1, Mandatory = $true)]
                    [string]
                    $FunctionName,

                    [Parameter(Position = 2, Mandatory = $true)]
                    [Type]
                    $ReturnType,

                    [Parameter(Position = 3)]
                    [Type[]]
                    $ParameterTypes,

                    [Parameter(Position = 4)]
                    [Runtime.InteropServices.CallingConvention]
                    $NativeCallingConvention,

                    [Parameter(Position = 5)]
                    [Runtime.InteropServices.CharSet]
                    $Charset,

                    [Switch]
                    $SetLastError
                )
                $Properties = @{
                    DllName = $DllName
                    FunctionName = $FunctionName
                    ReturnType = $ReturnType
                }
                if ($ParameterTypes) { $Properties['ParameterTypes'] = $ParameterTypes }
                if ($NativeCallingConvention) { $Properties['NativeCallingConvention'] = $NativeCallingConvention }
                if ($Charset) { $Properties['Charset'] = $Charset }
                if ($SetLastError) { $Properties['SetLastError'] = $SetLastError }
                New-Object PSObject -Property $Properties
            }
            function local:Add-Win32Type {
                [OutputType([Hashtable])]
                Param(
                    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
                    [String]
                    $DllName,

                    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
                    [String]
                    $FunctionName,

                    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
                    [Type]
                    $ReturnType,

                    [Parameter(ValueFromPipelineByPropertyName = $true)]
                    [Type[]]
                    $ParameterTypes,

                    [Parameter(ValueFromPipelineByPropertyName = $true)]
                    [Runtime.InteropServices.CallingConvention]
                    $NativeCallingConvention = [Runtime.InteropServices.CallingConvention]::StdCall,

                    [Parameter(ValueFromPipelineByPropertyName = $true)]
                    [Runtime.InteropServices.CharSet]
                    $Charset = [Runtime.InteropServices.CharSet]::Auto,

                    [Parameter(ValueFromPipelineByPropertyName = $true)]
                    [Switch]
                    $SetLastError,

                    [Parameter(Mandatory = $true)]
                    [ValidateScript({($_ -is [Reflection.Emit.ModuleBuilder]) -or ($_ -is [Reflection.Assembly])})]
                    $Module,

                    [ValidateNotNull()]
                    [String]
                    $Namespace = ''
                )
                BEGIN { $TypeHash = @{} }
                PROCESS {
                    if ($Module -is [Reflection.Assembly]) {
                        if ($Namespace) { $TypeHash[$DllName] = $Module.GetType("$Namespace.$DllName") }
                        else { $TypeHash[$DllName] = $Module.GetType($DllName) }
                    }
                    else # Define one type for each DLL
                    {
                        if (!$TypeHash.ContainsKey($DllName)) {
                            if ($Namespace) { $TypeHash[$DllName] = $Module.DefineType("$Namespace.$DllName", 'Public,BeforeFieldInit') }
                            else { $TypeHash[$DllName] = $Module.DefineType($DllName, 'Public,BeforeFieldInit') }
                        }

                        $Method = $TypeHash[$DllName].DefineMethod($FunctionName, 'Public,Static,PinvokeImpl', $ReturnType, $ParameterTypes)

                        # Make each ByRef parameter an Out parameter
                        $i = 1
                        foreach($Parameter in $ParameterTypes) { if ($Parameter.IsByRef) { [void]$Method.DefineParameter($i, 'Out', $null) } $i++ }

                        $DllImport = [Runtime.InteropServices.DllImportAttribute]
                        $SetLastErrorField = $DllImport.GetField('SetLastError')
                        $CallingConventionField = $DllImport.GetField('CallingConvention')
                        $CharsetField = $DllImport.GetField('CharSet')
                        if ($SetLastError) { $SLEValue = $true } else { $SLEValue = $false }

                        # Equivalent to C# version of [DllImport(DllName)]
                        $Constructor = [Runtime.InteropServices.DllImportAttribute].GetConstructor([String])
                        $DllImportAttribute = New-Object Reflection.Emit.CustomAttributeBuilder($Constructor, $DllName, [Reflection.PropertyInfo[]] @(), [Object[]] @(), [Reflection.FieldInfo[]] @($SetLastErrorField, $CallingConventionField, $CharsetField), [Object[]] @($SLEValue, ([Runtime.InteropServices.CallingConvention] $NativeCallingConvention), ([Runtime.InteropServices.CharSet] $Charset)))
                        $Method.SetCustomAttribute($DllImportAttribute)
                    }
                }
                END {
                    if ($Module -is [Reflection.Assembly]) { return $TypeHash }
                    $ReturnTypes = @{}
                    foreach ($Key in $TypeHash.Keys) {
                        $Type = $TypeHash[$Key].CreateType()
                        $ReturnTypes[$Key] = $Type
                    }
                return $ReturnTypes
                }
            }

            $Domain = [AppDomain]::CurrentDomain
            $DynAssembly = New-Object System.Reflection.AssemblyName('Modules')
            $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
            $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
            $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]

            #region MODULE_INFO
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('MODULE_INFO', $Attributes, [ValueType], 12)
            [void]$TypeBuilder.DefineField('lpBaseOfDll', [IntPtr], 'Public')
            [void]$TypeBuilder.DefineField('SizeOfImage', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('EntryPoint', [IntPtr], 'Public')
            $MODULE_INFO = $TypeBuilder.CreateType()
            #endregion MODULE_INFO

            $FunctionDefinitions = @(
                #Kernel32
                (func kernel32 OpenProcess ([IntPtr]) @([Int32], [Bool], [Int32]) -SetLastError),
                (func kernel32 CloseHandle ([Bool]) @([IntPtr]) -SetLastError),

                #Psapi
                (func psapi EnumProcessModulesEx ([Bool]) @([IntPtr], [IntPtr].MakeArrayType(), [UInt32], [UInt32].MakeByRefType(), [Int32]) -SetLastError),
                (func psapi GetModuleInformation ([Bool]) @([IntPtr], [IntPtr], $MODULE_INFO.MakeByRefType(), [UInt32]) -SetLastError), 
                (func psapi GetModuleBaseNameW ([UInt32]) @([IntPtr], [IntPtr], [Text.StringBuilder], [Int32]) -Charset Unicode -SetLastError),
                (func psapi GetModuleFileNameExW ([UInt32]) @([IntPtr], [IntPtr], [Text.StringBuilder], [Int32]) -Charset Unicode -SetLastError)
            )
            $Types = $FunctionDefinitions | Add-Win32Type -Module $ModuleBuilder -Namespace 'Win32'
            $Kernel32 = $Types['kernel32']
            $Psapi = $Types['psapi']
            #endregion WinAPI

            if ($ProcessName -ne "") { $Processes = Get-Process -Name $ProcessName }
            elseif ($ProcessId -ne -1) { $Processes = Get-Process -Id $ProcessId }
            if ($Hash -ne "") {
                switch ($Hash) {
                       'MD5' { $CryptoProvider = New-Object System.Security.Cryptography.MD5CryptoServiceProvider }
                      'SHA1' { $CryptoProvider = New-Object System.Security.Cryptography.SHA1CryptoServiceProvider }
                    'SHA256' { $CryptoProvider = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider }
                    'SHA384' { $CryptoProvider = New-Object System.Security.Cryptography.SHA384CryptoServiceProvider }
                    'SHA512' { $CryptoProvider = New-Object System.Security.Cryptography.SHA512CryptoServiceProvider }
                }
            }

            foreach ($Process in $Processes) {
                if (($hProcess = $Kernel32::OpenProcess(0x1F0FFF, $false, $Process.Id)) -eq 0) {
                    Write-Error "Unable to open a handle for process $($Process.Id)!"
                    continue
                }

                #Initialize parameters for EPM
                $cbNeeded = 0
                if (!$Psapi::EnumProcessModulesEx($hProcess, $null, 0, [ref]$cbNeeded, 3)) {
                    Write-Error "Failed to get module-buffer size for process $($Process.Id)!"
                    continue
                }
                $ArraySize = $cbNeeded / [IntPtr]::Size

                $hModules = New-Object IntPtr[] $ArraySize

                $cb = $cbNeeded;
                if (!$Psapi::EnumProcessModulesEx($hProcess, $hModules, $cb, [ref]$cbNeeded, 3)) {
                    Write-Error "Failed to get module handles for process $($Process.Id)!"
                    continue
                }
                for ($i = 0; $i -lt $ArraySize; $i++)
                {
                    $ModInfo = [Activator]::CreateInstance($MODULE_INFO)
                    $lpFileName = [Activator]::CreateInstance([System.Text.StringBuilder], 256)
                    $lpModuleBaseName = [Activator]::CreateInstance([System.Text.StringBuilder], 32)

                    if ($Psapi::GetModuleFileNameExW($hProcess, $hModules[$i], $lpFileName, $lpFileName.Capacity) -eq 0) {
                        $lpFileName = "Failed to get module path!"
                    }
                    if ($Psapi::GetModuleBaseNameW($hProcess, $hModules[$i], $lpModuleBaseName, $lpModuleBaseName.Capacity) -eq 0) {
                        $lpModuleBaseName = "Failed to get module base name!"
                    }
                    if (!$Psapi::GetModuleInformation($hProcess, $hModules[$i], [ref]$ModInfo,  [Runtime.InteropServices.Marshal]::SizeOf($ModInfo))) {
                        Write-Error "Failed to get module information!"
                    }

                    $Path = $lpFileName.ToString()

                    if (([IO.File]::Exists($Path)) -and ($CryptoProvider -ne $null)) {
                        $Data = [IO.File]::ReadAllBytes($Path)
                        $ModuleHash = [BitConverter]::ToString($CryptoProvider.ComputeHash($Data)).Replace('-', '')
                    }
                    else { $ModuleHash = $null }

                    if ($Hash -ne "") {
                        $Properties = @{
                            Path = $Path
                            Name = $lpModuleBaseName.ToString()
                            BaseAddress = $ModInfo.lpBaseOfDll
                            Size = $ModInfo.SizeOfImage
                            EntryPoint = $ModInfo.EntryPoint
                            $Hash = $ModuleHash
                        }
                        New-Object -TypeName PSObject -Property $Properties
                    }
                    else {
                        $Properties = @{
                            Path = $Path
                            Name = $lpModuleBaseName.ToString()
                            BaseAddress = $ModInfo.lpBaseOfDll
                            Size = $ModInfo.SizeOfImage
                            EntryPoint = $ModInfo.EntryPoint
                        }
                        New-Object -TypeName PSObject -Property $Properties
                    }

                    $ModInfo = $null
                    $lpFileName = $null
                    $lpModuleBaseName = $null
                }
                if (!$Kernel32::CloseHandle($hProcess)) { Write-Error "Failed to close handle for process $($Process.Id)" }
            }
    }# End RemoteScriptblock
        
    if ($PSBoundParameters['TargetList']) {
        if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }        
        
        $ReturnedObjects = New-Object Collections.ArrayList
        $HostsRemaining = [Collections.ArrayList]$TargetList
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)

        Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -ArgumentList @($Name, $Id, $Hash) -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit |
        ForEach-Object { 
            if ($HostsRemaining -contains $_.PSComputerName) { $HostsRemaining.Remove($_.PSComputerName) }
            [void]$ReturnedObjects.Add($_)
            Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)
        }
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Completed" -Completed
    }
    else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($Name, $Id, $Hash) }

    Get-ErrorHost -ErrorFileVerbose $ErrorFileVerbose -ErrorFileHosts $ErrorFileHosts

    #Check to see if Whitelist Hashtable exists before performing lookups
    if ($PSBoundParameters['WhiteList']) {
        New-WhiteList -CsvFile $WhiteList -VariableName "ModuleWhiteList"
    }
    if ($ModuleWhiteList -and $ReturnedObjects) {
        foreach ($Module in $ReturnedObjects) {
            
            #Check the hash table for the hash of the file
            if ($Module.Hash -ne $null) { $wl = $ModuleWhiteList.ContainsKey($Module.Hash) }
            else { $wl = $false }

            #Check to see if $wl has a value in it,If wl as a value then the SHA1 is in the whitelist 
            if ($wl) { Add-Member -InputObject $Module -MemberType NoteProperty -Name WhiteListed -Value "Yes" -Force }
            else { Add-Member -InputObject $Module -MemberType NoteProperty -Name WhiteListed -Value "No" -Force }
        }
    }
    else { Write-Verbose "Whitelist Hashtable not created - Comparison not done" }
    
    if ($ReturnedObjects -ne $null) {
        if ($PSBoundParameters['CSV']) { $ReturnedObjects | Export-Csv -Path $OutputFilePath -Append -NoTypeInformation -ErrorAction SilentlyContinue }
        elseif ($PSBoundParameters['TXT']) { $ReturnedObjects | Out-File -FilePath $OutputFilePath -Append -ErrorAction SilentlyContinue }
        else { Write-Output $ReturnedObjects }
    }

    [GC]::Collect()
    $ScriptTime.Stop()
    Write-Verbose "Done, execution time: $($ScriptTime.Elapsed)"
}