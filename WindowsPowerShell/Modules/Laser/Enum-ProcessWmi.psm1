function Enum-ProcessWmi {
<#
.SYNOPSIS
Gathers information about processes on remote systems.

.DESCRIPTION
This commandlet uses Windows Management Instrumentation to collect process information from remote systems.

Specify computers by name or IP address.

Use the -Verbose switch to see detailed information.

.PARAMETER TargetList 
Specify a list of hosts to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example gets a list of computers from the pipeline and sends output to a csv file.

PS C:\> New-TargetList -Cidr 10.10.20.0/24 | Enum-ProcessWmi -CSV C:\pathto\output.csv

.EXAMPLE
The following example specifies a computer and sends output to a csv file.

PS C:\> Enum-ProcessWmi -TargetList Server01 -CSV C:\pathto\output.csv

.NOTES
Version: 1.0.0915
Re-Written by RBOT

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
        Class = "Win32_Process"
        ErrorAction = "Stop"
    }

    $RunspaceScript = { 
        Param([String]$Computer, [Hashtable]$Parameters)
        $Parameters.ComputerName = $Computer

        try { $Processes = Get-WmiObject @Parameters }
        catch { 
            Write-Warning ("{0}: {1}" -f $Computer,$_.Exception.Message)
            break
        }

        $ProcessList = New-Object Collections.ArrayList

        foreach ($Process in $Processes) {
            
            $Owner = $Process.GetOwner()
          
            #Getting Parent Process info
            $ParentProcess = $Processes | Where-Object { $_.ProcessId -eq $Process.ParentProcessId }
            
            try { $ParentStartTime = [Management.ManagementDateTimeConverter]::ToDateTime($ParentProcess.CreationDate) }
            catch { $ParentStartTime = $ParentProcess.CreationDate }
            
            try { $StartTime = [Management.ManagementDateTimeConverter]::ToDateTime($Process.CreationDate) }
            catch { $StartTime = $Process.CreationDate } 

            $IsTrueParent = $StartTime -gt $ParentStartTime

            $Properties = @{
                'ComputerName' = $Process.CSName
                'SessionID' = $Process.SessionId
                'Name' = $Process.Name
                'Path' = $Process.ExecutablePath
                'StartTime' = $StartTime
                'PID' = $Process.ProcessId
                'PPID' = $Process.ParentProcessId
                'ParentName' = $ParentProcess.Name
                'ParentStartTime' = $ParentStartTime
                'IsTrueParent' = $IsTrueParent
                'CommandLine' = $Process.CommandLine
                'VM' = "$("{0:N2}" -f ($Process.VM/1024/1024))MB"
                'User' = $Owner.User
                'Domain' = $Owner.Domain                    
            }
            [void]$ProcessList.Add((New-Object -TypeName PSObject -Property $Properties))
        }
        Write-Output $ProcessList
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
    Write-Progress -Activity 'Waiting for Win32_Process queries to complete...' -Status "Hosts Remaining: $RemainingRunspaces" -PercentComplete 0
    
    # Listen for Ctrl+C
    [console]::TreatControlCAsInput = $true

    $ErrorDate = Get-Date -Format yyyyMMdd_hhmmss
    
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
                    Out-File -Append -InputObject $Job.PowerShell.Streams.Warning -FilePath ("$ErrorLocal\$ErrorDate" + "_Enum-ProcessWmi.txt")
                }

                $Job.PowerShell.Dispose()
                $Job.Result = $null
                $Job.PowerShell = $null
                $RemainingRunspaces--
                Write-Progress -Activity 'Waiting for Win32_Process queries to complete...' -Status "Hosts Remaining: $RemainingRunspaces" -PercentComplete (($TotalRunspaces - $RemainingRunspaces) / $TotalRunspaces * 100)
            } 

            if ($Job.Result -ne $null) { $More = $true }
        }
                   
        # Remove completed jobs
        $Jobs = $Runspaces.Clone()
        $Jobs | where { $_.Result -eq $null } | foreach { Write-Verbose ("Removing {0}" -f $_.Computer) ; $Runspaces.Remove($_) }     
    } while ($More)
        
    Write-Progress -Activity 'Waiting for Win32_Process queries to complete...' -Status 'Completed' -Completed

    [console]::TreatControlCAsInput = $false
    $RunspacePool.Dispose()
    [GC]::Collect()
}