function Enum-EventsWMI() {
<#
.SYNOPSIS
Pull all relevant logs specified in the config file from the hosts specified in the host file. Parses them into CSVs.

.DESCRIPTION
This version is designed to work against XP Systems

.EXAMPLE
This program should only be run from the python script LogAnalysis.py

.NOTES
Version: 1.0
Author: Wyleczuk-Stern

.INPUTS

.OUTPUTS
#>
	[CmdLetBinding(SupportsShouldProcess=$False)]
    param(
		[Parameter()]
        [string]$ConfigFileName = "$dirConfigPath" + 'Enum-EventsWMI.ini',
		[Parameter()]
		[string]$outputFileName = 'Enum-EventsWMI',
		[Parameter()]
		[string]$ArchivePath = "$dirConfigPath"+"archive.txt",
        [Parameter()]
		[switch]$CSV, 
		[Parameter(Mandatory=$True)]
		[string[]]$ComputerName, 
		[Parameter()]
		[switch]$TXT, 
		[Parameter()]
		[switch]$Ping
    ) #End Param
	
	#Define the code that will run in each thread
	$ScriptBlock = {
		Param($log_list, $remote_host, $archive, $ArchivePath)
		$results_list = @()
		$OS = Get-WmiObject -Computer $remote_host -Class Win32_OperatingSystem
		ForEach($log in $log_list){
			$log_list_results = @()
            #Properly format the list of logs
			$splitlog = $log.split() | where {$_}
			$filter = @{
				LogName = $splitlog[0]
				Id = $splitlog[1]
                #Only look at the last two days
				StartTime = (Get-Date).addDays(-1)
			}
            #Try to get the particular log from the host. If the log is empty, an exception is thrown. Hence the try/catch
			try {
				#This should get both Windows 7 and Windows XP logs
				#Get-WinEvent is faster, which is why that option is built in
				if($OS.caption -like "*Windows 7*") {
					$events = Get-WinEvent -FilterHashtable $filter -ComputerName $remote_host -ErrorAction SilentlyContinue
				} else {
					$logfile = $splitlog[0]
					$eventcode = $splitlog[1]
					$events = Get-WmiObject Win32_NTLogEvent -filter "(logfile='$logfile') AND (eventcode='$eventcode')" -ComputerName $remote_host -ErrorAction SilentlyContinue
				}
			}
			catch [Exception]{
				#Do nothing. The log is empty or something else is broken
			}
            #Iterate through all the events and create a PSObject and add it to the list of PSObjects
			#Replace new lines in message with semi-colons
			ForEach($event in $events) {
				#Properly format the events
				try {
					$event.Message = $event.Message -replace "`n","; " -replace "`r","; "
				}
				catch [Exception] {
					#This event has no message
				}
				$details = @{}
				$valid = 1
				$md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
				$utf8 = New-Object -TypeName System.Text.UTF8Encoding
				#Depending on if it's Windows 7 or Windows XP, the event log has different format
				$hash = ""
				if($OS.caption -like "*Windows 7*" -and $event.Id -ne $null) {
					$detailsCombined = "" + $event.TimeCreated + $event.ProviderName + $event.Id + $event.Message + $remote_host
					#Get the hash of the event log
					$hash = [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($detailsCombined)))
					$details = @{
						'Time Created' = $event.TimeCreated;
						'Provider Name' = $event.ProviderName;
						'ID' = $event.Id;
						'Message' = $event.Message
						'Host' = $remote_host
						'Hash' = $hash
						'OS' = $OS.caption
					}
				} elseif($event.EventCode -ne $null){
					$detailsCombined = "" + $event.TimeGenerated + $event.SourceName + $event.EventCode + $event.Message + $remote_host
					#Get the hash of the event log
					$hash = [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($detailsCombined)))
					$details = @{
						'Time Created' = $event.TimeGenerated;
						'Provider Name' = $event.SourceName;
						'ID' = $event.EventCode;
						'Message' = $event.Message
						'Host' = $remote_host
						'Hash' = $hash
						'OS' = $OS.caption
					}
				} else {
					$valid = 0
				}
				#Only add valid entries to the list and only if they haven't been added before by checking the archive
				if($valid -eq 1 -and $hash -ne $NULL) {
					$containsHash = $archive.ContainsKey($hash)
					if(-Not $containsHash) {
						$log_list_results += New-Object -TypeName PSObject -Property $details
						echo $hash >> $ArchivePath
					}
				}
			}
			$results_list += , $log_list_results
		}
		return $results_list
	}
	
    #Get the list of logs to collect and the list of hosts
	$loglist = Get-Content $ConfigFileName | select -Skip 1
	$hostlist = ValidateTargets($ComputerName)
	SetOutandErrorFiles
	$RunspaceCollection = @()
	$RunspacePool = [RunspaceFactory]::CreateRunspacePool(1,10)
	$RunspacePool.Open()
	#Get the content of the archive file. Create one if none exists
	$archive = ""
	if(Test-Path $ArchivePath) {
		#$archive = Get-Content $ArchivePath
        [array]$hash_file = Get-Content $ArchivePath
        $archive = @{}
        foreach ($hash in $hash_file){
        $archive.add("$hash", "$hash")
    }
	} else {
		echo "" > $ArchivePath
		$archive = @{}
	}
	#Create the credential object
	<#$credentials = Get-Content $CredFile
	$username = $credentials[0]
	$password = $credentials[1]
	$secstr = New-Object -TypeName System.Security.SecureString
	$password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
	$cred = New-Object -typename System.Management.Automation.PSCredential -ArgumentList $username,$secstr#>
	ForEach($computer in $hostlist)  {
		#Create a PowerShell object to run. Add the script and arguments
		#$Powershell = [PowerShell]::Create().AddScript($ScriptBlock).AddArgument($loglist).AddArgument($computer).AddArgument($cred).AddArgument($archive)
		$Powershell = [PowerShell]::Create().AddScript($ScriptBlock).AddArgument($loglist).AddArgument($computer).AddArgument($archive).AddArgument($ArchivePath)
		#Specify runspace to use
		$Powershell.RunspacePool = $RunspacePool
		#create Runspace collection
		Write-Host "Starting thread..."
		[Collections.Arraylist]$RunspaceCollection += New-Object -TypeName PSObject -Property @{
			Runspace = $Powershell.BeginInvoke()
			PowerShell = $PowerShell
		}
	}
	#Check for completion
	$combined_event_log_list = @{}
	While($RunspaceCollection) {
		ForEach($Runspace in $RunspaceCollection.ToArray()) {
			If($Runspace.Runspace.IsCompleted) {
				Write-Output "Closing thread..."
				$output = $Runspace.PowerShell.EndInvoke($Runspace.Runspace)
				#Iterate through the output and move the event logs into the proper space in the hashtable
				write-output "output size: "
				write-output $output.count
				ForEach($entry in $output) 
				{
					try {
						if($entry.count -gt 0) {
							$index = $entry[0].ID
							if($combined_event_log_list.ContainsKey($index)) {
								$combined_event_log_list.Get_Item($index) += $entry
							} else {
								$combined_event_log_list.Set_Item($index, $entry)
							}
						}
					}
					catch [Exception] {
						#Do nothing
					}
				}
				$Runspace.PowerShell.Dispose()
				$RunspaceCollection.Remove($Runspace)
			}
		}
	}
	$RunspacePool.Close()
	$count = 0
	$Date = Get-Date -UFormat %Y%m%d_%H%M%S
    if(!($Date | Select-String -Pattern "^\d\d\d\d\d_" -Quiet)){
        if($Date | Select-String -Pattern "^\d\d\d\d_" -Quiet){
            $Date = $Date.Insert(2,"0")
        }elseif($Date | Select-String -Pattern "^\d\d\d_" -Quiet){
            $Date = $Date.Insert(2,"00")
        }
    }
	#Pipe everything to different CSVs
	ForEach($log in $combined_event_log_list.GetEnumerator()) {
		$outputFileName = $diroutputlocal + $date + "_Enum-EventsWMI_" + $($log.key)
        write-host "Outputting to $outputfileName"
		$($log.value) | Export-CSV -Path "$outputFileName.csv" -NoTypeInformation -Append -ErrorAction SilentlyContinue
	}
    write-host "done.."
}

