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

Param( 
	[Parameter(Mandatory = $True)][ValidateNotNull()]$jobFile,
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
else {
	"Daily Backup"
	$scope = $(Date).DayofWeek
	$options = @("/E", "/M") 
}

if ($Test) {
	"Test Run..."
	$Test = $True
	$testLog = ".test.log"
	$testSwtich = "/L"
}
else {
	"Live run..."
	$Test = $False
	$testLog = $Null
	$testSwtich = $Null 
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
	$excludeFiles = $null
	$excludeDirs = $null
	$srcServer = $job.srcServer
	$srcShare = $job.srcShare
	$srcSharePath = "\\" + $srcServer + "\" + $srcShare
	$dstServer = $job.dstServer
	$dstShare = $job.dstShare
	$dstSharePath = "\\$dstServer\$dstShare"
	$excludeDirs = @("Temp", "Adobe Premiere Pro Preview Files", "$RECYCLE.BIN", "System Volume Information", "Autobackup", "Updater5", "Halo Combat Evolved")
	if ($job.excludeDirs) { $excludeDirs = $excludeDirs + @($job.excludeDirs.split(",")) }
	$excludeFiles = $excludeFiles + @("*.log", "*desktop.ini", "*.db", "*.crdownload", "*.tmp")
	if ($job.excludeFiles) { $excludeFiles = $excludeFiles + @($job.excludeFiles.split(",")) }
	if ( !(Test-Path $srcSharePath) -or !(Test-Path $dstSharePath ) ) {
		if (!(Test-Path $srcSharePath)) { Report-Msg -type "[ERROR]" -msg "Problem with Src Path: $srcSharePath" -hue Red }
		if (!(Test-Path $dstSharePath)) { Report-Msg -type "[ERROR]" -msg "Problem with Dst Path: $dstSharePath" -hue Red }
	}
	else {
		$dstPath = "\\$dstServer\$dstShare\$scope\$srcShare"
		if ( !(Test-Path .\logs\$srcServer ) ) { MD .\logs\$srcServer }
		$RoboLogFile = ".\logs\$srcServer\$srcShare-to-$dstServer-$scope-" + $(date).year + "-" + $(date).month + "-" + $(date).day + ".log" + $testLog
		if ( (Test-Path $dstpath) -and ($scope -ne "Full") ) {
			Report-Msg -Type "ACTION" -msg "Removing Prior Daily: $dstpath" -Hue Red
			if (!$Test) { Get-ChildItem -Path $dstPath -Recurse | Remove-Item -Force -Recurse -Confirm:$False }
			else { "Test Run. Not really deleting $dstPath." }
			# "Deleted $dstPath. Waiting...";read-host
		}
		Report-Msg -msg "Src:$srcSharePath | Dst:$dstPath | Options:$options" -Hue Gray
		# Report-Msg -msg "ROBOCOPY $srcSharePath $dstPath $options /XD $excludeDirs /XF $excludeFiles /LOG:$RoboLogFile /W:0 /R:0 /NFL /NDL /XA:S $testSwtich"
		# ROBOCOPY $srcSharePath $dstPath $options /XD $excludeDirs /XF $excludeFiles /LOG:$RoboLogFile /W:0 /R:0 /NFL /NDL /XA:S $testSwtich
		ROBOCOPY $srcSharePath $dstPath $options /XD $excludeDirs /XF $excludeFiles /W:0 /R:0 /NFL /NDL /XA:S $testSwtich
	}
	if ($Slow) { Read-Host "ENTER to proceed" }
}
ErrorCheck ; $error.clear() # Report any errors and clear $error for next run.
"Begin Email Call..."
\\mirage\Scripts\CommonFunctions\Send-HTMLEmail.ps1 -InputObject $emailObjArray -Subject $Subject -Helpdesk:$False -Test:$Test
"End Email Call...`n"
$emailObjArray = $null
$Helpdesk = $null
# End Backup Script