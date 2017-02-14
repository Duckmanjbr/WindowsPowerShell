function Get-SchTasksRpc {
<#
.SYNOPSIS
Retrieves information about scheduled tasks.

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

PS C:\> $Targs = New-TargetList -Cidr 10.10.20.0/24
PS C:\> Get-SchTasksRpc -TargetList $Targs -CSV C:\pathto\schtasks.csv

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

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$CSV,
		
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TXT
    ) #End Param

    if ($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif ($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    $RunspaceScript = {
        Param([String]$Computer)

        # Create TaskService object
        try { $Schedule = New-Object -ComObject 'Schedule.Service' } 
        catch { 
            Write-Errror "Schedule.Service COM Object not found."
	        break
        }

        # Connect to remote host
        try { $Schedule.Connect($Computer) }
        catch {
            Write-Warning "$Computer $($_.Exception.Message)"
            break
        }

        function Get-AllTaskSubFolders {
            param ($FolderRefernce = $Schedule.GetFolder('\'))
            
            $FoldersCollection = New-Object Collections.ArrayList
            
            if (($Folders = $FolderRefernce.GetFolders(1))) {
                foreach ($Folder in $Folders) {
                    [void]$FoldersCollection.Add($Folder)
                    if ($Folder.GetFolders(1)) {
                        Get-AllTaskSubFolders -FolderRefernce $Folder
                    }
                }
            }
            Write-Output $FoldersCollection
        }
        
        # Recurse task folders
        $AllTaskFolders = [Collections.ArrayList](Get-AllTaskSubFolders)

        # Include root folder
        if ($AllTaskFolders -eq $null) { $AllTaskFolders = $Schedule.GetFolder('\') }
        else { [void]$AllTaskFolders.Add($Schedule.GetFolder('\')) }

        # Get tasks from folders
        foreach ($Folder in $AllTaskFolders) {
            
            $Tasks = $Folder.GetTasks(1)
            
            if ($Tasks -ne $null) {
                foreach ($Task in $Tasks) {
                    
                    # Build obj from xml
                    $TaskXml = [Xml]$Task.Xml
                    $Triggers = $TaskXml.Task.Triggers
                    
                    # Enumerate trigger
                    if ($Triggers) {
                        $TriggerProperties = Get-Member -MemberType Property -InputObject $Triggers
                        foreach ($Property in $TriggerProperties) {
                            $TriggerType = $Property.Name
                        }
                    }

                    # Enumerate state
                    switch ($Task.State) {
                              0 { $State = 'Unknown' }
                              1 { $State = 'Disabled' }
                              2 { $State = 'Queued' }
                              3 { $State = 'Ready' }
                              4 { $State = 'Running' }
                        default { $State = 'Unknown' }
                    }
                    
                    $Properties = @{
	                    'Name' = $Task.Name
                        'Path' = $Task.Path
                        'State' = $State
                        'Enabled' = $Task.Enabled
                        'LastRunTime' = $Task.LastRunTime
                        'LastTaskResult' = $Task.LastTaskResult
                        'NumberOfMissedRuns' = $Task.NumberofMissedRuns
                        'NextRunTime' = $Task.NextRunTime
                        'Author' =  $TaskXml.Task.RegistrationInfo.Author
                        'UserId' = $TaskXml.Task.Principals.Principal.UserID
                        'Description' = $TaskXml.Task.RegistrationInfo.Description
                        'TriggerType' = $TriggerType
                        'ComputerName' = $Schedule.TargetServer
                    }
	                New-Object -TypeName PSObject -Property $Properties
                }
            }
        }
    }# End RunspaceScript 

    Write-Verbose 'Creating runspace pool and session states.'
    $SessionState = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $SessionState, $Host)
    $RunspacePool.Open()  

    $Runspaces = New-Object Collections.ArrayList

    foreach ($Computer in $TargetList) {
        
        # Create the powershell instance
        $PowerShell = [PowerShell]::Create()
        [void]$PowerShell.AddScript($RunspaceScript)
        [void]$PowerShell.AddArgument($Computer)
           
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
    Write-Progress -Activity 'Waiting for scheduled task queries to complete...' -Status "Hosts Remaining: $RemainingRunspaces" -PercentComplete 0
    
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
                    Out-File -Append -InputObject $Job.PowerShell.Streams.Warning.Message -FilePath ("$ErrorLocal\$ErrorDate" + "_Get-SchTasksRpc.txt")
                }

                $Job.PowerShell.Dispose()
                $Job.Result = $null
                $Job.PowerShell = $null
                $RemainingRunspaces--
                Write-Progress -Activity 'Waiting for scheduled task queries to complete...' -Status "Hosts Remaining: $RemainingRunspaces" -PercentComplete (($TotalRunspaces - $RemainingRunspaces) / $TotalRunspaces * 100)
            } 

            if ($Job.Result -ne $null) { $More = $true }
        }
                   
        # Remove completed jobs
        $Jobs = $Runspaces.Clone()
        $Jobs | where { $_.Result -eq $null } | foreach { Write-Verbose ("Removing {0}" -f $_.Computer) ; $Runspaces.Remove($_) }     
    } while ($More)
        
    Write-Progress -Activity 'Waiting for scheduled task queries to complete...' -Status 'Completed' -Completed

    [console]::TreatControlCAsInput = $false
    $RunspacePool.Dispose()
    [GC]::Collect()
}