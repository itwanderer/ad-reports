# ad-reports

get-help .\reports.ps1 -det

NAME
    .\reports.ps1

SYNOPSIS
    Creates and updates direct and all report (indirect) groups for managers based on directReports attribute


SYNTAX
    .\reports.ps1 [-update] [<CommonParameters>]


DESCRIPTION
    This script performs the following:

    1.  Generates a list of direct reports
    2.  Generates a list of all reports by traversing the directReports hierarchy
    3.  Creates 2 lists, 1 with enabled reports and 1 with disabled reports, for both direct and all reports
    4.  Creates the allReports or direcReports group, if necessary, using the convention samaccountname-directReports
    or samaccountname-Allreports
    5.  Updates group members by adding or removing enabled and disabled members respectively
    6.  Produces a report comparing current group members vs. membership based on directReports attribute and user
    state (enabled or disabled)

    Mote:  The script runs in report mode when -update argument is not specified


PARAMETERS
    -update [<SwitchParameter>]
        Boolean switch to indicate if group membershop should be update. Script runs in report mode otherwise

    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer, PipelineVariable, and OutVariable. For more information, see
        about_CommonParameters (http://go.microsoft.com/fwlink/?LinkID=113216).

    -------------------------- EXAMPLE 1 --------------------------

    To produce a report

    .\reports.ps1




    -------------------------- EXAMPLE 2 --------------------------

    To update group memberships

    .\reports.ps1 -update




REMARKS
    To see the examples, type: "get-help C:\Users\Administrator\Documents\reports.ps1 -examples".
    For more information, type: "get-help C:\Users\Administrator\Documents\reports.ps1 -detailed".
    For technical information, type: "get-help C:\Users\Administrator\Documents\reports.ps1 -full".
    For online help, type: "get-help C:\Users\Administrator\Documents\reports.ps1 -online"

