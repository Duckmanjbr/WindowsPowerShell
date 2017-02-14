function Enum-DriverWMI{
<#
.SYNOPSIS


.DESCRIPTION


.PARAMETER CSV 

.PARAMETER ComputerName 

.PARAMETER TXT 

.PARAMETER Ping 


.EXAMPLE
PS C:\> Enum-Driver

.NOTES
Version: 3.0
Author : Ryan "Candy" Rickert

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
        $ErrorFileNameH,$ErrorFileNameV,$outputFileName = SetOutandErrorFiles -outputFileName "Enum-DriverWMI" -csv $CSV -txt $TXT
        #$global:error.clear()
    } #End BEGIN
    PROCESS{
        $ComputerArray = ValidateTargets($ComputerName)
		try{
			$customDriveList = @()
			$driver = Get-WmiObject win32_systemdriver -ComputerName $ComputerArray | Select Name, PathName, Caption
			foreach($d in $driver){
				$props = @{
					'Name' = $d.Name;
					'Path' = $d.PathName;
					'Caption' = $d.Caption;
					'ScanType' = 'Driver'
				}
				$obj = New-Object -TypeName PSObject -Property $props
				$customDriveList += $obj
			}
			#Check to see if Whitelist Hashtable exists before performing lookups
			if($CSV) {
				OutCustom -object $customDriveList -CSV $CSV
			}else{
				OutCustom -object $customDriveList
			}
		}catch{
			Write-Output "Something happened while processing $ComputerArray"
		}
    } #End PROCESS
    END{
        Clear-Variable -Name obj,customDriveList
    } #End END   
} #End Enum-Service funcion

