function server-loop{
    while($true){
        Write-Host "Starting enum-processWMI loop"
        Enum-ProcessWMI2 -ComputerName (Get-Content T:\OPERATORS\Rickert\targs\servers.txt) -CSV
        Write-Host "Sleeping for 300 seconds"
        sleep 300
    }

}

