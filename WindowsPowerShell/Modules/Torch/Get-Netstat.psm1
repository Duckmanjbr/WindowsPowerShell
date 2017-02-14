function Get-Netstat {
<#
.SYNOPSIS
Gathers network connection information from remote systems.

.DESCRIPTION
This commandlet uses Windows Remote Management to collect network connection information from remote systems.

.PARAMETER TargetList 
Specify host(s) to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example gets a list of computers from the pipeline and sends output to a csv file.

PS C:\> New-TargetList -Cidr 10.10.20.0/24 | Get-Netstat -CSV C:\pathto\output.csv

.EXAMPLE
The following example specifies a computer and sends output to a csv file.

PS C:\> Get-Netstat -TargetList Server01 -CSV C:\pathto\output.csv

.NOTES
Version: 0.1
Author : Jesse "RBOT" Davis

.INPUTS

.OUTPUTS

.LINK
#>
[CmdLetBinding(SupportsShouldProcess = $false)]
    Param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]$TargetList,

        [Parameter()]
        [Switch]$ConfirmTargets,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int]$ThrottleLimit = 10,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$CSV,
	
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TXT
    )
    if($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Get-Netstat
        
    $Global:Error.Clear()
    $RemoteScriptBlock = {
        #region WinAPI

        function local:Get-DelegateType {
            Param
            (
                [OutputType([Type])]
            
                [Parameter( Position = 0)]
                [Type[]]
                $Parameters = (New-Object Type[](0)),
            
                [Parameter( Position = 1 )]
                [Type]
                $ReturnType = [Void]
            )

            $Domain = [AppDomain]::CurrentDomain
            $DynAssembly = New-Object System.Reflection.AssemblyName('ReflectedDelegate')
            $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
            $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
            $TypeBuilder = $ModuleBuilder.DefineType('MyDelegateType', 'Class, Public, Sealed, AnsiClass, AutoClass', [MulticastDelegate])
            $ConstructorBuilder = $TypeBuilder.DefineConstructor('RTSpecialName, HideBySig, Public', [Reflection.CallingConventions]::Standard, $Parameters)
            $ConstructorBuilder.SetImplementationFlags('Runtime, Managed')
            $MethodBuilder = $TypeBuilder.DefineMethod('Invoke', 'Public, HideBySig, NewSlot, Virtual', $ReturnType, $Parameters)
            $MethodBuilder.SetImplementationFlags('Runtime, Managed')
        
            Write-Output $TypeBuilder.CreateType()
        }
        function local:Get-ProcAddress {
            Param(
                [OutputType([IntPtr])]
        
                [Parameter( Position = 0, Mandatory = $True )]
                [String]
                $Module,
            
                [Parameter( Position = 1, Mandatory = $True )]
                [String]
                $Procedure
            )

            # Get a reference to System.dll in the GAC
            $SystemAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { $_.GlobalAssemblyCache -And $_.Location.Split('\\')[-1].Equals('System.dll') }
            $UnsafeNativeMethods = $SystemAssembly.GetType('Microsoft.Win32.UnsafeNativeMethods')
            # Get a reference to the GetModuleHandle and GetProcAddress methods
            $GetModuleHandle = $UnsafeNativeMethods.GetMethod('GetModuleHandle')
            $GetProcAddress = $UnsafeNativeMethods.GetMethod('GetProcAddress')
            # Get a handle to the module specified
            $Kern32Handle = $GetModuleHandle.Invoke($null, @($Module))
            $tmpPtr = New-Object IntPtr
            $HandleRef = New-Object System.Runtime.InteropServices.HandleRef($tmpPtr, $Kern32Handle)
        
            # Return the address of the function
            Write-Output $GetProcAddress.Invoke($null, @([Runtime.InteropServices.HandleRef]$HandleRef, $Procedure))
        }

        $Domain = [AppDomain]::CurrentDomain
        $DynAssembly = New-Object System.Reflection.AssemblyName('Netstat')
        $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
        $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
        $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]

        #region ENUM MIB_TCP_STATE
        $TypeBuilder = $ModuleBuilder.DefineEnum('MIB_TCP_STATE', 'Public', [UInt32])
        [void]$TypeBuilder.DefineLiteral('NONE', [UInt32] 0)
        [void]$TypeBuilder.DefineLiteral('CLOSED', [UInt32] 0x01)
        [void]$TypeBuilder.DefineLiteral('LISTENING', [UInt32] 0x02)
        [void]$TypeBuilder.DefineLiteral('SYN_SENT', [UInt32] 0x03)
        [void]$TypeBuilder.DefineLiteral('SYN_RCVD', [UInt32] 0x04)
        [void]$TypeBuilder.DefineLiteral('ESTABLISHED', [UInt32] 0x05)
        [void]$TypeBuilder.DefineLiteral('FIN_WAIT1', [UInt32] 0x06)
        [void]$TypeBuilder.DefineLiteral('FIN_WAIT2', [UInt32] 0x07)
        [void]$TypeBuilder.DefineLiteral('CLOSE_WAIT', [UInt32] 0x08)
        [void]$TypeBuilder.DefineLiteral('CLOSING', [UInt32] 0x09)
        [void]$TypeBuilder.DefineLiteral('LAST_ACK', [UInt32] 0x0A)
        [void]$TypeBuilder.DefineLiteral('TIME_WAIT', [UInt32] 0x0B)
        [void]$TypeBuilder.DefineLiteral('DELETE_TCB', [UInt32] 0x0C)
        $MIB_TCP_STATE = $TypeBuilder.CreateType()
        #endregion ENUM MIB_TCP_STATE

        #region MIB_TCPROW_OWNER_PID
        $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
        $TypeBuilder = $ModuleBuilder.DefineType('MIB_TCPROW_OWNER_PID', $Attributes, [ValueType], 24)
        [void]$TypeBuilder.DefineField('dwState', $MIB_TCP_STATE, 'Public')
        [void]$TypeBuilder.DefineField('dwLocalAddr', [UInt32], 'Public')
        $LocalPortField = $TypeBuilder.DefineField('dwLocalPort', [byte[]], 'Public')
        $FieldArray = @([Runtime.InteropServices.MarshalAsAttribute].GetField('SizeConst'))
        $ConstructorValue = [Runtime.InteropServices.UnmanagedType]::ByValArray
        $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 4))
        [void]$LocalPortField.SetCustomAttribute($AttribBuilder)
        [void]$TypeBuilder.DefineField('dwRemoteAddr', [UInt32], 'Public')
        $RemotePortField = $TypeBuilder.DefineField('dwRemotePort', [byte[]], 'Public')
        $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 4))
        [void]$RemotePortField.SetCustomAttribute($AttribBuilder)
        [void]$TypeBuilder.DefineField('dwOwningPid', [UInt32], 'Public')
        $MIB_TCPROW_OWNER_PID = $TypeBuilder.CreateType()
        #endregion MIB_TCPROW_OWNER_PID

        #region MIB_TCP6ROW_OWNER_PID
        $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
        $TypeBuilder = $ModuleBuilder.DefineType('MIB_TCP6ROW_OWNER_PID', $Attributes, [ValueType], 56)
        $LocalAddrField = $TypeBuilder.DefineField('ucLocalAddr', [byte[]], 'Public, HasFieldMarshal')    
        $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 16))
        [void]$LocalAddrField.SetCustomAttribute($AttribBuilder)
        [void]$TypeBuilder.DefineField('dwLocalScopeId', [UInt32], 'Public')
        $LocalPortField = $TypeBuilder.DefineField('dwLocalPort', [byte[]], 'Public')
        $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 4))
        [void]$LocalPortField.SetCustomAttribute($AttribBuilder)
        $RemoteAddrField = $TypeBuilder.DefineField('ucRemoteAddr', [byte[]], 'Public, HasFieldMarshal')
        $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 16))
        [void]$RemoteAddrField.SetCustomAttribute($AttribBuilder)
        [void]$TypeBuilder.DefineField('dwRemoteScopeId', [UInt32], 'Public')
        $RemotePortField = $TypeBuilder.DefineField('dwRemotePort', [byte[]], 'Public')
        $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 4))
        [void]$RemotePortField.SetCustomAttribute($AttribBuilder)
        [void]$TypeBuilder.DefineField('dwState', $MIB_TCP_STATE, 'Public')
        [void]$TypeBuilder.DefineField('dwOwningPid', [UInt32], 'Public')
        $MIB_TCP6ROW_OWNER_PID = $TypeBuilder.CreateType()
        #endregion MIB_TCP6ROW_OWNER_PID
        
        #region MIB_UDPROW_OWNER_PID
        $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
        $TypeBuilder = $ModuleBuilder.DefineType('MIB_UDPROW_OWNER_PID', $Attributes, [ValueType], 12)
        [void]$TypeBuilder.DefineField('dwLocalAddr', [UInt32], 'Public')
        $LocalPortField = $TypeBuilder.DefineField('dwLocalPort', [byte[]], 'Public')
        $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 4))
        [void]$LocalPortField.SetCustomAttribute($AttribBuilder)
        [void]$TypeBuilder.DefineField('dwOwningPid', [UInt32], 'Public')
        $MIB_UDPROW_OWNER_PID = $TypeBuilder.CreateType()
        #endregion MIB_UDPROW_OWNER_PID

        #region MIB_UDP6ROW_OWNER_PID
        $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
        $TypeBuilder = $ModuleBuilder.DefineType('MIB_UDP6ROW_OWNER_PID', $Attributes, [ValueType], 28)
        $LocalAddrField = $TypeBuilder.DefineField('ucLocalAddr', [byte[]], 'Public, HasFieldMarshal')
        $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 16))
        [void]$LocalAddrField.SetCustomAttribute($AttribBuilder)
        [void]$TypeBuilder.DefineField('dwLocalScopeId', [UInt32], 'Public')
        $LocalPortField = $TypeBuilder.DefineField('dwLocalPort', [byte[]], 'Public')
        $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 4))
        [void]$LocalPortField.SetCustomAttribute($AttribBuilder)
        [void]$TypeBuilder.DefineField('dwOwningPid', [UInt32], 'Public')
        $MIB_UDP6ROW_OWNER_PID = $TypeBuilder.CreateType()
        #endregion MIB_UDP6ROW_OWNER_PID

        #Function LoadLibraryA
        $LoadLibraryAAddr = Get-ProcAddress kernel32.dll LoadLibraryA
        $LoadLibraryADelegate = Get-DelegateType @([String]) ([IntPtr])
        $LoadLibraryA = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($LoadLibraryAAddr, $LoadLibraryADelegate)

        #Load the IP Help API
        [void]$LoadLibraryA.Invoke("iphlpapi.dll")

        #Function GetExtendedTcpTable
        if(($GetExtendedTcpTableAddr = Get-ProcAddress iphlpapi.dll GetExtendedTcpTable) -eq 0) 
        {
            Write-Error "GetExtendedTcpTable is not supported on this version of Windows, only Vista+"
            break
        }
        $GetExtendedTcpTableDelegate = Get-DelegateType @([IntPtr], [UInt32].MakeByRefType(), [bool], [UInt32], [UInt32], [UInt32]) ([UInt32])
        $GetExtendedTcpTable = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetExtendedTcpTableAddr, $GetExtendedTcpTableDelegate)

        #Function GetExtendedUdpTable
        if(($GetExtendedUdpTableAddr = Get-ProcAddress iphlpapi.dll GetExtendedUdpTable) -eq 0) 
        {
            Write-Error "GetExtendedUdpTable is not supported on this version of Windows, only Vista+"
            break
        }
        $GetExtendedUdpTableDelegate = Get-DelegateType @([IntPtr], [UInt32].MakeByRefType(), [bool], [UInt32], [UInt32], [UInt32]) ([UInt32])
        $GetExtendedUdpTable = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetExtendedUdpTableAddr, $GetExtendedUdpTableDelegate)

        #endregion WinAPI 

        $CommandLine = New-Object hashtable
        Get-WmiObject Win32_process | ForEach-Object { $CommandLine.Add($_.ProcessId, $_.CommandLine) }

        #region TCP4 
    
        [UInt32]$BufferSize = 0
        [UInt32]$AF_INET = 2      #IPv4

        #Get necessary buffersize
        [void]$GetExtendedTcpTable.Invoke([IntPtr]::Zero, [ref]$BufferSize, $True, $AF_INET, 5, 0)

        #Allocate buffer
        [IntPtr]$Tcp4TableBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($BufferSize)

        if(($Return = $GetExtendedTcpTable.Invoke($Tcp4TableBuffer, [ref]$BufferSize, $True, $AF_INET, 5, 0)) -ne 0)
        {
            Write-Error "Call to GetExtendedTcpTable failed, returned $Return."
            exit
        }
        else
        {
            $dwNumEntries = [Runtime.InteropServices.Marshal]::ReadInt32($Tcp4TableBuffer)  #first Int32 of TcpTable struct is the number of rows
            $Tcp4RowPtr = [IntPtr]($Tcp4TableBuffer.ToInt64() + 4)                          #first row is after dwNumEntries, Int32 is size 4

            for ($i = 0; $i -lt $dwNumEntries; $i++)
            {
                $Tcp4Row = [Runtime.InteropServices.Marshal]::PtrToStructure($Tcp4RowPtr, [Type]$MIB_TCPROW_OWNER_PID)
                $Properties = @{
                    'LocalAddress'  = ([Net.IPAddress]$Tcp4Row.dwLocalAddr).IPAddressToString
                    'LocalPort'     = [BitConverter]::ToUInt16([byte[]]@($Tcp4Row.dwLocalPort[1], $Tcp4Row.dwLocalPort[0]),0)
                    'RemoteAddress' = ([Net.IPAddress]$Tcp4Row.dwRemoteAddr).IPAddressToString
                    'RemotePort'    = [BitConverter]::ToUInt16([byte[]]@($Tcp4Row.dwRemotePort[1], $Tcp4Row.dwRemotePort[0]),0)
                    'State'         = $Tcp4Row.dwState
                    'PID'           = $Tcp4Row.dwOwningPid
                    'Commandline'   = $CommandLine[$Tcp4Row.dwOwningPid]
                    'Proto'         = "TCP4"
                    }
                $obj = New-Object -TypeName PSObject -Property $Properties
                $obj.PSObject.TypeNames.Insert(0,'Tcp4Entry')
                Write-Output $obj

                #Set pointer to next row
                $Tcp4RowPtr = [IntPtr]($Tcp4RowPtr.ToInt64() + [Runtime.InteropServices.Marshal]::SizeOf([Type]$MIB_TCPROW_OWNER_PID))
            }
            #Free the memory allocated earlier
            [Runtime.InteropServices.Marshal]::FreeHGlobal($Tcp4TableBuffer)
        }
        #endregion TCP4
    
        #region TCP6

        $BufferSize = 0
        $AF_INET = 23      #IPv6

        #Get necessary buffersize
        [void]$GetExtendedTcpTable.Invoke([IntPtr]::Zero, [ref]$BufferSize, $True, $AF_INET, 5, 0)

        #Allocate buffer
        [IntPtr]$Tcp6TableBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($BufferSize)

        if(($Return = $GetExtendedTcpTable.Invoke($Tcp6TableBuffer, [ref]$BufferSize, $True, $AF_INET, 5, 0)) -ne 0)
        {
            Write-Error "Call to GetExtendedTcpTable failed, returned $Return."
            exit
        }
        else
        {
            $dwNumEntries = [Runtime.InteropServices.Marshal]::ReadInt32($Tcp6TableBuffer)  #first Int32 of TcpTable struct is the number of rows
            $Tcp6RowPtr = [IntPtr]($Tcp6TableBuffer.ToInt64() + 4)                                 #first row is after dwNumEntries, Int32 is size 4

            for ($i = 0; $i -lt $dwNumEntries; $i++)
            {
                $Tcp6Row = [Runtime.InteropServices.Marshal]::PtrToStructure($Tcp6RowPtr, [Type]$MIB_TCP6ROW_OWNER_PID)
                $Properties = @{
                    'LocalAddress'  = ([Net.IPAddress]$Tcp6Row.ucLocalAddr).IPAddressToString
                    'LocalPort'     = [BitConverter]::ToUInt16([byte[]]@($Tcp6Row.dwLocalPort[1], $Tcp6Row.dwLocalPort[0]),0)
                    'RemoteAddress' = ([Net.IPAddress]$Tcp6Row.ucRemoteAddr).IPAddressToString
                    'RemotePort'    = [BitConverter]::ToUInt16([byte[]]@($Tcp6Row.dwRemotePort[1], $Tcp6Row.dwRemotePort[0]),0)
                    'State'         = $Tcp6Row.dwState
                    'PID'           = $Tcp6Row.dwOwningPid
                    'Commandline'   = $CommandLine[$Tcp6Row.dwOwningPid]
                    'Proto'         = "TCP6"
                    }
                $obj = New-Object -TypeName PSObject -Property $Properties
                $obj.PSObject.TypeNames.Insert(0,'Tcp6Entry')
                Write-Output $obj

                #Set pointer to next row
                $Tcp6RowPtr = [IntPtr]($Tcp6RowPtr.ToInt64() + [Runtime.InteropServices.Marshal]::SizeOf([Type]$MIB_TCP6ROW_OWNER_PID))
            }
            #Free the memory allocated earlier
            [Runtime.InteropServices.Marshal]::FreeHGlobal($Tcp6TableBuffer)
        }
        #endregion TCP6

        #region UDP4
    
        [UInt32]$BufferSize = 0
        [UInt32]$AF_INET = 2      #IPv4

        #Get necessary buffersize
        [void]$GetExtendedUdpTable.Invoke([IntPtr]::Zero, [ref]$BufferSize, $True, $AF_INET, 2, 0)

        #Allocate buffer
        [IntPtr]$Udp4TableBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($BufferSize)

        if(($Return = $GetExtendedUdpTable.Invoke($Udp4TableBuffer, [ref]$BufferSize, $True, $AF_INET, 2, 0)) -ne 0)
        {
            Write-Error "Call to GetExtendedUdpTable failed, returned $Return."
            exit
        }
        else
        {
            $dwNumEntries = [Runtime.InteropServices.Marshal]::ReadInt32($Udp4TableBuffer)  #first Int32 of UdpTable struct is the number of rows
            $Udp4RowPtr = [IntPtr]($Udp4TableBuffer.ToInt64() + 8)                                 #first row is after dwNumEntries, Int32 is size 4 + 4 bytes of padding

            for ($i = 0; $i -lt $dwNumEntries; $i++)
            {
                $Udp4Row = [Runtime.InteropServices.Marshal]::PtrToStructure($Udp4RowPtr, [Type]$MIB_UDPROW_OWNER_PID)
                $Properties = @{
                    'LocalAddress'  = ([Net.IPAddress]$Udp4Row.dwLocalAddr).IPAddressToString
                    'LocalPort'     = [BitConverter]::ToUInt16([byte[]]@($Udp4Row.dwLocalPort[1], $Udp4Row.dwLocalPort[0]),0)
                    'PID'           = $Udp4Row.dwOwningPid
                    'Commandline'   = $CommandLine[$Udp4Row.dwOwningPid]
                    'Proto'         = "UDP4"
                    }
                $obj = New-Object -TypeName PSObject -Property $Properties
                $obj.PSObject.TypeNames.Insert(0,'Udp4Entry')
                Write-Output $obj

                #Set pointer to next row
                $Udp4RowPtr = [IntPtr]($Udp4RowPtr.ToInt64() + [Runtime.InteropServices.Marshal]::SizeOf([Type]$MIB_UDPROW_OWNER_PID) + 148) #148 bytes of padding...?
            }
            #Free the memory allocated earlier
            [Runtime.InteropServices.Marshal]::FreeHGlobal($Udp4TableBuffer)
        }
        #endregion UDP4

        #region UDP6
    
        [UInt32]$BufferSize = 0
        [UInt32]$AF_INET = 23      #IPv6

        #Get necessary buffersize
        [void]$GetExtendedUdpTable.Invoke([IntPtr]::Zero, [ref]$BufferSize, $True, $AF_INET, 2, 0)

        #Allocate buffer
        [IntPtr]$Udp6TableBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($BufferSize)

        if(($Return = $GetExtendedUdpTable.Invoke($Udp6TableBuffer, [ref]$BufferSize, $True, $AF_INET, 2, 0)) -ne 0)
        {
            Write-Error "Call to GetExtendedUdpTable failed, returned $Return."
            exit
        }
        else
        {
            $dwNumEntries = [Runtime.InteropServices.Marshal]::ReadInt32($Udp6TableBuffer)  #first Int32 of UdpTable struct is the number of rows
            $Udp6RowPtr = [IntPtr]($Udp6TableBuffer.ToInt64() + 8)                                 #first row is after dwNumEntries, Int32 is size 4 + 4 bytes of padding

            for ($i = 0; $i -lt $dwNumEntries; $i++)
            {
                $Udp6Row = [Runtime.InteropServices.Marshal]::PtrToStructure($Udp6RowPtr, [Type]$MIB_UDP6ROW_OWNER_PID)
                $Properties = @{
                    'LocalAddress'  = ([Net.IPAddress]$Udp6Row.ucLocalAddr).IPAddressToString
                    'LocalPort'     = [BitConverter]::ToUInt16([byte[]]@($Udp6Row.dwLocalPort[1], $Udp6Row.dwLocalPort[0]),0)
                    'PID'           = $Udp6Row.dwOwningPid
                    'Commandline'   = $CommandLine[$Udp6Row.dwOwningPid]
                    'Proto'         = "UDP6"
                    }
                $obj = New-Object -TypeName PSObject -Property $Properties
                $obj.PSObject.TypeNames.Insert(0,'Udp4Entry')
                Write-Output $obj

                #Set pointer to next row
                $Udp6RowPtr = [IntPtr]($Udp6RowPtr.ToInt64() + [Runtime.InteropServices.Marshal]::SizeOf([Type]$MIB_UDPROW_OWNER_PID) + 164) #164 bytes of padding...?
            }
            #Free the memory allocated earlier
            [Runtime.InteropServices.Marshal]::FreeHGlobal($Udp6TableBuffer)
        }
        #endregion UDP6
    }#End RemoteScriptBlock

    if ($PSBoundParameters['TargetList']) {
        if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }        
        
        $ReturnedObjects = New-Object Collections.ArrayList
        $HostsRemaining = [Collections.ArrayList]$TargetList
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)

        Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit |
        ForEach-Object { 
            if ($HostsRemaining -contains $_.PSComputerName) { $HostsRemaining.Remove($_.PSComputerName) }
            [void]$ReturnedObjects.Add($_)
            Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)
        }
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Completed" -Completed
    }
    else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock }

    Get-ErrorHost -ErrorFileVerbose $ErrorFileVerbose -ErrorFileHosts $ErrorFileHosts

    if ($ReturnedObjects -ne $null) {
        if ($PSBoundParameters['CSV']) { $ReturnedObjects | Export-Csv -Path $OutputFilePath -Append -NoTypeInformation -ErrorAction SilentlyContinue }
        elseif ($PSBoundParameters['TXT']) { $ReturnedObjects | Out-File -FilePath $OutputFilePath -Append -ErrorAction SilentlyContinue }
        else { Write-Output $ReturnedObjects }
    }

    [GC]::Collect()
    $ScriptTime.Stop()
    Write-Verbose "Done, execution time: $($ScriptTime.Elapsed)"
}