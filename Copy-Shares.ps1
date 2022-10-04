# Use Run as Administrator in Powershell, cmd.exe, or as a Scheduled Task.
# Use -Mirror switch to purge extra files from destination
# Backup Job file header: srcServer|srcShare|dstServer|dstShare|excludeDirs|excludeFiles

[CmdletBinding()]
param (
 [Alias('cred')]
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$BackupCredential,
 [string]$JobFile,
 [switch]$Mirror,
 [Alias('wi')]
 [switch]$WhatIf
)

function Add-ExcludedFiles {
 process {
  $excludedFileTypes = @('*.log', '*desktop.ini', '*.crdownload', '*.tmp',
   '*.mp4', '*.avi', '*.mpeg', '*.mov', 'thumbs.db', '*.pst', '*.ost')
  if ($_.excludeFiles) {
   $customFileTypes = $_.excludeFiles -split ','
   $_.excludeFiles = $customFileTypes + $excludedFileTypes
  }
  else {
   $_.excludeFiles = $excludedFileTypes
  }
  $_
 }
}

function Backup-Share {
 process {
  $src = '\\{0}\{1}' -f $_.srcServer, $_.srcShare
  $dst = '\\{0}\{1}\{2}\{3}' -f $_.dstServer, $_.dstShare, $_.srcServer, $_.srcShare

  Write-Host ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.Name, $src, $dst) -Fore Magenta
  Write-Debug 'Process?'
  $srcParams = @{type = 'Source'; name = 'X'; cred = $BackupCredential; root = $src }
  $dstParams = @{type = 'Destination'; name = 'Y'; cred = $BackupCredential; root = $dst }
  'X', 'Y' | Disconnect-PSShare
  $srcParams, $dstParams | Connect-PSShare
  if (-not(Get-PSdrive -Name X,Y -ErrorAction SilentlyContinue)){
   Write-Warning ('{0},Src or Dst not found. Skipping. [{1}],[{2}]' -f $MyInvocation.MyCommand.Name, $src, $dst)
   'X', 'Y' | Disconnect-PSShare
   return
  }
  $options = if ($Mirror) { @('/MIR') } else { @('/E', '/M') }
  if ($WhatIf) { $testSwitch = '/L' }
  Write-Host ('{0},Copying [{1}] to [{2}]' -f $MyInvocation.MyCommand.Name, $src, $dst) -Fore Green
  # "ROBOCOPY X:\ Y:\  $options /W:0 /R:0 /NFL /NDL /XF $excludedFileTypes /XA:S $testSwitch"
  ROBOCOPY X:\ Y:\ $options /W:0 /R:0 /NFL /NDL /XF $excludedFileTypes /XA:S $testSwitch
  'X', 'Y' | Disconnect-PSShare
 }
}

function Connect-PSShare {
 process {
  $msgVars = $MyInvocation.MyCommand.Name, $_.type, $_.name, $_.root, $_.cred.UserName
  Write-Host ('{0},[{1}],[{2}],[{3}],[{4}]' -f $msgVars) -Fore Blue
  if (-not(Get-PSDrive -Name $_ -ErrorAction SilentlyContinue)) {
   $newDrive = @{
    Name        = $_.nameK
    Root        = $_.root
    PSProvider  = 'FileSystem'
    Persist     = $True
    Scope = 'Global'
    ErrorAction = 'SilentlyContinue'
    Credential  = $_.cred
   }
   New-PSDrive @newDrive | Out-Null
   # Get-PSDRive
  }
  else {
   Write-Error ('{0},PSDrive Exists. {1}. Please check environment. EXITING.' -f $MyInvocation.MyCommand.Name, $_.name)
   EXIT
  }
 }
}

function Disconnect-PSShare {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_) -Fore Yellow
  if (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) {
   Remove-PSDrive -Name $_ -Confirm:$false -Force -ErrorAction SilentlyContinue
  }
  if (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) {
   $driveLetter = $_+':'
   $deleteDrive = 'NET USE {0} /DELETE' -f $driveLetter
   Write-Host ('Trying: {0}' -f $deleteDrive) -Fore Red
   echo 'Y' | net use $driveLetter /delete
  }
 }
}

function Get-BackupJobs {
 process {
  Import-Csv -Path $_ -Delimiter '|'
 }
}

$JobFile | Get-BackupJobs | Add-ExcludedFiles | Backup-Share -shareCred $BackupCredential