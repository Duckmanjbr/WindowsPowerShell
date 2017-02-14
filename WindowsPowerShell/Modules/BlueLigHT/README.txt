LAST UPDATED: 	2 Aug 2015
POC: 			Capt. Ryan Rickert, 92 IOS/DOT, ryan.rickert.3@us.af.mil

The current iteration of BlueLight is a series of Powershell cmdlets that can be
used to gather host information. Previous users of Bluelight will notice that the
file structure has been changed significantly. This has been done for organizational
purposes; the use and functionality of BlueLight-Torch has been preserved.
One noticeable difference, however, is that although the file structure seems to
indicate that Torch and Laser are distinct modules (and they are), those modules
are nested modules under BlueLight.


Thus the following command will return all functions specified in Torch and Laser:

	Get-Command -Module BlueLight
	
However, referencing the Torch module directly will return nothing.

1. Base Configuration

	All user profiles should contain a **Junction** to the most current Bluelight directory.
	For example, the following junction, or something like it, should exist:
		C:\Users\assessor1\Documents\WindowsPowershell\ 
		- This is a junction pointing to something like:
			J:\Bluelight2.0\
	To verify that your junction has been properly created:
		1. Navigate to your user profile documents folder (C:\Users\[username]\Documents)
		2. Double click on the WindowsPowershell\ folder
		3. Verify that the directory you are in is IDENTICAL to the Bluelight directory:
			3.a: profile.ps1 exists
			3.b: The explorer navigation bar indicates you are in your profile
	
	If any of the above is not valid:
		1. Location junction.exe (from the SysInternals Suite)
		2. Run junction.exe C:\Users\[username]\Documents\WindowsPowershell\ J:\[Current BL Dir]
		
2. Working Configuration
	The primary configuration file is located in ...\BlueLight2.0\Modules\BlueLight\Config\Config.ini
	
	This is the file where you will specify your username, domain, domain controller IP, and all
	standard output directories.