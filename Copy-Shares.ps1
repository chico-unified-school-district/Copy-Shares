# Use Run as Administrator in Powershell, cmd.exe, or as a Scheduled Task.
# Use -Mirror switch to purge extra files from destination
# Backup Job file header: srcServer|srcShare|dstServer|dstShare|excludeDirs|excludeFiles

[CmdletBinding()]
param (
    $JobFile,
    [switch]$Mirror,
    [switch]$WhatIf
)
 
$jobs = Import-Csv -Path $JobFile -Delimiter '|'
$excludeFiles = @('*.log', '*desktop.ini', '*.crdownload', '*.tmp', '*.mp4', '*.avi', '*.mpeg', '*.mov', 'thumbs.db', '*.pst', '*.ost')
if ($WhatIf) { $testSwitch = '/L' }
foreach ($job in $jobs) {
    $src = '\\{0}\{1}' -f $job.srcServer, $job.srcShare
    $dst = '\\{0}\{1}\{2}\{3}' -f $job.dstServer, $job.dstShare, $job.srcServer, $job.srcShare
    $options = if ($Mirror) { @('/MIR') } else { @('/E', '/M') }
    ROBOCOPY $src $dst $options /W:0 /R:0 /NFL /NDL /XF $excludeFiles /XA:S $testSwitch
}