# Powershell ,Robocopy, and New-PSDrive work in concert to achieve file copy nirvana.
# You can do ANYTHING if you've visited ZOMBO.COM
[CmdletBinding()]
param (
 [Alias('cred')]
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$BackupCredential,
 [Parameter(Mandatory = $True)]
 [string]$SQLiteDatabaseFile,
 [Parameter(Mandatory = $True)]
 [string[]]$SourceServers,
 [Parameter(Mandatory = $True)]
 # If running this script in parallel on the same system+account use unique driveletters
 [string]$SourceDriveLetter,
 [Parameter(Mandatory = $True)]
 # If running this script in parallel on the same system+account use unique driveletters
 [string]$DestDriveLetter,
 [switch]$Mirror,
 [switch]$ShowProcess,
 [switch]$ListJobData,
 [switch]$ListJobObjects,
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

function Add-LogPath {
 process {
  $logRoot = '.\logs\' + $_.srcServer
  if (-not(Test-Path -Path $logRoot)) {
   New-Item -Path $logRoot -ItemType Directory -Confirm:$false | Out-Null
  }
  $logPath = '/LOG:.\logs\{0}\{0}-{1}-{2}.log' -f $_.srcServer, $_.srcShare, (Get-Date -f yyyy-MM-dd)
  Add-Member -InputObject $_ -MemberType NoteProperty -Name logPath -Value $logPath
  $_
 }
}

function Add-SrcDstPaths {
 process {
  $src = '\\{0}\{1}' -f $_.srcServer, $_.srcShare
  Add-Member -InputObject $_ -MemberType NoteProperty -Name src -Value $src
  $dst = '\\{0}\{1}' -f $_.dstServer, $_.dstShare
  Add-Member -InputObject $_ -MemberType NoteProperty -Name dst -Value $dst
  $_
 }
}

function Add-SrcDstParams {
 process {
  # Source Area
  $src = '\\{0}\{1}' -f $_.srcServer, $_.srcShare
  Add-Member -InputObject $_ -MemberType NoteProperty -Name src -Value $src

  $srcParams = @{type = 'Source'; name = $SourceDriveLetter; cred = $BackupCredential; root = $_.src }
  Write-Verbose ( $srcParams | Out-String )
  Add-Member -InputObject $_ -MemberType NoteProperty -Name srcParams -Value $srcParams

  $srcCopyPath = '{0}:\' -f $srcParams.name
  Write-Verbose ( $srcCopyPath | Out-String )
  Add-Member -InputObject $_ -MemberType NoteProperty -Name srcCopyPath -Value $srcCopyPath

  # Destination Area
  $dst = '\\{0}\{1}' -f $_.dstServer, $_.dstShare
  Add-Member -InputObject $_ -MemberType NoteProperty -Name dst -Value $dst

  $dstParams = @{type = 'Destination'; name = $DestDriveLetter; cred = $BackupCredential; root = $_.dst }
  Write-Verbose ( $dstParams | Out-String )
  Add-Member -InputObject $_ -MemberType NoteProperty -Name dstParams -Value $dstParams

  $dstCopyPath = '{0}:\{1}\{2}' -f $dstParams.name, $_.srcServer, $_.srcShare
  Write-Verbose ( $dstCopyPath | Out-String )
  Add-Member -InputObject $_ -MemberType NoteProperty -Name dstCopyPath -Value $dstCopyPath

  $_
 }
}

function Add-ExcludedDirs {
 process {
  $excludedDirs = @('Temp', 'Autobackup', 'Updater5',
   '$RECYCLE.BIN', 'AppData', 'iTunes', 'DropBox',
   'Favorites', 'Application Data')
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
  Write-Verbose ( $_ | Out-String )
  Write-Debug 'Process?'

  $_.srcParams.name, $_.dstParams.name | Disconnect-PSShare
  $_.srcParams, $_.dstParams | Connect-PSShare

  if (-not(Get-PSdrive -Name X, Y -ErrorAction SilentlyContinue)) {
   # Ensure drives are mapped correctly
   Write-Warning ('{0},Src or Dst not found. Skipping. [{1}],[{2}]' -f $MyInvocation.MyCommand.Name, $_.src, $_.dst)
   $_.srcParams.name, $_.dstParams.name | Disconnect-PSShare
   continue
  }
  $_ | New-DstDirectory
  Write-Host ('{0},Copying [{1}] to [{2}]' -f $MyInvocation.MyCommand.Name, $_.src, $_.dst) -Fore Green
  ROBOCOPY $_.srcCopyPath $_.dstCopyPath $_.copyType $_.behavior /XF $_.excludeFiles /XD $_.excludeDirs $_.testSwitch $_.logPath

  $_.srcParams.name, $_.dstParams.name | Disconnect-PSShare
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

function Get-BackupJobs ($sqliteDB, [string[]]$servers) {
 'PSSQLite' | Add-Module
 # format server list for sql
 foreach ($serv in $servers) { $serversIN += "`'$serv`'," }
 $sql = 'SELECT * FROM jobs WHERE srcServer COLLATE NOCASE IN ({0}) ORDER BY srcServer,srcShare' -f $serversIN.TrimEnd(',')
 Invoke-SqliteQuery -DataSource $sqliteDB -Query $sql
}

function New-DstDirectory {
 process {
  if (-not(Test-Path -Path $_.dstCopyPath)) {
   Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.dstCopyPath)
   New-Item -Path $_.dstCopyPath -ItemType Directory -Confirm:$false
  }
 }
}

function Remove-ExpiredLogs {
 # https://www.thomasmaurer.ch/2010/12/powershell-delete-files-older-than/
 $logPath = '.\logs'
 $daysBack = -14
 $currentDate = Get-Date
 $dateToDelete = $CurrentDate.AddDays($daysback)
 Write-Host ('{0},Older than {1} days' -f $MyInvocation.MyCommand.Name, ($daysBack.ToString().replace('-', '')))
 Get-ChildItem -Path $logPath -Recurse |
 Where-Object { $_.LastWriteTime -lt $dateToDelete } | Remove-Item
}

filter Select-Jobs {
 if ($_.executeJob -eq 'TRUE') { $_ }
}

# ====================================================================================
. .\lib\Add-Module.ps1

$jobData = Get-BackupJobs -sqliteDB $SQLiteDatabaseFile -servers $SourceServers | Select-Jobs

if ($ListJobData) { $jobData | Format-Table }

Remove-ExpiredLogs

$jobObjects = $jobData | Add-ExcludedFiles | Add-ExcludedDirs |
Add-SrcDstParams | Add-CopyType | Add-Behavior | Add-TestSwitch

if ($ListJobObjects) { $jobObjects }

$jobObjects | Backup-Share