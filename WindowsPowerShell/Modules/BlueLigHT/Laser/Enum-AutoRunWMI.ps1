function Enum-AutoRunWMI{
<#
.SYNOPSIS


.DESCRIPTION


.PARAMETER CSV 

.PARAMETER ComputerName 

.PARAMETER TXT 

.PARAMETER Ping 


.EXAMPLE
PS C:\> Enum-Service

.NOTES
Version: 1.0
Author/Contributor: Jared Atkinson/ Christopher Maffuccio

.INPUTS

.OUTPUTS

.LINK
#>
    [CmdLetBinding(SupportsShouldProcess=$False)]
    Param(
        [Parameter()]
		[switch]$CSV, 
		[Parameter(Mandatory=$True)]
		[string[]]$ComputerName, 
		[Parameter()]
		[switch]$TXT, 
		[Parameter()]
		[switch]$Ping
    ) #End Param
    BEGIN{
        $ErrorFileNameH,$ErrorFileNameV,$outputFileName = SetOutandErrorFiles -outputFileName "Enum-AutorunWMI" -csv $CSV -txt $TXT
        #$global:error.clear()
    } #End BEGIN
    PROCESS{
        $ComputerArray = ValidateTargets($ComputerName)
		try{
			$customStartList = @()
			$start = Get-WmiObject win32_startupcommand -ComputerName $ComputerArray | Select Caption, Command, Description, Location, Name, User
			foreach($s in $start){
				$props = @{
                        'Caption' = $s.Caption;
						'Command' = $s.Command;
						'Description' = $s.Description;
						'Location' = $s.Location;
						'Name' = $s.Name;
						'User' = $s.User;
                }
				$obj = New-Object -TypeName PSObject -Property $props
				$customStartList += $obj
			}
			#Check to see if Whitelist Hashtable exists before performing lookups
			if($CSV) {
				OutCustom -object $customStartList -CSV $CSV -outputFile $outputFileName
			}else{
				OutCustom -object $customStartList
			}
		}catch{
			Write-Output "Something happened while processing $ComputerArray"
		}
        
    } #End PROCESS
    END{
        Clear-Variable -Name obj,customStartList
    } #End END   
} #End Enum-AutoRun function

