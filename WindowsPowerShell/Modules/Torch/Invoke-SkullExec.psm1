function Invoke-SkullExec {
[CmdletBinding(DefaultParameterSetName = "Run")]
    Param(
        [Parameter(Position = 0, Mandatory = $True)]
        [String]$ComputerName,

        [Parameter(ParameterSetName = "Run")]
        [ValidateNotNullOrEmpty()]
        [String]$Run = 'cmd.exe',

        [Parameter(ParameterSetName = "PushExe")]
        [ValidateNotNullOrEmpty()]
        [String]$PushExe,

        [Parameter()]
        [String]$Arguments = "",

        [Parameter()]
        [Switch]$AsSystem,

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$NoProfile,

        [Parameter()]
        [Switch]$NoWait,

        [Parameter()]
        [String]$WorkingDir,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$RenameTo = 'atintsvc',      
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$PsExecPath = $Global:PsExecPath
    )
    if (![IO.File]::Exists($PsExecPath)) {
        Write-Warning "Could not find PsExec, please specify full path to PsExec in -PsExecPath parameter."
        break
    }

    $CommandlineOptions = New-Object String[](0)
    if (!$PSBoundParameters['RenameTo']) { $CommandlineOptions += "-r svchost" }

    switch ($PSBoundParameters.Keys) {
                 'NoWait' { $CommandlineOptions += '-d' }  
                  'Force' { $CommandlineOptions += '-f' }
               'AsSystem' { $CommandlineOptions += '-s' }
               'RenameTo' { $CommandlineOptions += "-r $($RenameTo)" }
             'WorkingDir' { $CommandlineOptions += "-w $($WorkingDir)" }
                'Timeout' { $CommandlineOptions += "-n $($TimeOut.ToString())" }
    }

    if ($PSCmdlet.ParameterSetName -eq "PushExe") { Invoke-Expression -Command ($PsExecPath + " \\$ComputerName " + ($CommandlineOptions -join ' ') + " -e -c $PushExe " + $Arguments) }
    else { Invoke-Expression -Command ($PsExecPath + " \\$ComputerName " + ($CommandlineOptions -join ' ') + " -e `"$Run`" " + $Arguments) }
}