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

choco install $installArgs podman-wsl --params "$packageParams" -s "'.;https://chocolatey.org/api/v2'" 

rm *.nupkg
