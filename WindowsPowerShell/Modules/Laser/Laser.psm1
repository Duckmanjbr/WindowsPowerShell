function Invoke-WmiRunspaceQuery {
<#
.SYNOPSIS
Creates a multi-threaded effect by using runspaces to speed up WMI queries to multiple hosts.

.PARAMETER TargetList 
Specify a list of hosts to retrieve data from.

.PARAMETER Parameters 
A hashtable of Get-WmiObject parameters that get passed to each runspace.

.PARAMETER Timeout 
Specify timeout length, defaults to 3 seconds.

.PARAMETER ThrottleLimit 
Specify maximum number of runspaces to use.

.NOTES
Version: 0.1
Author : RBOT

.INPUTS

.OUTPUTS

.LINK
#>
[CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
		[String[]]$TargetList,

        [Parameter()]
        [Hashtable]$Parameters,
        
        [Parameter()]
        [int]$ThrottleLimit = 10,

        [Parameter()]
        [int]$Timeout = 300
    )

    $Scriptblock = { 
        Param([String]$Computer, [Hashtable]$Parameters)

        $Parameters.ComputerName = $Computer
        Get-WmiObject @Parameters    
    }

    Write-Verbose "Creating runspace pool and session states."
    $SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $SessionState, $Host)
    $RunspacePool.Open()  

    $Runspaces = New-Object Collections.ArrayList

    foreach ($Computer in $TargetList) {
        #Create the powershell instance and supply the scriptblock with the other parameters 
        $PowerShell = [PowerShell]::Create()
        [void]$PowerShell.AddScript($ScriptBlock)
        [void]$PowerShell.AddArgument($Computer)
        [void]$PowerShell.AddArgument($Parameters)
        [void]$PowerShell.AddParameter('EnableAllPrivileges')
           
        #Add the runspace into the powershell instance
        $PowerShell.RunspacePool = $RunspacePool
           
        #Create a temporary collection for each runspace
        $Temp = "" | Select-Object PowerShell,Runspace,Computer
        $Temp.Computer = $Computer
        $Temp.PowerShell = $PowerShell
           
        #Save the handle output when calling BeginInvoke() that will be used later to end the runspace
        $Temp.Runspace = $PowerShell.BeginInvoke()
        Write-Verbose ("Adding {0} collection" -f $Temp.Computer)
        [void]$Runspaces.Add($Temp)
    }

    $TotalRunspaces = $Runspaces.Count           
    Write-Verbose "Checking status of runspace jobs."
    do {
        Write-Progress -Activity "Waiting for $($Parameters.Class) query to complete - *This may take a while*" -Status "Hosts Remaining: $($Runspaces.Count)" -PercentComplete (($TotalRunspaces - $Runspaces.Count) / $TargetList.Count * 100)
        $More = $false         
        foreach ($Runspace in $Runspaces) {
            if ($Runspace.Runspace.isCompleted) {
                $Runspace.PowerShell.EndInvoke($Runspace.Runspace)
                $Runspace.PowerShell.Dispose()
                $Runspace.Runspace = $null
                $Runspace.PowerShell = $null
            } 
            elseif ($Runspace.Runspace -ne $null) { $More = $true }
        }
        if ($More -and $PSBoundParameters['Timeout']) { Start-Sleep -Milliseconds $Timeout }
                   
        #Clean out unused runspace jobs
        $Temphash = $Runspaces.Clone()
        $Temphash | Where-Object { $_.Runspace -eq $null } | 
                    ForEach-Object { 
                        Write-Verbose ("Removing {0}" -f $_.Computer)
                        $Runspaces.Remove($_)
                    }            
    } while ($More)

    Write-Progress -Activity "Waiting for queries to complete" -Status "Completed" -Completed
    [GC]::Collect()
}
