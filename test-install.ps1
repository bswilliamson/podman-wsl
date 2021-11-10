param($Debug, $Verbose, $Nameserver)

wsl --unregister podman

$ErrorActionPreference = 'Stop'

choco pack

$installArgs = @('-f', '-y')
if ($Debug -eq $true) {
  $installArgs += '-d'
}
if ($Verbose -eq $true) {
  $installArgs += '-v'
}

$packageParams = @()

if (-not [String]::IsNullOrWhiteSpace($Nameserver)) {
  $packageParams += "/Nameserver:$Nameserver"
}

$opts = @('-s', '.;https://chocolatey.org/api/v2')

if (-not $packageParams.Length -eq 0) {
  $opts += "--params"
  foreach ($param in $packageParams) {
    $opts += "$param"
  }
}

choco install $installArgs podman-wsl $opts

Remove-Item *.nupkg
