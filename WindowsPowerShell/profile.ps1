function Get-Banner {
    param([Parameter(Position = 0)][Int32]$BannerId)

        if (($BannerId -notmatch "[0-8]") -or (!$PSBoundParameters['BannerId'])) { $BannerID = Get-Random -Minimum 1 -Maximum 8 }
        Write-Host

        switch ($BannerID)
        {
            1 {
                Write-Host "     __             ___         __       ___  " -foregroundcolor Blue
                Write-Host "    |__) |    |  | |__  |    | / _`` |__|  |  " -foregroundcolor Blue
                Write-Host "    |__) |___ \__/ |___ |___ | \__> |  |  |   " -foregroundcolor Blue
                Write-Host -Foreground Black
            }

            2 {
                Write-Host "          __                       __    " -ForegroundColor Red
                Write-Host "         /__`` |__/ |  | |    |    /__``   " -ForegroundColor Red
                Write-Host "         .__/ |  \ \__/ |___ |___ .__/   " -ForegroundColor Red
                Write-Host "        __        ___     __  __        __   __    "
                Write-Host "  |  | /__``  /\  |__     (__\  _)    | /  \ /__`` "
                Write-Host "  \__/ .__/ /~~\ |        __/ /__    | \__/ .__/   "
                Write-Host "     __             ___         __       ___  " -ForegroundColor Blue
                Write-Host "    |__) |    |  | |__  |    | / _`` |__|  |  " -ForegroundColor Blue
                Write-Host "    |__) |___ \__/ |___ |___ | \__> |  |  |   " -ForegroundColor Blue
                Write-Host -ForegroundColor Black
            }

            3 {
                Write-Host "             .=     ,        =.             " -ForegroundColor Blue
                Write-Host "     _  _   /'/    )\,/,/(_   \ \           " -ForegroundColor Blue 
                Write-Host "      ``//-.|  (  ,\\)\//\)\/_  ) |         " -ForegroundColor Blue
                Write-Host "      //___\   ``\\\/\\/\/\\///`'  /         " -ForegroundColor Blue
                Write-Host "   ,-`"~``-._ ```"--`'_   ```"`"`"``  _ \```'`"~-,_         " -ForegroundColor Blue
                Write-Host "   \       ``-.  `'_``.      .`'_`` \ ,-`"~``/         " -ForegroundColor Blue
                Write-Host "    ``.__.-`'``/   (-\        /-) |-.__,'         " -ForegroundColor Blue
                Write-Host "      ||   |     \O)  /^\ (O/  |         " -ForegroundColor Blue
                Write-Host "      ``\\  |         /   ``\    /         " -ForegroundColor Blue
                Write-Host "        \\  \       /      ``\ /         " -ForegroundColor Blue
                Write-Host "         ``\\ ``-.  /`' .---.--.\         " -ForegroundColor Blue
                Write-Host "           ``\\/``~(, `'()      (`'         " -ForegroundColor Blue
                Write-Host "            /(O) \\   _,.-.,_)         " -ForegroundColor Blue
                Write-Host "           //  \\ ``\`'``      /         " -ForegroundColor Blue
                Write-Host "          / |  ||   ```"`"`"`"~`"``         " -ForegroundColor Blue
                Write-Host "        /`'  |__||                    " -ForegroundColor Blue
                Write-Host "              ``o                    " -ForegroundColor Blue
                Write-Host -ForegroundColor Black
            }

            4 {
                Write-Host "       .--._.--.--.__.--.--.__.--.--._.--.    "
                Write-Host "     _(_      _Y_      _Y_      _Y_      _)_   "
                Write-Host "    [___]    [___]    [___]    [___]    [___]  "
                Write-Host -NoNewLine "    /:`' \  " -ForegroundColor Blue
                Write-Host -NoNewLine "  /:`' \  " -ForegroundColor Blue
                Write-Host -NoNewLine "  /:`' \  " -ForegroundColor Blue
                Write-Host -NoNewLine "  /:`' \  " -ForegroundColor Blue
                Write-Host -NoNewLine "  /:`' \  " -ForegroundColor Blue
                Write-Host
                Write-Host -NoNewLine "   |::   | " -ForegroundColor Blue
                Write-Host -NoNewLine " |::   | " -ForegroundColor Blue
                Write-Host -NoNewLine " |::   | " -ForegroundColor Blue
                Write-Host -NoNewLine " |::   | " -ForegroundColor Blue
                Write-Host -NoNewLine " |::   | " -ForegroundColor Blue
                Write-Host
                Write-Host -NoNewLine "   \::.  / " -ForegroundColor Blue
                Write-Host -NoNewLine " \::.  / " -ForegroundColor Blue
                Write-Host -NoNewLine " \::.  / " -ForegroundColor Blue
                Write-Host -NoNewLine " \::.  / " -ForegroundColor Blue
                Write-Host -NoNewLine " \::.  / " -ForegroundColor Blue
                Write-Host
                Write-Host -NoNewLine "    \::./  " -ForegroundColor Blue
                Write-Host -NoNewLine "  \::./  " -ForegroundColor Blue
                Write-Host -NoNewLine "  \::./  " -ForegroundColor Blue
                Write-Host -NoNewLine "  \::./  " -ForegroundColor Blue
                Write-Host -NoNewLine "  \::./  " -ForegroundColor Blue
                Write-Host
                Write-Host -NoNewLine "     ``=`'   " -ForegroundColor Blue
                Write-Host -NoNewLine "   ``=`'   " -ForegroundColor Blue
                Write-Host -NoNewLine "   ``=`'   " -ForegroundColor Blue
                Write-Host -NoNewLine "   ``=`'   " -ForegroundColor Blue
                Write-Host -NoNewLine "   ``=`'   " -ForegroundColor Blue
                Write-Host -ForegroundColor Black
                Write-Host
            }

            5 {
                Write-Host "                        (   ." -ForegroundColor Red
                Write-Host "            .     *      )        )" -ForegroundColor Red
                Write-Host "                     (  (|  ))   (      ." -ForegroundColor Red
                Write-Host "                 )   )\/ ( ( (    )          (" -ForegroundColor Red
                Write-Host "         *  (   ((  /     ))\))  ( *)    )   ))" -ForegroundColor Red
                Write-Host "       (     \   )\(          |  ))( )  (|  (*|" -ForegroundColor Red
                Write-Host "       *)     ))/   |          )/  \((  ) \   |" -ForegroundColor Red
                Write-Host "       (     (      .        -.     V )/   )(    (" -ForegroundColor Red
                Write-Host "        \   /     .   \            .       \))   ))" -ForegroundColor Red
                Write-Host -NoNewLine "          )(      ( |  |   )" -ForegroundColor Red
                Write-Host -NoNewLine " SKULLS" -ForegroundColor Blue
                Write-Host "     .    (  /" -ForegroundColor Red
                Write-Host -NoNewLine "         )(    " -ForegroundColor Red
                Write-Host -NoNewLine ",`')"
                Write-Host -NoNewLine ")     \ /  " -ForegroundColor Red
                Write-Host -NoNewLine " 92IOS" -ForegroundColor Blue
                Write-Host -NoNewLine "  \( " -ForegroundColor Red
                Write-Host -NoNewLine "``."
                Write-Host "    )" -ForegroundColor Red
                Write-Host -NoNewLine "         (\>  " -ForegroundColor Red
                Write-Host -NoNewLine ",`'/__      "
                Write-Host -NoNewLine "))   " -ForegroundColor Red
                Write-Host -NoNewLine " USAF" -ForegroundColor Blue
                Write-Host -NoNewLine "    __``.  "
                Write-Host "/" -ForegroundColor Red
                Write-Host -NoNewLine "        ( \   " -ForegroundColor Red
                Write-Host -NoNewLine "| /  ___   "
                Write-Host -NoNewLine "("  -ForegroundColor Red
                Write-Host -NoNewLine " \/     ___   \ | "
                Write-Host "( (" -ForegroundColor Red
                Write-Host -NoNewLine "         \.)  " -ForegroundColor Red
                Write-Host -NoNewLine "|/  /   \__      __/   \   \|  "
                Write-Host "))" -ForegroundColor Red
                Write-Host -NoNewLine "        .  \. " -ForegroundColor Red
                Write-Host -NoNewLine "|>  \      | __ |      /   <|  "
                Write-Host "/ (" -ForegroundColor Red
                Write-Host -NoNewLine "          )  )" -ForegroundColor Red
                Write-Host -NoNewLine "/    \____/ :..: \____/     \ "
                Write-Host "<  ))" -ForegroundColor Red
                Write-Host -NoNewLine "           \" -ForegroundColor Red
                Write-Host -NoNewLine "  |    ----;`' / | \ ;----     |   "
                Write-Host "/" -ForegroundColor Red
                Write-Host "               \__.       \/^\/       .__/"
                Write-Host "                V| \                 / |V"
                Write-Host "                 | |T~\___!___!___/~T| |"
                Write-Host "                 | |``IIII_I_I_I_IIII`'| |"
                Write-Host "                 |  \`,III I I I III,/  |"
                Write-Host "                  \   `~~~~~~~~~~~~~   /"
                Write-Host "                    \   .       .   /"
                Write-Host "                      \.    ^    ./"
                Write-Host "                        ^~~~^~~~^"
                Write-Host -ForegroundColor Black
            }

            6 {
                Write-Host "                    _,.---,---.,_           "
                Write-Host "                ,;~'             '~;,        "
                Write-Host "              ,;                     ;,      "
                Write-Host -NoNewLine "             ;             "
                Write-Host -NoNewLine "SKULLS" -ForegroundColor Blue
                Write-Host "      ;       "
                Write-Host -NoNewLine "            ,'              "
                Write-Host -NoNewLine "92IOS" -ForegroundColor Blue
                Write-Host "      /'      "
                Write-Host -NoNewLine "           ,;                "
                Write-Host -NoNewLine "USAF    " -ForegroundColor Blue
                Write-Host "/' ;,      "
                Write-Host "           ; ;      .           . <-'  ; |      "
                Write-Host -NoNewLine "           | ;   "
                Write-Host -NoNewLine "___            ___   " -ForegroundColor Blue
                Write-Host ";  |      "
                Write-Host -NoNewLine "           |/   "
                Write-Host -NoNewLine "/   \__      __/   \" -ForegroundColor Blue
                Write-Host "   \ |    "
                Write-Host -NoNewLine "           |>   "
                Write-Host -NoNewLine "\      |" -ForegroundColor Blue
                Write-Host -NoNewLine " __ "
                Write-Host -NoNewLine "|      /" -ForegroundColor Blue
                Write-Host "    <|    "
                Write-Host -NoNewLine "            \    "
                Write-Host -NoNewLine "\____/ " -ForegroundColor Blue
                Write-Host -NoNewLine ":..: "
                Write-Host -NoNewLine "\____/" -ForegroundColor Blue
                Write-Host "     \     "
                Write-Host "            |    ----;' / | \ ;----     |     "
                Write-Host "             \__.       \/^\/       .__/      "
                Write-Host "              V| \                 / |V       "              
                Write-Host "               | |T~\___!___!___/~T| |      "
                Write-Host "               | |'IIII_I_I_I_IIII'| |      "
                Write-Host "               |  \,III I I I III,/  |      "
                Write-Host "                \   ''~~~~~~~~~~''  /      "
                Write-Host "                  \   .       .   /          "          
                Write-Host "                    \.    ^    ./            "
                Write-Host "                      ^~~~^~~~^               "              
                Write-Host -ForegroundColor Black
            }

            7 {
                Write-Host "                          _------_ " -ForegroundColor Blue
                Write-Host "                        -~        ~- " -ForegroundColor Blue
                Write-Host -NoNewLine "                       -     " -ForegroundColor Blue
                Write-Host -NoNewLine "_      "
                Write-Host "- " -ForegroundColor Blue
                Write-Host -NoNewLine "                      -      " -ForegroundColor Blue
                Write-Host -NoNewLine "|"
                Write-Host -NoNewLine ">      " -ForegroundColor Blue
                Write-Host "- " -ForegroundColor Blue
                Write-Host -NoNewLine "                      -      " -ForegroundColor Blue
                Write-Host -NoNewLine "|"
                Write-Host "<      - " -ForegroundColor Blue
                Write-Host -NoNewLine "                       -     " -ForegroundColor Blue
                Write-Host -NoNewLine "|"
                Write-Host ">     - " -ForegroundColor Blue
                Write-Host -NoNewLine "                        -    " -ForegroundColor Blue
                Write-Host -NoNewLine "||    "
                Write-Host "- " -ForegroundColor Blue
                Write-Host -NoNewLine "                         -   " -ForegroundColor Blue
                Write-Host -NoNewLine "||   "
                Write-Host "- " -ForegroundColor Blue
                Write-Host -NoNewLine "                          -" -ForegroundColor Blue
                Write-Host -NoNewLine "__||__"
                Write-Host "- " -ForegroundColor Blue
                Write-Host -NoNewLine "    __             ___ " -ForegroundColor Blue
                Write-Host -NoNewLine "   |______|           "
                Write-Host "__       ___" -ForegroundColor Blue
                Write-Host -NoNewLine "   |__) |    |  | |__     " -ForegroundColor Blue
                Write-Host -NoNewLine "<______>   "
                Write-Host "|    | / _`` |__|  |" -ForegroundColor Blue
                Write-Host -NoNewLine "   |__) |___ \__/ |___    " -ForegroundColor Blue
                Write-Host -NoNewLine "<______>   "
                Write-Host "|___ | \__> |  |  |" -ForegroundColor Blue
                Write-Host "                             \/ "
                Write-Host -ForegroundColor Black
            }

            8 {
                Write-Host "                                 / " -ForegroundColor Blue
                Write-Host -NoNewLine "                      _.----"
                Write-Host ".  /  _  " -ForegroundColor Blue 
                Write-Host -NoNewLine "    .----------------`" /  "
                Write-Host "/  \  -``        " -ForegroundColor Blue 
                Write-Host -NoNewLine "   (    PoSh >_     | |   "
                Write-Host -NoNewLine ")  " -ForegroundColor DarkCyan
                Write-Host "|   ----       " -ForegroundColor Blue
                Write-Host -NoNewLine "    ``----------------._\  "
                Write-Host "\  /  -._        " -ForegroundColor Blue 
                Write-Host -NoNewLine "                       `"----"
                Write-Host "`'  \      " -ForegroundColor Blue 
                Write-Host -NoNewLine "                                 \                " -ForegroundColor Blue
                Write-Host "RBOT" -ForegroundColor DarkBlue
                Write-Host -ForegroundColor Black
            }
        }

        Write-Host
        if ($BannerId -ne 0) {
            Write-Host " USAF 92 IOS - Skulls - BlueLigHT - PowerShell 'Torch/Laser'"
        } 
        else  {
            Write-Host -NoNewLine " USAF 92 IOS -"
            Write-Host -NoNewLine " Skulls" -ForegroundColor Red
            Write-Host -NoNewLine " -"
            Write-Host -NoNewLine " BlueLight" -ForegroundColor Blue
            Write-Host " - Win PowerShell cmdlets" -ForegroundColor Black
        }
        Write-Host
        Write-Host " Current Version: $CurrentVersion"
        Write-Host "            Date: 18 Aug 2015"
        Write-Host "             POC: Jesse `"RBOT`" Davis"
        Write-Host
        Write-Host "        Current Domain: $TargetDomain"
        Write-Host
}

function Start-BlueLigHT {
[CmdLetBinding(SupportsShouldProcess = $false)]
    param (
        [Parameter(Mandatory = $true)]
        [String]$ConfigFilePath
    )
 
    if ([IO.File]::Exists($ConfigFilePath)) {
        $file = Get-Content $ConfigFilePath
        foreach ($line in $file) {  
            if ($line[0] -ne '#' -and -not [String]::IsNullOrEmpty($line)) {
             
                # split the contents of each line in the file on the =               
                $contents = $line.split('=')
                # the data before the = becomes the variable name
                $varName = $contents[0] 
                # the data after the = becomes the variable value                                       
                $varValue = $contents[1]
                # create a variable call varName with a value of varValue
                Set-Variable -Name $varName -Value $varValue -scope global
            }     
        }
    }
    else {
        Write-Warning "Config file not found at the specified location, try again!"
        break
    }

    Get-Banner
    
    #Test Domain Admin Credentials
    if ($TargetDomain -eq $null) {
        Write-Warning "No target domain specified!"
        $Global:TargetDomain = Read-Host "Please specify target domain to continue"
    }
    if ($DomainControllerIp -eq $null) {
        Write-Warning "Domain controller IP address not found!"
        $DomainControllerIp = Read-Host "Please specify domain controller's IP address to continue"
    }
    
    Write-Host '[*]' -NoNewline -ForegroundColor Yellow
    Write-Host 'Testing Domain Admin Credentials'
    try { [void](Get-WmiObject Win32_OperatingSystem -ComputerName $DomainControllerIP) }
    catch [UnauthorizedAccessException] {
        Throw 'Domain admin credentials invalid!'  
    }
    Write-Host '[+]' -NoNewline -ForegroundColor Green
    Write-Host 'Domain Admin Credentials Valid.'

    if (![IO.Directory]::Exists($Transcript)) {
        $Global:Transcript = Read-Host -Debug "Transcript directory not found. Enter new Transcript directory"
        if (![IO.Directory]::Exists($Transcript)) {
            New-Item -Path $Transcript -ItemType Directory -Confirm
        }
    }

    $Transcript = (Resolve-Path $Transcript).Path
    $User = Read-Host "Enter Your Call Sign"
    $TranscriptPath = $Transcript.TrimEnd('\') + "\$(Get-Date -Format yyyyMMdd_hhmmss)"  + '_' + $User + ".txt"

    Start-Transcript -Path $TranscriptPath
    Import-Module BlueLigHT
}
