function Invoke-RemoteCommand {
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Scriptblock]$Scriptblock,

	[Parameter()]
	[String[]]$TargetList,

        [Parameter()]
        [Object[]]$ScriptBlockArgs,
        
        [Parameter()]
        [int]$Timeout = 300 
    )

    $i = 0
    $NoMachineProfile = New-PSSessionOption -NoMachineProfile

    foreach($Computer in $TargetList){

        [void](Invoke-Command -AsJob -Scriptblock $Scriptblock -ArgumentList $ScriptBlockArgs -ComputerName $Computer -SessionOption $NoMachineProfile -ErrorAction SilentlyContinue)
        $i++
        Write-Progress -Activity "Executing - *This may take a while*" -status "Host jobs started: $i of $TotalComputers" -PercentComplete ($i / $TotalComputers * 100)
   }

   #Rickert - Adding jobbing
   Write-Progress -Activity "Starting Jobs" -Status "Done" -Completed
   Write-Verbose "All jobs started, waiting at most $($Timeout / 60) minutes for jobs to complete"
   [void](Wait-Job -Timeout $Timeout $(Get-Job) -ErrorAction SilentlyContinue)
   Write-Verbose "Done waiting, starting to process jobs."

   $script:obj = @()
   foreach ($job in (Get-Job))
   {
        if ($job.State -eq 'Completed')
        {
            $script:obj += Receive-Job $job -ErrorAction SilentlyContinue
        }
        elseif($job.State -eq 'Failed')
        {
            Write-Error "[-] $($job.Location) $(Get-Date -UFormat %T) failed."
        }
        else
        {
            Write-Error "[-] $($job.Location) $(Get-Date -UFormat %T) failed with state $($job.State)"
            $job.StopJob()
        }
		if ($job)
        {
			try { [void](Remove-Job $job -Force -ErrorAction SilentlyContinue) }
            catch{ continue }
		}
   }
   if($script:obj)
   {
        return $script:obj
        Clear-Variable -Name obj
   }
   [GC]::Collect()
}

