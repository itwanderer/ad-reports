[CmdletBinding()]
Param(
    [Switch]$update
)

If ($PSBoundParameters['Debug'])  {
	$DebugPreference = 'Continue'
}


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
    $GroupMembers = Get-ADGroupMember -Identity $GroupName
    Write-Host "    Total Members (current membership): $($GroupMembers.sAMAccountName.count)"
    return $MemberHash

}

Function Update-GroupMembership {

    Param (
        $MemberHash,
        $GroupName


    )

 
    If ($MemberHash.ContainsKey("Enabled")) {
        Write-Host "Adding members to $($GroupName)"
        Add-ADGroupMember -Identity $GroupName -Members $MemberHash.Get_Item("Enabled").sAMAccountName -Confirm:$False
    }
    If ($MemberHash.ContainsKey("Disabled")) {
        Write-Host "Removing group members from $($GroupName)"
        Remove-ADGroupMember -Identity $GroupName -Members $MemberHash.Get_Item("Disabled").sAMAccountName -Confirm:$False
    }


    
}

Function Main {

    $Managers = Get-ADUser -LDAPFilter "(&(objectclass=user)(directreports=*))"

    ForEach ($Mgr in $Managers) {

        $drMemberHash = @{}    
        $DirectReports = Generate-Reports -ManagerDN $Mgr.DistinguishedName
        $drMemberHash = Process-Reports -List $DirectReports -Group "$($Mgr.SamAccountName)-DirectReports"
    
    
        $arMemberHash = @{}
        $AllReports = Generate-Reports -ManagerDN $Mgr.DistinguishedName -Recursive
        $arMemberHash = Process-Reports -List $AllReports -Group "$($Mgr.SamAccountName)-AllReports"
        #use $hash.ContainsKey("key) to check for key existence since it is possible that only one key exists
        #use $hash.Get_Item("key") to get value for associated key

        If ($update) {

            Write-Host "Updating group membership for $($Mgr.SamAccountName)-DirectReports"
            Update-GroupMembership -MemberHash $drMemberHash -GroupName "$($Mgr.SamAccountName)-DirectReports"

            Write-Host "Updating group membership for $($Mgr.SamAccountName)-AllReports"
            Update-GroupMembership -MemberHash $arMemberHash -GroupName "$($Mgr.SamAccountName)-AllReports"



        }
    
    }

}

Main

