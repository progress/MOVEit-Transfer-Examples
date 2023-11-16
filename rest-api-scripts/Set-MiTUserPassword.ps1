#Requires -Modules MOVEit.MIT

<#
.SYNOPSIS
    Sample script to set user's passwords to a random password and optionally send a password change
    notification and optionally override the force change password behavior.
.NOTES
    Prompts for confirmation
    Only includes EndUsers
.COMPONENT
    Requires the MOVEit.MIT module
    Install-Module -Name MOVEit.MIT
.EXAMPLE
    # Set password for a single user
    .\Set-MiTUserPassword.ps1 -Hostname <hostname> -Credential <username> -Username <username-to-set> -IsExactMatch
.EXAMPLE
    # Set password for multiple users
    .\Set-MiTUserPassword.ps1 -Hostname <hostname> -Credential <username> -Username <username-to-set>
.EXAMPLE
    # Set password and send notification    
    .\Set-MiTUserPassword.ps1 -Hostname <hostname> -Credential <username> -Username <username-to-set> -SendPasswordChangeNotification
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param (
    [Parameter(Mandatory)]
    [string]$Hostname,

    [Parameter(Mandatory)]
    [System.Management.Automation.Credential()]
    [pscredential]$Credential,

    [Parameter(Mandatory)]
    [string]$Username,

    [Parameter()]
    [switch]$IsExactMatch,

    [Parameter()]
    [switch]$SendPasswordChangeNotification,

    [Parameter()]
    [bool]$ForceChangePassword
)

# Function to generate random passwords
function New-RandomPassword  {
    -join ( @(
        ($lcase   = 'a'..'z')                   | Get-Random
        ($ucase   = 'A'..'Z')                   | Get-Random
        ($numeric = '0'..'9')                   | Get-Random
        ($symbol  = '!@#$%^&*'.ToCharArray())   | Get-Random
        ($lcase + $ucase + $numeric + $symbol)  | Get-Random -Count 10
    ) | Get-Random -Shuffle ) 
}

# Exit if we can't connect
try { Connect-MITServer -Hostname $hostname -Credential $Credential } catch { throw }

# Get the list of users and output them
($userList = Get-MITUser -Username $Username -IsExactMatch:$IsExactMatch -Permission EndUsers)

# Process each user
$userList | ForEach-Object {
    if ($PSCmdlet.ShouldProcess($_.Username, "Set Password")) {
        $user = $_        
        try{
            $user = $_ | Set-MITUser -Password (New-RandomPassword) -SendPasswordChangeNotification $SendPasswordChangeNotification
            "User '$($user.username)' password reset."
            
            if ($PSBoundParameters.ContainsKey('ForceChangePassword')) {
                $user = $_ | Set-MITUser -ForceChangePassword $ForceChangePassword
                "User '$($user.username)' ForceChangePassword set to $ForceChangePassword"
            }                        
        }
        catch {
            Write-Error "User '$($user.username)'. $PSItem"
        }
    }
}

Disconnect-MITServer