function Confirm-Hash {
    Param (
        [Parameter(Position = 0, ValueFromPipeline = $True, Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $HashList,

        [Parameter(Position = 1, HelpMessage="Enter a hash algortihm to use.")]
        [ValidateSet('MD5','SHA1','SHA256','SHA384','SHA512')]
        [ValidateNotNullOrEmpty()]
        [String]
        $HashAlgorithm = 'SHA1'
    ) #end param

    if($HashList.Count -gt 1)
    {
        foreach($Hash in $HashList)
        {
            switch ($HashAlgorithm) 
            {
                'MD5' 
                { 
                    if(($Hash.Length -ne 32) -or (([regex]::match($Hash,"[0-9A-Fa-f]{32}")).Success -eq $false)) 
                    {
                        Write-Error "$Hash is not a valid MD5 hash." 
                    }
                    else { $true }
                    break
                }     
                'SHA1' 
                { 
                    if(($Hash.Length -ne 40) -or (([regex]::match($Hash,"[0-9A-Fa-f]{40}")).Success -eq $false))
                    {
                        Write-Error "$Hash is not a valid SHA1 hash."
                    } 
                    else { $true }
                    break
                }
                'SHA256' 
                {
                    if(($Hash.Length -ne 64) -or (([regex]::match($Hash,"[0-9A-Fa-f]{64}")).Success -eq $false))
                    {
                        Write-Error "$Hash is not a valid SHA256 hash."
                    } 
                    else { $True }
                    break
                }
                'SHA384' 
                { 
                    if(($Hash.Length -ne 96) -or (([regex]::match($Hash,"[0-9A-Fa-f]{96}")).Success -eq $false))
                    {
                        Write-Error "$Hash is not a valid SHA384 hash."
                    }
                    else { $true }
                    break
                }
                'SHA512' 
                { 
                    if(($Hash.Length -ne 128) -or (([regex]::match($Hash,"[0-9A-Fa-f]{128}")).Success -eq $false))
                    {
                        Write-Error "$Hash is not a valid SHA512 hash."
                    }
                    else { $true }
                    break
                }
            }
        }
    }
    
    else
    {
        switch ($HashAlgorithm) 
        {
            'MD5' 
            { 
                if(($HashList[0].Length -ne 32) -or (([regex]::match($HashList,"[0-9A-Fa-f]{32}")).Success -eq $false)) 
                {
                    Write-Error "$HashList is not a valid MD5 hash." 
                }
                else { $true }
                break
            }
            'SHA1' 
            { 
                if(($HashList[0].Length -ne 40) -or (([regex]::match($HashList,"[0-9A-Fa-f]{40}")).Success -eq $false))
                {
                    Write-Error "$HashList is not a valid SHA1 hash."
                } 
                else { $true }
                break
            }
            'SHA256' 
            {
                if(($HashList[0].Length -ne 64) -or (([regex]::match($HashList,"[0-9A-Fa-f]{64}")).Success -eq $false))
                {
                    Write-Error "$HashList is not a valid SHA256 hash."
                } 
                else { $True }
                break
            }
            'SHA384' 
            { 
                if(($HashList[0].Length -ne 96) -or (([regex]::match($HashList,"[0-9A-Fa-f]{96}")).Success -eq $false))
                {
                    Write-Error "$HashList is not a valid SHA384 hash."
                }
                else { $true }
                break
            }
            'SHA512' 
            { 
                if(($HashList[0].Length -ne 128) -or (([regex]::match($HashList,"[0-9A-Fa-f]{128}")).Success -eq $false))
                {
                    Write-Error "$HashList is not a valid SHA512 hash."
                }
                else { $true }
                break
            }
        }
    }   
}

function Confirm-WinRmEnabled {
<#
.SYNOPSIS
Tests for and configures WinRM functionality on remote hosts.

.DESCRIPTION
This cmdlet can test Windows Remote Management and configure it if it's not already configured.

Specify computers by name or IP address.

Use the -Verbose switch to see detailed information.

.PARAMETER TargetList 
Indicates one or more computer names or IPs to use.  Separate multiple names with a comma.

.PARAMETER Deploy 
Attempts to start and configure the WinRM service.

.EXAMPLE
The following example tests if WinRm is properly configured and attempts to start and configure the service if it is not.

PS C:\> Confirm-WinRmEnabled -TargetList Server01 -Deploy

.NOTES
Version: 0.1
Author : Jesse "RBOT" Davis
#>
    Param(
        [Parameter(Mandatory = $true)]
        [String[]]$TargetList,

        [Parameter()]
        [Switch]$Deploy
    )

    $i = 1
    $WinRmOn = New-Object Collections.Arraylist
    $WinRmOff = New-Object Collections.Arraylist
    
    foreach ($Computer in $TargetList) {
        #Progress bar
        Write-Progress -Activity "Confirming WinRm Enabled" -status "Hosts Processed: $i of $($TargetList.Count)" -PercentComplete ($i / $TargetList.Count * 100)
                
        $NoMachineProfile = New-PSSessionOption -NoMachineProfile
        
        #Test if WinRM is configured
        if (Invoke-Command -ComputerName $Computer -ScriptBlock { $true } -ErrorAction SilentlyContinue -SessionOption $NoMachineProfile) 
        {
            Write-Verbose "$Computer - WinRm properly configured."
            [void]$WinRmOn.Add($Computer)
        }
        else {     
            Write-Verbose "$Computer - WinRm Not Configured"
            [void]$WinRmOff.Add($Computer)
            
            if ($Deploy.IsPresent)  #push winrmdeploy.cmd to the machine and start it
            {
                $WinRmEnabled = New-Object Collections.Arraylist
                $WinRmFailed = New-Object Collections.Arraylist
                $PsExecFailed = New-Object Collections.Arraylist

                try {
                    Write-Verbose "Attempting to push WinRm startup script..."  

                    Invoke-SkullExec -ComputerName $Computer -AsSystem -NoProfile -Force -PushExe $Torch\Deployment\winrmdeploy.cmd 2>&1 | Out-File -Append -FilePath "$Torch\Deployment\out\$(Get-Date -Format yyyyMMdd_hhmmss)_winrmdeploy.txt" 
                
                    #Verify enabling was successful
                    if (Invoke-Command -ComputerName $Computer -ScriptBlock { $true } -ErrorAction SilentlyContinue -SessionOption $NoMachineProfile) {       
                        Write-Verbose "$Computer - WinRm successfully configured"
                        [void]$WinRmEnabled.Add($Computer)
                    }
                    else {
                        Write-Verbose "$Computer - Failed to configure WinRm... Moving on."
                        [void]$WinRmFailed.Add($Computer)
                    }
                }     
                catch {
                    Write-Verbose "$Computer - Failed to push file... Moving on."
                    [void]$PsExecFailed.Add($Computer)
                }
            }
        }  
        $i++
    }
    Write-Verbose "Finished checking WinRm."
    Write-Verbose "Hosts with WinRm enabled: $($WinRmOn.Count + $WinRmEnabled.Count)"
    Write-Verbose "Hosts without WinRm enabled: $($WinRmOff.Count + $WinRmFailed.Count + $PsExecFailed.Count)"

    $Properties = @{
        WinRmOn = $WinRmOn
        WinRmOff = $WinRmOff
        WinRmEnabled = $WinRmEnabled
        WinRmFailed = $WinRmFailed
        PsExecFailed = $PsExecFailed
    }

    $obj = New-Object -TypeName psobject -Property $Properties
    Write-Output $obj
}

function Out-EncodedCommand {
<#
.SYNOPSIS

Compresses, Base-64 encodes, and generates command-line output for a PowerShell payload script.
 
.DESCRIPTION

Out-EncodedCommand prepares a PowerShell script such that it can be pasted into a command prompt. The scenario for using this tool is the following: You compromise a machine, have a shell and want to execute a PowerShell script as a payload. This technique eliminates the need for an interactive PowerShell 'shell' and it bypasses any PowerShell execution policies.

.PARAMETER ScriptBlock

Specifies a scriptblock containing your payload.

.PARAMETER Path

Specifies the path to your payload.

.PARAMETER NoExit

Outputs the option to not exit after running startup commands.

.PARAMETER NoProfile

Outputs the option to not load the Windows PowerShell profile.

.PARAMETER NonInteractive

Outputs the option to not present an interactive prompt to the user.

.PARAMETER Wow64

Calls the x86 (Wow64) version of PowerShell on x86_64 Windows installations.

.PARAMETER WindowStyle

Outputs the option to set the window style to Normal, Minimized, Maximized or Hidden.

.EXAMPLE

C:\PS> Out-EncodedCommand -ScriptBlock {Write-Host 'hello, world!'}

powershell -C sal a New-Object;iex(a IO.StreamReader((a IO.Compression.DeflateStream([IO.MemoryStream][Convert]::FromBase64String('Cy/KLEnV9cgvLlFQz0jNycnXUSjPL8pJUVQHAA=='),[IO.Compression.CompressionMode]::Decompress)),[Text.Encoding]::ASCII)).ReadToEnd()

#>
    Param (
        [Parameter(Position = 0, ValueFromPipeline = $True, ParameterSetName = 'ScriptBlock' )]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]
        $ScriptBlock,

        [Parameter(Position = 0, ParameterSetName = 'FilePath' )]
        [ValidateNotNullOrEmpty()]
        [String]
        $Path,

        [Switch]
        $NoExit,

        [Switch]
        $NoProfile,

        [Switch]
        $NonInteractive,

        [Switch]
        $Wow64,

        [ValidateSet('Normal', 'Minimized', 'Maximized', 'Hidden')]
        [String]
        $WindowStyle
    )

    if ($PSBoundParameters['Path']) {
        [void](Get-ChildItem $Path -ErrorAction Stop)
        $ScriptBytes = [IO.File]::ReadAllBytes((Resolve-Path $Path))
    }
    else { $ScriptBytes = ([Text.Encoding]::ASCII).GetBytes($ScriptBlock) }

    $CompressedStream = New-Object IO.MemoryStream
    $DeflateStream = New-Object IO.Compression.DeflateStream ($CompressedStream, [IO.Compression.CompressionMode]::Compress)
    $DeflateStream.Write($ScriptBytes, 0, $ScriptBytes.Length)
    $DeflateStream.Dispose()
    $CompressedScriptBytes = $CompressedStream.ToArray()
    $CompressedStream.Dispose()
    $EncodedCompressedScript = [Convert]::ToBase64String($CompressedScriptBytes)

    # Generate the code that will decompress and execute the payload. This code is intentionally ugly to save space.
    $NewScript = 'sal a New-Object;iex(a IO.StreamReader((a IO.Compression.DeflateStream([IO.MemoryStream][Convert]::FromBase64String(' + "'$EncodedCompressedScript'" + '),[IO.Compression.CompressionMode]::Decompress)),[Text.Encoding]::ASCII)).ReadToEnd()'

    # Build the command line options
    $CommandlineOptions = New-Object String[](0)
    switch ($PSBoundParameters.Keys) {
                'NoExit' { $CommandlineOptions += '-NoE' }
             'NoProfile' { $CommandlineOptions += '-NoP' } 
        'NonInteractive' { $CommandlineOptions += '-NonI' } 
           'WindowStyle' { $CommandlineOptions += "-W $($PSBoundParameters['WindowStyle'])" }
    }

    $CmdMaxLength = 8190

    if ($Wow64.IsPresent) {
        $CommandLineOutput = "$($Env:windir)\SysWOW64\WindowsPowerShell\v1.0\powershell.exe $($CommandlineOptions -join ' ') -C `"$NewScript`""
    }
    else { $CommandLineOutput = "powershell $($CommandlineOptions -join ' ') -C `"$NewScript`"" }

    if ($CommandLineOutput.Length -gt $CmdMaxLength) { 
        Write-Warning 'This command exceeds the maximum allowed length!'
        break
    }
    Write-Output $CommandLineOutput
}
