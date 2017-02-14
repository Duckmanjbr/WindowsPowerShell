function Get-SchTasks {
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
PS C:\> Get-SchTasks -TargetList $Targs -CSV C:\pathto\schtasks.csv

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

    if($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }
    
    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Get-SchTasks
        
    $Global:Error.Clear()

    $RemoteScriptblock = {

        try { $Schedule = New-Object -ComObject 'Schedule.Service' } 
        catch { 
            Write-Errror "Schedule.Service COM Object not found."
	        break
        }
        $Schedule.Connect() 

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
    }

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