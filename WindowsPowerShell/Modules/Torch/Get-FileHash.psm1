function Get-FileHash {
<#
.SYNOPSIS
Retrieves hash for specified files from the file system of remote machines.

.DESCRIPTION
This cmdlet uses Windows Remote Management to collect file hash information from remote systems.

Specify computers by name or IP address.

Use the -Verbose switch to see detailed information.

.PARAMETER TargetList 
Specify host(s) to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections.

.PARAMETER Hash 
Specify the hash algorithm to use, default is SHA1. MD5 may not be supported on some systems due to FIPS policy.

.PARAMETER Directory
The directory where the search begins.

.PARAMETER File 
File to search for.

.PARAMETER Recurse
Enables searching through the file system recursively.

.EXAMPLE
The following example retrieves SHA1 hashes for every accessible file on the C volume of Server01 and writes the output to a text file.

PS C:\> Get-FileHash -TargetList Server01 -HashAlgorithm SHA1 -Directory C:\ -Recurse -TXT -ToFile C:\output.txt

.EXAMPLE
The following example retrieves SHA256 hashes for all accessible files in the C:\ directory of two different computers and writes the output to a comma-separated-value file (csv).

PS C:\> Get-FileHash -TargetList Server01,Server02 -HashAlgorithm SHA256 -Directory C:\ -CSV -ToFile C:\output.csv

.EXAMPLE
The following example recursively searches the C:\Windows\ directory of Server01 for files named "cmd.exe" and returns the SHA1 hash of any files it finds, writing the output to a csv file.

PS C:\> Get-FileHash -TargetList Server01 -HashAlgorithm SHA1 -CSV -ToFile C:\output.csv -Recurse -Directory "c:\windows\" -File cmd.exe

.EXAMPLE
The following example is the same as above except it adds a timeout period of 10 minutes instead of 5.

PS C:\> Get-FileHash -TargetList Server01 -HashAlgorithm SHA1 -CSV -ToFile C:\output.csv -Recurse -Directory "c:\windows\" -File cmd.exe -Timeout 600

.NOTES
Version: 0.1
Author : RBOT

#>
[CmdLetBinding(SupportsShouldProcess = $false)]
    Param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$TargetList,

        [Parameter()]
        [Switch]$ConfirmTargets,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int]$ThrottleLimit = 10,

        [Parameter()]
        [ValidateSet('MD5','SHA1','SHA256','SHA384','SHA512')]
        [String]$Hash = 'SHA1',
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$Directory, 

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$File = "",
		        
        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$CSV,
		
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TXT
    )    
    if($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Get-Netstat
        
    $Global:Error.Clear()

    $RemoteScriptblock = {
        param([String]$Directory, [Bool]$Recurse, [String]$Hash, [String]$File)

            if (![IO.Directory]::Exists($Directory)) { 
                Write-Error "$Directory does not exist!"
                exit
            }

            switch ($Hash) {
                   'MD5' { $CryptoProvider = New-Object Security.Cryptography.MD5CryptoServiceProvider; break }
                  'SHA1' { $CryptoProvider = New-Object Security.Cryptography.SHA1CryptoServiceProvider; break }
                'SHA256' { $CryptoProvider = New-Object Security.Cryptography.SHA256CryptoServiceProvider; break }
                'SHA384' { $CryptoProvider = New-Object Security.Cryptography.SHA384CryptoServiceProvider; break }
                'SHA512' { $CryptoProvider = New-Object Security.Cryptography.SHA512CryptoServiceProvider; break }
            }

            if($Recurse -and ($File -ne "")) {
                $FoundFile = Invoke-Expression "cmd.exe /c dir /b /s /a-l $Directory 2>&1 | findstr /i $File 2>&1"
                foreach ($Path in $FoundFile) 
                { 
                    if(($Path -like "*Application Data\Application Data*") -or ($Path -like "*<<<<*")) { continue } 
                    try { $FileHash = [BitConverter]::ToString($CryptoProvider.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '') }
                    catch [Management.Automation.MethodInvocationException] { $FileHash = "Locked File" }
                    $Properties = @{
                        $Hash = $FileHash
                        'FilePath' = $Path
                    }
                    New-Object -TypeName PSObject -Property $Properties
                }
            }

            elseif($Recurse -and ($File -eq "")) {
                $FilePaths = Invoke-Expression "cmd.exe /c dir /b /s /a-l $Directory 2>&1" 
                $Skipped = 0
                foreach ($Path in $FilePaths) 
                { 
                    if(($Path -like "*Application Data\Application Data*") -or ($Path -like "*<<<<*")) { continue }                       
                    try { $FileHash = [BitConverter]::ToString($CryptoProvider.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '') }
                    catch [Management.Automation.MethodInvocationException] { $FileHash = "Locked File" }
                    $Properties = @{
                        $Hash = $FileHash
                        'FilePath' = $Path
                    }    
                    New-Object -TypeName PSObject -Property $Properties
                }
                Write-Verbose "Skipped $Skipped erroneous paths."
            }
                
            elseif((!$Recurse) -and ($File -ne "")) {
                $FilePaths = Get-ChildItem -Force $Directory | Where-Object { $_.Mode -notlike "d*" } | Select-Object -ExpandProperty FullName | Select-String $File
                foreach ($Path in $FilePaths) 
                { 
                    try { $FileHash = [BitConverter]::ToString($CryptoProvider.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '') }
                    catch [Management.Automation.MethodInvocationException] { $FileHash = "Locked File" }
                    $Properties = @{
                        $Hash = $FileHash
                        'FilePath' = $Path
                    }
                    New-Object -TypeName PSObject -Property $Properties
                }
            }

            elseif((!$Recurse) -and ($File -eq "")) {
                $FilePaths = Get-ChildItem -Force $Directory | Where-Object { $_.Mode -notlike "d*" } | Select-Object -ExpandProperty FullName
                foreach ($Path in $FilePaths) 
                { 
                    try { $FileHash = [BitConverter]::ToString($CryptoProvider.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '') }
                    catch [Management.Automation.MethodInvocationException] { $FileHash = "Locked File" }
                    $Properties = @{
                        $Hash = $FileHash
                        'FilePath' = $Path
                    }
                    New-Object -TypeName PSObject -Property $Properties
                }
            }
    }#end RemoteScriptblock
        
    if ($PSBoundParameters['TargetList']) {
        if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }        
        
        $ReturnedObjects = New-Object Collections.ArrayList
        $HostsRemaining = [Collections.ArrayList]$TargetList
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)

        Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -ArgumentList @($Directory, $Recurse, $Hash, $File) -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit |
        ForEach-Object { 
            if ($HostsRemaining -contains $_.PSComputerName) { $HostsRemaining.Remove($_.PSComputerName) }
            [void]$ReturnedObjects.Add($_)
            Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)
        }
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Completed" -Completed
    }
    else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($Directory, $Recurse, $Hash, $File) }

    Get-ErrorHost -ErrorFileVerbose $ErrorFileVerbose -ErrorFileHosts $ErrorFileHosts

    if ($ReturnedObjects -ne $null) {
        if ($PSBoundParameters['CSV']) { $ReturnedObjects | Export-Csv -Path $OutputFilePath -Append -NoTypeInformation -ErrorAction SilentlyContinue }
        elseif ($PSBoundParameters['TXT']) { $ReturnedObjects | Out-File -FilePath $OutputFilePath -Append -ErrorAction SilentlyContinue }
        else { Write-Output $ReturnedObjects }
    }

    [GC]::Collect()
    $ScriptTime.Stop()
    Write-Verbose "Done, execution time: $($ScriptTime.Elapsed)"
}