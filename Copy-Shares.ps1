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
 [switch]$ShowProcess,
 [Alias('wi')]
 [switch]$WhatIf
)

function Add-Behavior {
 process {
  if ($ShowProcess) { $behavior = '/W:0', '/R:0', '/XA:S' }
  else { $behavior = '/W:0', '/R:0', '/NFL', '/NDL', '/XA:S' }
  Add-Member -InputObject $_ -MemberType NoteProperty -Name behavior -Value $behavior
  $_
 }
}

function Add-CopyType {
 process {
  $copyType = if ($Mirror) { @('/MIR') } else { @('/E', '/M') }
  Add-Member -InputObject $_ -MemberType NoteProperty -Name copyType -Value $copyType
  $_
 }
}

function Add-SrcDstData {
 process {
  $src = '\\{0}\{1}' -f $_.srcServer, $_.srcShare
  Add-Member -InputObject $_ -MemberType NoteProperty -Name src -Value $src
  $dst = '\\{0}\{1}\{2}\{3}' -f $_.dstServer, $_.dstShare, $_.srcServer, $_.srcShare
  Add-Member -InputObject $_ -MemberType NoteProperty -Name dst -Value $dst
  $_
 }
}

function Add-SrcDstParams ([System.Management.Automation.PSCredential]$cred) {
 process {
  $srcParams = @{type = 'Source'; name = 'X'; cred = $cred; root = $_.src }
  Add-Member -InputObject $_ -MemberType NoteProperty -Name srcParams -Value $srcParams
  $dstParams = @{type = 'Destination'; name = 'Y'; cred = $cred; root = $_.dst }
  Add-Member -InputObject $_ -MemberType NoteProperty -Name dstParams -Value $dstParams
  $_
 }
}

function Add-ExcludedDirs {
 process {
  $excludedDirs = @('Temp', 'Autobackup', 'Updater5',
   '$RECYCLE.BIN', 'AppData', 'iTunes', 'DropBox', 'Application Data')
  if ($_.excludeDirs) {
   $customDirs = $_.excludeDirs -split ','
   $_.excludeDirs = $customDirs + $excludedDirs | Sort-Object -Unique
  }
  else {
   $_.excludeDirs = $excludedDirs
  }
  $_
 }
}

function Add-ExcludedFiles {
 process {
  $excludedFileTypes = @('*.log', '*desktop.ini', '*.crdownload', '*.tmp',
   '*.mp4', '*.avi', '*.mpeg', '*.mov', 'thumbs.db', '*.pst', '*.ost', '*Aeries*.url', '~*')
  if ($_.excludeFiles) {
   $customFileTypes = $_.excludeFiles -split ','
   $_.excludeFiles = $customFileTypes + $excludedFileTypes | Sort-Object -Unique
  }
  else {
   $_.excludeFiles = $excludedFileTypes
  }
  $_
 }
}

function Add-TestSwitch {
 process {
  $testSwitch = if ($WhatIf) { '/L' } else { '/MT:32' }
  Add-Member -InputObject $_ -MemberType NoteProperty -Name testSwitch -Value $testSwitch
  $_
 }
}

function Backup-Share {
 process {
  Write-Host ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.Name, $_.src, $_.dst) -Fore Magenta
  Write-Debug 'Process?'

  'X', 'Y' | Disconnect-PSShare
  $_.srcParams, $_.dstParams | Connect-PSShare

  if (-not(Get-PSdrive -Name X, Y -ErrorAction SilentlyContinue)) {
   # Ensure drives are mapped correctly
   Write-Warning ('{0},Src or Dst not found. Skipping. [{1}],[{2}]' -f $MyInvocation.MyCommand.Name, $_.src, $_.dst)
   'X', 'Y' | Disconnect-PSShare
   return
  }

  Write-Host ('{0},Copying [{1}] to [{2}]' -f $MyInvocation.MyCommand.Name, $_.src, $_.dst) -Fore Green
  ROBOCOPY X:\ Y:\ $_.copyType $_.behavior /XF $_.excludeFiles /XD $_.excludeDirs $_.testSwitch

  'X', 'Y' | Disconnect-PSShare
 }
}

function Connect-PSShare {
 process {
  $msgVars = $MyInvocation.MyCommand.Name, $_.type, $_.name, $_.root, $_.cred.UserName
  Write-Host ('{0},[{1}],[{2}],[{3}],[{4}]' -f $msgVars) -Fore Blue
  if (-not(Get-PSDrive -Name $_ -ErrorAction SilentlyContinue)) {
   $newDrive = @{
    Name        = $_.name
    Root        = $_.root
    PSProvider  = 'FileSystem'
    Persist     = $True
    Scope       = 'Global'
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
   $driveLetter = $_ + ':'
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

$JobFile | Get-BackupJobs | Add-ExcludedFiles | Add-ExcludedDirs |
Add-SrcDstData | Add-SrcDstParams -cred $BackupCredential | Add-CopyType |
Add-Behavior | Add-TestSwitch | Backup-Share