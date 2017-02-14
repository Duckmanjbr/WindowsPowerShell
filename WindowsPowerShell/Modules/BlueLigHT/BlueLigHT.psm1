function Send-PingAsync {
[CmdLetBinding()]
     Param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]$ComputerName,
        
        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [Int32]$Timeout = 250
    ) #End Param

    $Pings = New-Object Collections.Arraylist

    foreach ($Computer in $ComputerName) {
        [void]$Pings.Add((New-Object Net.NetworkInformation.Ping).SendPingAsync($Computer, $Timeout))
    }
    Write-Verbose "Waiting for ping tasks to complete..."
    [Threading.Tasks.Task]::WaitAll($Pings)

    foreach ($Ping in $Pings) { Write-Output $Ping.Result }
}

function Set-ErrorFiles {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$ModuleName
    )
    # $Date stores the Date Value (used in naming output files). The Date scheme is YearJulianDay-HourMin.
    $Date = Get-Date -Format yyyyMMdd_hhmmss

    # Creating the name of the ErrorFile.  Name contains $ErrorFile (From Config File) $Date and .txt
    Set-Variable -Name ErrorFileHosts -Value ("$ErrorLocal\" + "$Date" + "_" + "$ModuleName" + ".error.txt") -Scope script

    # Creating the name of the verbose ErrorFile.  Name contains $ErrorFile (From Config File) $Date and .txt
    Set-Variable -Name ErrorFileVerbose -Value ("$ErrorLocal\" + "$Date" + "_" + "$ModuleName" + ".errorV.txt") -Scope script

    return @($ErrorFileHosts,$ErrorFileVerbose)
}

function Confirm-Targets {
    Param([String[]]$Targets) 

        function local:Resolve-IpAddress ($LocalIPAddresses, $IpAddress) {
            # If no Hostname is specified then skip this step
            if ($IpAddress -eq "NULL") { return "NULL" }

            # Check for IP Address w/regex
            if ($IpAddress -match "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}")
            {
                if ($LocalIPAddresses -contains $IpAddress) { $HostName = "localhost" } # If given address is a local address return localhost
   
                else { 
                    # If the address is not a local address then try to resolve the IP using DNS
                    
                    try { 
                        $HostName = ([Net.Dns]::GetHostByAddress($IpAddress)).HostName
                        Write-Host -nonewline "[+] " -ForegroundColor Green
                        Write-Host "$IpAddress resolved to $HostName"
                        return $HostName 
                    }

                    # If no hostname is found then output the IP Address to the error files 
                    catch { 
                        Write-Host -nonewline "[-] " -ForegroundColor Red
                        Write-Host "$IpAddress UnResolveable"
                        return "NULL"
                    }
                }
            } 
            Write-Output $IpAddress
        }
        function local:Test-FQDN ($HostName) {
            # If no Hostname is specified then skip this step
            if ($HostName -eq "NULL") { return "NULL" }

            # Check to see if the Hostname contains the DNS Suffix
            if ($HostName -notmatch $TargetDomain) 
            {
                # Check to see if the host is not localhost
                if (($HostName -ne "NULL") -and ($HostName -ne "localhost"))
                {
                    # Add the DNS Suffix to the hostname
                    $HostName += "." + $TargetDomain
                }
            }
            return $HostName
        }

        $ValidTargets = New-Object Collections.Arraylist

        # Enumerate all local IP Addresses
        $LocalIPAddresses = New-Object Collections.Arraylist
        $IPConfigSet = Get-WmiObject Win32_NetworkAdapterConfiguration 
        foreach ($IPConfig in $IPConfigSet) { 
            foreach ($addr in $Ipconfig.Ipaddress) { 
                [void]$LocalIPAddresses.Add($addr)
            } 
        } 

        foreach ($Target in $Targets)
        {
            # test if it is an IP
            $HostName = Resolve-IpAddress $LocalIPAddresses $Target

            # test if FQDN is attached
            $HostName = Test-FQDN $HostName

            if ($HostName -ne "NULL") 
            {
                [void]$ValidTargets.Add($HostName)
            }
        }
        Write-Output $ValidTargets
}

function Get-ErrorHost {
    Param(
        [Parameter()]
        [string]$ErrorFileVerbose,

        [Parameter()]
        [string]$ErrorFileHosts
    )
    
    $errortest = 0
    foreach ($err in $global:error)
    {
        # Test if the error was caused by a PS Remoting Error 
        if($err.FullyQualifiedErrorId -eq "PSSessionStateBroken")
        {
            # string manipulation to produce hostname that had an error
            $HostName = (($err.tostring().split('[')[1]).split(']'))[0]

            Write-Error "$HostName failed"

            # Output Verbose information to verbose error file
            "$HostName -- $err" | Out-File -Encoding ascii -FilePath $ErrorFileVerbose -Append

            # Output Hostname to error file
            "$errorname" | Out-File -Encoding ascii -FilePath $ErrorFileHosts -Append    
            $errortest++   
        }
        else
        {
            #write-host "Caught additional error on remote host"
            # If error is caused for an unknown reason add it to the Verbose Error File
            "$err" | Out-File -Encoding ascii -FilePath $ErrorFileVerbose -Append
            $errortest++ 
        }
    }
    if ($errortest -gt 0){ Write-Warning "$errortest additional errors written to $ErrorFileVerbose" }
}

# Make a white-list Object in memory from the hashes present in a file
function New-Whitelist {
    Param(
        [Parameter(Mandatory=$true)]
        [String]$CsvFile,

		[Parameter()]
		[String]$VariableName
    )
    $WhiteList = New-Object Hashtable
    try{
        [array]$WhiteListFile = Get-Content $CsvFile
        
        foreach($Hash in $WhiteListFile)
        {
            $WhiteList.Add("$Hash"," ")
        }

        Set-Variable -Name $VariableName -Value $WhiteList
        Write-Verbose "Whitelist hashtable created from $CsvFile stored in $VariableName"
        Write-Output $WhiteList
    }
    catch
    {
        Write-Error "Failed to create whitelist from $CsvFile"
    }
}
