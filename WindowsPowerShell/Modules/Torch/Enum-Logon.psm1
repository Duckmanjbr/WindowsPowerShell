function Enum-Logon {
<#
.SYNOPSIS
Pull the security event logs that correspond to Successful Logon Events from each host from the past 24 hours.

.DESCRIPTION
This commandlet uses Windows Remote Management to collect Successful logon Events in the Windows Event Logs of remote systems.

Specify computers by name or IP address.

Use the -Verbose switch to see detailed information.

.PARAMETER TargetList 
Specify host(s) to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections.

.PARAMETER Hours
When specified, determines how many hours of logs to collect.  By default, it collects the past 24 hours.
To go back one day, set days to 0 and hours to 24.

.PARAMETER Days
When specified, determines how many days of logs to collect.  By default, days is set to 0.

.PARAMETER Timeout 
Specify timeout length, defaults to 3 seconds.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example gets a list of computer names from the pipeline. It then sends output to a text file.

PS C:\> New-TargetList -Cidr 10.10.20.0/24 | Enum-Logon -TXT C:\pathto\output.txt

.EXAMPLE
The following example specifies a computername and sends output to a comma-separated file (csv).

PS C:\> Enum-Logon -TargetList Server01 -CSV C:\pathto\output.csv

.NOTES
Version: 2.0.0915
Author : RBOT

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
        [Int]$Hours = 24,

        [Parameter()]
        [Int]$Days = 0,

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
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Enum-Logon
        
    $Global:Error.Clear()

    $RemoteScriptblock = {
        Param([int]$Days, [int]$Hours)

        if ($Hours -lt 0) { $Hours = 24 }
        if ($Days -lt 0) { $Days = 0 }

        #Convert days to hours, add to hours
        $Hours += ($Days * 24)
        Write-Verbose "Calculated Time = $Hours hours"
			
        # Make the start time, remembering to negate the hours so we get a date in the past
        $StartTime = [DateTime]::Now.AddHours($Hours * -1)

        $LogonEvents = Get-WinEvent -FilterHashtable @{LogName='Security'; Id='4624'; EndTime=([DateTime]::Now); StartTime=$StartTime}
        $Skipped = 0 
        foreach($Entry in $LogonEvents) {
			if ($Entry -ne $null) {
                
                # Convert entry to xml
                $Event = [xml]$Entry.ToXml()

                # Grab object properties from xml
                $Properties = New-Object Hashtable
                $Event.Event.EventData.Data | ForEach-Object { $Properties.Add($_.Name, $_.'#text') }

                if (($Properties.SubjectUserName -like '*blueteam*') -or ($Properties.SubjectUserName -like '$svc.area52.*')) { 
                    $Skipped++
                    continue 
                }

                # Enumerate logontype
                switch ($Properties.LogonType) {
                        '2' { $Properties.Add('LogonTypeName', 'Interactive') }
                        '3' { $Properties.Add('LogonTypeName', 'Network') }
                        '4' { $Properties.Add('LogonTypeName', 'Batch') }
                        '5' { $Properties.Add('LogonTypeName', 'Service') }
                        '7' { $Properties.Add('LogonTypeName', 'Unlock') }
                        '8' { $Properties.Add('LogonTypeName', 'NetworkCleartext') }
                        '9' { $Properties.Add('LogonTypeName', 'NewCredentials') }
                       '10' { $Properties.Add('LogonTypeName', 'RemoteInteractive') }
                       '11' { $Properties.Add('LogonTypeName', 'CachedInteractive') }
                    default { $Properties.Add('LogonTypeName', 'Unknown') }
                }
                New-Object -TypeName PSObject -Property $Properties
            }
            else { Write-Warning "$env:COMPUTERNAME had no logon information for the time specified." }
        }
        Write-Warning "Skipped $Skipped whitelisted entries on $env:COMPUTERNAME."
    }

    if ($PSBoundParameters['TargetList']) {
        if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }        
        $ReturnedObjects = Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -ArgumentList @($Days,$Hours) -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit
    }
    else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($Days,$Hours) }

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
