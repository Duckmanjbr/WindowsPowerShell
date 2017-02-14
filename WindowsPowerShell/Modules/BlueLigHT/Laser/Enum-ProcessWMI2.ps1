function Enum-ProcessWMI2{
<#
.SYNOPSIS


.DESCRIPTION


.PARAMETER CSV 

.PARAMETER ComputerName 

.PARAMETER TXT 

.EXAMPLE
PS C:\> Enum-ProcessWMI -ComputerName localhost

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
        [string]$ConfigFileName = "$dirConfigPath" + 'Enum-ProcessWMI2.ini',
        [Parameter()]
		[switch]$CSV, 
		[Parameter(Mandatory=$True)]
		[string[]]$ComputerName, 
		[Parameter()]
		[switch]$TXT
    ) #End Param
    BEGIN{
        Write-Output "Reading config file"
        ReadConfigFile -configFile $ConfigFileName
       
        SetOutandErrorFiles
        #$global:error.clear()
        
    } #End BEGIN
    PROCESS{
        $ComputerArray = ValidateTargets($ComputerName)
        try{
            $customProcList = @()
            $procJobs = @()
            Write-Output "Starting Jobs"
            $i=1
            foreach($comp in $ComputerArray){
                $sblock = {
                    param($comp)
                    Get-WmiObject win32_process  -EnableAllPrivileges -ComputerName $comp |
                            select Name, VM, ProcessId, ParentProcessId, CommandLine, CreationDate, SessionId, @{l='User';e={($_.getowner().user)}}, @{l='Domain';e={($_.getowner().domain)}}, ExecutablePath, CSName
                }#end scriptblock
                $procJobs += Start-Job -ScriptBlock $sblock -ArgumentList $comp -Name "Enum-ProcessWMI-$comp"
                $i++
                if (($i % 5) -eq 0){
                    Write-Output "5 jobs started, waiting for them to finish"
                    $doneJobs = @(Wait-Job -job $procJobs -Timeout 60)
            
                    Write-Output "Processing Jobs"
                    
                    foreach ($j in $doneJobs){
                        $process = Receive-Job $j
                        if ($j.state -eq "Completed"){
                            foreach($p in $process){
                                $props = @{
                                    'ComputerName' = $p.CSName;
                                    'SessionID' = $p.SessionId;
                                    'Name' = $p.Name;
                                    'Path' = $p.ExecutablePath;
                                    'CreationDate' = $p.CreationDate;
                                    'PId' = $p.ProcessId;
                                    'PPID' = $p.ParentProcessId;
                                    'CommandLine' = $p.CommandLine;
                                    'MemoryUse' = "$($p.VM / 1024 / 1024) MB.";
                                    'User' = $p.User;
                                    'Domain' = $p.Domain;                    
                                }
                                $obj = New-Object -TypeName PSObject -Property $props
                                $customProcList += $obj
                            }#end foreach
                        }#end if
                    }#end foreach
                    Remove-Job $procJobs
                    $procJobs = @()
                }#end if $i % 5
                
            }#end foreach
            Write-Output "Waiting for $i jobs to finish"
            if($procJobs.Length -gt 0){
                $doneJobs = @(Wait-Job -job $procJobs -Timeout 60)
                
                Write-Output "Processing Jobs"
                
                foreach ($j in $doneJobs){
                    $process = Receive-Job $j
                    if ($j.state -eq "Completed"){
                        foreach($p in $process){
                            $props = @{
                                'ComputerName' = $p.CSName;
                                'SessionID' = $p.SessionId;
                                'Name' = $p.Name;
                                'Path' = $p.ExecutablePath;
                                'CreationDate' = $p.CreationDate;
                                'PId' = $p.ProcessId;
                                'PPID' = $p.ParentProcessId;
                                'CommandLine' = $p.CommandLine;
                                'MemoryUse' = "$($p.VM / 1024 / 1024) MB.";
                                'User' = $p.User;
                                'Domain' = $p.Domain;                    
                            }
                            $obj = New-Object -TypeName PSObject -Property $props
                            $customProcList += $obj
                        }#end foreach
                    }#end if
                }#end foreach
                
                Write-Output "Clearing Jobs"
                Remove-Job $donejobs
            }
            #Check to see if Whitelist Hashtable exists before performing lookups
            if($CSV){
                Write-Output "Calling OutCustom with outfile=$outputFileName"
                OutCustom -object $customProcList -CSV -outputFile $outputFileName
            }else{
                OutCustom -object $customProcList
            }
        }catch{
                Write-Output "Something happened, I'm not sure what"
        }
    } #End PROCESS
    END{
        Clear-Variable -Name customProcList
    } #End END   
}

