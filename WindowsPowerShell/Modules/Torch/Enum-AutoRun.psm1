function Enum-AutoRun {
<#
.SYNOPSIS
Retrieve information about commands that will run when a user logs in

.DESCRIPTION
The Win32_StartupCommand WMI class represents a command that runs automatically when a user logs onto the computer system.
This class will return startup commands located in:
HKLM\Software\Microsoft\Windows\CurrentVersion\Run
HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce
HKU\ProgID\Software\Microsoft\Windows\CurrentVersion\Run
systemdrive\Documents and Settings\All Users\Start Menu\Programs\Startup
systemdrive\Documents and Settings\username\Start Menu\Programs\Startup

.PARAMETER TargetList 
Specify host(s) to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections..

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example gets a list of computers from the pipeline and sends output to a csv file.

PS C:\> New-TargetList -Cidr 10.10.20.0/24 | Enum-AutoRuns -CSV C:\pathto\output.csv

.NOTES
Version: 4.1.0915
Author : Jared "Huck" Atkinson / Ryan "Candy" Rickert
Cleaned by RBOT Sep 15

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
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Enum-AutoRun
        
    $Global:Error.Clear()

    $RemoteScriptblock = {
        $StartTime = [DateTime]::Now
        $StartupCommands = Get-WmiObject Win32_StartupCommand
        foreach ($Command in $StartupCommands) {           
            $obj = New-Object -TypeName PSObject
            $obj | Add-Member -MemberType NoteProperty -Name TIME -Value $StartTime
            $obj | Add-Member -MemberType NoteProperty -Name COMMAND -Value $Command.Command
            $obj | Add-Member -MemberType NoteProperty -Name LOCATION -Value $Command.Location
            $obj | Add-Member -MemberType NoteProperty -Name CAPTION -Value $Command.Caption
            $obj | Add-Member -MemberType NoteProperty -Name USER -Value $Command.User
            Write-Output $obj
        }
    }

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