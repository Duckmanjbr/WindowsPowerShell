######Updated:  30 Sep 2015
######POC:  Jesse "RBOT" Davis, jesse.davis.5@us.af.mil
<hr>
The current iteration of BlueLight is a major re-write aimed at eliminating its original hard-coded deficiencies and lack of error checking/handling. BlueLigHT is a collection of Powershell scripts that can be used to gather host information. Previous 
users of Bluelight will notice that the file structure has been changed significantly, this has been done for organizational purposes. The use and functionality of BlueLight Torch has been preserved, expanded, and streamlined. One noticeable difference is that Torch and Laser are now properly treated as distinct modules, imported at runtime by the Start-BlueLigHT routine.

The following command will return all functions specific to the base BlueLigHT module:
  * **Get-Command -Module BlueLight**

To get a list of functions from the Torch / Laser Modules:
  * **Get-Command -Module Torch**
  * **Get-Command -Module Laser**

1. Base Configuration
  * All user profiles should contain a symbolic link to the most current BlueLigHT directory. For example, the following symlink should exist: **C:\Users\assessor\Documents\WindowsPowershell\** 
  * This is a symlink pointing to something like: **J:\BlueLigHT\**
  * To verify that your symlink has been properly created:
    1. Navigate to your user profile documents folder **C:\Users\username\Documents**
    2. Open the **WindowsPowershell** folder
    3. Verify that the directory's contents are IDENTICAL to the BlueLigHT directory.

2. If any of the above is not valid, create a new symlink with the following command:
  * **cmd.exe /c mklink /d $HOME\Documents\WindowsPowershell\ [Path to BlueLigHT]**
		
3. Working Configuration
  * The primary configuration file is located in ...\BlueLigHT\WindowsPowershell\Config.ini
  * This is the file where you will specify your username, domain, domain controller IP, and any other required 
configuration infomation.
