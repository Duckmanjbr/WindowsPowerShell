function Enum-Process {
<#
.SYNOPSIS
Gathers information about processes on remote systems.

.DESCRIPTION
This commandlet uses Windows Remote Management to collect Windows Process information from remote systems.

Specify computers by name or IP address.

Use the -Verbose switch to see detailed information.

.PARAMETER TargetList 
Specify host(s) to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections.

.PARAMETER WhiteList 
Specify path to Whitelist file to compare retrieved data against.

.PARAMETER Hash 
Specify the hash algorithm to use, default is SHA1. MD5 may not be supported on some systems due to FIPS policy.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example gets a list of computers from the pipeline and sends output to a csv file.

PS C:\> New-TargetList -Cidr 10.10.20.0/24 | Enum-Service -CSV C:\pathto\output.csv

.EXAMPLE
The following example specifies a computer and sends output to a csv file.

PS C:\> Enum-Service -TargetList Server01 -CSV C:\pathto\output.csv

.NOTES
Version: 3.1.0915
Changes for Splunk compatability approved by Lt. Rickert 16 Mar 15
Re-Written by RBOT Sep 15

.INPUTS

.OUTPUTS

.LINK
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
        [ValidateNotNullOrEmpty()]
        [String]$WhiteList,
        
        [Parameter()]
        [ValidateSet('MD5','SHA1','SHA256','SHA384','SHA512')]
        [String]$Hash = 'SHA1',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$CSV,
		
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TXT
    ) #End Param

    if($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Enum-Process
        
    $Global:Error.Clear()

    $RemoteScriptblock = {
        Param([String]$Hash)
        
        $StartTime = [DateTime]::Now

        switch ($Hash) {
               'MD5' { try { $CryptoProvider = New-Object System.Security.Cryptography.MD5CryptoServiceProvider } catch { $NoCrypto = $true } }
              'SHA1' { try { $CryptoProvider = New-Object System.Security.Cryptography.SHA1CryptoServiceProvider } catch { $NoCrypto = $true } }
            'SHA256' { try { $CryptoProvider = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider } catch { $NoCrypto = $true } }
            'SHA384' { try { $CryptoProvider = New-Object System.Security.Cryptography.SHA384CryptoServiceProvider } catch { $NoCrypto = $true } }
            'SHA512' { try { $CryptoProvider = New-Object System.Security.Cryptography.SHA512CryptoServiceProvider } catch { $NoCrypto = $true } }
        }
 
        $Processes = Get-WmiObject Win32_Process

        foreach ($Process in $Processes) {
            $ProcessHash = "Error While Computing Hash" #used to prevent previous hash being the value if hash computation error occurs

            if ($Process.ExecutablePath) {
                $Path = $Process.ExecutablePath
                $Data = [IO.File]::ReadAllBytes($Path)
                if ($NoCrypto) { $ProcessHash = "No Crypto" }
                else { $ProcessHash = [BitConverter]::ToString($CryptoProvider.ComputeHash($Data)).Replace('-', '') }      
            }
            else {
                #Perform secondary path check
                $Proc2 = Get-Process -Id $Process.ProcessId 

                if ($Proc2.Path) { 
                    $Path = $Proc2.Path
                    $Data = [IO.File]::ReadAllBytes($Path)
                    if ($NoCrypto) { $ProcessHash = "No Crypto" }
                    else { $ProcessHash = [BitConverter]::ToString($CryptoProvider.ComputeHash($Data)).Replace('-', '') } 
                }
                else { $ProcessHash = "NoPath" }
            }

            $Owner = $Process.GetOwner()
          
            #Getting Parent Process info
            $ParentProcess = $Processes | Where-Object { $_.ProcessId -eq $Process.ParentProcessId }
            
            try { $ParentStartTime = [Management.ManagementDateTimeConverter]::ToDateTime($ParentProcess.CreationDate) }
            catch { $ParentStartTime = $ParentProcess.CreationDate }
            
            try { $StartTime = [Management.ManagementDateTimeConverter]::ToDateTime($Process.CreationDate) }
            catch { $StartTime = $Process.CreationDate }

            $IsTrueParent = $StartTime -gt $ParentStartTime

            $obj = New-Object -TypeName PSObject

            $obj | Add-Member -MemberType NoteProperty -Name TIME -Value $StartTime 
            $obj | Add-Member -MemberType NoteProperty -Name NAME -Value $Process.Name
            $obj | Add-Member -MemberType NoteProperty -Name PATH -Value $Path
            $obj | Add-Member -MemberType NoteProperty -Name PROCSTARTTIME -Value $StartTime
            $obj | Add-Member -MemberType NoteProperty -Name PID -Value $Process.ProcessId
            $obj | Add-Member -MemberType NoteProperty -Name PRIORITY -Value $Process.Priority                 
            $obj | Add-Member -MemberType NoteProperty -Name PPID -Value $Process.ParentProcessId
            $obj | Add-Member -MemberType NoteProperty -Name PARENTNAME -Value $ParentProcess.Name
            $obj | Add-Member -MemberType NoteProperty -Name PARENTSTARTTIME -Value $ParentStartTime 
            $obj | Add-Member -MemberType NoteProperty -Name TRUEPARENT -Value $IsTrueParent
            $obj | Add-Member -MemberType NoteProperty -Name COMMANDLINE -Value $Process.CommandLine
            $obj | Add-Member -MemberType NoteProperty -Name USER -Value $Owner.User
            $obj | Add-Member -MemberType NoteProperty -Name DOMAIN -Value $Owner.Domain
            $obj | Add-Member -MemberType NoteProperty -Name $Hash -Value $ProcessHash
            $Obj | Add-Member -MemberType NoteProperty -Name VM -Value "$("{0:N2}" -f ($Process.VM/1024/1024))MB"
            $obj | Add-Member -MemberType NoteProperty -Name ScanType -Value 'Process'
            Write-Output $obj
        }
    }#end RemoteScriptblock

    if ($PSBoundParameters['TargetList']) {
        if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }        
        
        $ReturnedObjects = New-Object Collections.ArrayList
        $HostsRemaining = [Collections.ArrayList]$TargetList
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)

        Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -ArgumentList @($Hash) -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit |
        ForEach-Object { 
            if ($HostsRemaining -contains $_.PSComputerName) { $HostsRemaining.Remove($_.PSComputerName) }
            [void]$ReturnedObjects.Add($_)
            Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)
        }
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Completed" -Completed
    }
    else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($Hash) }

    Get-ErrorHost -ErrorFileVerbose $ErrorFileVerbose -ErrorFileHosts $ErrorFileHosts

    #Check to see if Whitelist Hashtable exists before performing lookups
    if ($PSBoundParameters['WhiteList']) {
        New-WhiteList -CsvFile $WhiteList -VariableName "ProcessWhiteList"
    }
    if ($ProcessWhitelist -and $ReturnedObjects) {
        foreach ($Process in $ReturnedObjects) {
            
            #Check the hash table for the hash of the file
            if ($Process.$Hash) { $wl = $ProcessWhitelist.ContainsKey($Process.$Hash) }
            else{ $wl = $false }

            #Check to see if $wl has a value in it,If wl as a value then the SHA1 is in the whitelist 
            if ($wl) { Add-Member -InputObject $Process -MemberType NoteProperty -Name WhiteListed -Value "Yes" -Force }
            else { Add-Member -InputObject $Process -MemberType NoteProperty -Name WhiteListed -Value "No" -Force }
        }
    }
    else { Write-Verbose "Whitelist Hashtable not created - Comparison not done" }
    
    if ($ReturnedObjects -ne $null) {
        if ($PSBoundParameters['CSV']) { $ReturnedObjects | Export-Csv -Path $OutputFilePath -Append -NoTypeInformation -ErrorAction SilentlyContinue }
        elseif ($PSBoundParameters['TXT']) { $ReturnedObjects | Out-File -FilePath $OutputFilePath -Append -ErrorAction SilentlyContinue }
        else { Write-Output $ReturnedObjects }
    }

    [GC]::Collect()
    $ScriptTime.Stop()
    Write-Verbose "Done, execution time: $($ScriptTime.Elapsed)"
}