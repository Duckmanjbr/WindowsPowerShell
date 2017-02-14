function Invoke-HostScansWmi {
[CmdletBinding(SupportsShouldProcess = $false)]
    Param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String[]]$TargetList = 'localhost',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$OutputDirectory
    )

    if (!$PSBoundParameters['OutputDirectory']) { $OutputDirectory = "$BlueLigHT\out" }
    try { $OutputDirectory = (Resolve-Path $OutputDirectory).Path }
    catch { break }
    
    Write-Verbose "Running Enum-ProcessWmi..."
    Enum-ProcessWmi -TargetList $TargetList -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Enum-ProcessWmi.csv") 
    [GC]::Collect()

    Write-Verbose "Running Enum-DriverWmi..."
    Enum-DriverWmi -TargetList $TargetList -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Enum-DriverWmi.csv")  
    [GC]::Collect()

    Write-Verbose "Running Enum-ServiceWmi..."
    Enum-ServiceWmi -TargetList $TargetList -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Enum-ServiceWmi.csv")  
    [GC]::Collect()

    Write-Verbose "Running Enum-AutoRunWmi..."
    Enum-AutoRunWmi -TargetList $TargetList -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Enum-AutoRunWmi.csv") 
    [GC]::Collect()
    
    Write-Verbose "Running Get-WmiEventFilter..."
    Get-WmiEventFilter -TargetList $TargetList -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Get-WmiEventFilter.csv") 
    [GC]::Collect()

    Write-Verbose "Running Get-SchTasksRpc..."
    Get-SchTasksRpc -TargetList $TargetList -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Get-SchTasksRpc.csv") 
    [GC]::Collect()

    Write-Verbose "6 Scans ran, number of hosts scanned: $($TargetList.Count)"
}
