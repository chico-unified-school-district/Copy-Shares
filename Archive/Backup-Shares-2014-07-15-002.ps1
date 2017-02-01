<#
.Synopsis
   Run an incremental or full backup to a specified server/device.
.DESCRIPTION
	This script uses Robocopy as its core program for performing backups of shared folders on file servers.
	The backups can be full or incremental
.EXAMPLE
   Backup-Shares -JobFile ".\jobs\Server1.txt"
   
   This runs an incremental, daily backup for all shares listed in "Server1.txt"
.EXAMPLE
   Backup-Shares -JobFile ".\jobs\Server1.txt" -FULL
   
   This runs a full, backup for all shares listed in "Server1.txt"
 .EXAMPLE
   Backup-Shares -JobFile ".\jobs\Server1.txt" -FULL -TEST
   
   This performs a test run in full backup mode for all shares listed in "Server1.txt".
   No data is copied, but log files are still generated for review.
.INPUTS
   a text based job file with the following data:
   Source Server
   Source Share
   Destination Server
   Destination Share
   Excluded Directories (Wildcards OK)
   Excluded Files (Wildcards OK)
   srcServer|srcShare|dstServer|dstShare|excludeDirs|excludeFiles
.OUTPUTS
   Console outputs are disaplyed and log files are generated on each run.
   No cleanup of log files is being performed so old logs must be manually purged.
.NOTES
	A text file is used to determine source and destination. 
	Format the "JobFile" as such: srcServer|srcShare|dstServer|dstShare|excludeDirs|excludeFiles
	The -JobFile Param is used to determine the JobFile. If the -Full is included a full copy is made.
	This will delete files in the destination that no longer exist in the source.
	If -Full is set to $False or not included a daily backup is run and file with teh archive bit set are 
	Copied and the bit is set to off.
	A test switch is included which disable actual coy operations and notifications.
	Logs for are automatically generated.
	The command after "Begin Email Call..." is to pass an object to an outside script for notification purposes.
.FUNCTIONALITY
   Script -> Input JobFile file + full/test parmaters -> files copied -> logs generated
#>

Param( 
	[Parameter(Mandatory=$True)][ValidateNotNull()]$jobFile,
	[Switch]$Full,
	[Switch]$Test
)

# Import Functions
$Common = "\\Gears\Support\Scripts\Common"
. "$Common\Testing\Check-Error-001.ps1"
. "$Common\Testing\Build-Report-001.ps1"

if ( $Full -eq $True ){ 
	"Full Backup"
	$scope = "Full"
	$options = @("/MIR") 
}
else { 
	"Daily Backup"
	$scope = $(Date).DayofWeek
	$options = @("/S", "/M")
}

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

$Global:Subject = "DO - $env:COMPUTERNAME Backup $(date) $((date).dayofweek) - Cooper"
$Global:Helpdesk = $False

$ScriptName =  $MyInvocation.MyCommand.Name
$ScriptLogFile = ".\logs\$ENV:COMPUTERNAME\$ScriptName-$scope-$($(date).year)-$($(date).month)-$($(date).day).log"+$testLog
if (!(Test-Path ".\Logs\$ENV:COMPUTERNAME")) { MD ".\Logs\$ENV:COMPUTERNAME" }

Report-Msg -Type "[SCRIPT]" -msg "$ENV:COMPUTERNAME | $ENV:USERNAME | $ScriptName -Full $Full -Test $Test" -Hue Yellow

ForEach ( $job in (Import-Csv $jobFile -Delimiter "|" ) ) {
	$excludeFiles = $null
	$excludeDirs = $null
	$srcServer = $job.srcServer
	$srcShare = $job.srcShare
	$srcSharePath = "\\$srcServer\$srcShare"
	$dstServer = $job.dstServer
	$dstShare = $job.dstShare
	$dstSharePath = "\\$dstServer\$dstShare"
	 # Set universally excluded directories for all jobs
	$excludeDirs = $excludeDirs + @("Temp"
									"Adobe Premiere Pro Preview Files"
									"$RECYCLE.BIN"
									"System Volume Information"
									"Autobackup"
									"Updater5"
									"Halo Combat Evolved"
	)
	# Appends custom folder exclusions from jobFile
	if ($job.excludeDirs) {
		$excludeDirs = $excludeDirs + @($job.excludeDirs.split(",")) 
	} 
	# Set universally excluded files for all jobs
	$excludeFiles = $excludeFiles + @(
									"*.log"
									"*desktop.ini"
									"*.db"
									"*.crdownload"
									"*.tmp"
	)
	 # Appends custom file exclusions from jobFile
	if ($job.excludeFiles) {
		$excludeFiles = $excludeFiles + @($job.excludeFiles.split(","))
	}
	
	if ( !(Test-Path $srcSharePath) -or !(Test-Path $dstSharePath ) ) {
		if (!(Test-Path $srcSharePath)) {Report-Msg -type "[ERROR]" -msg "Problem with Src Path: $srcSharePath" -hue Red}
		if (!(Test-Path $dstSharePath)) {Report-Msg -type "[ERROR]" -msg "Problem with Dst Path: $dstSharePath" -hue Red}
	}
	else {
		$dstPath = "\\$dstServer\$dstShare\$scope\$srcShare"
		if ( !(Test-Path .\logs\$srcServer ) ) { MD .\logs\$srcServer }
		$RoboLogFile = "\\Gears\Support\Scripts\Servers\backup\logs\$srcServer\$srcShare-to-$dstServer-$scope-"+$(date).year+"-"+$(date).month+"-"+$(date).day+".log"+$testLog
		if ( (Test-Path $dstpath) -and ($scope -ne "Full") ) {
			Report-Msg -Type "ACTION" -msg "Removing Prior Daily: $dstpath" -Hue Red
			Get-ChildItem -Path $dstPath -Recurse | Remove-Item -Force -Recurse -Confirm:$False -WhatIf:$Test
			# "Deleted $dstPath. Waiting...";read-host
			if ($Test) {"Test Run. Not really deleting $dstPath."}
		}
		Report-Msg -msg "Src:$srcSharePath | Dst:$dstPath | Options:$options" -Hue Gray
		$sb = [scriptblock]::Create("ROBOCOPY $srcSharePath $dstPath $options /XD $excludeDirs /XF $excludeFiles /LOG:$RoboLogFile /W:0 /R:0 /NFL /NDL /XA:S $testSwtich")
		$sb
		# Start-Job -Name "$SrcServer-$SrcShare" -ScriptBlock $sb
		# Get-Job -Name "$SrcServer-$SrcShare" | Select Name,Command
		# "Waiting...";Read-Host
	}
}

if ($Test) {
	Get-Job
	"ENTER"
	Read-Host
	Stop-Job *
	Remove-Job *
}
else { get-job | Select name,command }
Check-Error | Report-Msg;  # Report any errors and clear $error for next run.
"Begin Email Call..."
# \\gears\Support\Scripts\ps\Common\Send-HTMLEmail.ps1 -InputObject $emailObjArray -Subject $Subject -Helpdesk:$False -Test:$Test
"End Email Call...`n"
$emailObjArray = $null
$Helpdesk = $null
# End Backup Script