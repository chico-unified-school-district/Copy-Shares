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


Param( [Parameter(Mandatory=$True)][ValidateNotNull()]$jobFile,[Switch]$Full,[Switch]$Test) ; CLS


# Import Functions
$Common = "\\Gears\Support\Scripts\Common"
. "$Common\Testing\Check-Error-001.ps1"
. "$Common\Report-Msg.ps1"

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

# $Global:emailObjArray = @()
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
	
	$excludeDirs = $excludeDirs + @("Temp"
									"Adobe Premiere Pro Preview Files"
									"$RECYCLE.BIN"
									"System Volume Information"
									"Autobackup"
									"Updater5"
									"Halo Combat Evolved"
	) # Set universally excluded directories for all jobs
	
	if ($job.excludeDirs) { 
		$excludeDirs = $excludeDirs + @($job.excludeDirs.split(",")) 
	} # Appends custom folder exclusions from jobFile
	
	$excludeFiles = $excludeFiles + @("*.log"
									"*desktop.ini"
									"*.db"
									"*.crdownload"
									"*.tmp"
	) # Set universally excluded files for all jobs
	
	if ($job.excludeFiles) { 
		$excludeFiles = $excludeFiles + @($job.excludeFiles.split(",")) 
	} # Appends custom file exclusions from jobFile
	
	if ( !(Test-Path $srcSharePath) -or !(Test-Path $dstSharePath ) ) {
		if (!(Test-Path $srcSharePath)) {Report-Msg -type "[ERROR]" -msg "Problem with Src Path: $srcSharePath" -hue Red}
		if (!(Test-Path $dstSharePath)) {Report-Msg -type "[ERROR]" -msg "Problem with Dst Path: $dstSharePath" -hue Red}
	}
	else {
		$dstPath = "\\$dstServer\$dstShare\$scope\$srcShare"
		if ( !(Test-Path .\logs\$srcServer ) ) { MD .\logs\$srcServer }
		$RoboLogFile = ".\logs\$srcServer\$srcShare-to-$dstServer-$scope-"+$(date).year+"-"+$(date).month+"-"+$(date).day+".log"+$testLog
		if ( (Test-Path $dstpath) -and ($scope -ne "Full") ) {
			Report-Msg -Type "ACTION" -msg "Removing Prior Daily: $dstpath" -Hue Red
			Get-ChildItem -Path $dstPath -Recurse | Remove-Item -Force -Recurse -Confirm:$False -WhatIf:$Test
			# "Deleted $dstPath. Waiting...";read-host
			if ($Test) {"Test Run. Not really deleting $dstPath."}
		}
		
		Report-Msg -msg "Src:$srcSharePath | Dst:$dstPath | Options:$options" -Hue Gray
		$args = ( $srcSharePath,$dstPath,$options,$excludeDirs,$excludeFiles,$RoboLogFile,$testSwtich )
		Start-Job -ScriptBlock { ROBOCOPY $args[0] $args[1] $args[2] /XD $args[3] /XF $args[4] /LOG:$args[5] /W:0 /R:0 /NFL /NDL /XA:S $args[6] } -ArgumentList $args
		Sleep 5
		Get-Job -Name "$SrcServer-$SrcShare" | Select Name,Command
		"Waiting...";Read-Host
	}
	# "Press ENTER key to continue...";read-host
}

if ($Test) {
	Get-Job
	"ENTER"
	Read-Host
	Stop-Job *
	Remove-Job *
}
else { get-job }
Check-Error ;  # Report any errors and clear $error for next run.
"Begin Email Call..."
# \\gears\Support\Scripts\ps\Common\Send-HTMLEmail.ps1 -InputObject $emailObjArray -Subject $Subject -Helpdesk:$False -Test:$Test
"End Email Call...`n"
$emailObjArray = $null
$Helpdesk = $null
# End Backup Script