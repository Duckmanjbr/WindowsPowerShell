function Enum-LogonWMI{
<#
.SYNOPSIS


.DESCRIPTION


.PARAMETER CSV 

.PARAMETER ComputerName 

.PARAMETER TXT 

.EXAMPLE
PS C:\> EnumLogonWMI -ComputerName localhost

.NOTES
Version: 1.0

.INPUTS
ComputerName - The hostname or IP addr to execute against

.OUTPUTS
A list of running processes on the target machine

.LINK
#>
    Param(
        
        [Parameter()]
		[switch]$CSV, 
		[Parameter(Mandatory=$True)]
		[string[]]$ComputerName, 
		[Parameter()]
		[switch]$TXT
    ) #End Param
    BEGIN{
        $ErrorFileNameH,$ErrorFileNameV,$outputFileName = SetOutandErrorFiles -outputFileName "Enum-LogonWMI" -csv $CSV -txt $TXT
        #$global:error.clear()
        
    } #End BEGIN
    PROCESS{
        $ComputerArray = ValidateTargets($ComputerName)
        #Write-Output "ComputerArray is $ComputerArray"
        
        $logonEvents = @()
        $logonObjsWin7 = @()
        $logonObjsWinXP = @()
        $time = [System.Management.ManagementDateTimeConverter]::ToDmtfDateTime((Get-Date).AddHours(-6))
        foreach($comp in $ComputerArray){
            $OS = Get-WmiObject -Computer $comp -Class Win32_OperatingSystem
            #try {
				#This should get both Windows 7 and Windows XP logs
				#Get-WinEvent is faster, which is why that option is built in
				if($OS.caption -like "*Windows 7*") {
					$events = Get-WinEvent -FilterHashtable @{logname='security';id=4624;starttime=(Get-Date).addhours(-24)} -ComputerName $comp -ErrorAction SilentlyContinue
				} else {
					$events = Get-WmiObject Win32_NTLogEvent -filter "(logfile='security') AND (eventcode='540') AND (TimeWritten>'$time')" -ComputerName $comp
				}
			#}catch {
                #Write-Host "Something happened grabbing events from $comp"
				#Do nothing. The log is empty or something else is broken
			#}
            if($OS.caption -like "*Windows 7*"){
                foreach($e in $Events){
                    $m = $e | select message
                    $skipped = 0
                    $props = @{
                        'Time' = $e.TimeCreated;
                        'LogonType' = ($m.message.split("`n")[8]).split("")[4];
                        'AccountName' = ($m.message.split("`n")[12]).split("")[4];
                        'SecurityID' = ($m.message.split("`n")[11]).split("")[4];
                        'AccountDomain' = ($m.message.split("`n")[13]).split("")[4];
                        'SourceAddress' = ($m.message.split("`n")[23]).split("")[4];
                        'SourcePort' = ($m.message.split("`n")[24]).split("")[4];
                        'LogonProcess' = ($m.message.split("`n")[27]).split("")[4];
                        'ComputerName' = $comp
                    }#end props
                    
                        $obj = New-Object -TypeName PSObject -Property $props
                        $logonObjsWin7 += $obj
                   
                 }#end foreach
            }else{
               foreach($e in $events){
                    $m = $e.message
                    try{
                        if ($m.split("`n").length > 30){
                            $props = @{
                                'Time' = [System.Management.ManagementDateTimeConverter]::ToDateTime($e.TimeGenerated);
                                'AccountName' = ($m.split("`n")[2]).split("")[3];
                                'LogonID' = $m.split("`n")[6].split("")[4];
                                'AccountDomain' = ($m.split("`n")[4]).split("")[3];
                                'SourceAddress' = $m.split("`n")[28].split("")[4];
                                'SourcePort' = $m.split("`n")[30].split("")[3];
                                'LogonType' = $m.split("`n")[8].split("")[3];
                                'ComputerName' = $comp;
                                'WorkstationName' = $m.split("`n")[14].split("")[3]
                            }#end props
                        }else{
                            $props = @{
                                'Time' = [System.Management.ManagementDateTimeConverter]::ToDateTime($e.TimeGenerated);
                                'AccountName' = ($m.split("`n")[2]).split("")[3];
                                'LogonID' = $m.split("`n")[6].split("")[4];
                                'AccountDomain' = ($m.split("`n")[4]).split("")[3];
                                'SourceAddress' = "-";
                                'SourcePort' = "-";
                                'LogonType' = $m.split("`n")[8].split("")[3];
                                'ComputerName' = $comp;
                                'WorkstationName' = $m.split("`n")[14].split("")[3]
                            }
                        }
                        
                            $obj = New-Object -TypeName PSObject -Property $props
                            $logonObjsWinXP += $obj
                            #write-host "user $($props['AccountName']) logged on"
                        
                   }catch{
                        Write-Output "error on message with length $($m.length)"
                        Write-Output $m
                   }
               }#end foreach($e in events)
              }#end else
        }#end foreach comp in comparray
            $logonEvents = $logonObjsWin7 + $logonObjsWinXP
            if($CSV){
                Write-Output "Calling OutCustom with outfile=$outputFileName"
                #OutCustom -object $logonObjsWin7 -CSV -outputFile $outputFileName1
                OutCustom -object $logonEvents -CSV $CSV -outputFile $outputFileName
            }else{
                #OutCustom -object $logonObjsWin7
                OutCustom -object $logonEvents
            }
        
    } #End PROCESS
    END{
        
    } #End END   
}

