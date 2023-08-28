# MOVEit Transfer "Copy Config" examples
 ## Description
 Included are some example scripts for copying the following configuration from one MiT server to another:
 - Users
 - Groups
 - Folders (including permissions)
 ## Requirements
 These scripts require
 - PowerShell 7
 - MOVEit.MIT module

 Once you have PowerShell 7 installed, install the MOVEit.MIT module:
 ```powershell
 Install-Module -Name MOVEit.MIT
 ```
 ## Usage
 After downloading the scripts, start with Users.  To run, simply change directories to the folder containing the scripts and type:
 ```powershell
 .\Copy-MiTUsers.ps1
 ```
 If this is the first time running the script, you may want to use the `-RunOnce` parameter.  This causes the script to only process the first 20 users rather than all of the users.
 ```powershell
 .\Copy-MiTUsers.ps1 -RunOnce
 ```
 The script will prompt for:
 - SrcHostname
 - SrcCredential
 - DstHostname
 - DstCredential

These can also be specified as parameters.  If the script can successfully connect to both servers, these parameters are _cached_ so they don't need to be provided again during the current PowerShell session.

After users, proceed to Groups:
```powershell
.\Copy-MiTGroups.ps1
```

And finally, Folders:
```powershell
.\Copy-MiTFolders.ps1
```
## Support
These script examples come with no warranty or support from anyone and are offered as-is.
 