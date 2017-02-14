function Enum-ProcessWMI{
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
		[switch]$CSV, 
		[Parameter(Mandatory=$True)]
		[string[]]$ComputerName, 
		[Parameter()]
		[switch]$TXT
    ) #End Param
    BEGIN{
        #Write-Output "Reading config file"
        #ReadConfigFile -configFile $ConfigFileName
        
        $ErrorFileNameH,$ErrorFileNameV,$outputFileName = SetOutandErrorFiles -outputFileName "Enum-ProcessWMI" -csv $CSV -txt $TXT
        #$global:error.clear()
        
    } #End BEGIN
    PROCESS{
        $ComputerArray = ValidateTargets($ComputerName)
        try{
            $customProcList = @()
            #$procJobs = @()
            #Write-Output "Starting Jobs"
            #$i=1
            
            $process = Get-WmiObject win32_process  -EnableAllPrivileges -ComputerName $ComputerArray |
                        select Name, VM, ProcessId, ParentProcessId, CommandLine, CreationDate, SessionId, @{l='User';e={($_.getowner().user)}}, @{l='Domain';e={($_.getowner().domain)}}, ExecutablePath, CSName
            
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
            }
            
            #Check to see if Whitelist Hashtable exists before performing lookups
            if($CSV){
                #Write-Output "Calling OutCustom with outfile=$outputFileName"
                OutCustom -object $customProcList -CSV $CSV -outputFile $outputFileName
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

