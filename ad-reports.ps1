<#
    
.SYNOPSIS


Creates and updates direct and all report (indirect) groups for managers based on directReports attribute

.DESCRIPTION


This script performs the following:

1.  Generates a list of direct reports 
2.  Generates a list of all reports by traversing the directReports hierarchy
3.  Creates 2 lists, 1 with enabled reports and 1 with disabled reports, for both direct and all reports
4.  Creates the allReports or direcReports group, if necessary, using the convention samaccountname-directReports or samaccountname-Allreports
5.  Updates group members by adding or removing enabled and disabled members respectively
6.  Produces a report comparing current group members vs. membership based on directReports attribute and user state (enabled or disabled)

Mote:  The script runs in report mode when -update argument is not specified

.PARAMETER ini

json formated configuration file

.PARAMETER update


Boolean switch to indicate if group membership should be updated.
Script runs in report mode without this parameter.

.EXAMPLE 


To produce a report 

.\reports.ps1 -ini reports_cfg.json

.EXAMPLE


To update group memberships

.\reports.ps1 -update -ini reports_cfg.json


.NOTES 

Define the source name on target event log using New-EventLog -LogName <NameOfLog> -Source <SourceName>.  Otherwise, records will not be successfully added to the event log on the machine where the script is running.


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
    [Parameter(Mandatory=$True)]
    [ValidateScript({If (Test-Path $_) {
            $True
        } 
        Else {
            $msg = "Configuration file, {0}, does not exist!  Exiting script..." -f $_
            Throw $msg
        }
        })]
    [String]$ini,
    [Switch]$update

)

If ($PSBoundParameters['Debug'])  {
	$DebugPreference = 'Continue'
}

#Region Functions


Function Logger {
    Param (

    $File,
    $LogContent,
    $DateFormat = 'yyyy/MM/dd HH:mm:ss'

    )
	$LogEntry = (Get-Date).ToString($DateFormat) + "	" + $LogContent
	Write-Verbose $LogEntry
	Add-Content -Path $File -Value $LogEntry -Force
}

Function Log-ScriptStart {

    $lc = "================Starting Script================="
    Logger -File $LogFilePath -LogContent $lc
    $lc = "Script Full Path: {0}" -f $PSCommandPath
    Logger -File $LogFilePath -LogContent $lc
    $lc = "Script Dir: {0}" -f $PSScriptRoot
    Logger -File $LogFilePath -LogContent $lc
    $lc = "User: {0}\{1}" -f $Env:USERDOMAIN, $Env:USERNAME
    Logger -File $LogFilePath -LogContent $lc
    $lc = "Computer Name: {0}" -f $Env:COMPUTERNAME
    Logger -File $LogFilePath -LogContent $lc
    $lc = "Domain DN: {0}" -f $Domain_DN
    Logger -File $LogFilePath -LogContent $lc
    $lc = "Group OU DN: {0}" -f $Group_BaseOu
    Logger -File $LogFilePath -LogContent $lc
    $lc = "Group DirectReports Suffix: {0}" -f $Config.Group_Suffix_DirectReports
    Logger -File $LogFilePath -LogContent $lc
    $lc = "Group AllReports Suffix: {0}" -f $Config.Group_Suffix_AllReports
    Logger -File $LogFilePath -LogContent $lc
    $lc = "User OU DN: {0}" -f $User_BaseOu
    Logger -File $LogFilePath -LogContent $lc
    $lc = "Manager Search Filter: {0}" -f $Config.Manager_Filter
    Logger -File $LogFilePath -LogContent $lc
    $lc = "Log File: {0}:" -f $LogFilePath
    Logger -File $LogFilePath -LogContent $lc
    $lc = "------------------------------------------------"
    Logger -File $LogFilePath -LogContent $lc
<#
    $lc = "Transcript File: {0}" -f $TranscriptFile
    Logger -File $LogFilePath -LogContent $lc
#>
}

Function Rename-LogFile {

    Param (

        [String]$FileName,
        [String]$DateFormat = 'yyyy-MM-dd_HH-mm-ss'

    )

    $ArchiveSuffix = '-' + ((Get-Item $FileName).LastWriteTime).ToString($DateFormat) + '.log'
    $ArchiveFile = $FileName -replace '.LOG$', $ArchiveSuffix

    $msg = "{0}: LogFile already exists, renaming to {1}" -f $FileName,$ArchiveFile
    Logger -File $LogFilePath -LogContent $msg

    Rename-Item $FileName $ArchiveFile
}

