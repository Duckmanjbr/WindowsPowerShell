function Enum-Adapter {
<#
.SYNOPSIS
Gathers information about network adapters on remote systems.

.DESCRIPTION
This commandlet uses Windows Remote Management to collect Windows Adapter information from remote systems.

Specify computers by name or IP address.

Use the -Verbose switch to see detailed information.

.PARAMETER TargetList 
Specify host(s) to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example gets a list of computers from the pipeline and sends output to a csv file.

PS C:\> New-TargetList -Cidr 10.10.20.0/24 | Enum-Adapter -CSV C:\pathto\output.csv

.EXAMPLE
The following example specifies a computer and sends output to a csv file.

PS C:\> Enum-Adapter -TargetList Server01 -CSV C:\pathto\output.csv

.NOTES
Version: 3.1.0915
Changes for Splunk compatability approved by Lt. Rickert 16 Mar 15
Re-Written by RBOT

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
        [String]$CSV,
		
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TXT
    ) #End Param

    if($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Enum-Adapter
        
    $Global:Error.Clear()

    $RemoteScriptblock = {
        $StartTime = [DateTime]::Now
        $NetworkAdapters = Get-WmiObject Win32_NetworkAdapter
        foreach ($Adapter in $NetworkAdapters) {
            switch ($Adapter.NetConnectionStatus) {
                0 { $ConnectionStatus = 'Disconnected'}
                1 { $ConnectionStatus = 'Connecting'}
                2 { $ConnectionStatus = 'Connected'}
                3 { $ConnectionStatus = 'Disconnecting'}
                4 { $ConnectionStatus = 'Hardware Not Present'}
                5 { $ConnectionStatus = 'Hardware Disabled'}
                6 { $ConnectionStatus = 'Hardware Malfunction'}
                7 { $ConnectionStatus = 'Media Disconnected'}
                8 { $ConnectionStatus = 'Authenticating'}
                9 { $ConnectionStatus = 'Authentication Succeeded'}
               10 { $ConnectionStatus = 'Authentication Failed'}
               11 { $ConnectionStatus = 'Invalid Address'}
               12 { $ConnectionStatus = 'Credentials Required'}
            }
            $NetworkAdapterConfig = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.Index -eq $Adapter.Index }

            $Properties = @{
                Time = $StartTime
                Interfacename = $Adapter.NetConnectionID
                ConnectionStatus = $ConnectionStatus
                Description = $Adapter.Description
                DefaultGateway = $NetworkAdapterConfig.DefaultIPGateway
                DHCPEnabled = $NetworkAdapterConfig.DHCPEnabled
                DNSDomain = $NetworkAdapterConfig.DNSDomain
                IPAddress = $NetworkAdapterConfig.IPAddress
                IPSubnet = $NetworkAdapterConfig.IPSubnet
                MACAddress = $Adapter.MACAddress
            }      
            New-Object -TypeName PSObject -Property $Properties
        }
    }#End RemoteScriptBlock

    if ($PSBoundParameters['TargetList']) {
        if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }        
        
        $ReturnedObjects = New-Object Collections.ArrayList
        $HostsRemaining = [Collections.ArrayList]$TargetList
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)

        Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit |
        ForEach-Object { 
            if ($HostsRemaining -contains $_.PSComputerName) { $HostsRemaining.Remove($_.PSComputerName) }
            [void]$ReturnedObjects.Add($_)
            Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)
        }
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Completed" -Completed
    }
    else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock }

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