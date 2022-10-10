[CmdletBinding()]
param(
 [string]$Database,
 [string]$SrcServer,
 [string]$SrcShare,
 [string]$DstServer,
 [string]$DstShare,
 [switch]$WhatIf
)
$data = $SrcServer, $SrcShare, $DstServer, $DstShare
$sql = "INSERT INTO jobs (srcServer,srcShare,dstServer,dstShare) VALUES (`'{0}`',`'{1}`',`'{2}`',`'{3}`');" -f $data
Write-Host $sql -Fore Green
if (-not$WhatIf) { Invoke-SqliteQuery -DataSource $Database -Query $sql }