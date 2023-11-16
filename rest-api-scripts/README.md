# MOVEit Transfer REST API examples
## Description
MOVEit Transfer supports a [REST API](https://docs.ipswitch.com/MOVEit/Transfer2023/Api/Rest/index.html).  These are some example PowerShell scripts that call the REST API. 

## Requirements
These scripts require
- MOVEit Automation server with REST API option
- PowerShell 7
- [MOVEit.MIT module](https://github.com/Tony-Perri/MOVEit.MIT)

Once you have PowerShell 7 installed, install the MOVEit.MIT module:
```powershell
Install-Module -Name MOVEit.MIT
```
## Usage
After downloading the scripts, simply change directories to the folder containing the scripts and run them.  Feel free to edit them as well, they are examples after all.

### Set-MiTUserPassword
Sample script to set user's passwords to a random password and optionally send a password change notification and optionally override the force change password behavior.
```powershell
# Set password for a single user
.\Set-MiTUserPassword.ps1 -Hostname <hostname> -Credential <username> -Username <username-to-set> -IsExactMatch

# Set password for multiple users
.\Set-MiTUserPassword.ps1 -Hostname <hostname> -Credential <username> -Username <username-to-set>

# Set password and send notification    
.\Set-MiTUserPassword.ps1 -Hostname <hostname> -Credential <username> -Username <username-to-set> -SendPasswordChangeNotification
```
## Support
These script examples come with no warranty or support from anyone and are offered as-is.
