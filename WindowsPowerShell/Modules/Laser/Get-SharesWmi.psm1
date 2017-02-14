function Get-SharesWmi {
<#
.SYNOPSIS
Retrieves information about local user accounts on a remote machine.

.DESCRIPTION


.PARAMETER TargetList 
Specify a list of hosts to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections, default is 10.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example gets a list of computers from the pipeline and sends output to a csv file.

PS C:\> New-TargetList -Cidr 10.10.20.0/24 | Get-AutoRunsWmi -CSV C:\pathto\output.csv

.EXAMPLE
The following example specifies a computer and sends output to a csv file.

PS C:\> Get-AutoRunsWmi -ComputerName Server01 -CSV C:\pathto\output.csv

.NOTES
Version: 1.0.0915
Author: RBOT

.INPUTS

.OUTPUTS

.LINK
#>
[CmdLetBinding(SupportsShouldProcess = $false)]
    Param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$TargetList = 'localhost',

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
    ) #End Param
    
    if ($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif ($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
          
    if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }         
        
    $Parameters = @{
        Class = "Win32_LogicalShareSecuritySetting"
        ErrorAction = "Stop"
    }

    $RunspaceScript = { 
        Param([String]$Computer, [Hashtable]$Parameters)
        $Parameters.ComputerName = $Computer

        try { $ShareSecuritySetting = Get-WmiObject @Parameters }
        catch { 
            Write-Warning ("{0}: {1}" -f $Computer,$_.Exception.Message)
            break
        }

        $ShareList = New-Object Collections.ArrayList

        foreach ($Share in $ShareSecuritySetting) {

            $SecurityDescriptor = $Share.GetSecurityDescriptor()
    
            foreach ($DACL in $SecurityDescriptor.Descriptor.DACL) {  
    
                switch ($DACL.AccessMask) {
                        2032127 { $AccessMask = 'FullControl' }
                        1179785 { $AccessMask = 'Read' }
                        1180063 { $AccessMask = 'Read, Write' }
                        1179817 { $AccessMask = 'ReadAndExecute' }
                    -1610612736 { $AccessMask = 'ReadAndExecuteExtended' }
                        1245631 { $AccessMask = 'ReadAndExecute, Modify, Write' }
                        1180095 { $AccessMask = 'ReadAndExecute, Write' }
                      268435456 { $AccessMask = 'FullControl (Sub Only)' }
                        default { $AccessMask = $DACL.AccessMask }
                }

                switch ($DACL.AceType) {
                    0 { $AceType = 'Allow' }
                    1 { $AceType = 'Deny' }
                    2 { $AceType = 'Audit' }
                }

                $Properties = @{
                    Computername = $Share.__SERVER
                    ShareName = $Share.Name
                    TrusteeDomain = $DACL.Trustee.Domain
                    TrusteeName = $DACL.Trustee.Name
                    TrusteeSID = $DACL.Trustee.SIDString
                    AceType = $AceType
                    AccessMask = $AccessMask
                }
                [void]$ShareList.Add((New-Object -TypeName PSObject -Property $Properties))
            }
        }
        Write-Output $ShareList
    }

    Write-Verbose 'Creating runspace pool and session states.'
    $SessionState = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $SessionState, $Host)
    $RunspacePool.Open()  

    $Runspaces = New-Object Collections.ArrayList

    foreach ($Computer in $TargetList) {
        #Create the powershell instance and supply the scriptblock with the other parameters 
        $PowerShell = [PowerShell]::Create()
        [void]$PowerShell.AddScript($RunspaceScript)
        [void]$PowerShell.AddArgument($Computer)
        [void]$PowerShell.AddArgument($Parameters)
        [void]$PowerShell.AddParameter('EnableAllPrivileges')
           
        # Assign instance to runspacepool
        $PowerShell.RunspacePool = $RunspacePool
           
        # Create an object for each runspace
        $Job = "" | Select-Object Computer,PowerShell,Result
        $Job.Computer = $Computer
        $Job.PowerShell = $PowerShell
        $Job.Result = $PowerShell.BeginInvoke() #Save the handle output when calling BeginInvoke() that will be used later to end the runspace
        
        Write-Verbose ("Adding {0} to jobs." -f $Job.Computer)
        [void]$Runspaces.Add($Job)
    }
    # Counters for progress bar
    $TotalRunspaces = $RemainingRunspaces = $Runspaces.Count         
    
    Write-Verbose 'Checking status of runspace jobs.'
    Write-Progress -Activity 'Waiting for Win32_StartupCommand queries to complete...' -Status "Hosts Remaining: $RemainingRunspaces" -PercentComplete 0
    
    # Listen for Ctrl+C
    [console]::TreatControlCAsInput = $true
    
    do {
        $More = $false   

        # Quit Gracefully
        if ([console]::KeyAvailable) { 
            $Key = [console]::ReadKey($true)
            if (($Key.Modifiers -band [ConsoleModifiers]::Control) -and ($Key.Key -eq 'C')) {
                Write-Warning "Caught escape sequence, quitting runspace jobs."
                $RunspacePool.Close()
                $RunspacePool.Dispose()
                [console]::TreatControlCAsInput = $false
                break
            }
        }      

        foreach ($Job in $Runspaces) {
            
            if ($Job.Result.IsCompleted) {
                    
                $ReturnedObjects = $Job.PowerShell.EndInvoke($Job.Result)
                if ($ReturnedObjects.Count -gt 0) {
                    if ($PSBoundParameters['CSV']) { $ReturnedObjects | Export-Csv -Path $OutputFilePath -Append -NoTypeInformation -ErrorAction SilentlyContinue }
                    elseif ($PSBoundParameters['TXT']) { $ReturnedObjects | Out-File -FilePath $OutputFilePath -Append -ErrorAction SilentlyContinue }
                    else { Write-Output $ReturnedObjects }
                }

                if ($Job.PowerShell.Streams.Warning.Count -gt 0) {
                    Out-File -Append -InputObject $Job.PowerShell.Streams.Warning -FilePath ("$ErrorLocal\$ErrorDate" + "_Enum-AutoRunWmi.txt")
                }

                $Job.PowerShell.Dispose()
                $Job.Result = $null
                $Job.PowerShell = $null
                $RemainingRunspaces--
                Write-Progress -Activity 'Waiting for Win32_StartupCommand queries to complete...' -Status "Hosts Remaining: $RemainingRunspaces" -PercentComplete (($TotalRunspaces - $RemainingRunspaces) / $TotalRunspaces * 100)
            } 

            if ($Job.Result -ne $null) { $More = $true }
        }
                   
        # Remove completed jobs
        $Jobs = $Runspaces.Clone()
        $Jobs | where { $_.Result -eq $null } | foreach { Write-Verbose ("Removing {0}" -f $_.Computer) ; $Runspaces.Remove($_) }     
    } while ($More)
        
    Write-Progress -Activity 'Waiting for Win32_StartupCommand queries to complete...' -Status 'Completed' -Completed

    [console]::TreatControlCAsInput = $false
    $RunspacePool.Dispose()
    [GC]::Collect()
}
