#Requires -Modules MOVEit.MIT
#Requires -Version 7

<#
.SYNOPSIS
    Copy MiT users from a source to a destination MiT server
.EXAMPLE
    ./Copy-MiTUsers
#>
[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $SrcHostname = $Global:MiTConnParams.SrcHostname ?? (Read-Host -Prompt "Enter hostname for source MiT server"),

    [Parameter()]
    [pscredential]
    $SrcCredential = $Global:MiTConnParams.SrcCredential ?? (Get-Credential -Message "Enter admin credentials for $SrcHostname"),

    [Parameter()]
    [string]
    $DstHostname = $Global:MiTConnParams.DstHostname ?? (Read-Host -Prompt "Enter hostname for destination MiT server"),

    [Parameter()]
    [pscredential]
    $DstCredential = $Global:MiTConnParams.DstCredential ?? (Get-Credential -Message "Enter admin credentials for $DstHostname"),

    [Parameter()]
    [string]
    $NewPassword,

    [Parameter()]
    [switch]
    $RunOnce
)

# Confirm we can connect to both src and dst
try {    
    Connect-MITServer -Hostname $SrcHostname -Credential $SrcCredential
    Disconnect-MITServer | Out-Null

    Connect-MITServer -Hostname $DstHostname -Credential $DstCredential
    # Get the root folder on the destination since we'll need it later.
    $dstRootFolder = Get-MITFolder -Path "/"
    Disconnect-MITServer | Out-Null

    # Create a hashtable to cache the connection parameters
    $Global:MiTConnParams = @{
        SrcHostname     = $SrcHostname
        SrcCredential   = $SrcCredential
        DstHostname     = $DstHostname
        DstCredential   = $DstCredential
    }

    "Connection parameters cached for re-running script or running other scripts"
}
catch {
    $Global:MiTConnParams = $null
    # Exit the script
    throw
}    


$stats = [pscustomobject]@{
    created = 0
    exists = 0
    error = 0
}

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

# We're going to copy users in batches.  We'll just use the REST API paging to
# do this.
$pagingParams = @{
    Page = 1
    PerPage = 20
    IncludePaging = $true
}

do {
    
    ### S O U R C E ###

    # Connect to source    
    Connect-MITServer -Hostname $SrcHostname -Credential $SrcCredential

    Write-Host "Fetching users from $SrcHostname"

    # Get a list of some users
    $paging, $userList = Get-MITUser @pagingParams
    
    Write-Host "Page $($paging.page) of $($paging.totalPages)"

    # Get the full details of each user needed to copy them
    # to the destination
    $srcUserList =  $userList | ForEach-Object {
        $user = Get-MITUser -UserId $_.id
        $homeFolderPath = $user.homeFolderID ? (Get-MITFolder -FolderId $user.homeFolderID).path : $null
        $user | Add-Member -MemberType NoteProperty -Name 'homeFolderPath' -Value $homeFolderPath
        $user
    }

    # Disconnect from source
    Disconnect-MITServer | Out-Null

    ### D E S T I N A T I O N ###

    # Connect to destination
    Connect-MITServer -Hostname $DstHostname -Credential $DstCredential

    Write-Host "Copying users to $DstHostname"
    
    # Copy each source user to the destination
    foreach ($srcUser in $srcUserList) {        
        try {
            # Check if the user already exists and if so, skip
            if (Get-MITUser -Username $($srcUser.Username) -IsExactMatch) {
                Write-Warning "User $($srcUser.Username) already exists.  Skipping."
                $stats.exists++
                continue
            }

            # Check if the home folder root for this user exists, otherwise, create it.
            # Note: this is only going to handle home folders that are 1 level deep (ie. /Home).
            if ($srcUser.homeFolderPath) {
                $homeFolderRootName = (Split-Path -Path $srcUser.homeFolderPath) -replace '^\\', ''
                if (-not ($dstRootFolder | Get-MITFolderContent -Name $homeFolderRootName -Subfolder)) {                    
                    $newFolder = $dstRootFolder | New-MITFolder -Name $homeFolderRootName -InheritPermissions None
                    "Folder $($newFolder.Path) created"
                }
            }

            # Use a hashtable to splat the parameters for New-MITUser
            $newUserSplat = @{
                Username            = $srcUser.username
                Fullname            = $srcUser.fullname
                Email               = $srcUser.email
                Password            = ($NewPassword) ? $NewPassword : (New-RandomPassword)
                ForceChangePassword = $true
                Permission          = $srcUser.permission
                HomeFolderPath      = $srcUser.homeFolderPath
                Notes               = $srcUser.notes
            }

            # Add the user
            $dstUser = New-MitUser @newUserSplat
            "User $($dstUser.Username) created"

            # Set other properites on the new user that can only be set one-by-one
            if ($dstUser.status -ne $srcUser.status) {
                $dstUser | Set-MITUser -Status $srcUser.Status | Out-Null
                "User $($dstUser.Username) updated Status"
            }

            if ($dstUser.authMethod -ne $srcUser.authmethod) {
                $dstUser | Set-MITUser -AuthMethod $srcUser.AuthMethod | Out-Null
                "User $($dstUser.Username) updated AuthMethod"
            }

            if ($dstUser.receivesNotification -ne $srcUser.receivesNotification) {
                $dstUser | Set-MITUser -ReceivesNotification $srcUser.ReceivesNotification | Out-Null            
                "User $($dstUser.Username) updated ReceivesNotification"
            }

            $stats.created++
        }
        catch {
            Write-Error "User $($srcUser.Username) encounterd errors."
            $_
            $stats.error++
        }
    }

    # Disconnect from destination
    Disconnect-MITServer | Out-Null

} while ($pagingParams.page++ -lt $paging.totalPages -and -not $RunOnce)

$stats