#Requires -Modules @{ ModuleName="MOVEit.MIT"; ModuleVersion="0.4.5" } 
#Requires -Version 7

<#
.SYNOPSIS
    Copy MiT groups from a source to a destination MiT server
.EXAMPLE
    ./Copy-MiTGroups
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

# Confirm we can connect to both src and des
try {    
    Connect-MITServer -Hostname $SrcHostname -Credential $SrcCredential
    Disconnect-MITServer | Out-Null

    Connect-MITServer -Hostname $DstHostname -Credential $DstCredential
    
     # Get all the users from the dst since we'll use this for group member stuff.
     "Fetching all users from $DstHostname"
     $dstUserList = Get-MITUser -All
 
     # Get all the groups from the dst to check if the group already exists
     "Fetching all groups from $DstHostname"
     $dstGroupList = Get-MITGroup -All
     
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

# We're going to copy groups in batches.  We'll just use the REST API paging to
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

    Write-Host "Fetching groups from $SrcHostname)"

    # Get a list of some groups
    $paging, $groupList = Get-MITGroup @pagingParams
    
    Write-Host "Page $($paging.page) of $($paging.totalPages)"

    # Get the group members of each groups too.
    $srcGroupList = $groupList  | ForEach-Object {
        $groupMember = Get-MITGroupMember -All -GroupId $_.id
        $_ | Add-Member -MemberType NoteProperty -Name 'member' -Value $groupMember
        $_
    }

    # Disconnect from source
    Disconnect-MITServer | Out-Null

    ### D E S T I N A T I O N ###

    # Connect to destination
    Connect-MITServer -Hostname $DstHostname -Credential $DstCredential

    Write-Host "Copying groups to $DstHostname"

    foreach ($srcGroup in $srcGroupList) {
        try{
            # Check if the group already exists
            if (${dstGroupList}?.Where({$_.name -eq $srcGroup.name}) ) {
                Write-Warning "Group $($srcGroup.name) already exists.  Skipping."
                $stats.exists++
                continue
            }

            # Add the group
            $newGroupSplat = @{
                Name = $srcGroup.name
                Description = $srcGroup.description
            }

            $dstGroup = New-MITGroup @newGroupSplat
            "Group $($dstGroup.name) created"

            # Add the group members
            
            # Need to get the userIds for the user's in the dst
            $newGroupMembers = foreach ($member in $srcGroup.member) {
                # Return the user from dstUserList with the matching username
                $dstUserList | Where-Object {$_.username -eq $member.username}
            }

            $dstGroup | Add-MITGroupMember -IncludePaging -UserIds $newGroupMembers.id | Out-Null
            "Group $($dstGroup.name) added $($newGroupMembers.Count) members"
            
            $stats.created++
        }
        catch {
            Write-Error "Group $($srcGroup.name) encounterd errors."
            $_
            $stats.error++
        }
    }

    # Disconnect from destination
    Disconnect-MITServer | Out-Null

} while ($pagingParams.page++ -lt $paging.totalPages -and -not $RunOnce)

$stats