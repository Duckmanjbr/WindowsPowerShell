function Get-SkullEventRpc {
<#
.SYNOPSIS
Pull the specified Windows Events from the past 24 hours.

.DESCRIPTION
This commandlet uses Remote Procedure Call (Rpc) built-in to Get-WinEvent and runspaces to collect Windows Event Log information from remote systems.

This cmdlet requires systems be able to support Get-WinEvent (Vista+) Rpc errors are likely firewall related.

.PARAMETER TargetList 
Specify host(s) to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections.

.PARAMETER LogName
Specify the name of the log to retrieve events from.

.PARAMETER EventId
Specify the ID number of the event to collect.

.PARAMETER StartTime
Specify a [DateTime] object at some point in the past to start from. Defaults to [DateTime]::Now.AddHours(-24), 24 hours in the past.

.PARAMETER EndTime
Specify a [DateTime] object at some point in time after specified StartTime. Defaults to [DateTime]::Now.

.PARAMETER Timeout 
Specify timeout length, defaults to 3 seconds.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example uses New-TargetList to create a list of targetable hosts and uses that list to collect cleared event logs over the past 24 hours and writes the output to the console.

PS C:\> $Targs = New-TargetList -Cidr 10.10.20.0/24
PS C:\> Get-SkullEventRpc -TargetList $Targs -LogName Security -EventId 1102

.EXAMPLE
The following example uses New-TargetList to create a list of targetable hosts and uses that list to collect failed logon attempts over the past 10 days and writes the output to a csv file.

PS C:\> $Targs = New-TargetList -Cidr 10.10.20.0/24
PS C:\> Get-SkullEventRpc -TargetList $Targs -LogName Security -EventId 4625 -StartTime ([DateTime]::Now.AddDays(-10)) -CSV C:\pathto\failed_logons.csv

.EXAMPLE
The following example uses New-TargetList to create a list of targetable hosts and uses that list to collect newly installed services over the past 10 days and writes the output to a csv file.

PS C:\> $Targs = New-TargetList -Cidr 10.10.20.0/24
PS C:\> Get-SkullEventRpc -TargetList $Targs -LogName System -EventId 7045 -StartTime ([DateTime]::Now.AddDays(-10)) -CSV C:\pathto\new_services.csv

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
        [String]$LogName = "",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$ProviderName = "",
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int]$EventId = 0,

        [Parameter()]
        [ValidateSet('Critical','Error','Warning','Information')]
        [String]$Level = "",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [DateTime]$StartTime,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [DateTime]$EndTime,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$CSV,
		
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TXT
    ) #End Param

    if ($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif ($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    switch ($Level) {
           'Critical' { $LevelValue = 1 }
              'Error' { $LevelValue = 2 }
            'Warning' { $LevelValue = 3 }
        'Information' { $LevelValue = 4 }
    } 
        
    $Filter = @{}
          if ($PSBoundParameters.LogName) { $Filter.Add('LogName', $LogName) }
     if ($PSBoundParameters.ProviderName) { $Filter.Add('ProviderName', $ProviderName) }
          if ($PSBoundParameters.EventId) { $Filter.Add('Id', $EventId) }
            if ($PSBoundParameters.Level) { $Filter.Add('Level', $LevelValue) }
        if ($PSBoundParameters.StartTime) { $Filter.Add('StartTime', $StartTime) }
          if ($PSBoundParameters.EndTime) { $Filter.Add('EndTime', $EndTime) }

    $Parameters = @{
        FilterHashtable = $Filter
        ErrorAction = 'Stop'
    }

    $RunspaceScript = {
        Param([String]$Computer, [Hashtable]$Parameters)

        $Parameters.ComputerName = $Computer

        try { $Events = Get-WinEvent @Parameters }
        catch { 
            Write-Warning ("{0}: {1}" -f $Computer,$_.Exception.Message)
            break
        }
            
        if ($Events -ne $null) { 
            foreach ($Event in $Events) {
                $Properties = New-Object Hashtable
                
                # Convert event to xml
                $EventXml = [xml]$Event.ToXml()

                # Try to grab object properties from xml, 
                try { $EventXml.Event.EventData.Data | ForEach-Object { $Properties.Add($_.Name, $_.'#text') } }
                catch { <# ErrorAction SilentlyContinue #> }

                # Add original properties back to object
                $Properties.Add('TimeCreated', $Event.TimeCreated)
                $Properties.Add('Level', $Event.LevelDisplayName)
                $Properties.Add('EventId', $Event.Id)
                $Properties.Add('ComputerName', $Computer)

                # Message property is sometimes added by Xml
                try { $Properties.Add('Message', $Event.Message) }
                catch { <# ErrorAction SilentlyContinue #> }

                $EventObject = New-Object -TypeName psobject -Property $Properties

                # Give our event objects a name incase anyone ever wants to parse them using a ps1xml
                $EventObject.PSTypeNames.Insert(0,"$($Event.ProviderName).$($Event.LogName).$($Event.Id)")
                
                Write-Output $EventObject
            }
        }
    }# End RunspaceScript 

    Write-Verbose "Creating runspace pool and session states."
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
    Write-Progress -Activity 'Waiting for SkullEvent queries to complete...' -Status "Hosts Remaining: $RemainingRunspaces" -PercentComplete 0
    
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
                        Out-File -Append -InputObject $Message -FilePath ("$ErrorLocal\$ErrorDate" + "_Get-SkullEventRpc.txt")
                }

                $Job.PowerShell.Dispose()
                $Job.Result = $null
                $Job.PowerShell = $null
                $RemainingRunspaces--
                Write-Progress -Activity 'Waiting for SkullEvent queries to complete...' -Status "Hosts Remaining: $RemainingRunspaces" -PercentComplete (($TotalRunspaces - $RemainingRunspaces) / $TotalRunspaces * 100)
            } 

            if ($Job.Result -ne $null) { $More = $true }
        }
                   
        # Remove completed jobs
        $Jobs = $Runspaces.Clone()
        $Jobs | where { $_.Result -eq $null } | foreach { Write-Verbose ("Removing {0}" -f $_.Computer) ; $Runspaces.Remove($_) }     
    } while ($More)
        
    Write-Progress -Activity 'Waiting for SkullEvent queries to complete...' -Status 'Completed' -Completed

    [console]::TreatControlCAsInput = $false
    $RunspacePool.Dispose()
    [GC]::Collect()
}