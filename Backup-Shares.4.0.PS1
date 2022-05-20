###################################################################
# Run an incremental or full backup to a specified server/device. #
###################################################################
# A text file is used to determine source and destination. 
# Format the "JobFile" as such: srcServer|srcShare|dstServer|dstShare|excludeDirs|excludeFiles
# The -JobFile Param is used to determine the JobFile. If the -Full is included a full copy is made.
# This will delete files in the destination that no longer exist in the source.
# If -Full is set to $False or not included a daily backup is run and file with teh archive bit set are 
# Copied and the bit is set to off.
# A test switch is included which disable actual coy operations and notifications.
# Logs for are automatically generated.
# The last line is to pass an object to an outside script for notification purposes.
[cmdletbinding()]
Param( 
 [Parameter(Mandatory = $True)][ValidateNotNull()]$jobFile,
 [switch]$complete,
	[Switch]$Full,
	[Switch]$Slow,
	[Switch]$Test
) 
# CLS

if ($Full ) { 
	"Full Backup"
	$scope = "Full"
	$options = @("/E", "/M")
}
elseif ($complete ) { 
	"Full Backup"
	$scope = "Full"
	$options = @("/E")
}
else {
	"Daily Backup"
	$scope = $(Date).DayofWeek
	$options = @("/E", "/M") 
}

if ($Test) {
	"[TEST] Run..."
	$Test = $True
	$testLog = ".test.log"
	$testSwitch = "/L"
}
else {
	"[LIVE] run..."
	$Test = $False
	$testLog = $Null
	$testSwitch = $Null 
} 

$cwd = Split-Path $MyInvocation.MyCommand.Path
$jobs = Import-Csv $jobFile -Delimiter "|" 
$Global:emailObjArray = @()
$Global:Subject = "DO - $env:COMPUTERNAME Backup $(date) $((date).dayofweek) - Cooper"
$Global:Helpdesk = $False
$ScriptName = $MyInvocation.MyCommand.Name
$ScriptLogFile = ".\logs\$ENV:COMPUTERNAME\$ScriptName-$scope-$($(date).year)-$($(date).month)-$($(date).day).log" + $testLog
$cwd ; CD $cwd

if (!(Test-Path ".\Logs\$ENV:COMPUTERNAME")) { MD ".\Logs\$ENV:COMPUTERNAME" }
Function Report-Msg ($type = "[INFO]", $msg, $hue = "Green") {
	Write-Host "$(date) $type $msg" -ForeGroundColor $hue -BackGroundColor Black
	Add-Content $ScriptLogFile -Value "$(date) $type $msg"
	$Global:emailObjArray += New-Object PSObject -Prop @{ Date = $(date); Type = $type; Msg = $msg }
	if ( $type -eq "[ERROR]" ) {
		"Errors Detected"
		$Global:Helpdesk = $True
		if ( $Subject -NotLike "*ERROR*" ) { $Global:Subject = "[ERROR] " + $Subject }
	}
}
Function ErrorCheck {
	if ( $Error.Count -ne 0 ) { ForEach ($item in $error) { Report-Msg -Type "[ERROR]" -msg "$item" -Hue Red } }
	else { Report-Msg -msg "No Powershell errors reported." }
} 
Report-Msg -Type "[SCRIPT]" -msg "$ENV:COMPUTERNAME | $ENV:USERNAME | $ScriptName $jobFile -Full $Full -Test $Test" -Hue Yellow
ForEach ( $job in $jobs ) {
	if ( $job.excludeDirs -eq "*" ) {
		Write-Verbose ( "$job", "excludeDirs set to *. Skipping..." | out-string )
		Continue
	}
	
	$excludeFiles = $null
	$excludeDirs = $null
	$srcServer = $job.srcServer
	$srcShare = $job.srcShare
	$srcSharePath = "\\" + $srcServer + "\" + $srcShare
	$dstServer = $job.dstServer
	$dstShare = $job.dstShare
	$dstSharePath = "\\$dstServer\$dstShare"
	$excludeDirs = @("Temp", "Autobackup", "Updater5")
 if ($job.excludeDirs) { $excludeDirs = $excludeDirs + @($job.excludeDirs.split(",")) }
	$excludeFiles = $excludeFiles + @('*.log', '*desktop.ini', '*.crdownload', '*.tmp', '*.mp4', '*.avi', '*.mpeg', '*.mov', 'thumbs.db', '*.pst', '*.ost')
	if ($job.excludeFiles) { $excludeFiles = $excludeFiles + @($job.excludeFiles.split(",")) }
	if ( !(Test-Path $srcSharePath) -or !(Test-Path $dstSharePath ) ) {
		if (!(Test-Path $srcSharePath)) { Report-Msg -type "[ERROR]" -msg "Problem with Src Path: $srcSharePath" -hue Red }
		if (!(Test-Path $dstSharePath)) { Report-Msg -type "[ERROR]" -msg "Problem with Dst Path: $dstSharePath" -hue Red }
	}
	else {
		$dstPath = "\\$dstServer\$dstShare\$srcServer\$srcShare"
		if ( !(Test-Path .\logs\$srcServer ) ) { MD .\logs\$srcServer }
  else {
   $limit = (Get-Date).AddDays(-15)
   Get-ChildItem -Path .\logs\$srcServer -Recurse -Force | Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt $limit } | Remove-Item -Force -Whatif:$test
  }
		$RoboLogFile = ".\logs\$srcServer\$srcShare-to-$dstServer-$scope-" + $(date).year + "-" + $(date).month + "-" + $(date).day + ".log" + $testLog
		# if ( (Test-Path $dstpath) -and ($scope -ne "Full") ) {
  # Report-Msg -Type "ACTION" -msg "Removing Prior Daily: $dstpath" -Hue Red
  # if (!$Test) { Get-ChildItem -Path $dstPath -Recurse | Remove-Item -Force -Recurse -Confirm:$False }
  # else { "Test Run. Not really deleting $dstPath." }
		# }
		Report-Msg -msg "Src:$srcSharePath | Dst:$dstPath | Options:$options" -Hue Gray
		Report-Msg -msg "ROBOCOPY $srcSharePath $dstPath $options /XD $excludeDirs /XF $excludeFiles /W:0 /R:0 /NFL /NDL /XA:S $testSwitch"
		# ROBOCOPY $srcSharePath $dstPath $options /XD $excludeDirs /XF $excludeFiles /LOG:$RoboLogFile /W:0 /R:0 /NFL /NDL /XA:S $testSwitch
		ROBOCOPY $srcSharePath $dstPath $options /W:0 /R:0 /NFL /NDL /XA:S $testSwitch
	}
 Write-Debug "$dstPath job completed."
}
ErrorCheck ; $error.clear() # Report any errors and clear $error for next run.
"Begin Email Call..."
\\mirage\Scripts\CommonFunctions\Send-HTMLEmail.ps1 -InputObject $emailObjArray -Subject $Subject -Helpdesk:$False -Test:$Test
"End Email Call...`n"
$emailObjArray = $null
$Helpdesk = $null
# End Backup Script