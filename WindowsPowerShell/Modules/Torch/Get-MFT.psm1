function Get-MFT {
<#
.SYNOPSIS
Retrieves MFT files from remote hosts.

.DESCRIPTION
This module implements runspace jobbing to create a multi-threaded effect and speed-up the retrieval of MFT files from remote hosts.

.PARAMETER MftObject 
Required input object created by Export-MFT module.

.PARAMETER OutputDirectory 
Specify path to output directory, where retrieved MFT files will be written.

.PARAMETER Remove 
Automatically deletes extracted MFT file from remote host after retrieval.

.PARAMETER Timeout
Specify milliseconds to wait for job to complete.

.PARAMETER ThrottleLimit 
Specify maximum number of simultaneous connections.

.EXAMPLE
The following example extracts the master file table from the F volume on Server01 and writes it to TEMP; the returned object is stored in $MFT. Get-MFT is then used to retrieve the extracted master file table and store it in C:\MFT_Files\

PS C:\> $MFT = Export-MFT -TargetList Server01 -Volume F
PS C:\> Get-MFT -MftObject $MFT -OutputDirectory C:\MFT_Files\

.EXAMPLE
The following example extracts the master file table from the system volume and writes it to TEMP. Then the MFT file is retrieved from Server01 and stored in C:\MFT_Files\Server01.mft. After retrieval the extracted MFT file is deleted from the TEMP directory on Server01 (auto cleanup).

PS C:\> Export-MFT -TargetList Server01 | Get-MFT -OutputDirectory C:\MFT_Files\ -Remove

.EXAMPLE
The following example extracts the master file table from the system volume of all hosts in the TargetList. The MFT files are then retrieved and stored in C:\MFT_Files\hostname.mft. After retrieval the extracted MFT files are deleted.

PS C:\> Export-MFT -TargetList (New-TargetList -Cidr 10.10.92.0/24) | Get-MFT -OutputDirectory C:\MFT_Files\ -Remove

.NOTES
Version: 0.1
Author : Jesse "RBOT" Davis

.INPUTS

.OUTPUTS

.LINK
#>
[CmdLetBinding(SupportsShouldProcess = $false)]
     Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject[]]$MftObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$OutputDirectory,

        [Parameter()]
        [Switch]$Remove,
                
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int]$ThrottleLimit = 10,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int]$Timeout = 10

    ) #End Param
        
    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Get-MFT        
    $Global:Error.Clear()

    if (![IO.Directory]::Exists($OutputDirectory)) {
        Write-Warning "$OutputDirectory does not exist, creating now."
        New-Item -ItemType Directory -Path $OutputDirectory
    }

    if ($MftObject.Count -lt 2) {
        Copy-Item -Path $MftObject.NetworkPath -Destination ($OutputDirectory.TrimEnd('\') + '\' + $MftObject.ComputerName + '.mft') -Verbose
        if ($Remove.IsPresent) { Remove-Item -Path $MftObject.NetworkPath -Verbose }
    }

    else {
        $ScriptBlock = {
            param([String]$NetworkPath, [String]$Destination, [Bool]$Remove)

            Copy-Item -Path $NetworkPath -Destination $Destination -Verbose
            if ($Remove) { Remove-Item -Path $NetworkPath -Verbose }
        }

        Write-Verbose "Creating runspace pool and session states."
        $SessionState = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $SessionState, $Host)
        $RunspacePool.Open()  

        $Runspaces = New-Object Collections.ArrayList

        foreach ($Object in $MftObject) {

            $Destination = $OutputDirectory.TrimEnd('\') + '\' + $Object.ComputerName + '.mft'

            #Create the powershell instance and supply the scriptblock with the other parameters 
            $PowerShell = [PowerShell]::Create()
            [void]$PowerShell.AddScript($ScriptBlock)
            [void]$PowerShell.AddArgument($Object.NetworkPath)
            [void]$PowerShell.AddArgument($Destination)
            [void]$PowerShell.AddArgument($Remove.IsPresent)
           
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
               
        Write-Verbose "Checking status of runspace jobs."
        do {
            $More = $false         
            foreach ($Runspace in $Runspaces) {
                if ($Runspace.Runspace.isCompleted) {
                    $Runspace.PowerShell.EndInvoke($Runspace.Runspace)
                    $Runspace.PowerShell.Dispose()
                    $Runspace.Runspace = $null
                    $Runspace.PowerShell = $null
                    $i++                  
                } 
                elseif ($Runspace.Runspace -ne $null) { $More = $true }
            }
            if ($More -and $PSBoundParameters.Timeout) { Start-Sleep -Milliseconds $Timeout }
                   
            #Clean out unused runspace jobs
            $Temphash = $Runspaces.Clone()
            $Temphash | Where-Object { $_.Runspace -eq $null } | 
                        ForEach-Object { 
                            Write-Verbose ("Removing {0}" -f $_.Computer)
                            $Runspaces.Remove($_)
                        }             
        } while ($More)
    }

    [GC]::Collect()
    $ScriptTime.Stop()
    Write-Verbose "Done, execution time: $($ScriptTime.Elapsed)"
}