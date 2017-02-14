function Get-WmiEventConsumer {
<#
.SYNOPSIS
Retrieves information about WMI event consumers.

.DESCRIPTION


.PARAMETER TargetList 
Specify a list of hosts to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example gets a list of computers from the pipeline and sends output to a csv file.

PS C:\> New-TargetList -Cidr 10.10.20.0/24 | Get-WmiEventConsumer -CSV C:\pathto\output.csv

.EXAMPLE
The following example specifies a computer and sends output to a csv file.

PS C:\> Get-WmiEventConsumer -TargetList Server01 -CSV C:\pathto\output.csv

.NOTES
Version: 0.1
Author: RBOT

.INPUTS

.OUTPUTS

.LINK
#>
[CmdLetBinding(SupportsShouldProcess = $false)]
    Param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$TargetList = 'localhost',

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
    
    if ($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif ($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
        
    if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }         
        
    $Parameters = @{
        Namespace = "root\subscription"
        Class = "__EventConsumer"
        ErrorAction = "Stop"
    }

    $RunspaceScript = {
        Param([String]$Computer, [Hashtable]$Parameters)
        $Parameters.ComputerName = $Computer

        try { $EventConsumers = Get-WmiObject @Parameters }
        catch { 
            Write-Warning ("{0}: {1}" -f $Computer,$_.Exception.Message)
            break
        }

        $ConsumerList = New-Object Collections.ArrayList
            
        foreach ($Consumer in $EventConsumers) {

            $CreatorSID = New-Object Security.Principal.SecurityIdentifier([byte[]]$Consumer.CreatorSID, 0)
            try { $Creator = $CreatorSID.Translate([Security.Principal.NTAccount]).Value }
            catch { $Creator = $null }

            switch ($Consumer.__CLASS) {
                "ActiveScriptEventConsumer" {
                    $Properties = @{
                        'Type' = "ActiveScriptEventConsumer"
                        'CreatorSID' = $CreatorSID.Value
                        'Creator' = $Creator
                        'Name' = $Consumer.Name
                        'KillTimeout' = $Consumer.KillTimeout
                        'ScriptingEngine' = $Consumer.ScriptingEngine
                        'ScriptFileName' = $Consumer.ScriptFileName
                        'ScriptText' = $Consumer.ScriptText
                        'ComputerName' = $Consumer.PSComputerName
                    }
                    [void]$ConsumerList.Add((New-Object -TypeName PSObject -Property $Properties))
                }
                "CommandLineEventConsumer" {
                    $Properties = @{
                        'Type' = "CommandLineEventConsumer"
                        'CreatorSID' = $CreatorSID.Value
                        'Creator' = $Creator
                        'Name' = $Consumer.Name
                        'KillTimeout' = $Consumer.KillTimeout
                        'CommandLineTemplate' = $Consumer.CommandLineTemplate
                        'CreateNewConsole' = $Consumer.CreateNewConsole
                        'CreateNewProcessGroup' = $Consumer.CreateNewProcessGroup
                        'CreateSeparateWowVdm' = $Consumer.CreateSeparateWowVdm
                        'DesktopName' = $Consumer.DesktopName
                        'ExecutablePath' = $Consumer.ExecutablePath
                        'FillAttributes' = $Consumer.FillAttributes
                        'ForceOffFeedback' = $Consumer.ForceOffFeedback
                        'ForceOnFeedback' = $Consumer.ForceOnFeedback
                        'Priority' = $Consumer.Priority
                        'RunInteractively' = $Consumer.RunInteractively
                        'ShowWindowCommand' = $Consumer.ShowWindowCommand
                        'UseDefaultErrorMode' = $Consumer.UseDefaultErrorMode
                        'WindowTitle' = $Consumer.WindowTitle
                        'WorkingDirectory' = $Consumer.WorkingDirectory
                        'XCoordinate' = $Consumer.XCoordinate
                        'XNumCharacters' = $Consumer.XNumCharacters
                        'XSize' = $Consumer.XSize
                        'YCoordinate' = $Consumer.YCoordinate
                        'YNumCharacters' = $Consumer.YNumCharacters
                        'YSize' = $Consumer.YSize
                        'FillAttribute' = $Consumer.FillAttribute
                        'ComputerName' = $Consumer.PSComputerName
                    }
                    [void]$ConsumerList.Add((New-Object -TypeName PSObject -Property $Properties))
                }
                "LogFileEventConsumer" {
                    $Properties = @{
                        'Type' = "LogFileEventConsumer"
                        'CreatorSID' = $CreatorSID.Value
                        'Creator' = $Creator
                        'Name' = $Consumer.Name
                        'Filename' = $Consumer.Filename
                        'IsUnicode' = $Consumer.IsUnicode
                        'MaximumFileSize' = $Consumer.MaximumFileSize
                        'Text' = $Consumer.Text
                        'ComputerName' = $Consumer.PSComputerName
                    }
                    [void]$ConsumerList.Add((New-Object -TypeName PSObject -Property $Properties))
                }
                "NTEventLogEventConsumer" {
                    $Properties = @{
                        'Type' = "NTEventLogEventConsumer"
                        'CreatorSID' = $CreatorSID.Value
                        'Creator' = $Creator
                        'Name' = $Consumer.Name
                        'Category' = $Consumer.Category
                        'NameOfRawDataProperty' = $Consumer.NameOfRawDataProperty
                        'EventID' = $Consumer.EventID
                        'EventType' = $Consumer.EventType
                        'InsertionStringTemplates' = $Consumer.InsertionStringTemplates
                        'NumberOfInsertionStrings' = $Consumer.NumberOfInsertionStrings
                        'SourceName' = $Consumer.SourceName
                        'UNCServerName' = $Consumer.UNCServerName
                        'ComputerName' = $Consumer.PSComputerName
                    }
                    [void]$ConsumerList.Add((New-Object -TypeName PSObject -Property $Properties))
                }
                "SMTPEventConsumer" {
                    $Properties = @{
                        'Type' = "SMTPEventConsumer"
                        'CreatorSID' = $CreatorSID.Value
                        'Creator' = $Creator
                        'Name' = $Consumer.Name
                        'BccLine' = $Consumer.BccLine
                        'CcLine' = $Consumer.CcLine
                        'FromLine' = $Consumer.FromLine
                        'HeaderFields' = $Consumer.HeaderFields
                        'Message' = $Consumer.Message
                        'ReplyToLine' = $Consumer.ReplyToLine
                        'SMTPServer' = $Consumer.SMTPServer
                        'Subject' = $Consumer.Subject
                        'ToLine' = $Consumer.ToLine
                        'ComputerName' = $Consumer.PSComputerName
                    }
                    [void]$ConsumerList.Add((New-Object -TypeName PSObject -Property $Properties))
                }
            }
        }
        Write-Output $ConsumerList
    }# End RunspaceScript 

    Write-Verbose "Creating runspace pool and session states."
    $SessionState = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $SessionState, $Host)
    $RunspacePool.Open()  

    $Runspaces = New-Object Collections.ArrayList

    foreach ($Computer in $TargetList) {
        #Create the powershell instance and supply the scriptblock with the other parameters 
        $PowerShell = [PowerShell]::Create()
        [void]$PowerShell.AddScript($RunspaceScript)
        [void]$PowerShell.AddArgument($Computer)
        [void]$PowerShell.AddArgument($Parameters)
        [void]$PowerShell.AddParameter('EnableAllPrivileges')
           
        # Assign instance to runspacepool
        $PowerShell.RunspacePool = $RunspacePool
           
        # Create an object for each runspace
        $Job = "" | Select-Object Computer,PowerShell,Result
        $Job.Computer = $Computer
        $Job.PowerShell = $PowerShell
        $Job.Result = $PowerShell.BeginInvoke() #Save the handle output when calling BeginInvoke() that will be used later to end the runspace
        
        Write-Verbose ("Adding {0} to jobs." -f $Job.Computer)
        [void]$Runspaces.Add($Job)
    }
    # Counters for progress bar
    $TotalRunspaces = $RemainingRunspaces = $Runspaces.Count         
    
    Write-Verbose 'Checking status of runspace jobs.'
    Write-Progress -Activity 'Waiting for WmiEventConsumer queries to complete...' -Status "Hosts Remaining: $RemainingRunspaces" -PercentComplete 0
    
    # Listen for Ctrl+C
    [console]::TreatControlCAsInput = $true
    
    do {
        $More = $false   

        # Quit Gracefully
        if ([console]::KeyAvailable) { 
            $Key = [console]::ReadKey($true)
            if (($Key.Modifiers -band [ConsoleModifiers]::Control) -and ($Key.Key -eq 'C')) {
                Write-Warning "Caught escape sequence, quitting runspace jobs."
                $RunspacePool.Close()
                $RunspacePool.Dispose()
                [console]::TreatControlCAsInput = $false
                break
            }
        }      

        foreach ($Job in $Runspaces) {
            
            if ($Job.Result.IsCompleted) {
                    
                $ReturnedObjects = $Job.PowerShell.EndInvoke($Job.Result)
                if ($ReturnedObjects.Count -gt 0) {
                    if ($PSBoundParameters['CSV']) { $ReturnedObjects | Export-Csv -Path $OutputFilePath -Append -NoTypeInformation -ErrorAction SilentlyContinue }
                    elseif ($PSBoundParameters['TXT']) { $ReturnedObjects | Out-File -FilePath $OutputFilePath -Append -ErrorAction SilentlyContinue }
                    else { Write-Output $ReturnedObjects }
                }

                if ($Job.PowerShell.Streams.Warning.Count -gt 0) {
                    Out-File -Append -InputObject $Job.PowerShell.Streams.Warning -FilePath ("$ErrorLocal\$ErrorDate" + "_Enum-AutoRunWmi.txt")
                }

                $Job.PowerShell.Dispose()
                $Job.Result = $null
                $Job.PowerShell = $null
                $RemainingRunspaces--
                Write-Progress -Activity 'Waiting for WmiEventConsumer queries to complete...' -Status "Hosts Remaining: $RemainingRunspaces" -PercentComplete (($TotalRunspaces - $RemainingRunspaces) / $TotalRunspaces * 100)
            } 

            if ($Job.Result -ne $null) { $More = $true }
        }
                   
        # Remove completed jobs
        $Jobs = $Runspaces.Clone()
        $Jobs | where { $_.Result -eq $null } | foreach { Write-Verbose ("Removing {0}" -f $_.Computer) ; $Runspaces.Remove($_) }     
    } while ($More)
        
    Write-Progress -Activity 'Waiting for WmiEventConsumer queries to complete...' -Status 'Completed' -Completed

    [console]::TreatControlCAsInput = $false
    $RunspacePool.Dispose()
    [GC]::Collect()
}
