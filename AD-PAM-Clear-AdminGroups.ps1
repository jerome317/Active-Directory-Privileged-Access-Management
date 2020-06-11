<#
.SYNOPSIS
  The script is used to clear the members of a local AD Security Group (Destination Group) related from the AD-PAM script.
.DESCRIPTION
  This script is part of a Privilege Access Management process using SharePoint and Flow. Once the request for elevated access has been approved, Flow will add the approved member to the Source Group.
  This script is designed to be scheduled with the interval of your choice.
  Some suggestions are:
  > Daily at the end of the business day or midnight so admins can still work if they need to
  > Weekly at early morning Monday if you want to be a little flexible. Please note, best practice is only have it when you need it.
  
  Part of the script is also an email notification feature, sends a notification to the member that they have been removed from the Destination Group.
    
.INPUTS
  The script requires input from CSV or array containing the name of the nested Active Directory
  
  This particular script will be using an array since there are only 3 groups (and to keep it simple without requiring another file).
    
  *If you decided to use this to more than 3 groups, then I recommend using a CSV file.
  CSV Filename: Sync-GroupMemberList.csv
  CSV Format/Headers:
  AADSecurityGroupObjectID,NestedADSecurityGroupName,ElevatedAdminGroupName
  OBJECT-ID-OF-YOUR-AAD-GROUP,AutomatedDomainAdmins,Domain Admins
  OBJECT-ID-OF-YOUR-AAD-GROUP,AutomatedEnterpriseAdmins,Enterprise Admins
  OBJECT-ID-OF-YOUR-AAD-GROUP,AutomatedSchemaAdmins,Schema Admins
  
.OUTPUTS Log File
  The script log file stored in C:\Windows\Temp\<name>.log
.NOTES
  Version:        1.0
  Author:         Jerome Liwanag
  Creation Date:  6/6/2020
  Purpose/Change: Initial script development
.EXAMPLE
  Not applicable
#>

###############
# For Logging #
###############

$VerbosePreference = "Continue"
$LogPath = "C:\Windows\Temp\AD-PAM\Logs"
Get-ChildItem "$LogPath\*.log" | Where-Object LastWriteTime -LT (Get-Date).AddDays(-7) | Remove-Item -Confirm:$false
$LogPathName = Join-Path -Path $LogPath -ChildPath "$($MyInvocation.MyCommand.Name)-$(Get-Date -Format 'MM-dd-yyyy')-$env:USERNAME.log"
Start-Transcript $LogPathName -Append

Write-Verbose "$(Get-Date): Start Log..."
####################
# Script Variables #
####################
#Email Settings
  $SMTPServer = "contoso-com.mail.protection.outlook.com" #DirectSend or your mail relay server.
  $FromEmail = "IT@contoso.com"
# If you used the CSV to add, you can reference it hear a well and use the same CSV source, since we only have 3, I've specificed them here instead of creating another file.
$NestedADSecurityGroupNames = "Automated Enterprise Admins", "Automated Schema Admins", "Automated Domain Admins"

###############
# Script Body #
###############
foreach ($OnPremGroup in $NestedADSecurityGroupNames) {

    $members = Get-ADGroupMember $OnPremGroup

    foreach ($member in $members) {
        
        $DisplayName = $member.Name
        $UserEmail = $member.UserPrincipalName
        $EmailSubject = "You have been removed from $OnPremGroup"
        
        Remove-ADGroupMember $OnPremGroup -Members $member -Confirm:$false 

        #Send an email confirmation to the requester and Manager
        $MessageBody = @"
        Hi $DisplayName,

        Your account has now been removed from the $OnPremGroup - which means it is no longer elevated.


        Thank you for adhering to IT Best Practices.

        Enterprise IT
        Processed by: PowerShell Script @ $env:Computername
"@
        #Send the email confirmation to the AD account, make sure you have a Send-As permission if you are using an actual mailbox
        Send-MailMessage –From $FromEmail –To $UserEmail –Subject $EmailSubject –Body $MessageBody -SmtpServer $SMTPServer -Port 25
    }
}
Stop-Transcript #end the logging