Function Generate-Reports {
	Param(
		[String]$ManagerDN,
		[String]$SearchBase,
		[Switch]$Recursive
	
	)
    $LdapFilter = "(&(objectclass=user)(manager=" + $managerDN + "))"
    #TODO: Add error checking for Get-ADUser
    $Error.Clear()
    Try {
	    $DirectReports = Get-ADUser -LDAPFilter $LdapFilter -pro directReports
    }
    Catch {

    }
    If ($DirectReports -eq $null) { continue; }
    $AllReports += $DirectReports

    If ($recursive) {

        ForEach ($entry in $DirectReports) {
             If ($entry.DirectReports -gt 0) {
                If ($entry.distinguishedname -eq $managerDN) {
                    $msg = "`tCircular manager reference, {0} reports to {0}, skipping to avoid loop" -f $entry.sAMAccountName
                    Logger -File $LogFilePath -LogContent $msg
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
    $msg = "`{0}:" -f $GroupName
    Logger -File $LogFilePath -LogContent $msg
    $msg = "`tTotal Reports (per directReports): {0}" -f $List.sAMAccountName.Count
    Logger -File $LogFilePath -LogContent $msg
    ForEach ($State in $ReportState) {
        If ($State.name -eq "True") { 
            $msg = "`t`tEnabled Reports: {0}" -f $State.Count
            $EnabledMembers = $State.group
            $MemberHash.Enabled = $EnabledMembers
        }
        Else {
            $msg = "`t`tDisabled Reports: {0}" -f $State.Count
            $DisabledMembers = $State.group
            $MemberHash.Disabled = $DisabledMembers
        }
        Logger -File $LogFilePath -LogContent $msg
        
    }

    If ((Get-ADGroup -Filter {Samaccountname -eq $GroupName}) -ne $null) {
        $GroupMembers = Get-ADGroupMember -Identity $GroupName
        $msg = "`tTotal Reports (current group members): {0}" -f $GroupMembers.sAMAccountName.count
    }
    Else {
        $msg = "`t{0} is not in AD yet" -f $GroupName
    }
    Logger -File $LogFilePath -LogContent $msg
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
    
    $Arguments = @{
        "Name" = $Name
        "SamAccountName" = $Name
        "GroupCategory" = $Category
        "GroupScope" = $Scope
        "Description" = $Description
        "Path" = $Base
    }
    $msg = "{0}: Creating new group" -f $Name
    Logger -File $LogFilePath -LogContent $msg
    $Error.Clear()
    Try {
        New-ADGroup @Arguments
        $msg = "{0}: Successfully created group" -f $Name
    }
    Catch {
        $msg = "{0}: {1} ; {2} error, {3} {4} ; {5}" -f `
                $Name, `
                $Error.ScriptStackTrace, `
                $Error.Categoryinfo.Activity, `
                $Error.Categoryinfo.TargetType, `
                $Error.CategoryInfo.Category, `
                $Error.Exception.Message
    }
    Finally {
        Logger -File $LogFilePath -LogContent $msg
    }
}

Function Update-GroupMembership {

    Param (
        $MemberHash,
        $GroupName


    )

 
    $GroupMembers = Get-ADGroupMember $GroupName | Select-Object -ExpandProperty DistinguishedName

    If ($MemberHash.ContainsKey("Enabled")) {
        $msg = "{0}: Checking if enabled members need to be added to group" -f $GroupName
        Logger -File $LogFilePath -LogContent $msg
        $MissingMembers = $Memberhash.Enabled.DistinguishedName | Where-Object {$GroupMembers -notcontains $_}
        If ($MissingMembers.Count -gt 0) {
            $msg = "{0}: There are {1} enabled members to add" -f $GroupName, $MissingMembers.Count
            Logger -File $LogFilePath -LogContent $msg
            $msg = "{0}: These users will be added" -f $GroupName
            Logger -File $LogFilePath -LogContent $msg
            ForEach ($entry in $MissingMembers) {
                $msg = "{0}: Member to add ==> {1}" -f $GroupName, $entry
                Logger -File $LogFilePath -LogContent $msg
            }
            Try {
                $msg = "{0}: Adding group members" -f $GroupName
                Logger -File $LogFilePath -LogContent $msg
                Add-ADGroupMember -Identity $GroupName -Members $MissingMembers -Confirm:$False
                $msg = "{0}: Successfully added group members" -f $GroupName
            }
            Catch {
                $msg = "{0} : {1} ; {2} error, {3} {4} ; {5}" -f `
                    $GroupName, `
                    $Error.ScriptStackTrace, `
                    $Error.Categoryinfo.Activity, `
                    $Error.Categoryinfo.TargetType, `
                    $Error.CategoryInfo.Category, `
                    $Error.Exception.Message
            }
            Finally {
                Logger -File $LogFilePath -LogContent $msg
            } 
        }
        Else {
            $msg = "{0}: No new members to add" -f $GroupName
            Logger -File $LogFilePath -LogContent $msg

        }

        $msg = "{0}: Checking if enabled members need to be removed from group" -f $GroupName
        Logger -File $LogFilePath -LogContent $msg
        $EnabledMembers = $Memberhash.Enabled.DistinguishedName
        $MembersToRemove =  $GroupMembers | Where-Object {$EnabledMembers -notcontains $_}
        If ($MembersToRemove.Count -gt 0) {
           $msg = "{0}: There are {1} enabled members to remove" -f $GroupName, $MembersToRemove.Count
           Logger -File $LogFilePath -LogContent $msg
           ForEach ($entry in $MembersToRemove) {
               $msg = "{0}: Member to remove ==> {1}" -f $GroupName, $entry
               Logger -File $LogFilePath -LogContent $msg
           }
           Try {
                $msg = "{0}: Removing enabled users from group" -f $GroupName
                Logger -File $LogFilePath -LogContent $msg
                Remove-ADGroupMember -Identity $GroupName -Members $MembersToRemove -Confirm:$False
                $msg = "{0}: Successfully removed group members" -f $GroupName
            }
            Catch {
                $msg = "{0} : {1} ; {2} error, {3} {4} ; {5}" -f `
                    $GroupName, `
                    $Error.ScriptStackTrace, `
                    $Error.Categoryinfo.Activity, `
                    $Error.Categoryinfo.TargetType, `
                    $Error.CategoryInfo.Category, `
                    $Error.Exception.Message
            }
            Finally {
                Logger -File $LogFilePath -LogContent $msg
            } 
        }
        Else {
           $msg = "{0}: There are no enabled members to remove" -f $GroupName
           Logger -File $LogFilePath -LogContent $msg
        }

    }

    If ($MemberHash.ContainsKey("Disabled")) {
        $msg = "{0}: Checking if disabled users need to be removed from  group" -f $GroupName
        Logger -File $LogFilePath -LogContent $msg
        $DisabledMembersToRemove = $MemberHash.Disabled.DistinguishedName|Where-Object {$GroupMembers -contains $_}
        If ($DisabledMembersToRemove.Count -gt 0) {
            $msg = "{0}: There are {1} disabled members to remove" -f $GroupName, $DisabledMembersToRemove.Count
            Logger -File $LogFilePath -LogContent $msg
            ForEach ($entry in $DisabledMembersToRemove) {
                $msg = "{0}: Disabled Member to remove ==> {1}" -f $GroupName, $entry
                 Logger -File $LogFilePath -LogContent $msg
            }
            Try {
                $msg = "{0}: Removing disabled group members" -f $GroupName
                Logger -File $LogFilePath -LogContent $msg
                Remove-ADGroupMember -Identity $GroupName -Members $DisabledMembersToRemove -Confirm:$False
                $msg = "{0}: Successfully removed disabled group members" -f $GroupName
            }
            Catch {
                $msg = "{0}: {1} ; {2} error, {3} {4} ; {5}" -f `
                    $Error.ScriptStackTrace, `
                    $Error.Categoryinfo.TargetType, `
                    $Error.CategoryInfo.Category, `
                    $Error.Exception.Message
            }
            Finally {
                Logger -File $LogFilePath -LogContent $msg
            } 
        }
        Else {
            $msg = "{0}: No disabled members to remove" -f $GroupName
            Logger -File $LogFilePath -LogContent $msg

        }

    }


    
}

#EndRegion

#Region Main

$StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

#initialize status codes
$GROUP_CREATE_SUCCESS = 100
$GROUP_CREATE_ERROR = 101
$GROUP_MEMBER_ADD_SUCCESS = 102 
$GROUP_MEMBER_ADD_ERROR = 103
$GROUP_MEMBER_REMOVE_SUCCESS = 104
$GROUP_MEMBER_REMOVE_ERROR = 105


#Read config file
$Error.Clear()
Try {
    $Config = Get-Content -Raw -Path $ini | ConvertFrom-Json
    $msg = "Successfully read json formatted config file, {0}" -f $ini
}
Catch {
    Throw
}

#Dynamic Variables
$Domain_DN = (Get-ADRootDSE).DefaultNamingContext

#Constructed Variables
$Group_BaseOu = "{0},{1}" -f $Config.Group_Ou_Rdn, $Domain_DN
$User_BaseOu = "{0},{1}" -f $Config.User_Ou_Rdn, $Domain_DN
$LogName = $MyInvocation.MyCommand.Name -replace   '.ps1$', $Config.LogFile_Suffix
$LogFileDir = "{0}\{1}" -f $PSScriptRoot,$Config.LogDir
$LogFilePath = "{0}\{1}" -f $LogFileDir, $LogName
#if (Test-Path $TranscriptFile) { Rename-LogFile -FileName $TranscriptFile }
If (!(Test-Path $LogFileDir)) { 
    Write-Warning -Message "$($LogDir) does not exist"
    Write-Host "Creating log directory, $($LogFileDir)"
    New-Item -Name $Config.LogDir -Path $PSScriptRoot -ItemType Directory
#    Throw
}
If (Test-Path $LogFilePath) { Rename-LogFile -FileName $LogFilePath }

#Start-Transcript -Path $TranscriptFile

Log-ScriptStart


#TODO: Add error handling for search below
$Error.Clear()
Try {
    $Managers = Get-ADUser -LDAPFilter $Config.Manager_Filter -SearchBase $User_BaseOu
}
Catch {
#    Throw
    $msg = "{0} : {1} error, {2} {3} ; {4}" -f `
            $Error.ScriptStackTrace, `
            $Error.Categoryinfo.Activity, `
            $Error.Categoryinfo.TargetType, `
            $Error.CategoryInfo.Category, `
            $Error.Exception.Message

    Write-Host $msg
    Exit
}

$lc = "There are {0} users with direct reports" -f $Managers.Count
Logger -File $LogFilePath -LogContent $lc

ForEach ($Mgr in $Managers) {

    $ProgressParms = @{
            'Activity' = 'Processing managers' 
            'Status' = 'Please wait.'
            'Id' = 0
    }
    Write-Progress @ProgressParms
    $drMemberHash = @{}
    $DirectReports = $null    
    $DirectReports = Generate-Reports -ManagerDN $Mgr.DistinguishedName
    $DirectReportsGroup = $Mgr.SamAccountName + $Config.Group_Suffix_DirectReports
    $drMemberHash = Process-Reports -List $DirectReports -Group $DirectReportsGroup


    $arMemberHash = @{}
    $AllReports = $null
    $AllReports = Generate-Reports -ManagerDN $Mgr.DistinguishedName -Recursive
    $AllReportsGroup = $Mgr.SamAccountName + $Config.Group_Suffix_AllReports
    $arMemberHash = Process-Reports -List $AllReports -Group $AllReportsGroup

    If ($update) {

        #Direct Reports group processing
        If ((Get-ADGroup -Filter {sAMAccountName -eq $DirectReportsGroup}) -eq $null) {
            $msg = "{0}: Group does not exist, calling function to create" -f $DirectReportsGroup
            Logger -File $LogFilePath -LogContent $msg
            Create-Group -Name $DirectReportsGroup -Base $Group_BaseOu
        } 

        $msg = "{0}: Reconciling group membership" -f $DirectReportsGroup
        Logger -File $LogFilePath -LogContent $msg
        Update-GroupMembership -MemberHash $drMemberHash -GroupName $DirectReportsGroup

        #All Reports group processing
        If ((Get-ADGroup -Filter {sAMAccountName -eq $AllReportsGroup}) -eq $null) {
            
            $msg = "{0}: Group does not exist, calling function to create" -f $AllReportsGroup
            Logger -File $LogFilePath -LogContent $msg
            Create-Group -Name $AllReportsGroup -Base $Group_BaseOu
        } 

        $msg = "{0}: Reconciling group membership" -f $AllReportsGroup
        Logger -File $LogFilePath -LogContent $msg
        Update-GroupMembership -MemberHash $arMemberHash -GroupName $AllReportsGroup



    }

}

$StopWatch.Stop()
$lc = "Script Duration: {0} ms" -f $StopWatch.Elapsed.Milliseconds
Logger -File $LogFilePath -LogContent $lc
Logger -File $LogFilePath -LogContent "================Completed Script================="
<#
$EventLogEntry = @{  "LogName" = $Config.EventLog_Name
                     "Source" = $Config.EventLog_Source
                     "EntryType" = "Information"
                     "EventId" = 1
                     "Message" = $(Get-Content $LogFilePath) -join "`n"
                     "ErrorAction" = "Continue"
                   }
$Error.Clear()
Try {
    Write-EventLog @EventLogEntry 
    $msg = "Successfully added Application log entry"
}
Catch {
#    Throw
    $msg = "{0} : {1} error, {2} {3} ; {4}" -f `
            $GroupName, `
            $Error.ScriptStackTrace, `
            $Error.Categoryinfo.Activity, `
            $Error.Categoryinfo.TargetType, `
            $Error.CategoryInfo.Category, `
            $Error.Exception.Message

}
Finally {
    Write-Host $msg -ForegroundColor Green
}
#>

#Stop-Transcript
#EndRegion

