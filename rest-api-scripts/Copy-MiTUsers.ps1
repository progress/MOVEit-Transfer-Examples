#Requires -Modules MOVEit.MIT
#Requires -Version 7

Set-StrictMode -Version Latest

# Edit to match your environment
$sourceParams = @{
    Hostname = '<source-mit-server>'
    Credential = (Get-Credential -Message "Login to Source" -Username 'admin')
}

# Confirm we can connect
try {    
    Connect-MITServer @sourceParams
    Disconnect-MITServer
}
catch {
    # Exit the script
    throw
}    

# Edit to match your environment
$destParams = @{
    Hostname = '<dest-mit-server>'
    Credential = (Get-Credential -Message "Login to Destination" -Username 'admin')
}

# Confirm we can connect
try {
    Connect-MITServer @destParams
    # Get the root folder on the destination since we'll need it later.
    $destRootFolder = Get-MITFolder -Path "/"
    Disconnect-MITServer
} 
catch {
    # Exit the script
    throw
}

# Edit for your preference
$defaultNewUserPassword = 'abc123'

# We're going to copy users in batches.  We'll just use the REST API paging to
# do this.
$pagingParams = @{
    Page = 1
    PerPage = 5
    IncludePaging = $true
}

do {
    
    ### S O U R C E ###

    # Connect to source    
    Connect-MITServer @sourceParams

    Write-Host "Fetching users from $($sourceParams.Hostname)"

    # Get a list of some users
    $paging, $userList = Get-MITUser @pagingParams
    
    Write-Host "Page $($paging.page) of $($paging.totalPages)"
    
    # Get the full details of each user needed to copy them
    # to the destination
    $sourceUser = @()
    $userList | ForEach-Object {
        $user = Get-MITUser -UserId $_.id
        $homeFolderPath = $user.homeFolderID ? (Get-MITFolder -FolderId $user.homeFolderID).path : $null
        $user | Add-Member -MemberType NoteProperty -Name 'homeFolderPath' -Value $homeFolderPath
        $sourceUser += $user
    }

    # Disconnect from source
    Disconnect-MITServer

    ### D E S T I N A T I O N ###

    # Connect to destination
    Connect-MITServer @destParams

    Write-Host "Copying users to $($destParams.Hostname)"
    
    # Copy each source user to the destination
    $sourceUser | ForEach-Object {
        # Use a hashtable to splat the parameters for New-MITUser
        $newUserSplat = @{
            Username            = $_.username
            Fullname            = $_.fullname
            Email               = $_.email
            Password            = $defaultNewUserPassword
            ForceChangePassword = $true
            Permission          = $_.permission
            HomeFolderPath      = $_.homeFolderPath
            Notes               = $_.notes
        }

        try {
            # Check if the user already exists and if so, skip
            if (Get-MITUser -Username $($newUserSplat.Username) -IsExactMatch) {
                Write-Warning "User $($newUserSplat.Username) already exists."
                return
            }

            # Check if the home folder root for this user exists, otherwise, create it.
            # Note: this is only going to handle home folders that are 1 level deep (ie. /Home).
            if ($newUserSplat.homeFolderPath) {
                $homeFolderRootName = ($newUserSplat.homeFolderPath -split '/')[1]
                if (-not ($destRootFolder | Get-MITFolderContent -Name $homeFolderRootName -Subfolder)) {                    
                    $newFolder = $destRootFolder | New-MITFolder -Name $homeFolderRootName -InheritPermissions None
                    "Folder $($newFolder.Path) created"
                }
            }

            # Add the user
            $newUser = New-MitUser @newUserSplat
            "User $($newUser.Username) created"

            # Set other attributes on the new user that can only be set one-by-one            
            $newUser | Set-MITUser -Status $_.Status | Out-Null            
            $newUser | Set-MITUser -AuthMethod $_.AuthMethod | Out-Null
            $newUser | Set-MITUser -ReceivesNotification $_.ReceivesNotification | Out-Null            
        }
        catch {
            Write-Error "User $($newUserSplat.Username) encounterd errors."
            $_
        }
    }

    # Disconnect from destination
    Disconnect-MITServer

} while ($pagingParams.page++ -lt $paging.totalPages)