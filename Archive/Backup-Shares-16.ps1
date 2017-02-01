###################################################################
# Run an incremental or full backup to a specified server/device. #
###################################################################
Param( [Parameter(Mandatory=$True)][ValidateNotNull()]$jobFile,[Switch]$Full,[Switch]$Test) ; CLS
# Variables
if ( $Full -eq $True ){ "Full Backup" ; $scope = "Full" ; $options = @("/MIR") }
else { "Daily Backup" ; $scope = $(Date).DayofWeek ; $options = @("/S", "/M") }
if ($Test) {
	"Test Run..."
	$Test=$True
	$testLog = ".test.log"
	$testSwtich = "/L"
}
else {
	"Live run..."
	$Test=$False
	$testLog = $Null
	$testSwtich = $Null 
} 
$cwd = Split-Path $MyInvocation.MyCommand.Path
$jobs = Import-Csv $jobFile -Delimiter "|" 
#$jobs
$Global:emailObjArray = @()
$Global:Subject = "DO - $env:COMPUTERNAME Backup $(date) $((date).dayofweek) - Cooper"
$Global:Helpdesk = $null
$ScriptName =  $MyInvocation.MyCommand.Name
$ScriptLogFile = ".\logs\$ENV:COMPUTERNAME\$ScriptName-$scope-$($(date).year)-$($(date).month)-$($(date).day).log"+$testLog
$cwd ; CD $cwd
Function Report-Msg ($type = "[INFO]",$msg,$hue = "Green") {
	Write-Host "$(date) $type $msg" -ForeGroundColor $hue
	Add-Content $ScriptLogFile -Value "$(date) $type $msg"
	$Global:emailObjArray += New-Object PSObject -Prop @{ Date=$(date); Type=$type; Msg=$msg }
	if ( $type -eq "[ERROR]" ) {
		"Errors Detected"
		$Global:Helpdesk = $true
		$Global:Subject = "[ERROR] "+$Global:Subject
	}
}
Function ErrorCheck {
	if ( $Error.Count -ne 0 ) { ForEach ($item in $error) { Report-Msg -Type "[ERROR]" -msg "$item" -Hue Red } }
	else {  Report-Msg -msg "No Powershell errors reported." }
} 
Report-Msg -msg "$ENV:COMPUTERNAME | $ENV:USERNAME | $ScriptName -Full $Full -Test $Test" -Hue Yellow
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
		$RoboLogFile = ".\logs\$srcServer\$srcShare-to-$dstServer-$scope-"+$(date).year+"-"+$(date).month+"-"+$(date).day+".log"+$testLog
		if ( (Test-Path $dstpath) -and ($scope -ne "Full") ) {
			Report-Msg -msg "Removing Prior Daily: $dstpath" -Hue Red
			if (!$Test) { Get-ChildItem -Path $dstPath -Recurse | Remove-Item -Force -Recurse -Confirm:$False }
			else { "Test Run. Not really deleting $dstPath." }
			# "Deleted $dstPath. Waiting...";read-host
		}
		Report-Msg -msg "Src:$srcSharePath Dst:$dstPath Options:$options" -Hue Gray
		ROBOCOPY $srcSharePath $dstPath $options /XD $excludeDirs /XF $excludeFiles /LOG:$RoboLogFile /W:0 /R:0 /NFL /NDL /XA:S $testSwtich
	}
	# "Press ENTER key to continue...";read-host
}
ErrorCheck ; $error.clear() # Report any errors and clear $error for next run.
Report-Msg -msg "SCRIPT END -----------------------------------" -Hue Yellow
"Begin Email Call..."
if ($Helpdesk) { \\gears\Support\Scripts\ps\Common\Send-HTMLEmail.ps1 -InputObject $emailObjArray -Subject $Subject -Helpdesk -Test:$Test }
else { \\gears\Support\Scripts\ps\Common\Send-HTMLEmail.ps1 -InputObject $emailObjArray -Subject $Subject -Test:$Test}
"End Email Call..."
$emailObjArray = $null
$Helpdesk = $null
# End Backup Script