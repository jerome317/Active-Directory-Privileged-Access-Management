#Requires -Modules AzureAD
<#
.SYNOPSIS
  The script is used to take the members of an Azure AD Security Group (Source Group), add them to the local AD Security Group (Destination Group), then remove them from the source Azure AD Security Group.
.DESCRIPTION
  This script is part of a Privilege Access Management process using SharePoint and Flow. Once the request for elevated access has been approved, Flow will add the approved member to the Source Group.
  This script is designed to be scheduled with the interval of your choice, to check for members on the Source Group.
  If there are members on the Source Group, the script will process them by adding them to the Destination Group.
  After processing the members, the script will clear the Source Group.
  
  Part of the script is also an email notification feature, sends a notification to the member and their manager that they have been added to the Destination Group.
    
.INPUTS
  The script requires input from CSV or array containing the Object ID of the Azure AD Security Group (Source Group), the name of the nested Active Directory and the corresponding name of the elevated Admin group.
  
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

Import-Module AzureAD
Import-Module ActiveDirectory

<#
HOT TIP: Use Credential Manager to store Service Account credentials
    If you don't have it, here's how (you onl'y have to do this once):
    1. Install this module:
    Install-Module -Name CredentialManager
    2. Then run the command below:
    $cred = $Host.UI.PromptForCredential("OFFICE 365 Credentials",$msg,"$env:username@tangoe.com",$env:userdomain)
    New-StoredCredential -Target "O365 for Scripting" -UserName $cred.UserName -Password $cred.GetNetworkCredential().Password -Comment 'I stored it here for scripting' -Persist Enterprise
    Clear
#>

$365LogonCred = Get-StoredCredential -Target "O365 for Scripting or THE NAME OF YOUR CREDENTIAL IN CREDENTIAL MANAGER"
Connect-AzureAD –Credential $365LogonCred

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

#Group Information
#NOTE: You can create a CSV for this, I just decided to specify each group since there is only 3.
  $hashArr = @(
    @{
    AADSecurityGroupObjectID = 'OBJECT-ID-OF-YOUR-AAD-GROUP'  #Object ID of your Azure AD Group
    NestedADSecurityGroupName = 'Automated Domain Admins'     #The name you use or called your destination / local AD security groups
    ElevatedAdminGroupName = 'Domain Admins'                  #This is just use for the email body
    },
    @{
    AADSecurityGroupObjectID = 'OBJECT-ID-OF-YOUR-AAD-GROUP'
    NestedADSecurityGroupName = 'Automated Enterprise Admins'
    ElevatedAdminGroupName = 'Enterprise Admins'
    },
    @{
    AADSecurityGroupObjectID = 'OBJECT-ID-OF-YOUR-AAD-GROUP'
    NestedADSecurityGroupName = 'Automated Schema Admins'
    ElevatedAdminGroupName = 'Schema Admins'
    }
)
############
# Function #
############
Function Set-AdminGroup
{
    param($AADGroup,$members,$OnPremGroup,$AdminGroupName)
    
    foreach ($member in $members) {

    #Set the variables for the processing and for the email communication
    $UserDisplayName = $member.DisplayName
    $UserSamAccountName = (Get-ADUser -filter {DisplayName -eq $UserDisplayName}).SamAccountName
    $UserEmail = $member.UserPrincipalName
    $ManagerEmail = Get-AzureADUserManager -ObjectId $member.ObjectId | Select-Object -ExpandProperty UserPrincipalName
    $EmailSubject = "You have been added to $OnPremGroup"
      #This will add the approved request to the Automated Admin security group
      Add-ADGroupMember -identity $OnPremGroup -members $UserSamAccountName

      #After adding the member to the group, we will remove them from the Azure AD security group to clean it up and ready for the next request.
      Remove-AzureADGroupMember -objectid $AADGroup.ObjectId -memberid $member.objectid

      #Send an email confirmation to the requester and Manager
      $MessageBody = @"
      Hi $DisplayName,

      This is a confirmation that your request has been completed.
      Your admin account $memberAdminAccount has been added to the $OnPremGroup, which is a nested group within $AdminGroupName.
      We will automatically revoke access at the pre-defined time to follow IT Security best practices.

      Thank you for adhering to IT Best Practices.

      Enterprise IT
      Processed by: PowerShell Script @ $env:Computername
"@
    #Send the email confirmation to the AD account, make sure you have a Send-As permission if you are using an actual mailbox
    Send-MailMessage –From $FromEmail –To $UserEmail -CC $ManagerEmail –Subject $EmailSubject –Body $MessageBody -SmtpServer $SMTPServer -Port 25

    }
}
###############
# Script Body #
###############

#Loop through each admin group.
foreach ($group in $hashArr){
  $AADGroup = Get-AzureADGroup -ObjectId $group.AADSecurityGroupObjectID
  $members = Get-azureadgroupMember -objectID $AADGroup.ObjectId 
  $OnPremGroup = $group.NestedADSecurityGroupName
  $AdminGroupName = $group.ElevatedAdminGroupName

  #Call the function we initialize at the beginning to start processing each admin group
  Set-AdminGroup -AADGroup $AADGroup -members $members -OnPremGroup $OnPremGroup -AdminGroupName $AdminGroupName
}

Stop-Transcript #stop the logging