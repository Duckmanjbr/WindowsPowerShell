function Enum-OSWMI{
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
Author : Jared "Huck" Atkinson

.INPUTS

.OUTPUTS

.LINK
#>
    [CmdLetBinding(SupportsShouldProcess=$False)]
    Param(
        [Parameter()]
        [string]$ConfigFileName = "$dirConfigPath" + 'Enum-OSWMI.ini',
        [Parameter()]
		[string[]]$ComputerName, 
		[Parameter()]
		[switch]$Ping
    ) #End Param
    BEGIN{
        ReadConfigFile -configFile $ConfigFileName
        SetOutandErrorFile
    } #End BEGIN
    PROCESS{
        $ComputerArray = ValidateTargets($ComputerName)
		try{
			$OS = Get-WmiObject -Computer $ComputerArray -Class Win32_OperatingSystem
			$7list = @()
			$XPlist = @()
			foreach($O in $OS){
				if($O.caption -like "*Windows 7*") {
					$7list += $O
				} else {
					$XPlist += $O
				}
			}
			#Check to see if Whitelist Hashtable exists before performing lookups
			Out-Custom -object $7list
			Out-Custom -object $xplist
		}catch{
			Write-Output "Something happened while processing OS list $ComputerArray"
		}
    } #End PROCESS
    END{
        Clear-Variable -Name obj,customOSList
    } #End END   
} #End Enum-Service funcion

