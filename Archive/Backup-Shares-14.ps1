###################################################################
# Run an incremental or full backup to a specified server/device. #
###################################################################
Param( [Parameter(Mandatory=$True)][ValidateNotNull()]$jobFile,[Switch]$Full=$FALSE,[Switch]$Test=$FALSE ) ; CLS
# Variables
if ( $Full -eq $True ){ "Full Backup" ; $scope = "Full" ; $options = @("/MIR") } # Setting Full
else { "Daily Backup" ; $scope = $(Date).DayofWeek ; $options = @("/S", "/M") } # Setting Daily
if ( $Test -eq $True ) { "Test Run..." ; $testSwtich = "/L"} else { $testSwtich = $null } # Test run
$cwd = Split-Path $MyInvocation.MyCommand.Path
$jobs = Import-Csv $jobFile -Delimiter "|" #; $jobs
$Global:emailObjArray = @()
$Global:Subject = "DO - $env:COMPUTERNAME Backup Report $((date).dayofweek) - Cooper"
$Global:Helpdesk = $null
$ScriptName =  $MyInvocation.MyCommand.Name
$ScriptLogFile = ".\logs\$ENV:COMPUTERNAME\BackupScriptLog-$scope-$($(date).year)-$($(date).month)-$($(date).day).log"
$cwd ; CD $cwd
# Functions
Function Report-Msg ($type = "[INFO]",$msg,$hue = "Green") {
	Write-Host "$(date) $type $msg" -ForeGroundColor $hue
	# Add-Content $ScriptLogFile -Value "$(date) $type $msg"
	$emailObjArray += New-Object PSObject -Prop @{ Date=$(date); Type=$type; Msg=$msg }
	$emailObjArray
	if ( $type -eq "[ERROR]" ) {
		"Errors Detected"
		$Global:Helpdesk = $true
		# $global:To = @("helpdesk@chicousd.org","jcooper@chicousd.org")
		$Subject = "[ERROR] "+$Subject
		$Subject
		Exit
		}
	} # End Report-Msg
Function ErrorCheck {
	if ( $Error.Count -ne 0 ) { ForEach ($item in $error) { Report-Msg -Type "[ERROR]" -msg "$item" -Hue Red } }
	else {  Report-Msg -msg "No Powershell errors reported." }
	} 
Report-Msg -msg "SCRIPT BEGIN: $ENV:COMPUTERNAME | $ENV:USERNAME | $ScriptName -Full $Full -Test $Test" -Hue Yellow
ForEach ( $job in $jobs ) {
	$excludeFiles = $null
	$excludeDirs = $null
	$srcServer = $job.srcServer
	$srcShare = $job.srcShare
	$srcSharePath = "\\"+$srcServer+"\"+$srcShare
	$dstServer = $job.dstServer
	$dstShare = $job.dstShare
	$dstSharePath = "\\$dstServer\$dstShare"
	$excludeDirs = @("Temp","Adobe Premiere Pro Preview Files","$RECYCLE.BIN","System Volume Information","Autobackup","Updater5")
	if ($job.excludeDirs) { $excludeDirs = $excludeDirs + @($job.excludeDirs.split(",")) }
	$excludeFiles = $excludeFiles + @("*.log","*desktop.ini","*.db","*.crdownload","*.tmp")
	if ($job.excludeFiles) { $excludeFiles = $excludeFiles + @($job.excludeFiles.split(",")) }
	if (!(Test-Path $srcSharePath)) {Report-Msg -type "[ERROR]" -msg "Problem with Src Path: $srcSharePath" -hue Red}
	elseif (!(Test-Path $dstSharePath )) {Report-Msg -type "[ERROR]" -msg "Problem with Dst Path: $dstSharePath" -hue Red}
	else {
		$dstPath = "\\$dstServer\$dstShare\$scope\$srcShare"
		if (!(Test-Path .\logs\$srcServer )) { MD .\logs\$srcServer } # Create Log Subfolder
		$RoboLogFile = ".\logs\$srcServer\$srcShare-to-$dstServer-$scope-"+$(date).year+"-"+$(date).month+"-"+$(date).day+".log"
		if ( (Test-Path $dstpath) -and ($scope -ne "Full") ) {
			Report-Msg -msg "Removing Prior Daily: $dstpath" -Hue Blue
			Get-ChildItem -Path $dstPath -Recurse | Remove-Item -Force -WhatIf
			}
		Report-Msg -msg "Src:$srcSharePath Dst:$dstPath Options:$options" -Hue Gray
		ROBOCOPY $srcSharePath $dstPath $options /XD $excludeDirs /XF $excludeFiles /LOG:$RoboLogFile /W:0 /R:0 /NFL /NDL /XA:S $testSwtich
		}
	# "Press ENTER key to continue...";read-host
	}
ErrorCheck ; $error.clear() # Report any errors and clear $error for next run.
# $emailObjArray
"Begin Email Call..."
$Helpdesk
if ($Helpdesk -eq $True ) { \\gears\Support\Scripts\ps\Common\Send-HTMLEmail-03.ps1 -InputObject $emailObjArray -Subject $Subject -Helpdesk }
else { \\gears\Support\Scripts\ps\Common\Send-HTMLEmail-03.ps1 -InputObject $emailObjArray -Subject $Subject }
$emailObjArray = $null # Clearing the email input array
$Helpdesk = $null
Report-Msg -msg "SCRIPT END -----------------------------------" -Hue Yellow
# End Backup Script