function Close-TcpConnection {
<#
.SYNOPSIS
Searches for and closes TCP connections.

.DESCRIPTION
This cmdlet uses Windows Remote Management to search for and close TCP connections.

Specify computers by name or IP address.

Use the -Verbose switch to see detailed information.

.PARAMETER TargetList 
Specify host(s) to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections.

.PARAMETER LocalPort
Specifies a local port to search for in existing TCP connections.

.PARAMETER RemoteAddress 
Specifies a remote IP address to search for in existing TCP connections.

.PARAMETER RemotePort
Specifies a remote port to search for in existing TCP connections.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example searches for connections to 192.168.0.1:443 from local port 31337 and closes matching connections.

PS C:\> Close-TcpConnection -TargetList Server01 -LocalPort 31337 -RemoteAddress 192.168.0.1 -RemotePort 443

.EXAMPLE
The following example searches a list of computers for any connections to any port on 192.168.0.1 from local port 31337 and closes matching connections.

PS C:\> New-TargetList -Cidr 192.168.1.0/24 | Close-TcpConnection -LocalPort 31337 -RemoteAddress 192.168.0.1

.EXAMPLE
The following example uses a list of targets stored in a variable to search for and connections to any port on 192.168.0.1 and closes matching connections.

PS C:\> $Targets = New-TargetList -Cidr 192.168.1.0/24
PS C:\> Close-TcpConnection -TargetList $Targets -RemoteAddress 192.168.0.1

.NOTES
Version: 0.1
Author : Jesse "RBOT" Davis

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

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [UInt16]$LocalPort,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$RemoteAddress,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [UInt16]$RemotePort,

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
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Close-TcpConnection
        
    $Global:error.clear()
    
    #LocalPort to RemoteAddress and RemotePort
    if($PSBoundParameters['LocalPort'] -and $PSBoundParameters['RemoteAddress'] -and $PSBoundParameters['RemotePort']) {
        $RemoteScriptBlock = {
            Param($LocalPort, $RemoteAddress, $RemotePort)
                #region WinAPI
    
                function local:Get-DelegateType {
                    Param (
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
                    $TypeBuilder.CreateType()
                }
                function local:Get-ProcAddress {
                    Param (
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
                    $GetProcAddress.Invoke($null, @([Runtime.InteropServices.HandleRef]$HandleRef, $Procedure))
                }
    
                $Domain = [AppDomain]::CurrentDomain
                $DynAssembly = New-Object System.Reflection.AssemblyName('CloseTcp4')
                $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
                $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
                $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]

                #Function LoadLibraryA
                $LoadLibraryAAddr = Get-ProcAddress kernel32.dll LoadLibraryA
	            $LoadLibraryADelegate = Get-DelegateType @([String]) ([IntPtr])
	            $LoadLibraryA = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($LoadLibraryAAddr, $LoadLibraryADelegate)

                #Load the IP Help API
                [void]$LoadLibraryA.Invoke("iphlpapi.dll")

                #region MIB_TCPROW
	            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
	            $TypeBuilder = $ModuleBuilder.DefineType('MIB_TCPROW', $Attributes, [ValueType], 20)
	            [void]$TypeBuilder.DefineField('dwState', [UInt32], 'Public')
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
	            $MIB_TCPROW = $TypeBuilder.CreateType()
                #endregion MIB_TCPROW

                $GetTcpTableAddr = Get-ProcAddress iphlpapi.dll GetTcpTable
                $GetTcpTableDelegate = Get-DelegateType @([IntPtr], [UInt32].MakeByRefType(), [bool]) ([Int32])
	            $GetTcpTable = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetTcpTableAddr, $GetTcpTableDelegate)

                $SetTcpEntryAddr = Get-ProcAddress iphlpapi.dll SetTcpEntry
                $SetTcpEntryDelegate = Get-DelegateType @([IntPtr]) ([Int32])
	            $SetTcpEntry = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($SetTcpEntryAddr, $SetTcpEntryDelegate)

                #endregion WinAPI

                [UInt32]$BufferSize = 0

                #Get necessary buffersize
                [void]$GetTcpTable.Invoke([IntPtr]::Zero, [ref]$BufferSize, $True)

                #Allocate buffer
                [IntPtr]$TcpTableBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($BufferSize)

                if(($Return = $GetTcpTable.Invoke($TcpTableBuffer, [ref]$BufferSize, $True)) -ne 0)
                {
                    Write-Error "Call to GetTcpTable failed, error code $Return."
                    exit
                }

                $dwNumEntries = [Runtime.InteropServices.Marshal]::ReadInt32($TcpTableBuffer)  #first Int32 of TcpTable struct is the number of rows
                $TcpRowPtr = [IntPtr]($TcpTableBuffer.ToInt64() + 4)                           #first row is after dwNumEntries, Int32 is size 4
            
                while ($dwNumEntries)
                {
                    $TcpRow = [Runtime.InteropServices.Marshal]::PtrToStructure($TcpRowPtr, [Type]$MIB_TCPROW)

                    $TcpRowRemoteAddr = ([Net.IPAddress]$TcpRow.dwRemoteAddr).IPAddressToString
                    $TcpRowRemotePort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwRemotePort[1], $TcpRow.dwRemotePort[0]),0) 
                    $TcpRowLocalAddr = ([Net.IPAddress]$TcpRow.dwLocalAddr).IPAddressToString
                    $TcpRowLocalPort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwLocalPort[1], $TcpRow.dwLocalPort[0]),0)

                    if(($TcpRowLocalPort -eq $LocalPort) -and ($TcpRowRemoteAddr -eq $RemoteAddress) -and ($TcpRowRemotePort -eq $RemotePort)) {
            
                        $TcpRow.dwState = 0x0C #MIB_TCB_DELETE, close connection
                        [Runtime.InteropServices.Marshal]::StructureToPtr($TcpRow, $TcpRowPtr, $false)

                        if($Result = $SetTcpEntry.Invoke($TcpRowPtr) -ne 0) 
                        { 
                            Write-Error "Unable to close connection from port $LocalPort to $($RemoteAddress):$($RemotePort), error code $Result."
                        }
                        else 
                        {
                            $Properties = @{
                                LocalAddress = $TcpRowLocalAddr
                                LocalPort = $TcpRowLocalPort
                                RemoteAddress = $TcpRowRemoteAddr
                                RemotePort = $TcpRowRemotePort
                                State = "Closed"
                            }
                            New-Object -TypeName PSObject -Property $Properties
                        }
                    }
                    $dwNumEntries--
                    $TcpRowPtr = [IntPtr]($TcpRowPtr.ToInt64() + [Runtime.InteropServices.Marshal]::SizeOf([Type]$MIB_TCPROW))
                }
                [Runtime.InteropServices.Marshal]::FreeHGlobal($TcpTableBuffer)
        }#end RemoteScriptBlock
    }

    #LocalPort to RemotePort
    elseif($PSBoundParameters['LocalPort'] -and $PSBoundParameters['RemotePort'] -and !$PSBoundParameters['RemoteAddress']) {        
        $RemoteScriptBlock = {
            Param($LocalPort, $RemoteAddress, $RemotePort)
                #region WinAPI
    
                function local:Get-DelegateType {
                    Param (
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
                    $TypeBuilder.CreateType()
                }
                function local:Get-ProcAddress{
                    Param (
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
                    $GetProcAddress.Invoke($null, @([Runtime.InteropServices.HandleRef]$HandleRef, $Procedure))
                }
    
                $Domain = [AppDomain]::CurrentDomain
                $DynAssembly = New-Object System.Reflection.AssemblyName('CloseTcp4')
                $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
                $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
                $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]

                #Function LoadLibraryA
                $LoadLibraryAAddr = Get-ProcAddress kernel32.dll LoadLibraryA
	            $LoadLibraryADelegate = Get-DelegateType @([String]) ([IntPtr])
	            $LoadLibraryA = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($LoadLibraryAAddr, $LoadLibraryADelegate)

                #Load the IP Help API
                [void]$LoadLibraryA.Invoke("iphlpapi.dll")

                #region MIB_TCPROW
	            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
	            $TypeBuilder = $ModuleBuilder.DefineType('MIB_TCPROW', $Attributes, [ValueType], 20)
	            [void]$TypeBuilder.DefineField('dwState', [UInt32], 'Public')
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
	            $MIB_TCPROW = $TypeBuilder.CreateType()
                #endregion MIB_TCPROW

                $GetTcpTableAddr = Get-ProcAddress iphlpapi.dll GetTcpTable
                $GetTcpTableDelegate = Get-DelegateType @([IntPtr], [UInt32].MakeByRefType(), [bool]) ([Int32])
	            $GetTcpTable = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetTcpTableAddr, $GetTcpTableDelegate)

                $SetTcpEntryAddr = Get-ProcAddress iphlpapi.dll SetTcpEntry
                $SetTcpEntryDelegate = Get-DelegateType @([IntPtr]) ([Int32])
	            $SetTcpEntry = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($SetTcpEntryAddr, $SetTcpEntryDelegate)

                #endregion WinAPI

                [UInt32]$BufferSize = 0

                #Get necessary buffersize
                [void]$GetTcpTable.Invoke([IntPtr]::Zero, [ref]$BufferSize, $True)

                #Allocate buffer
                [IntPtr]$TcpTableBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($BufferSize)

                if(($Return = $GetTcpTable.Invoke($TcpTableBuffer, [ref]$BufferSize, $True)) -ne 0)
                {
                    Write-Error "Call to GetTcpTable failed, error code $Return."
                    exit
                }

                $dwNumEntries = [Runtime.InteropServices.Marshal]::ReadInt32($TcpTableBuffer)  #first Int32 of TcpTable struct is the number of rows
                $TcpRowPtr = [IntPtr]($TcpTableBuffer.ToInt64() + 4)                           #first row is after dwNumEntries, Int32 is size 4
            
                while ($dwNumEntries)
                {
                    $TcpRow = [Runtime.InteropServices.Marshal]::PtrToStructure($TcpRowPtr, [Type]$MIB_TCPROW)

                    $TcpRowRemoteAddr = ([Net.IPAddress]$TcpRow.dwRemoteAddr).IPAddressToString
                    $TcpRowRemotePort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwRemotePort[1], $TcpRow.dwRemotePort[0]),0) 
                    $TcpRowLocalAddr = ([Net.IPAddress]$TcpRow.dwLocalAddr).IPAddressToString
                    $TcpRowLocalPort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwLocalPort[1], $TcpRow.dwLocalPort[0]),0)

                    if(($TcpRowRemotePort -eq $RemotePort) -and ($TcpRowLocalPort -eq $LocalPort)) {
            
                        $TcpRow.dwState = 0x0C #MIB_TCB_DELETE, close connection
                        [Runtime.InteropServices.Marshal]::StructureToPtr($TcpRow, $TcpRowPtr, $false)

                        if($Result = $SetTcpEntry.Invoke($TcpRowPtr) -ne 0) 
                        { 
                            Write-Error "Unable to close connection to $RemoteAddress, error code $Result."
                        }
                        else 
                        {
                            $Properties = @{
                                LocalAddress = $TcpRowLocalAddr
                                LocalPort = $TcpRowLocalPort
                                RemoteAddress = $TcpRowRemoteAddr
                                RemotePort = $TcpRowRemotePort
                                State = "Closed"
                            }
                            New-Object -TypeName PSObject -Property $Properties
                        }
                    }
                    $dwNumEntries--
                    $TcpRowPtr = [IntPtr]($TcpRowPtr.ToInt64() + [Runtime.InteropServices.Marshal]::SizeOf([Type]$MIB_TCPROW))
                }
                [Runtime.InteropServices.Marshal]::FreeHGlobal($TcpTableBuffer)
        }#end RemoteScriptBlock
    }

    #LocalPort to RemoteAddress
    elseif($PSBoundParameters['LocalPort'] -and $PSBoundParameters['RemoteAddress'] -and !$PSBoundParameters['RemotePort']) {
        $RemoteScriptBlock = {
            Param($LocalPort, $RemoteAddress, $RemotePort)
                #region WinAPI
    
                function local:Get-DelegateType {
                    Param (
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
                    $TypeBuilder.CreateType()
                }
                function local:Get-ProcAddress {
                    Param (
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
                    $GetProcAddress.Invoke($null, @([Runtime.InteropServices.HandleRef]$HandleRef, $Procedure))
                }
    
                $Domain = [AppDomain]::CurrentDomain
                $DynAssembly = New-Object System.Reflection.AssemblyName('CloseTcp4')
                $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
                $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
                $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]

                #Function LoadLibraryA
                $LoadLibraryAAddr = Get-ProcAddress kernel32.dll LoadLibraryA
	            $LoadLibraryADelegate = Get-DelegateType @([String]) ([IntPtr])
	            $LoadLibraryA = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($LoadLibraryAAddr, $LoadLibraryADelegate)

                #Load the IP Help API
                [void]$LoadLibraryA.Invoke("iphlpapi.dll")

                #region MIB_TCPROW
	            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
	            $TypeBuilder = $ModuleBuilder.DefineType('MIB_TCPROW', $Attributes, [ValueType], 20)
	            [void]$TypeBuilder.DefineField('dwState', [UInt32], 'Public')
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
	            $MIB_TCPROW = $TypeBuilder.CreateType()
                #endregion MIB_TCPROW

                $GetTcpTableAddr = Get-ProcAddress iphlpapi.dll GetTcpTable
                $GetTcpTableDelegate = Get-DelegateType @([IntPtr], [UInt32].MakeByRefType(), [bool]) ([Int32])
	            $GetTcpTable = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetTcpTableAddr, $GetTcpTableDelegate)

                $SetTcpEntryAddr = Get-ProcAddress iphlpapi.dll SetTcpEntry
                $SetTcpEntryDelegate = Get-DelegateType @([IntPtr]) ([Int32])
	            $SetTcpEntry = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($SetTcpEntryAddr, $SetTcpEntryDelegate)

                #endregion WinAPI

                [UInt32]$BufferSize = 0

                #Get necessary buffersize
                [void]$GetTcpTable.Invoke([IntPtr]::Zero, [ref]$BufferSize, $True)

                #Allocate buffer
                [IntPtr]$TcpTableBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($BufferSize)

                if(($Return = $GetTcpTable.Invoke($TcpTableBuffer, [ref]$BufferSize, $True)) -ne 0)
                {
                    Write-Error "Call to GetTcpTable failed, error code $Return."
                    exit
                }

                $dwNumEntries = [Runtime.InteropServices.Marshal]::ReadInt32($TcpTableBuffer)  #first Int32 of TcpTable struct is the number of rows
                $TcpRowPtr = [IntPtr]($TcpTableBuffer.ToInt64() + 4)                           #first row is after dwNumEntries, Int32 is size 4
            
                while ($dwNumEntries)
                {
                    $TcpRow = [Runtime.InteropServices.Marshal]::PtrToStructure($TcpRowPtr, [Type]$MIB_TCPROW)

                    $TcpRowRemoteAddr = ([Net.IPAddress]$TcpRow.dwRemoteAddr).IPAddressToString
                    $TcpRowRemotePort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwRemotePort[1], $TcpRow.dwRemotePort[0]),0) 
                    $TcpRowLocalAddr = ([Net.IPAddress]$TcpRow.dwLocalAddr).IPAddressToString
                    $TcpRowLocalPort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwLocalPort[1], $TcpRow.dwLocalPort[0]),0)

                    if(($TcpRowRemoteAddr -eq $RemoteAddress) -and ($TcpRowLocalPort -eq $LocalPort)) {
            
                        $TcpRow.dwState = 0x0C #MIB_TCB_DELETE, close connection
                        [Runtime.InteropServices.Marshal]::StructureToPtr($TcpRow, $TcpRowPtr, $false)

                        if($Result = $SetTcpEntry.Invoke($TcpRowPtr) -ne 0) 
                        { 
                            Write-Error "Unable to close connection to $RemoteAddress, error code $Result."
                        }
                        else 
                        {
                            $Properties = @{
                                LocalAddress = $TcpRowLocalAddr
                                LocalPort = $TcpRowLocalPort
                                RemoteAddress = $TcpRowRemoteAddr
                                RemotePort = $TcpRowRemotePort
                                State = "Closed"
                            }
                            New-Object -TypeName PSObject -Property $Properties
                        }
                    }
                    $dwNumEntries--
                    $TcpRowPtr = [IntPtr]($TcpRowPtr.ToInt64() + [Runtime.InteropServices.Marshal]::SizeOf([Type]$MIB_TCPROW))
                }
                [Runtime.InteropServices.Marshal]::FreeHGlobal($TcpTableBuffer)
        }#end RemoteScriptBlock
    }

    #Any to RemoteAddress and RemotePort
    elseif($PSBoundParameters['RemoteAddress'] -and $PSBoundParameters['RemotePort'] -and !$PSBoundParameters['LocalPort']) {
        $RemoteScriptBlock = {
            Param($LocalPort, $RemoteAddress, $RemotePort)
                #region WinAPI
    
                function local:Get-DelegateType {
                    Param (
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
                    $TypeBuilder.CreateType()
                }

                function local:Get-ProcAddress {
                    Param (
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
                    $GetProcAddress.Invoke($null, @([Runtime.InteropServices.HandleRef]$HandleRef, $Procedure))
                }
    
                $Domain = [AppDomain]::CurrentDomain
                $DynAssembly = New-Object System.Reflection.AssemblyName('CloseTcp4')
                $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
                $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
                $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]

                #Function LoadLibraryA
                $LoadLibraryAAddr = Get-ProcAddress kernel32.dll LoadLibraryA
	            $LoadLibraryADelegate = Get-DelegateType @([String]) ([IntPtr])
	            $LoadLibraryA = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($LoadLibraryAAddr, $LoadLibraryADelegate)

                #Load the IP Help API
                [void]$LoadLibraryA.Invoke("iphlpapi.dll")

                #region MIB_TCPROW
	            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
	            $TypeBuilder = $ModuleBuilder.DefineType('MIB_TCPROW', $Attributes, [ValueType], 20)
	            [void]$TypeBuilder.DefineField('dwState', [UInt32], 'Public')
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
	            $MIB_TCPROW = $TypeBuilder.CreateType()
                #endregion MIB_TCPROW

                $GetTcpTableAddr = Get-ProcAddress iphlpapi.dll GetTcpTable
                $GetTcpTableDelegate = Get-DelegateType @([IntPtr], [UInt32].MakeByRefType(), [bool]) ([Int32])
	            $GetTcpTable = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetTcpTableAddr, $GetTcpTableDelegate)

                $SetTcpEntryAddr = Get-ProcAddress iphlpapi.dll SetTcpEntry
                $SetTcpEntryDelegate = Get-DelegateType @([IntPtr]) ([Int32])
	            $SetTcpEntry = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($SetTcpEntryAddr, $SetTcpEntryDelegate)

                #endregion WinAPI

                [UInt32]$BufferSize = 0

                #Get necessary buffersize
                [void]$GetTcpTable.Invoke([IntPtr]::Zero, [ref]$BufferSize, $True)

                #Allocate buffer
                [IntPtr]$TcpTableBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($BufferSize)

                if(($Return = $GetTcpTable.Invoke($TcpTableBuffer, [ref]$BufferSize, $True)) -ne 0)
                {
                    Write-Error "Call to GetTcpTable failed, error code $Return."
                    exit
                }

                $dwNumEntries = [Runtime.InteropServices.Marshal]::ReadInt32($TcpTableBuffer)  #first Int32 of TcpTable struct is the number of rows
                $TcpRowPtr = [IntPtr]($TcpTableBuffer.ToInt64() + 4)                           #first row is after dwNumEntries, Int32 is size 4
            
                while ($dwNumEntries)
                {
                    $TcpRow = [Runtime.InteropServices.Marshal]::PtrToStructure($TcpRowPtr, [Type]$MIB_TCPROW)

                    $TcpRowRemoteAddr = ([Net.IPAddress]$TcpRow.dwRemoteAddr).IPAddressToString
                    $TcpRowRemotePort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwRemotePort[1], $TcpRow.dwRemotePort[0]),0) 
                    $TcpRowLocalAddr = ([Net.IPAddress]$TcpRow.dwLocalAddr).IPAddressToString
                    $TcpRowLocalPort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwLocalPort[1], $TcpRow.dwLocalPort[0]),0)

                    if(($TcpRowRemoteAddr -eq $RemoteAddress) -and ($TcpRowRemotePort -eq $RemotePort)) {
            
                        $TcpRow.dwState = 0x0C #MIB_TCB_DELETE, close connection
                        [Runtime.InteropServices.Marshal]::StructureToPtr($TcpRow, $TcpRowPtr, $false)

                        if($Result = $SetTcpEntry.Invoke($TcpRowPtr) -ne 0) 
                        { 
                            Write-Error "Unable to close connection to $($RemoteAddress):$($RemotePort), error code $Result."
                        }
                        else 
                        {
                            $Properties = @{
                                LocalAddress = $TcpRowLocalAddr
                                LocalPort = $TcpRowLocalPort
                                RemoteAddress = $TcpRowRemoteAddr
                                RemotePort = $TcpRowRemotePort
                                State = "Closed"
                            }
                            New-Object -TypeName PSObject -Property $Properties
                        }
                    }
                    $dwNumEntries--
                    $TcpRowPtr = [IntPtr]($TcpRowPtr.ToInt64() + [Runtime.InteropServices.Marshal]::SizeOf([Type]$MIB_TCPROW))
                }
                [Runtime.InteropServices.Marshal]::FreeHGlobal($TcpTableBuffer)
        }#end RemoteScriptBlock
    }

    #Any to RemoteAddress only
    elseif($PSBoundParameters['RemoteAddress'] -and !$PSBoundParameters['RemotePort'] -and !$PSBoundParameters['LocalPort']) {
        $RemoteScriptBlock = {
            Param($LocalPort, $RemoteAddress, $RemotePort)
                #region WinAPI
    
                function local:Get-DelegateType {
                    Param (
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
                    $TypeBuilder.CreateType()
                }
                function local:Get-ProcAddress {
                    Param (
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
                    $GetProcAddress.Invoke($null, @([Runtime.InteropServices.HandleRef]$HandleRef, $Procedure))
                }
    
                $Domain = [AppDomain]::CurrentDomain
                $DynAssembly = New-Object System.Reflection.AssemblyName('CloseTcp4')
                $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
                $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
                $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]

                #Function LoadLibraryA
                $LoadLibraryAAddr = Get-ProcAddress kernel32.dll LoadLibraryA
	            $LoadLibraryADelegate = Get-DelegateType @([String]) ([IntPtr])
	            $LoadLibraryA = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($LoadLibraryAAddr, $LoadLibraryADelegate)

                #Load the IP Help API
                [void]$LoadLibraryA.Invoke("iphlpapi.dll")

                #region MIB_TCPROW
	            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
	            $TypeBuilder = $ModuleBuilder.DefineType('MIB_TCPROW', $Attributes, [ValueType], 20)
	            [void]$TypeBuilder.DefineField('dwState', [UInt32], 'Public')
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
	            $MIB_TCPROW = $TypeBuilder.CreateType()
                #endregion MIB_TCPROW

                $GetTcpTableAddr = Get-ProcAddress iphlpapi.dll GetTcpTable
                $GetTcpTableDelegate = Get-DelegateType @([IntPtr], [UInt32].MakeByRefType(), [bool]) ([Int32])
	            $GetTcpTable = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetTcpTableAddr, $GetTcpTableDelegate)

                $SetTcpEntryAddr = Get-ProcAddress iphlpapi.dll SetTcpEntry
                $SetTcpEntryDelegate = Get-DelegateType @([IntPtr]) ([Int32])
	            $SetTcpEntry = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($SetTcpEntryAddr, $SetTcpEntryDelegate)

                #endregion WinAPI

                [UInt32]$BufferSize = 0

                #Get necessary buffersize
                [void]$GetTcpTable.Invoke([IntPtr]::Zero, [ref]$BufferSize, $True)

                #Allocate buffer
                [IntPtr]$TcpTableBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($BufferSize)

                if(($Return = $GetTcpTable.Invoke($TcpTableBuffer, [ref]$BufferSize, $True)) -ne 0)
                {
                    Write-Error "Call to GetTcpTable failed, error code $Return."
                    exit
                }

                $dwNumEntries = [Runtime.InteropServices.Marshal]::ReadInt32($TcpTableBuffer)  #first Int32 of TcpTable struct is the number of rows
                $TcpRowPtr = [IntPtr]($TcpTableBuffer.ToInt64() + 4)                           #first row is after dwNumEntries, Int32 is size 4
            
                while ($dwNumEntries)
                {
                    $TcpRow = [Runtime.InteropServices.Marshal]::PtrToStructure($TcpRowPtr, [Type]$MIB_TCPROW)

                    $TcpRowRemoteAddr = ([Net.IPAddress]$TcpRow.dwRemoteAddr).IPAddressToString
                    $TcpRowRemotePort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwRemotePort[1], $TcpRow.dwRemotePort[0]),0) 
                    $TcpRowLocalAddr = ([Net.IPAddress]$TcpRow.dwLocalAddr).IPAddressToString
                    $TcpRowLocalPort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwLocalPort[1], $TcpRow.dwLocalPort[0]),0)

                    if(($TcpRowRemoteAddr -eq $RemoteAddress)) {
            
                        $TcpRow.dwState = 0x0C #MIB_TCB_DELETE, close connection
                        [Runtime.InteropServices.Marshal]::StructureToPtr($TcpRow, $TcpRowPtr, $false)

                        if($Result = $SetTcpEntry.Invoke($TcpRowPtr) -ne 0) 
                        { 
                            Write-Error "Unable to close connection to $RemoteAddress, error code $Result."
                        }
                        else 
                        {
                            $Properties = @{
                                LocalAddress = $TcpRowLocalAddr
                                LocalPort = $TcpRowLocalPort
                                RemoteAddress = $TcpRowRemoteAddr
                                RemotePort = $TcpRowRemotePort
                                State = "Closed"
                            }
                            New-Object -TypeName PSObject -Property $Properties
                        }
                    }
                    $dwNumEntries--
                    $TcpRowPtr = [IntPtr]($TcpRowPtr.ToInt64() + [Runtime.InteropServices.Marshal]::SizeOf([Type]$MIB_TCPROW))
                }
                [Runtime.InteropServices.Marshal]::FreeHGlobal($TcpTableBuffer)
        }#end RemoteScriptBlock
    }

    #Any to RemotePort only
    elseif($PSBoundParameters['RemotePort'] -and !$PSBoundParameters['RemoteAddress'] -and !$PSBoundParameters['LocalPort']) {
        $RemoteScriptBlock = {
            Param($LocalPort, $RemoteAddress, $RemotePort)
                #region WinAPI
    
                function local:Get-DelegateType {
                    Param (
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
                    $TypeBuilder.CreateType()
                }
                function local:Get-ProcAddress {
                    Param (
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
                    $GetProcAddress.Invoke($null, @([Runtime.InteropServices.HandleRef]$HandleRef, $Procedure))
                }
    
                $Domain = [AppDomain]::CurrentDomain
                $DynAssembly = New-Object System.Reflection.AssemblyName('CloseTcp4')
                $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
                $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
                $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]

                #Function LoadLibraryA
                $LoadLibraryAAddr = Get-ProcAddress kernel32.dll LoadLibraryA
	            $LoadLibraryADelegate = Get-DelegateType @([String]) ([IntPtr])
	            $LoadLibraryA = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($LoadLibraryAAddr, $LoadLibraryADelegate)

                #Load the IP Help API
                [void]$LoadLibraryA.Invoke("iphlpapi.dll")

                #region MIB_TCPROW
	            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
	            $TypeBuilder = $ModuleBuilder.DefineType('MIB_TCPROW', $Attributes, [ValueType], 20)
	            [void]$TypeBuilder.DefineField('dwState', [UInt32], 'Public')
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
	            $MIB_TCPROW = $TypeBuilder.CreateType()
                #endregion MIB_TCPROW

                $GetTcpTableAddr = Get-ProcAddress iphlpapi.dll GetTcpTable
                $GetTcpTableDelegate = Get-DelegateType @([IntPtr], [UInt32].MakeByRefType(), [bool]) ([Int32])
	            $GetTcpTable = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetTcpTableAddr, $GetTcpTableDelegate)

                $SetTcpEntryAddr = Get-ProcAddress iphlpapi.dll SetTcpEntry
                $SetTcpEntryDelegate = Get-DelegateType @([IntPtr]) ([Int32])
	            $SetTcpEntry = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($SetTcpEntryAddr, $SetTcpEntryDelegate)

                #endregion WinAPI

                [UInt32]$BufferSize = 0

                #Get necessary buffersize
                [void]$GetTcpTable.Invoke([IntPtr]::Zero, [ref]$BufferSize, $True)

                #Allocate buffer
                [IntPtr]$TcpTableBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($BufferSize)

                if(($Return = $GetTcpTable.Invoke($TcpTableBuffer, [ref]$BufferSize, $True)) -ne 0)
                {
                    Write-Error "Call to GetTcpTable failed, error code $Return."
                    exit
                }

                $dwNumEntries = [Runtime.InteropServices.Marshal]::ReadInt32($TcpTableBuffer)  #first Int32 of TcpTable struct is the number of rows
                $TcpRowPtr = [IntPtr]($TcpTableBuffer.ToInt64() + 4)                           #first row is after dwNumEntries, Int32 is size 4
            
                while ($dwNumEntries) {
                    $TcpRow = [Runtime.InteropServices.Marshal]::PtrToStructure($TcpRowPtr, [Type]$MIB_TCPROW)

                    $TcpRowRemoteAddr = ([Net.IPAddress]$TcpRow.dwRemoteAddr).IPAddressToString
                    $TcpRowRemotePort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwRemotePort[1], $TcpRow.dwRemotePort[0]),0) 
                    $TcpRowLocalAddr = ([Net.IPAddress]$TcpRow.dwLocalAddr).IPAddressToString
                    $TcpRowLocalPort = [BitConverter]::ToUInt16([byte[]]@($TcpRow.dwLocalPort[1], $TcpRow.dwLocalPort[0]),0)

                    if(($TcpRowRemotePort -eq $RemotePort)) {
            
                        $TcpRow.dwState = 0x0C #MIB_TCB_DELETE, close connection
                        [Runtime.InteropServices.Marshal]::StructureToPtr($TcpRow, $TcpRowPtr, $false)

                        if($Result = $SetTcpEntry.Invoke($TcpRowPtr) -ne 0) { 
                            Write-Error "Unable to close connection to $RemoteAddress, error code $Result."
                        }
                        else {
                            $Properties = @{
                                LocalAddress = $TcpRowLocalAddr
                                LocalPort = $TcpRowLocalPort
                                RemoteAddress = $TcpRowRemoteAddr
                                RemotePort = $TcpRowRemotePort
                                State = "Closed"
                            }
                            New-Object -TypeName PSObject -Property $Properties
                        }
                    }
                    $dwNumEntries--
                    $TcpRowPtr = [IntPtr]($TcpRowPtr.ToInt64() + [Runtime.InteropServices.Marshal]::SizeOf([Type]$MIB_TCPROW))
                }
                [Runtime.InteropServices.Marshal]::FreeHGlobal($TcpTableBuffer)
        }#end RemoteScriptBlock
    }

    else { Write-Warning "You must specify at least one of the following: LocalPort, RemotePort, or RemoteAddress."; break }

    if ($PSBoundParameters['TargetList']) {
        if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }        
        
        $ReturnedObjects = New-Object Collections.ArrayList
        $HostsRemaining = [Collections.ArrayList]$TargetList
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)

        Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -ArgumentList @($LocalPort, $RemoteAddress, $RemotePort) -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit |
        ForEach-Object { 
            if ($HostsRemaining -contains $_.PSComputerName) { $HostsRemaining.Remove($_.PSComputerName) }
            [void]$ReturnedObjects.Add($_)
            Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)
        }
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Completed" -Completed
    }
    else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($LocalPort, $RemoteAddress, $RemotePort) }

    Get-ErrorHost -ErrorFileVerbose $ErrorFileVerbose -ErrorFileHosts $ErrorFileHosts

    if($ReturnedObjects) {
        if($PSBoundParameters['CSV']) { $ReturnedObjects | Export-Csv -Path $OutputFilePath -Append -NoTypeInformation -ErrorAction SilentlyContinue }
        elseif ($PSBoundParameters['TXT']) { $ReturnedObjects | Out-File -FilePath $OutputFilePath -Append -ErrorAction SilentlyContinue }
        else { Write-Output $ReturnedObjects }
    }

    [GC]::Collect()
    $ScriptTime.Stop()
    Write-Verbose "Done, execution time: $($ScriptTime.Elapsed)"
}