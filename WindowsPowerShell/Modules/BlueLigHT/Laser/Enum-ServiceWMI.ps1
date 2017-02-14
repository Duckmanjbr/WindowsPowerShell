function Enum-ServiceWMI{
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
Author/Contributor: Rickert

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
        $ErrorFileNameH,$ErrorFileNameV,$outputFileName = SetOutandErrorFiles -outputFileName "Enum-ServiceWMI" -csv $CSV -txt $TXT
        #$global:error.clear()
    } #End BEGIN
    PROCESS{
        $ComputerArray = ValidateTargets($ComputerName)
		try{
			$customServiceList = @()
			$service = Get-WmiObject win32_service -ComputerName $ComputerArray | Select Name, PathName, ServiceType, State, ProcessId, DisplayName
			foreach($s in $service){
				$props = @{
                        'Name' = $s.Name;
                        'CommandLine' = $s.PathName;
                        #'Path' = $path;
                        'Type' = $s.ServiceType;
                        'State' = $s.State;
                        'ProcessId' = $s.ProcessId;
                        'DisplayName' = $s.DisplayName;
						#Changed 14 May 2014 to display parent process - Maffuccio
                        #'ParentProcess' = (Get-Process -Id $s.ProcessId).name;
                }
				$obj = New-Object -TypeName PSObject -Property $props
				$customServiceList += $obj
			}
			
			if($CSV) {
				OutCustom -object $customServiceList -CSV $CSV
			}else{
				OutCustom -object $customServiceList
			}
		}catch{
			Write-Output "Something happened while processing $ComputerArray"
		}
        
    } #End PROCESS
    END{
        Clear-Variable -Name obj,customServiceList
    } #End END   
} #End Enum-Service function

