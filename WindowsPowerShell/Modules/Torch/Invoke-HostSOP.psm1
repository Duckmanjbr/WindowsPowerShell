function Invoke-HostSOP {
<#
.SYNOPSIS

.DESCRIPTION
This script executes the Host SOP

.NOTES

Output Files:
targs_WINRM_already_on.txt            All hosts that already have WinRM properly configured
targs_WINRM_need_started.txt          All hosts that are alive and do *NOT* have WinRM started
targs_WINRM_successfully_started.txt  All hosts that have have had WinRM enabled and started during script execution
targs_WINRM_Failed_to_start           All hosts that this script has attempted to start WinRM on and has failed
targs_PsExec_Failed.txt               All hosts that PsExec failed to run winrmdeploy.cmd script on
targs_WINRM_enabled.txt               All hosts that can have WinRM commands run on them
#>
    Param(
        [Parameter()]
	    [String[]]$TargetList,

        [Parameter()]
	    [Switch]$DeployWinRm,

        [Parameter()]
	    [Switch]$Scan
    ) #End Param

    #region HELPERS
    function local:Sort-WinRmEnabledFile {
        $WinRmDeployed = Get-Content $BlueLigHT\Deployment\out\master_WINRM_enabled.txt -ErrorAction SilentlyContinue
        $WinRmDeployed = $WinRmDeployed | Sort-Object -Unique
        $WinRmDeployed | Out-File $BlueLigHT\Deployment\out\master_WINRM_enabled.txt
    }
    function local:Write-HostSopSummary {
        Param(
            [Parameter()]
	        [Int]$Count
        )
               $NeedWinRm = Get-Content $BlueLigHT\Deployment\out\targs_WINRM_need_started.txt -ErrorAction SilentlyContinue
            $WinRmStarted = Get-Content $BlueLigHT\Deployment\out\targs_WINRM_successfully_started.txt -ErrorAction SilentlyContinue
             $WinRmFailed = Get-Content $BlueLigHT\Deployment\out\targs_WINRM_Failed_to_start.txt -ErrorAction SilentlyContinue
            $WinRmEnabled = Get-Content $BlueLigHT\out\HostSOP\targs_WINRM_enabled.txt -ErrorAction SilentlyContinue
    
            Write-Output "Number of alive hosts: $Count`n"
            Write-Output "Number of hosts that needed WinRM enabled: $($NeedWinRm.Count)`n"
            Write-Output "Number of hosts that WinRM successfully started on: $($WinRmStarted.Count)`n"
            Write-Output "Number of hosts where WinRM failed to start: $($WinRmFailed.Count)`n"
            Write-Output "Number of hosts with WinRM enabled: $($WinRmEnabled.Count)`n"
    }
    #endregion HELPERS

    #Verify winrm is running on the box, if its not try and turn in on
    Write-Host -NoNewline "**********************" -ForegroundColor Green
    Write-Host -NoNewLine " Checking WinRm " -ForegroundColor Yellow
    Write-Host "**********************" -ForegroundColor Green
    if ($DeployWinRm.IsPresent) { 
        $Configuration = Confirm-WinRmEnabled -TargetList $TargetList -Deploy -Verbose
        $Configuration.WinRmOn      | Out-File -Append -FilePath $BlueLigHT\out\HostSOP\targs_WINRM_enabled.txt
        $Configuration.WinRmOn      | Out-File -Append -FilePath $BlueLigHT\Deployment\out\targs_WINRM_already_on.txt
        $Configuration.WinRmOff     | Out-File -Append -FilePath $BlueLigHT\Deployment\out\targs_WINRM_need_started.txt
        $Configuration.WinRmEnabled | Out-File -Append -FilePath $BlueLigHT\Deployment\out\targs_WINRM_successfully_started.txt
        $Configuration.WinRmEnabled | Out-File -Append -FilePath $BlueLigHT\out\HostSOP\targs_WINRM_enabled.txt
        $Configuration.WinRmEnabled | Out-File -Append -FilePath $BlueLigHT\Deployment\out\master_WINRM_enabled.txt
        $Configuration.WinRmFailed  | Out-File -Append -FilePath $BlueLigHT\Deployment\out\targs_WINRM_Failed_to_start.txt
        $Configuration.WinRmFailed  | Out-File -Append -FilePath $BlueLigHT\Deployment\out\targs_WINRM_need_started.txt
        $Configuration.PsExecFailed | Out-File -Append -FilePath $BlueLigHT\Deployment\out\targs_PsExec_Failed_to_push_script.txt
        $Configuration.PsExecFailed | Out-File -Append -FilePath $BlueLigHT\Deployment\out\targs_WINRM_need_started.txt
    }
    else { 
        $Configuration = Confirm-WinRmEnabled -TargetList $TargetList -Verbose
        $Configuration.WinRmOn  | Out-File -Append -FilePath $BlueLigHT\out\HostSOP\targs_WINRM_enabled.txt
        $Configuration.WinRmOn  | Out-File -Append -FilePath $BlueLigHT\Deployment\out\targs_WINRM_already_on.txt
        $Configuration.WinRmOff | Out-File -Append -FilePath $BlueLigHT\Deployment\out\targs_WINRM_need_started.txt
    }

    Sort-WinRmEnabledFile    #Update Master File
  
    if ($Scan.IsPresent) #Execute the host scans
    {
        Write-Host -NoNewline "**********************" -ForegroundColor Green
        Write-Host -NoNewLine " Scanning Hosts " -ForegroundColor Yellow
        Write-Host "**********************" -ForegroundColor Green
        Invoke-HostScans -TargetList $Configuration.WinRmOn -Verbose
    
        Write-Host -NoNewline "*********************" -ForegroundColor Green
        Write-Host -NoNewLine " Host SOP Results " -ForegroundColor Yellow
        Write-Host "*********************" -ForegroundColor Green
        $HostSopSummary = Write-HostSopSummary -Count $Configuration.WinRmOn.Count

        $HostSopSummary | Out-File -FilePath ("$BlueLigHT\out\HostSOP\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_HostSopSummary.txt")
        Write-Host $HostSopSummary
    }

    #archive the output of WinRM status files
    $archiveFilename = "$BlueLigHT\Deployment\Archive\{0:yyyyMMdd_HHmmss}_targs_WINRM_need_started.txt" -f (Get-Date)
    Copy-Item $BlueLigHT\Deployment\out\targs_WINRM_need_started.txt $archiveFilename
    
    $archiveFilename = "$BlueLigHT\Deployment\Archive\{0:yyyyMMdd_HHmmss}_targs_WINRM_Failed_to_start.txt" -f (Get-Date)
    Copy-Item $BlueLigHT\Deployment\out\targs_WINRM_Failed_to_start.txt $archiveFilename
    
    $archiveFilename = "$BlueLigHT\Deployment\Archive\{0:yyyyMMdd_HHmmss}_targs_WINRM_enabled.txt" -f (Get-Date)
    Copy-Item $BlueLigHT\out\HostSOP\targs_WINRM_enabled.txt $archiveFilename
}