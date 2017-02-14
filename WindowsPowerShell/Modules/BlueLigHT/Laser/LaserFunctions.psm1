# Used to set the current output, error and verbose error files
function SetOutandErrorFiles
{
    # $Date stores the Date Value (used in naming output files). The Date scheme is YearJulianDay-HourMin.
    param(
        [parameter()]
        [string]$outputFileName,
        [Parameter()]
		[Boolean] $CSV,
        [Parameter()]
        [Boolean] $TXT
    )
    # Creating the name of the ErrorFile.  Name contains $ErrorFile (From Config File) $Date and .txt
    Set-Variable -name errorFileNameH -value ("$dirErrorLocal" + "$Date" + "_" + "$outputFileName" + ".error.txt") -scope global
    # Creating the name of the ErrorFile.  Name contains $ErrorFile (From Config File) $Date and .txt
    Set-Variable -name errorFileNameV -value ("$dirErrorLocal" + "$Date" + "_" + "$outputFileName" + ".errorV.txt") -scope global
    # Creating the name of the OutPutFile.  Name contains $OutPutFile (From Config File) $Date and .txt
    Set-Variable -name outputFileName2 -value ("$dirOutputLocal" + "$Date" + "_" + "$outputFileName" + ".output") -scope global
    # Appends the file type to the end of the file name based on the chosen output format
    if ($TXT -eq $TRUE)
    {
        $outputFileName2 += ".txt"    
    } elseif ($CSV -eq $TRUE)
    {
        $outputFileName2 += ".csv"    
    }
    Write-host "Finished Setting Out and Error Files"
    #Set-Variable -name outputFileName -value ("$outputFileName") -scope global
    return @($errorFileNameH,$errorFileNameV,$outputFileName2)
} # End of SetOutandErrorFiles
##################################################################
##################################################################
# Used to take an input Config File and Create Variables based on the Contents
function ReadConfigFile 
{
    param(
        [Parameter(Mandatory=$true)]
        $ConfigFile
    )
    Write-Host
    # Read in the .ini file
    Write-Host "Config Path: " $dirconfigpath
    Write-Host "Config File: " $ConfigFile `n
    $file = Get-Content $configFile
    foreach ($line in $file) {      
        # split the contents of each line in the file on the =               
        $contents = $line.split('=')
        # the data before the = becomes the variable name
        $varName = $contents[0] 
        # the data after the = becomes the variable value                                       
        $varValue = $contents[1]
        # create a variable call varName with a value of varValue
        Set-Variable -Name $varName -Value $varValue -scope global     
    }
} # End of ReadConfigFile
##################################################################
##################################################################
function ValidateTargets($a)
{
	return $a
    $xkcd = @()

    foreach ($b in $a)
    {
        # test if it is an IP
        $c = ResolveIPs($b)
        # test if FQDN is attached
        $d = TestFQDN($c)
        # test of pingable
        $e = PingTarget($d)
        if ($e -ne "NULL") 
        {
            $xkcd += $e
        }
		else {
			$xkcd += $b
		}
    }

    return $xkcd
} # End of ValidateTargets

##################################################################
# Resolve IPs to hostnames
# Uses System/OS namerserver (oustide of module/cmdlet scope)
function ResolveIPs($arg1)
{
    # If no Hostname is specified then skip this step
    if ($arg1 -eq "NULL") { return "NULL" }
    # Check for IP Address
    # Reg Ex to match IP Address
    if ($arg1 -match "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}")
    {
        # Enumerate all local IP Addresses
        $localaddresses = ""
        $IPConfigSet = Get-WmiObject Win32_NetworkAdapterConfiguration 
        foreach ($IPConfig in $IPConfigSet) { 
            foreach ($addr in $Ipconfig.Ipaddress) { 
                $localaddresses += $addr + " "
            } 
        } 
        # Determine if given address is local address
        # If given address is a local address return localhost
        if ($localaddresses.contains($arg1)) {
            $xkcd = "localhost"
        # If the address is not a local address then resolve the IP using DNS
        } else {
            $xkcd = [System.Net.Dns]::GetHostByAddress($arg1)
            $xkcd = [string]$xkcd.hostname
        }
        # If no hostname is found then output the IP Address to the error files 
        if ($xkcd -match "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}") 
        {
            "$arg1" | Out-File -Encoding "ASCII" $ErrorFileNameH -append
            "$arg1 -- DNS Hostname/IP Resolution Failed" | Out-File -Encoding "ASCII" $ErrorFileNameV -append
            Write-Host -nonewline "[-] " -ForegroundColor Red
            Write-Host "$arg1 UnResolveable"
            return "NULL"
        # If the IP Address is resolved then output success and the hostname
        } else {
            Write-Host -nonewline "[+] " -ForegroundColor Green
            Write-Host "$arg1 resolved to $xkcd "
            return $xkcd
        }
    }
    return $arg1
} # End of ResolveIPs
##################################################################


##################################################################
#
function TestFQDN($arg1)
{
    # If no Hostname is specified then skip this step
    if ($arg1 -eq "NULL") { return "NULL" }
    # Check to see if the Hostname contains the DNS Suffix
    if ($arg1 -notmatch $TargetDomain) 
    {
        # Check to see if the host is not localhost
        if (($arg1 -ne "NULL") -and ($arg1 -ne "localhost"))
        {
            # Add the DNS Suffix to the hostname
            $arg1 += "." + $TargetDomain
        }
    }
    return $arg1
}
# End of TestFQDN
##################################################################


##################################################################
# Used to Ping Each Remote Target Before Initiating Remote Session
function PingTarget($arg1)
{
    # If no Hostname is specified then skip this step
    if ($arg1 -eq "NULL") { return "NULL" }
    
    # Check to see if the $Ping switch was specified
    if ($Ping -eq $TRUE)
    {
        # ping target, get TRUE/FALSE
        $pingable = Test-Connection -ComputerName $arg1 -Count 1 -Quiet
        # IF ping failed, output to error files
        if ($pingable -eq $FALSE) 
        {
            "$arg1" | Out-File -Encoding "ASCII" $ErrorFileNameH -append
            "$arg1 -- Ping Failed" | Out-File -Encoding "ASCII" $ErrorFileNameV -append
            Write-Host -nonewline "[-] " -ForegroundColor Red
            Write-Host "$arg1 UnPingable"
            $arg1 = "NULL"
        } else {
            Write-Host -nonewline "[+] " -ForegroundColor Green
            Write-Host "$arg1 Pingable"
        }
    }

    # by default, if '-Ping' is not used, then it is assumed the host is alive
    # return the name of the computer that is alive
    Return $arg1
} # End of PingTargs
##################################################################

##################################################################
function OutCustom{
    Param(
        [Parameter(Mandatory=$TRUE,ValueFromPipeline=$FALSE)]
        $object,
		[Parameter()]
		[Boolean] $CSV,
        [Parameter()]
        [Boolean] $TXT,
        [Parameter()]
        [String] $outputFileName 
    )
        
    # If $CSV Switch is used then output to CSV File
    if($CSV){
        Write-Output "Writing file to $outputFileName"
        $object | Export-Csv -Path "$outputFileName" -NoTypeInformation -Append -ErrorAction SilentlyContinue
    # If $TXT Switch is used then output to TXT File
    }elseif($TXT){
        $object | Out-File -Encoding "ASCII" -FilePath $outputFileName -Append -ErrorAction SilentlyContinue
    # Output to Console by Default
    }else{
        $object | Out-GridView
    }
}
##################################################################

##################################################################
#Requires -Version 2.0

<#
  This Export-CSV behaves exactly like native Export-CSV
  However it has one optional switch -Append
  Which lets you append new data to existing CSV file: e.g.
  Get-Process | Select ProcessName, CPU | Export-CSV processes.csv -Append
  
  For details, see

http://dmitrysotnikov.wordpress.com/2010/01/19/export-csv-append/

  (c) Dmitry Sotnikov  
#>

function Export-CSV {
[CmdletBinding(DefaultParameterSetName='Delimiter',
  SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
 [Parameter(Mandatory=$true, ValueFromPipeline=$true,
           ValueFromPipelineByPropertyName=$true)]
 [System.Management.Automation.PSObject]
 ${InputObject},

 [Parameter(Mandatory=$true, Position=0)]
 [Alias('PSPath')]
 [System.String]
 ${Path},
 
 #region -Append
 [Switch]
 ${Append},
 #endregion 

 [Switch]
 ${Force},

 [Switch]
 ${NoClobber},

 [ValidateSet('Unicode','UTF7','UTF8','ASCII','UTF32',
                  'BigEndianUnicode','Default','OEM')]
 [System.String]
 ${Encoding},

 [Parameter(ParameterSetName='Delimiter', Position=1)]
 [ValidateNotNull()]
 [System.Char]
 ${Delimiter},

 [Parameter(ParameterSetName='UseCulture')]
 [Switch]
 ${UseCulture},

 [Alias('NTI')]
 [Switch]
 ${NoTypeInformation})

begin
{
 # This variable will tell us whether we actually need to append
 # to existing file
 $AppendMode = $false
 
 try {
  $outBuffer = $null
  if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
  {
      $PSBoundParameters['OutBuffer'] = 1
  }
  $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Export-Csv',
    [System.Management.Automation.CommandTypes]::Cmdlet)
        
        
 #String variable to become the target command line
 $scriptCmdPipeline = ''

 # Add new parameter handling
 # Process and remove the Append parameter if it is present
 if ($Append) {
  
  $PSBoundParameters.Remove('Append') | Out-Null
    
  if ($Path) {
   if (Test-Path $Path) {        
    # Need to construct new command line
    $AppendMode = $true
    
    if ($Encoding.Length -eq 0) {
     # ASCII is default encoding for Export-CSV
     $Encoding = 'ASCII'
    }
    
    # For Append we use ConvertTo-CSV instead of Export
    $scriptCmdPipeline += 'ConvertTo-Csv -NoTypeInformation '
    
    # Inherit other CSV convertion parameters
    if ( $UseCulture ) {
     $scriptCmdPipeline += ' -UseCulture '
    }
    if ( $Delimiter ) {
     $scriptCmdPipeline += " -Delimiter '$Delimiter' "
    } 
    
    # Skip the first line (the one with the property names) 
    $scriptCmdPipeline += ' | Foreach-Object {$start=$true}'
    $scriptCmdPipeline += '{if ($start) {$start=$false} else {$_}} '
    
    # Add file output
    $scriptCmdPipeline += " | Out-File -Encoding `"ASCII`" -FilePath '$Path'"
    $scriptCmdPipeline += " -Append "
    
    if ($Force) {
     $scriptCmdPipeline += ' -Force'
    }

    if ($NoClobber) {
     $scriptCmdPipeline += ' -NoClobber'
    }   
   }
  }
 }  
 $scriptCmd = {& $wrappedCmd @PSBoundParameters }
 
 if ( $AppendMode ) {
  # redefine command line
  $scriptCmd = $ExecutionContext.InvokeCommand.NewScriptBlock(
      $scriptCmdPipeline
    )
 } else {
  # execute Export-CSV as we got it because
  # either -Append is missing or file does not exist
  $scriptCmd = $ExecutionContext.InvokeCommand.NewScriptBlock(
      [string]$scriptCmd
    )
 }

 # standard pipeline initialization
 $steppablePipeline = $scriptCmd.GetSteppablePipeline(
        $myInvocation.CommandOrigin)
 $steppablePipeline.Begin($PSCmdlet)
 
 } catch {
   throw
 }
    
}

process
{
  try {
      $steppablePipeline.Process($_)
  } catch {
      throw
  }
}

end
{
  try {
      $steppablePipeline.End()
  } catch {
      throw
  }
}
<#
.ForwardHelpTargetName Export-Csv
.ForwardHelpCategory Cmdlet
#>
}#