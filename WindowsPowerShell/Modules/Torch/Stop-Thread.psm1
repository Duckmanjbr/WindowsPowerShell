function Stop-Thread {
<#
.SYNOPSIS

A wrapper for kernel32!TerminateThread

.PARAMETER ComputerName 
Specify the computer name or IP address of the machine to stop the thread on.

.PARAMETER ThreadId 
Specify the ID of a thread to terminate.

.EXAMPLE
The following example specifies a computer and terminates thread 1337.

PS C:\> Stop-Thread -ComputerName Server01 -ThreadId 1337
Thread 1337 terminated.

.NOTES
Version: 0.1
Author : Jesse "RBOT" Davis

.INPUTS

.OUTPUTS

.LINK
#>
[CmdLetBinding(SupportsShouldProcess = $False)]
    Param(
        [Parameter()]
        [String]$ComputerName,

        [Parameter(Mandatory = $True)]
        [Int]$ThreadId
    )

    $RemoteScriptBlock = {
        Param([Int]$ThreadId)

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
        $DynAssembly = New-Object System.Reflection.AssemblyName('ThreadKill')
        $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
        $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
        $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]

        #OpenThread
        $OpenThreadAddr = Get-ProcAddress kernel32.dll OpenThread
        $OpenThreadDelegate = Get-DelegateType @([Int32], [Bool], [Int32]) ([IntPtr])
        $OpenThread = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($OpenThreadAddr, $OpenThreadDelegate)

        #TerminateThread
        $TerminateThreadAddr = Get-ProcAddress kernel32.dll TerminateThread
        $TerminateThreadDelegate = Get-DelegateType @([IntPtr], [Int32]) ([bool])
        $TerminateThread = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($TerminateThreadAddr, $TerminateThreadDelegate)
        
        #CloseHandle
        $CloseHandleAddr = Get-ProcAddress kernel32.dll CloseHandle
        $CloseHandleDelegate = Get-DelegateType @([IntPtr]) ([bool])
        $CloseHandle = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($CloseHandleAddr, $CloseHandleDelegate)

        #Open a handle to the thread
        if (($hThread = $OpenThread.Invoke(1, $false, $ThreadId)) -eq 0) { Write-Error "Unable to get a handle for thread $($ThreadId)." }
    
        if($TerminateThread.Invoke($hThread, 0)) { Write-Output "Thread $ThreadId terminated." }
        else { Write-Error "Thread $ThreadId not terminated." }   

        [void]$CloseHandle.Invoke($hThread)
    }
    
    if ($PSBoundParameters.ComputerName) {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock $RemoteScriptBlock -ArgumentList @($ThreadId) -SessionOption (New-PSSessionOption -NoMachineProfile)
    }
    else { Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($ThreadId) }
}