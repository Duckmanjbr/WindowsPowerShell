function Search-FileHash {
<#
.SYNOPSIS
Searches for specified file hash(es) on the file system of remote machines.

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

.PARAMETER HashList 
Supply an array of hashes to search for.

.PARAMETER Hash 
Specify the hash algorithm to use, default is SHA1. MD5 may not be supported on some systems due to FIPS policy.

.PARAMETER Directory
Specify the directory where the search begins.

.PARAMETER Recurse
Spefifies that all subdirectories should also be searched.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example will take a long time, trying to hash every file on the system.

PS C:\> Search-FileHash -TargetList $Targs -HashList (Get-Content C:\badguytoolhashes.txt) -Directory C:\ -Recurse -TXT C:\pathto\output.txt

.EXAMPLE
The following example searches the users directory, output is written to a comma-separated file (csv).

PS C:\> Search-FileHash -TargetList $Targs -HashList (Get-Content C:\SuperEvilHashes.txt) -Directory C:\Users -Recurse -CSV C:\pathto\output.csv

.NOTES
Version: 0.1
Author : RBOT

.INPUTS

.OUTPUTS

.LINK
#>
    [CmdletBinding(SupportsShouldProcess=$false)] 
    Param(		
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$TargetList,

        [Parameter()]
        [Switch]$ConfirmTargets,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int]$ThrottleLimit = 10,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]$HashList,

        [Parameter()]
        [ValidateSet('MD5','SHA1','SHA256','SHA384','SHA512')]
        [String]$Hash = 'SHA1',
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
		[String]$Directory, 
		        
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
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Search-FileHash
        
    $Global:Error.Clear()
         
    Confirm-Hash -HashList $HashList -Hash $Hash

    if($HashList.Count -gt 1) {
        $RemoteScriptblock = {
            param([String]$Directory, [Bool]$Recurse, [String[]]$HashList, [String]$Hash)
                    
                if (!(Test-Path -Path $Directory)) {
                    Write-Error "$Directory does not exist on $env:COMPUTERNAME"
                    break
                }

                switch ($Hash) {
                       'MD5' { $CryptoProvider = New-Object Security.Cryptography.MD5CryptoServiceProvider; break }
                      'SHA1' { $CryptoProvider = New-Object Security.Cryptography.SHA1CryptoServiceProvider; break }
                    'SHA256' { $CryptoProvider = New-Object Security.Cryptography.SHA256CryptoServiceProvider; break }
                    'SHA384' { $CryptoProvider = New-Object Security.Cryptography.SHA384CryptoServiceProvider; break }
                    'SHA512' { $CryptoProvider = New-Object Security.Cryptography.SHA512CryptoServiceProvider; break }
                }

                if ($Recurse) {                                                                                                                                                                
                    $FilePaths = Invoke-Expression "cmd.exe /c dir /b /s /ah /as /a-d $Directory 2>&1"
                    $HashTable = New-Object Hashtable

                    foreach ($Path in $FilePaths) { 
                        try { $FileHash = [BitConverter]::ToString($CryptoProvider.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '') }
                        catch [Management.Automation.MethodInvocationException] { 
                            Write-Warning "Unable to compute $Hash for $Path" 
                            continue
                        }
                        $HashTable.Add($Path,$FileHash)                          
                    }

                    foreach ($Hash in $HashList) {
                        if($HashTable.ContainsValue($Hash.ToUpper())) {
                            foreach ($Key in ($HashTable.GetEnumerator() | Where-Object { $_.Value -eq $Hash.ToUpper() })) { 
                                $Properties = @{
                                    $Hash = $Hash.ToUpper()
                                    'FilePath' = $Key.name 
                                }
                                New-Object -TypeName PSObject -Property $Properties
                            }
                        }
                    } 
                }
                else {                                                                                                                                                                
                    $FilePaths = Get-ChildItem -Force $Directory | Where-Object { $_.Mode -notlike "d*" } | Select-Object -ExpandProperty FullName
                    $HashTable = New-Object Hashtable

                    foreach ($Path in $FilePaths) { 
                        try { $FileHash = [BitConverter]::ToString($CryptoProvider.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '') }
                        catch [Management.Automation.MethodInvocationException] { 
                            Write-Warning "Unable to compute $Hash for $Path" 
                            continue
                        }
                        $HashTable.Add($Path,$FileHash)                          
                    }

                    foreach ($Hash in $HashList) {
                        if($HashTable.ContainsValue($Hash.ToUpper())) {
                            foreach ($Key in ($HashTable.GetEnumerator() | Where-Object { $_.Value -eq $Hash.ToUpper() })) { 
                                $Properties = @{
                                    $Hash = $Hash.ToUpper()
                                    'FilePath' = $Key.name 
                                }
                                New-Object -TypeName PSObject -Property $Properties
                            }
                        }
                    } 
                }
        }#end RemoteScriptblock
    }        
    else {
        $RemoteScriptblock = {
            param([String]$Directory, [Bool]$Recurse, [String[]]$HashList, [String]$Hash)
                    
                [void](Get-ChildItem $Directory -ErrorAction Stop)

                switch ($Hash) {
                       'MD5' { $CryptoProvider = New-Object Security.Cryptography.MD5CryptoServiceProvider; break }
                      'SHA1' { $CryptoProvider = New-Object Security.Cryptography.SHA1CryptoServiceProvider; break }
                    'SHA256' { $CryptoProvider = New-Object Security.Cryptography.SHA256CryptoServiceProvider; break }
                    'SHA384' { $CryptoProvider = New-Object Security.Cryptography.SHA384CryptoServiceProvider; break }
                    'SHA512' { $CryptoProvider = New-Object Security.Cryptography.SHA512CryptoServiceProvider; break }
                }

                if ($Recurse) {                                                                                                                                                                
                    $FilePaths = Invoke-Expression "cmd.exe /c dir /b /s /ah /as /a-d $Directory 2>&1"
                    $HashTable = New-Object Hashtable

                    foreach ($Path in $FilePaths) { 
                        try { $FileHash = [BitConverter]::ToString($CryptoProvider.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '') }
                        catch [Management.Automation.MethodInvocationException] { 
                            Write-Warning "Unable to compute $Hash for $Path" 
                            continue
                        }
                        $HashTable.Add($FileHash,$Path)                          
                    }
                         
                    if($HashTable.ContainsValue(($HashList[0].ToUpper()))) {
                        foreach ($Key in ($HashTable.GetEnumerator() | Where-Object { $_.Value -eq $HashList[0].ToUpper() })) { 
                            $Properties = @{
                                $Hash = $HashList[0].ToUpper()
                                'FilePath' = $Key.name 
                            }
                            New-Object -TypeName PSObject -Property $Properties
                        }
                    }
                            
                }
                else {                                                                                                                                                                
                    $FilePaths = Get-ChildItem -Force $Directory | Where-Object { $_.Mode -notlike "d*" } | Select-Object -ExpandProperty FullName
                    $HashTable = New-Object Hashtable

                    foreach ($Path in $FilePaths) { 
                        try { $FileHash = [BitConverter]::ToString($CryptoProvider.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '') }
                        catch [Management.Automation.MethodInvocationException] { 
                            Write-Warning "Unable to compute $Hash for $Path" 
                            continue
                        }
                        $HashTable.Add($Path,$FileHash)                          
                    }
                         
                    if($HashTable.ContainsValue(($HashList[0].ToUpper()))) {
                        foreach ($Key in ($HashTable.GetEnumerator() | Where-Object { $_.Value -eq $HashList[0].ToUpper() })) { 
                            $Properties = @{
                                $Hash = $HashList[0].ToUpper()
                                'FilePath' = $Key.name 
                            }
                            New-Object -TypeName PSObject -Property $Properties
                        }
                    }
                }
        }#end RemoteScriptblock
    }
        
    if ($PSBoundParameters['TargetList']) {
        if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }        
        
        $ReturnedObjects = New-Object Collections.ArrayList
        $HostsRemaining = [Collections.ArrayList]$TargetList
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)

        Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -ArgumentList @($Directory, $Recurse, $HashList, $Hash) -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit |
        ForEach-Object { 
            if ($HostsRemaining -contains $_.PSComputerName) { $HostsRemaining.Remove($_.PSComputerName) }
            [void]$ReturnedObjects.Add($_)
            Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)
        }
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Completed" -Completed
    }
    else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($Directory, $Recurse, $HashList, $Hash) }

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