function Enum-WinEvents {
<#
.SYNOPSIS
Pull the specified Windows Events from the past 24 hours.

.DESCRIPTION
This commandlet uses Windows Remote Management to collect Windows Event Log information from remote systems.

Specify computers by name or IP address.

Use the -Hours switch to change the number of hours of logs to collect.  By default, it collects the past 24 hours.

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
The following example gets a list of computer names from the pipe.  It then sends output to a text file.

PS C:\> New-TargetList -Cidr 10.10.20.0/24 | Enum-WinEvents -TXT C:\pathto\output.txt

.EXAMPLE
The following example specifies two computer names and sends output to a comma-separated file (csv).

PS C:\> Enum-WinEvents -TargetList Server01,Server02 -CSV C:\pathto\output.csv

.NOTES
Version: 1.0.20150908
Author/Contributor: Mr. White 318th
Cleaned by RBOT Sep 15

.INPUTS

.OUTPUTS

.LINK
#>
[CmdLetBinding(SupportsShouldProcess=$False)]
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
    if ($PSBoundParameters['ToFile']) { $OutputFilePath = (Resolve-Path (Split-Path $ToFile -Parent) -ErrorAction Stop).Path + '\' + (Split-Path $ToFile -Leaf) }

    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Enum-WinEvents
        
    $Global:Error.Clear()
    
    $RemoteScriptBlock = {
        Param([int]$Days, [int]$Hours)
            
        function New-LogObject {
			$obj = New-Object -TypeName PSObject
			
			$obj | Add-Member -MemberType NoteProperty -Name TIME -Value $timeGenerated
			$obj | Add-Member -MemberType NoteProperty -Name LOGFILENAME -Value $logFileName
			$obj | Add-Member -MemberType NoteProperty -Name ID -Value $ID
			$obj | Add-Member -MemberType NoteProperty -Name ENTRYTYPE -Value $EntryType
			$obj | Add-Member -MemberType NoteProperty -Name MACHINENAME -Value $MachineName
			$obj | Add-Member -MemberType NoteProperty -Name SITE -Value $Site
			$obj | Add-Member -MemberType NoteProperty -Name SOURCE -Value $Source
			$obj | Add-Member -MemberType NoteProperty -Name USERNAME -Value $UserName
			$obj | Add-Member -MemberType NoteProperty -Name EVENTDESCRIPTION -Value $eventDescription
			$obj | Add-Member -MemberType NoteProperty -Name SubjectSecurityID -Value $subjectSecurityID
			$obj | Add-Member -MemberType NoteProperty -Name SubjectAccountName -Value $subjectAccountName
			$obj | Add-Member -MemberType NoteProperty -Name SubjectDomainName -Value $subjectAccountDomain
			$obj | Add-Member -MemberType NoteProperty -Name MemberSecurityID -Value $memberSecurityID
			$obj | Add-Member -MemberType NoteProperty -Name MemberAccountName -Value $memberAccountName
			$obj | Add-Member -MemberType NoteProperty -Name GroupSecurityID -Value $groupSecurityID
			$obj | Add-Member -MemberType NoteProperty -Name GroupName -Value $groupName
			$obj | Add-Member -MemberType NoteProperty -Name GroupDomain -Value $groupDomain
			$obj | Add-Member -MemberType NoteProperty -Name LockedSecurityID -Value $lockedSecurityID
			$obj | Add-Member -MemberType NoteProperty -Name LockedAccountName -Value $lockedAccountName
			$obj | Add-Member -MemberType NoteProperty -Name LogonFailedSecurityID -Value $logonFailedSecurityID
			$obj | Add-Member -MemberType NoteProperty -Name LogonFailedAccountName -Value $logonFailedAccountName
			$obj | Add-Member -MemberType NoteProperty -Name LogonFailedAccountDomain -Value $logonFailedAccountDomain
			$obj | Add-Member -MemberType NoteProperty -Name LogonFailedReason -Value $logonFailedReason
			$obj | Add-Member -MemberType NoteProperty -Name LogonProcess -Value $logonProcess
			$obj | Add-Member -MemberType NoteProperty -Name CallerProcessName -Value $callerProcessName
			$obj | Add-Member -MemberType NoteProperty -Name Privileges -Value $privileges
			$obj | Add-Member -MemberType NoteProperty -Name SourceAddress -Value $sourceAddress
			$obj | Add-Member -MemberType NoteProperty -Name WorkstationName -Value $workstationName
			$obj | Add-Member -MemberType NoteProperty -Name CallerComputerName -Value $callerComputerName
				
            Write-Output $obj
		} 
        Write-Verbose "Input Days = $Days"
        Write-Verbose "Input Hours = $Hours"

        # In case hours is less than 0, convert negative number to positive
		if ($Hours -lt 0) { $Hours *= -1 }

		# In case days is less than 0, convert negative number to positive
		if ($Days -lt 0) { $Days *= -1 }

		# Convert days to hours, add to hours
		$Hours += ($Days * 24)

        Write-Verbose "Calculated Time = $Hours hours"
			
        # Make the start time, remembering to negate the hours so we get a date in the past
		$StartTime = [DateTime]::Now.AddHours($Hours * -1)
            
        # Get Log Data
        $SecurityLog = Get-EventLog -LogName "Security" -After $StartTime | Where-Object { ($_.InstanceID -eq 1102) -or `
                                                                                            ($_.InstanceID -eq 4740) -or `
                                                                                            ($_.InstanceID -eq 4728) -or `
                                                                                            ($_.InstanceID -eq 4732) -or `
                                                                                            ($_.InstanceID -eq 4756) -or `
                                                                                            ($_.InstanceID -eq 4625) -or `
                                                                                            ($_.InstanceID -eq 4735) }         
        $SystemLog = Get-EventLog -LogName "System" -After $StartTime | Where-Object { ($_.InstanceID -eq 104) -or `
                                                                                        ($_.InstanceID -eq 6008) }
            
        if ($SecurityLog -eq $null) { Write-Error "$env:COMPUTERNAME : Returned 0 security events." }
        else {
            foreach ($Event in $SecurityLog) {
				if ($Event -ne $null) { 
					$Message = $Event.Message
				
					#set Common Values
					$logFileName = "Security"
					$timeGenerated = $Event.TimeGenerated
					$ID = $Event.InstanceID
					$EntryType = $Event.EntryType
					$MachineName = $Event.MachineName
					$Site = $Event.Site
					$Source = $Event.Source
					$UserName = $Event.UserName
					$EventventDescription = ($Message.split("`n"))[0]
				
					#set non common values to null
					$subjectSecurityID = "N/A to ID: $ID" 
					$subjectAccountName = "N/A to ID: $ID" 
					$subjectAccountDomain = "N/A to ID: $ID" 
					$groupSecurityID = "N/A to ID: $ID" 
					$groupName = "N/A to ID: $ID"
					$groupDomain = "N/A to ID: $ID"
					$MessageemberSecurityID = "N/A to ID: $ID"
					$MessageemberAccountName = "N/A to ID: $ID"
					$privileges = "N/A to ID: $ID" 
					$logonFailedSecurityID = "N/A to ID: $ID" 
					$logonFailedAccountName = "N/A to ID: $ID" 
					$logonFailedAccountDomain = "N/A to ID: $ID" 
					$logonFailedReason = "N/A to ID: $ID" 
					$callerProcessName = "N/A to ID: $ID" 
					$workstationName = "N/A to ID: $ID" 
					$logonProcess = "N/A to ID: $ID" 
					$lockedSecurityID = "N/A to ID: $ID" 
					$lockedAccountName = "N/A to ID: $ID" 
					$callerComputerName = "N/A to ID: $ID"
					$sourceAddress = "N/A to ID: $ID"
					
                    switch ($Event.InstanceId) {
                        4625 {
						        $Line = $Message.split("`n")[3]
						        $seperator = "Security ID:"
						        $subjectSecurityID = ($Line -split $seperator)[1].Trim()
						        # The subject account name
						        $Line = $Message.split("`n")[4]
						        $seperator = "Account Name:"
						        $subjectAccountName = ($Line -split $seperator)[1].Trim()
						        # The subject account domain
						        $Line = $Message.split("`n")[5]
						        $seperator = "Account Domain:"
						        $subjectAccountDomain = ($Line -split $seperator)[1].Trim()
						        # The subject security ID
						        $Line = $Message.split("`n")[11]
						        $seperator = "Security ID:"
						        $logonFailedSecurityID = ($Line -split $seperator)[1].Trim()
						        # The logon failed account name
						        $Line = $Message.split("`n")[12]
						        $seperator = "Account Name:"
						        $logonFailedAccountName = ($Line -split $seperator)[1].Trim()
						        # The logon failed account domain
						        $Line = $Message.split("`n")[13]
						        $seperator = "Account Domain:"
						        $logonFailedAccountDomain = ($Line -split $seperator)[1].Trim()
						        # The reason the logon failed
						        $Line = $Message.split("`n")[16]
						        $seperator = "Failure Reason:"
						        $logonFailedReason = ($Line -split $seperator)[1].Trim()
						        # The caller process name
						        $Line = $Message.split("`n")[22]
						        $seperator = "Caller Process Name:"
						        $callerProcessName = ($Line -split $seperator)[1].Trim()
						        # The workstation name
						        $Line = $Message.split("`n")[25]
						        $seperator = "Workstation Name:"
						        $workstationName = ($Line -split $seperator)[1].Trim()
						        # The source network address
						        $Line = $Message.split("`n")[26]
						        $seperator = "Source Network Address:"
						        $sourceAddress = ($Line -split $seperator)[1].Trim()
						        # The logon process
						        $Line = $Message.split("`n")[30]
						        $seperator = "Logon Process:"
						        $logonProcess = ($Line -split $seperator)[1].Trim()
					    }
                        4740 {
                                # The subject security ID
						        $Line = $Message.split("`n")[3]
						        $seperator = "Security ID:"
						        $subjectSecurityID = ($Line -split $seperator)[1].Trim()
						        # The subject account name
						        $Line = $Message.split("`n")[4]
						        $seperator = "Account Name:"
						        $subjectAccountName = ($Line -split $seperator)[1].Trim()
						        # The subject account domain
						        $Line = $Message.split("`n")[5]
						        $seperator = "Account Domain:"
						        $subjectAccountDomain = ($Line -split $seperator)[1].Trim()
						        # The security ID of the locked out account
						        $Line = $Message.split("`n")[9]
						        $seperator = "Security ID:"
						        $lockedSecurityID = ($Line -split $seperator)[1].Trim()
						        # The locked out account name
						        $Line = $Message.split("`n")[10]
						        $seperator = "Account Name:"
						        $lockedAccountName = ($Line -split $seperator)[1].Trim()
						        # The calling computer name
						        $Line = $Message.split("`n")[13]
						        $seperator = "Caller Computer Name:"
						        $callerComputerName = ($Line -split $seperator)[1].Trim()
                        }
                        4728 {
                                # The subject security ID
						        $Line = $Message.split("`n")[3]
						        $seperator = "Security ID:"
						        $subjectSecurityID = ($Line -split $seperator)[1].Trim()
						        # The subject account name
						        $Line = $Message.split("`n")[4]
						        $seperator = "Account Name:"
						        $subjectAccountName = ($Line -split $seperator)[1].Trim()
						        # The subject account domain
						        $Line = $Message.split("`n")[5]
						        $seperator = "Account Domain:"
						        $subjectAccountDomain = ($Line -split $seperator)[1].Trim()
						        # The member security ID
						        $Line = $Message.split("`n")[9]
						        $seperator = "Security ID:"
						        $memberSecurityID = ($Line -split $seperator)[1].Trim()
						        # The member account name
						        $Line = $Message.split("`n")[10]
						        $seperator = "Account Name:"
						        $memberAccountName = ($Line -split $seperator)[1].Trim()
						        # The group security ID
						        $Line = $Message.split("`n")[13]
						        $seperator = "Security ID:"
						        $groupSecurityID = ($Line -split $seperator)[1].Trim()
						        # The group name
						        $Line = $Message.split("`n")[14]
						        $seperator = "Group Name:"
						        $groupName = ($Line -split $seperator)[1].Trim()
						        # The group domain
						        $Line = $Message.split("`n")[15]
						        $seperator = "Group Domain:"
						        $groupDomain = ($Line -split $seperator)[1].Trim()
						        # The privileges
						        $Line = $Message.split("`n")[18]
						        $seperator = "Privileges:"
						        $privileges = ($Line -split $seperator)[1].Trim()
                        }
                        4732 {
                                # The subject security ID
						        $Line = $Message.split("`n")[3]
						        $seperator = "Security ID:"
						        $subjectSecurityID = ($Line -split $seperator)[1].Trim()
						        # The subject account name
						        $Line = $Message.split("`n")[4]
						        $seperator = "Account Name:"
						        $subjectAccountName = ($Line -split $seperator)[1].Trim()
						        # The subject account domain
						        $Line = $Message.split("`n")[5]
						        $seperator = "Account Domain:"
						        $subjectAccountDomain = ($Line -split $seperator)[1].Trim()
						        # The member security ID
						        $Line = $Message.split("`n")[9]
						        $seperator = "Security ID:"
						        $memberSecurityID = ($Line -split $seperator)[1].Trim()
						        # The member account name
						        $Line = $Message.split("`n")[10]
						        $seperator = "Account Name:"
						        $memberAccountName = ($Line -split $seperator)[1].Trim()
						        # The group security ID
						        $Line = $Message.split("`n")[13]
						        $seperator = "Security ID:"
						        $groupSecurityID = ($Line -split $seperator)[1].Trim()
						        # The group name
						        $Line = $Message.split("`n")[14]
						        $seperator = "Group Name:"
						        $groupName = ($Line -split $seperator)[1].Trim()
						        # The group domain
						        $Line = $Message.split("`n")[15]
						        $seperator = "Group Domain:"
						        $groupDomain = ($Line -split $seperator)[1].Trim()
						        # The privileges
						        $Line = $Message.split("`n")[18]
						        $seperator = "Privileges:"
						        $privileges = ($Line -split $seperator)[1].Trim()
                        }
                        4756 {
                                # The subject security ID
						        $Line = $Message.split("`n")[3]
						        $seperator = "Security ID:"
						        $subjectSecurityID = ($Line -split $seperator)[1].Trim()
						        # The subject account name
						        $Line = $Message.split("`n")[4]
						        $seperator = "Account Name:"
						        $subjectAccountName = ($Line -split $seperator)[1].Trim()
						        # The subject account domain
						        $Line = $Message.split("`n")[5]
						        $seperator = "Account Domain:"
						        $subjectAccountDomain = ($Line -split $seperator)[1].Trim()
						        # The member security ID
						        $Line = $Message.split("`n")[9]
						        $seperator = "Security ID:"
						        $memberSecurityID = ($Line -split $seperator)[1].Trim()
						        # The member account name
						        $Line = $Message.split("`n")[10]
						        $seperator = "Account Name:"
						        $memberAccountName = ($Line -split $seperator)[1].Trim()
						        # The group security ID
						        $Line = $Message.split("`n")[13]
						        $seperator = "Security ID:"
						        $groupSecurityID = ($Line -split $seperator)[1].Trim()
						        # The group name
						        $Line = $Message.split("`n")[14]
						        $seperator = "Group Name:"
						        $groupName = ($Line -split $seperator)[1].Trim()
						        # The group domain
						        $Line = $Message.split("`n")[15]
						        $seperator = "Group Domain:"
						        $groupDomain = ($Line -split $seperator)[1].Trim()
						        # The privileges
						        $Line = $Message.split("`n")[18]
						        $seperator = "Privileges:"
						        $privileges = ($Line -split $seperator)[1].Trim()
                        }
                        4735 {
                                # The subject security ID
						        $Line = $Message.split("`n")[3]
						        $seperator = "Security ID:"
						        $subjectSecurityID = ($Line -split $seperator)[1].Trim()
						        # The subject account name
						        $Line = $Message.split("`n")[4]
						        $seperator = "Account Name:"
						        $subjectAccountName = ($Line -split $seperator)[1].Trim()
						        # The subject account domain
						        $Line = $Message.split("`n")[5]
						        $seperator = "Account Domain:"
						        $subjectAccountDomain = ($Line -split $seperator)[1].Trim()						
						        #Group Security ID
						        $Line = $Message.split("`n")[9]
						        $seperator = "Security ID:"
						        $groupSecurityID = ($Line -split $seperator)[1].Trim()						
						        #Group Name
						        $Line = $Message.split("`n")[10]
						        $seperator = "Group Name:"
						        $groupName = ($Line -split $seperator)[1].Trim()						
						        #Group Domain
						        $Line = $Message.split("`n")[11]
						        $seperator = "Group Domain:"
						        $groupDomain = ($Line -split $seperator)[1].Trim()  
                        }
                        1102 {
                                # The subject security ID
						        $Line = $Message.split("`n")[2]
						        $seperator = "Security ID:"
						        $subjectSecurityID = ($Line -split $seperator)[1].Trim()
						        # The subject account name
						        $Line = $Message.split("`n")[3]
						        $seperator = "Account Name:"
						        $subjectAccountName = ($Line -split $seperator)[1].Trim()
						        # The subject account domain
						        $Line = $Message.split("`n")[4]
						        $seperator = "Domain Name:"
						        $subjectAccountDomain = ($Line -split $seperator)[1].Trim()
                        }
                    }
                    $obj = New-LogObject			
                    Write-Output $obj
				}
				else { Write-Error "$env:COMPUTERNAME : Security event returned was null." }
            }
        }
        if ($SystemLog -eq $null) { Write-Error "$env:COMPUTERNAME : Returned 0 system events." }
		else {
            foreach ($Event in $SystemLog) {
				if ($Event -ne $null) {
					$Message = $Event.Message
				
					#set Common Values
					$logFileName = "System"
					$timeGenerated = $Event.TimeGenerated
					$ID = $Event.InstanceID
					$EntryType = $Event.EntryType
					$MachineName = $Event.MachineName
					$Site = $Event.Site
					$Source = $Event.Source
					$UserName = $Event.UserName
					$eventDescription = ($m.split("`n"))[0]
					
					#set non common values to null
					$subjectSecurityID = "N/A to ID: $ID" 
					$subjectAccountName = "N/A to ID: $ID" 
					$subjectAccountDomain = "N/A to ID: $ID"
					$groupSecurityID = "N/A to ID: $ID" 
					$groupName = "N/A to ID: $ID"
					$groupDomain = "N/A to ID: $ID"
					$memberSecurityID = "N/A to ID: $ID"
					$memberAccountName = "N/A to ID: $ID"
					$privileges = "N/A to ID: $ID" 
					$logonFailedSecurityID = "N/A to ID: $ID" 
					$logonFailedAccountName = "N/A to ID: $ID"
					$logonFailedAccountDomain = "N/A to ID: $ID" 
					$logonFailedReason = "N/A to ID: $ID" 
					$callerProcessName = "N/A to ID: $ID" 
					$workstationName = "N/A to ID: $ID" 
					$logonProcess = "N/A to ID: $ID" 
					$lockedSecurityID = "N/A to ID: $ID" 
					$lockedAccountName = "N/A to ID: $ID" 
					$callerComputerName = "N/A to ID: $ID"
					$sourceAddress = "N/A to ID: $ID"
					
					#Event Specific values
					# Determine the event ID and set appropriate variables
					if ($Event.InstanceID -eq 104)
					{ # In case the event ID is 104
						# Add specific event information here
					}
					elseif ($Event.InstanceID -eq 6008)
					{ # In case the event ID is 6008
						# Add specific event information here
					}
					# Function defined above reuses code for consistency and easy maintenance
					# Create common output object
					$obj = New-LogObject			
					Write-Output $obj
				}	
				else { Write-Error "$env:COMPUTERNAME : System event returned was null." }
            }
        } 
    }# End RemoteScriptblock 

    if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }
        
    $ReturnedObjects = Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit

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
