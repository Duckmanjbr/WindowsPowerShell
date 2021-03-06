function Get-SkullEvent {
<#
.SYNOPSIS
Pull the specified Windows Event from the past 24 hours.

.DESCRIPTION
This commandlet uses Windows Remote Management to collect Windows Event Log information from remote systems.

Specify computers by name or IP address.

Use the -Verbose switch to see detailed information.

.PARAMETER TargetList 
Specify host(s) to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections.

.PARAMETER LogName
Specify the name of the log to retrieve events from.

.PARAMETER ProviderName
Specify the name of the provider to retrieve events from.

.PARAMETER Level
Specify the level of the events to retrieve: Critical, Error, Warning, or Information.

.PARAMETER EventId
Specify the Id number of the event to collect.

.PARAMETER StartTime
Specify a [DateTime] object at some point in the past to start searching from. 

.PARAMETER EndTime
Specify a [DateTime] object to stop searching at. Default is [DateTime]::Now.

.PARAMETER Timeout 
Specify timeout length, defaults to 3 seconds.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example retrieves all events matching Id 104 from the System log on the local machine and writes the output to the console.

PS C:\> Get-SkullEvent -LogName System -EventId 104


EventId Level                          TimeCreated                                                  Message                                                     
------- -----                          -----------                                                  -------                                                     
    104 Information                    6/7/2015 8:48:46 AM                                          The Application log file was cleared.                       
    104 Information                    6/7/2015 8:48:38 AM                                          The Setup log file was cleared.                             
    104 Information                    6/7/2015 8:48:34 AM                                          The System log file was cleared.      

.EXAMPLE
The following example retrieves all Critical level events from the System log on the local machine and writes the output to the console.

PS C:\> Get-SkullEvent -LogName System -Level Critical


BugcheckParameter1   : 0x0
BootAppStatus        : 0
Message              : The system has rebooted without cleanly shutting down first. This error could be caused if the system stopped responding, crashed, or lost power unexpectedly.
BugcheckParameter4   : 0x0
PowerButtonTimestamp : 0
SleepInProgress      : 0
TimeCreated          : 8/31/2015 4:05:46 PM
Level                : Critical
BugcheckParameter3   : 0x0
EventId              : 41
BugcheckParameter2   : 0x0
BugcheckCode         : 0

.EXAMPLE
The following example retrieves all events matching Id 20 from the Microsoft-Windows-WindowsUpdateClient provider on the local machine and writes the output to the console.

PS C:\> Get-SkullEvent -ProviderName Microsoft-Windows-WindowsUpdateClient -EventId 20


updateRevisionNumber : 200
TimeCreated          : 7/17/2015 12:04:30 AM
serviceGuid          : {7971F918-A847-4430-9279-4A52D1EFE18D}
Message              : Installation Failure: Windows failed to install the following update with error 0x80070652: Update for Microsoft Project 2013 (KB3054956) 32-Bit Edition.
updateGuid           : {557BCE53-8AC9-449F-9DBB-07E9D3B24596}
errorCode            : 0x80070652
EventId              : 20
updateTitle          : Update for Microsoft Project 2013 (KB3054956) 32-Bit Edition
Level                : Error

.EXAMPLE
The following example uses New-TargetList to create a list of targetable hosts and uses that list to collect cleared event logs over the past 24 hours and writes the output to the console.

PS C:\> $Targs = New-TargetList -Cidr 10.10.20.0/24
PS C:\> Get-SkullEvent -TargetList $Targs -LogName Security -EventId 1102

.EXAMPLE
The following example uses New-TargetList to create a list of targetable hosts and uses that list to collect failed logon attempts over the past 10 days and writes the output to a csv file.

PS C:\> $Targs = New-TargetList -Cidr 10.10.20.0/24
PS C:\> Get-SkullEvent -TargetList $Targs -LogName Security -EventId 4625 -StartTime ([DateTime]::Now.AddDays(-10)) -CSV C:\pathto\failed_logons.csv

.EXAMPLE
The following example uses New-TargetList to create a list of targetable hosts and uses that list to collect newly installed services over the past 10 days and writes the output to a csv file.

PS C:\> $Targs = New-TargetList -Cidr 10.10.20.0/24
PS C:\> Get-SkullEvent -TargetList $Targs -LogName System -EventId 7045 -StartTime ([DateTime]::Now.AddDays(-10)) -CSV C:\pathto\new_services.csv

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

    if($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Get-SkullEvent
        
    $Global:Error.Clear()

    $RemoteScriptblock = {
        Param(
            [Parameter()]$LogName,
            [Parameter()]$ProviderName,        
            [Parameter()]$EventId,
            [Parameter()]$Level,
            [Parameter()]$StartTime,
            [Parameter()]$EndTime
        )
        
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

        $Events = Get-WinEvent -FilterHashtable $Filter -ErrorAction SilentlyContinue
            
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

                # Message property is sometimes added by Xml
                try { $Properties.Add('Message', $Event.Message) }
                catch { <# ErrorAction SilentlyContinue #> }

                $EventObject = New-Object -TypeName psobject -Property $Properties

                # Give our event objects a name incase anyone ever wants to parse them using a ps1xml
                $EventObject.PSTypeNames.Insert(0,"$($Event.ProviderName).$($Event.LogName).$($Event.Id)")
                
                Write-Output $EventObject
            }
        }
        else { Write-Warning ($env:COMPUTERNAME + ': No events were found that match the specified selection criteria.') }
    }# End RemoteScriptblock 

    if ($PSBoundParameters['TargetList']) {
        if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }        
        
        $ReturnedObjects = New-Object Collections.ArrayList
        $HostsRemaining = [Collections.ArrayList]$TargetList
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)

        Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -ArgumentList @($LogName, $ProviderName, $EventId, $Level, $StartTime, $EndTime) -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit |
        ForEach-Object { 
            if ($HostsRemaining -contains $_.PSComputerName) { $HostsRemaining.Remove($_.PSComputerName) }
            [void]$ReturnedObjects.Add($_)
            Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)
        }
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Completed" -Completed
    }
    else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($LogName, $ProviderName, $EventId, $Level, $StartTime, $EndTime) }

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