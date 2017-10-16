<#
    
.SYNOPSIS

Creates amd updates direct and all report (indirect) groups for managers,i.e. users with populated directReports attribute

.DESCRIPTION

This script performs the following:

1.  Generates a list of direct reports 
2.  Generates a list of all reports by traversing the directReports hierarchy
3.  Creates 2 lists, 1 with enabled reports and 1 with disabled reports, for both direct and all reports
4.  Creates the allReports or direcReports group, if necessary, using the convention samaccountname-directReports or samaccountname-Allreports
5.  Updates group members by adding or removing enabled and disabled members respectively
6.  Produces a report comparing current group members vs. membership based on directReports attribute and user state (enabled or disabled)

Mote:  The script runs in report mode when -update argument is not specified

.PARAMETER update

Boolean switch to indicate if group membershop should be update. Script runs in report mode otherwise

.EXAMPLE 

To produce a report 

.\reports.ps1

.EXAMPLE

To update group memberships

.\reports.ps1 -update


.NOTES 

Any miscellaneous notes on using the script or function.

.LINK

A cross-reference to another help topic; you can have more than one of these. If you include a URL beginning with http:// or https://, the shell will open that URL when the Help command’s –online parameter is used.

#>


<#
TODO:
- add logging to file and eventlog
- send email of report
#>
[CmdletBinding()]
Param(
    [Switch]$update
)

If ($PSBoundParameters['Debug'])  {
	$DebugPreference = 'Continue'
}

#Region Functions

Function Generate-Reports {
	Param(
		[String]$ManagerDN,
		[String]$SearchBase,
		[Switch]$Recursive
	
	)
    $LdapFilter = "(&(objectclass=user)(manager=" + $managerDN + "))"
	$DirectReports = Get-ADUser -LDAPFilter $LdapFilter -pro directReports
    if ($DirectReports -eq $null) { continue; }
    $AllReports += $DirectReports

    If ($recursive) {

        ForEach ($entry in $DirectReports) {
             If ($entry.DirectReports -gt 0) {
                If ($entry.distinguishedname -eq $managerDN) {
                    Write-Host "Circular manager reference, skipping $($entry.name)"
                    Continue
                }
                Generate-Reports -managerDN $entry.distinguishedname  -recursive
            }
        
        }
    }

    return $AllReports
}




Function Process-Reports {
    Param(
        $List,
        $GroupName
    )
    
    $MemberHash = @{}
    $DisabledMembers = $null
    $EnabledMembers = $null

    $ReportState = $List | Group-Object Enabled| Sort-Object Name -Descending
    Write-Host "`n$($GroupName)"
    Write-Host "    Total Members (per directReports attrib): $($List.sAMAccountName.Count)"
    ForEach ($State in $ReportState) {
        If ($State.name -eq "True") { 
            Write-Host "      Enabled Members: $($State.Count)"
            $EnabledMembers = $State.group
            $MemberHash.Enabled = $EnabledMembers
        }
        Else {
            Write-Host "      Disabled Members: $($State.Count)"
            $DisabledMembers = $State.group
            $MemberHash.Disabled = $DisabledMembers
        }
        
    }

    #TODO: Check if group exists before running query
    $GroupMembers = Get-ADGroupMember -Identity $GroupName
    Write-Host "    Total Members (current membership): $($GroupMembers.sAMAccountName.count)"
    return $MemberHash

}

Function Create-Group {

    Param(

        [string]$Name,
        [string]$Base,
        [string]$Category = "Security",
        [string]$Scope = "Universal",
        [string]$Description = "Auto Generated"
    )
    
    #TODO: Error checking using try .... catch
    New-ADGroup -Name $Name `
                -SamAccountName $Name `
                -GroupCategory $Category `
                -GroupScope $Scope `
                -Description $Description `
                -Path $Base


}

Function Update-GroupMembership {

    Param (
        $MemberHash,
        $GroupName


    )

 
    #TODO: Error checking using try .... catch
    If ($MemberHash.ContainsKey("Enabled")) {
        Write-Host "Adding members to $($GroupName)"
        Add-ADGroupMember -Identity $GroupName -Members $MemberHash.Get_Item("Enabled").sAMAccountName -Confirm:$False
    }

    #TODO: Error checking using try .... catch
    If ($MemberHash.ContainsKey("Disabled")) {
        Write-Host "Removing group members from $($GroupName)"
        Remove-ADGroupMember -Identity $GroupName -Members $MemberHash.Get_Item("Disabled").sAMAccountName -Confirm:$False
    }


    
}

#EndRegion

#Region Main

#TODO: Store Constant Vars in a JSON file
#Constant Variables
$GROUP_RB = 'OU=Reporting Structure,OU=Groups,OU=Managed'
$GROUP_ALLREPORTS_SUFFIX = '-AllReports'
$GROUP_DIRECTREPORTS_SUFFIX = '-DirectReports'
$USER_RB = 'OU=Users,OU=Managed'
$USER_FILTER = '(&(objectclass=user)(directReports=*))'
$SEARCH_SCOPE = 'subtree'
$LOGFILE_SUFFIX = '_Log.log' 

#Dynamic Variables
$Domain_DN = (Get-ADRootDSE).DefaultNamingContext

#Constructed Variables
$GroupBaseOU = $GROUP_RB + "," + $Domain_DN
$UserBaseOU = $USER_RB + "," + $Domain_DN
$LogPath = $PSCommandPath -replace   '.ps1$', $LOGFILE_SUFFIX


$Managers = Get-ADUser -LDAPFilter $USER_FILTER -SearchBase $UserBaseOU

ForEach ($Mgr in $Managers) {

    $drMemberHash = @{}    
    $DirectReports = Generate-Reports -ManagerDN $Mgr.DistinguishedName
    $drMemberHash = Process-Reports -List $DirectReports -Group "$($Mgr.SamAccountName)-DirectReports"


    $arMemberHash = @{}
    $AllReports = Generate-Reports -ManagerDN $Mgr.DistinguishedName -Recursive
    $arMemberHash = Process-Reports -List $AllReports -Group "$($Mgr.SamAccountName)-AllReports"

    If ($update) {

        $DirectReportsGroup = $Mgr.SamAccountName + $GROUP_DIRECTREPORTS_SUFFIX
        $AllReportsGroup = $Mgr.SamAccountName + $GROUP_ALLREPORTS_SUFFIX

        If ((Get-ADGroup -Filter {sAMAccountName -eq $DirectReportsGroup}) -eq $null) {
            Write-Host "$($DirectReportsGroup) does not exist, calling function to create"
            Create-Group -Name $DirectReportsGroup -Base $GroupBaseOU
        } 

        Write-Host "Updating group membership for $($DirectReportsGroup)"
        Update-GroupMembership -MemberHash $drMemberHash -GroupName $DirectReportsGroup

        If ((Get-ADGroup -Filter {sAMAccountName -eq $AllReportsGroup}) -eq $null) {
            Write-Host "$($AllReportsGroup) does not exist, calling function to create"
            Create-Group -Name $AllReportsGroup -Base $GroupBaseOU
        } 

        Write-Host "Updating group membership for $($AllReportsGroup)"
        Update-GroupMembership -MemberHash $arMemberHash -GroupName $AllReportsGroup



    }

}


#EndRegion

