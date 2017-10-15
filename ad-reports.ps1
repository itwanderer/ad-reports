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
        $Group
    )
    
    $MemberHash = @{}
    $DisabledMembers = $null
    $EnabledMembers = $null

    $ReportState = $List | Group-Object Enabled| Sort-Object Name -Descending
    Write-Host "`n$($Group)"
    Write-Host "    Total Members: $($List.sAMAccountName.Count)"
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
    return $MemberHash

}

$Managers = Get-ADUser -LDAPFilter "(&(objectclass=user)(directreports=*))"

ForEach ($Mgr in $Managers) {

    $drMemberHash = @{}    
    $DirectReports = Generate-Reports -ManagerDN $Mgr.DistinguishedName
    $drMemberHash = Process-Reports -List $DirectReports -Group "$($Mgr.samAccountName)-DirectReports"
    
    
    $arMemberHash = @{}
    $AllReports = Generate-Reports -ManagerDN $Mgr.DistinguishedName -Recursive
    $arMemberHash = Process-Reports -List $AllReports -Group "$($Mgr.SamAccountName)-AllReports"
    #use $hash.ContainsKey("key) to check for key existence since it is possible that only one key exists
    #use $hash.Get_Item("key") to get value for associated key
    
}

