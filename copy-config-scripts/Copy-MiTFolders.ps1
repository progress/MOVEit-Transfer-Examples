#Requires -Modules MOVEit.MIT
#Requires -Version 7

<#
.SYNOPSIS
    Copy MiT folders from a source to a destination MiT server.  Includes
    copying acls.
.EXAMPLE
    ./Copy-MiTFolders
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
    [switch]
    $RunOnce
)

# Confirm we can connect to both src and dst
try {    
    Connect-MITServer -Hostname $SrcHostname -Credential $SrcCredential

    # Get all the users from the source since we'll use this for acl stuff.
    "Fetching all users from $SrcHostname"
    $page = 1
    $srcUserList = do {
        $paging, $userList = Get-MITUser -IncludePaging -Page $page -PerPage 100
        $userList
    } while ($page++ -lt $paging.totalPages)

    # Get all the groups from the source since we'll use this for acl stuff.
    "Fetching all groups from $SrcHostname"
    $page = 1
    $srcGroupList = do {
        $paging, $userList = Get-MITGroup -IncludePaging -Page $page -PerPage 100
        $userList
    } while ($page++ -lt $paging.totalPages)

    Disconnect-MITServer | Out-Null

    Connect-MITServer -Hostname $DstHostname -Credential $DstCredential

     # Get all the users from the dst since we'll use this for acls.
     "Fetching all users from $DstHostname"
     $page = 1
     $dstUserList = do {
         $paging, $userList = Get-MITUser -IncludePaging -Page $page -PerPage 100
         $userList
     } while ($page++ -lt $paging.totalPages)
 
     # Get all the groups from the dst since we'll use this for acls
     "Fetching all groups from $DstHostname"
     $page = 1
     $dstGroupList = do {
         $paging, $groupList = Get-MITGroup -IncludePaging -Page $page -PerPage 100
         $groupList
     } while ($page++ -lt $paging.totalPages)

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
    exists  = 0
    error   = 0
    acl     = 0
    aclerror = 0
}

# We're going to copy folders in batches.  We'll just use the REST API paging to
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

    Write-Host "Fetching folders from $SrcHostname"

    # Get a list of some folders, sorting by path, so we don't need to use recursion
    $paging, $folderList = Get-MITFolder @pagingParams -SortField path
    
    Write-Host "Page $($paging.page) of $($paging.totalPages)"

    # Get the full details and acls of each folder needed to copy them
    # to the destination.  
    $srcFolderList = $folderList  | ForEach-Object {
        $folder = Get-MITFolder -FolderId $_.id
        $folderAcl = Get-MITFolderAcl -FolderId $_.id
        $folder | Add-Member -MemberType NoteProperty -Name 'acl' -Value $folderAcl
        $folder
    }

    # Disconnect from source
    Disconnect-MITServer

    ### D E S T I N A T I O N ###

    # Connect to destination
    Connect-MITServer -Hostname $DstHostname -Credential $DstCredential

    Write-Host "Copying folders to $DstHostname"
        
    # Copy each source folder to the destination
    foreach ($srcFolder in $srcFolderList | Where-Object { $_.folderType -eq 'Normal' } ) {        
        try {
            # Get the dstFolder, creating if necessary.  We don't just want to skip the folder if it already
            # exists because we still want to update the permissions.
            if (-not ($dstFolder = Get-MITFolder -Path $srcFolder.path) ) {
                $dstParentFolderPath = (Split-Path -Path $srcFolder.path) -replace '\\', '/'
                # Let's see if we already have the dstParentFolder from the previous folder,
                # otherwise, get it.
                if (-not ($dstParentFolder = Get-MITFolder -Path $dstParentFolderPath) ) {
                        throw "Unable to get parent folder"
                }
                
                $newFolderSplat = @{
                    Name = $srcFolder.name
                    InheritPermissions = $srcFolder.parentInheritRights ? 'Always' : 'None'
                }                
                $dstFolder = $dstParentFolder | New-MITFolder @newFolderSplat
                "Folder $($dstFolder.path) created"   
                $stats.created++ 
            }
            else {
                Write-Warning "Folder $($dstFolder.path) already exists"

                # Get the full folder details
                $dstFolder = $dstFolder | Get-MITFolder
                
                #Update InheritPermissions if needed
                if (-not ([bool]$srcFolder.parentInheritRights -eq [bool]$dstFolder.parentInheritRights) ) {
                    $dstFolder = $dstFolder | Set-MITFolder -InheritAccess ([bool]$srcFolder.parentInheritRights)
                    "Folder $($dstFolder.path) inherit access changed"
                }
                $stats.exists++
            }            
        }
        catch {
            Write-Error "Folder $($srcFolder.path) encounterd errors."
            $_
            $stats.error++
            # Continue to the next folder
            continue
        }

        # Now let's update the user and group acls.
        foreach ($acl in $srcFolder.acl | Where-Object { $_.type -in 'User','Group' -and $_.isEditable} ){
            try {

                $typeId = $null
                if ($acl.type -eq 'User') {
                    # Let's find the user for this ACL
                    $srcFolderAclUser = $srcUserList | Where-Object { $_.id -eq $acl.id }

                    # Get the user on  dst with the matching username from src
                    # $dstFolderAclUser = Get-MITUser -Username $srcFolderAclUser.username -IsExactMatch
                    $dstFolderAclUser = $dstUserList | Where-Object { $_.username -eq $srcFolderAclUser.username}
                    $typeId = $dstFolderAclUser.id
                }
                elseif ($acl.type -eq 'Group') {
                    $srcFolderAclGroup = $srcGroupList | Where-Object { $_.id -eq $acl.id }
                    $dstFolderAclGroup = $dstGroupList | Where-Object { $_.name -eq $srcFolderAclGroup.name}
                    $typeId = $dstFolderAclGroup.id
                }

                if (-not $typeId) {
                    Write-Error "Unable to find $($acl.type) for $($acl.name) acl" -ErrorAction Stop
                }
                            
                $dstFolderAclSplat = @{
                    Type                = $acl.type
                    TypeId              = $typeId
                    ReadFiles           = $acl.permissions.readFiles
                    WriteFiles          = $acl.permissions.WriteFiles
                    DeleteFiles         = $acl.permissions.deleteFiles
                    ListFiles           = $acl.permissions.listFiles
                    Notify              = $acl.permissions.notify
                    AddDeleteSubfolders = $acl.permissions.addDeleteSubfolders
                    Share               = $acl.permissions.share
                    Admin               = $acl.permissions.admin
                    ListUsers           = $acl.permissions.listUsers
                }
                
                $dstFolder | Set-MITFolderAcl @dstFolderAclSplat | Out-Null   
                $stats.acl++             
            }
            catch {
                Write-Error "Folder $($srcFolder.path) acl $($acl.name) encountered errors"
                $_
                $stats.aclerror++
            }
        }        
    }

    # Disconnect from destination
    Disconnect-MITServer | Out-Null

} while ($pagingParams.page++ -lt $paging.totalPages -and -not $RunOnce)

$stats