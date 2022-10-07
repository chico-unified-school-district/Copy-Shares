function Add-Module {
 process {
  Write-Verbose ('{0}: {1}' -f $MyInvocation.MyCommand.Name, $_)
  if (-not(Get-Module -Name $_ -ListAvailable)) {
   $install = @{
    Scope              = 'CurrentUser'
    AllowClobber       = $true
    SkipPublisherCheck = $true
    Confirm            = $false
    Force              = $true
   }
   Find-Module -Name $_ | Install-Module @install
  }
  Import-Module -Name $_ -Force -ErrorAction Stop -Verbose:$false | Out-Null
  # Get-Module -Name $_
 }
}