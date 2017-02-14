function Invoke-HostScans {
[CmdletBinding(SupportsShouldProcess = $false)]
    Param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String[]]$TargetList,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$OutputDirectory
    )

    if (!$PSBoundParameters['OutputDirectory']) { $OutputDirectory = "$BlueLigHT\out" }
    try { $OutputDirectory = (Resolve-Path $OutputDirectory).Path }
    catch { break }

    Write-Verbose "Running Enum-Process..."
    Enum-Process -TargetList $TargetList -Hash SHA1 -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Enum-Process.csv") 
    [GC]::Collect()

    Write-Verbose "Running Enum-Driver..."
    Enum-Driver -TargetList $TargetList -Hash SHA1 -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Enum-Driver.csv")  
    [GC]::Collect()

    Write-Verbose "Running Enum-Service..."
    Enum-Service -TargetList $TargetList -Hash SHA1 -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Enum-Service.csv")  
    [GC]::Collect()

    Write-Verbose "Running Enum-Pipe..."
    Enum-Pipe -TargetList $TargetList -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Enum-Pipe.csv")
    [GC]::Collect()

    Write-Verbose "Running Enum-AutoRun..."
    Enum-AutoRun -TargetList $TargetList -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Enum-AutoRun.csv") 
    [GC]::Collect()

    Write-Verbose "Running Enum-Logon..."
    Enum-Logon -TargetList $TargetList -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Enum-Logon.csv")
    [GC]::Collect()

    Write-Verbose "Running Get-Netstat..."
    Get-Netstat -TargetList $TargetList -CSV ("$OutputDirectory\$(Get-Date -Format yyyyMMdd_hhmmss)" + "_Get-Netstat.csv") 
    [GC]::Collect()

    Write-Verbose "7 Scans ran, number of hosts scanned: $($TargetList.Count)"
}