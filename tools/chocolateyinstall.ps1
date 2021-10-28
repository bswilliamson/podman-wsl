$ErrorActionPreference = 'Stop'

#
# Function definitions
#

Function Get-Proxy {
  Param($url)
  $proxy = [System.Net.WebRequest]::DefaultWebProxy.GetProxy($url).AbsoluteUri
  if ($proxy -eq $url) {
    return ''
  }
  return $proxy
}

Function Run-WSLScript {
  $Command = $args -join " && "
  wsl -d podman -u root -e /bin/bash --login -c "$Command"
}

Function Install-Linux {
  Param($Nameserver, $HttpProxy, $HttpsProxy)

  Write-Output "Installing linux"

  $name = "podman-wsl-rootfs"
  $path = "$env:temp\$name"
  $hash = "47ccf9a773fb2e23c0b762c8d42748834e3dc06317eca7c23238ac962e31ddbe"

  Get-ChocolateyWebFile `
    -PackageName "$name" `
    -FileFullPath "$path.tar.xz" `
    -ChecksumType 'sha256' `
    -Checksum $hash `
    -Url64Bit 'https://kojipkgs.fedoraproject.org/packages/Fedora-Container-Base/35/20211014.n.0/images/Fedora-Container-Base-35-20211014.n.0.x86_64.tar.xz'
  
  Remove-Item -Recurse "$path" -ErrorAction Ignore

  Get-ChocolateyUnzip -FileFullPath "$path.tar.xz" -Destination "$path\.."
  Get-ChocolateyUnzip -FileFullPath "$path.tar" -Destination "$path"
  Remove-Item "$path.tar"

  $layerDir = (Get-ChildItem -Directory "$path")[0].FullName
  $image = "$layerDir\layer.tar"

  wsl --import podman --version 2 "$env:LOCALAPPDATA\podman-wsl\" "$image"

  if (-not [String]::IsNullOrWhiteSpace($HttpProxy)) {
    Run-WSLScript "echo 'export http_proxy=$HttpProxy' >> /etc/profile.d/proxy.sh"
  }

  if (-not [String]::IsNullOrWhiteSpace($HttpsProxy)) {
    Run-WSLScript "echo 'export https_proxy=$HttpProxy' >> /etc/profile.d/proxy.sh"
  }
  
  if (-not [String]::IsNullOrWhiteSpace($nameserver)) {
    Run-WSLScript `
      "rm /etc/resolv.conf" `
      "echo nameserver $Nameserver > /etc/resolv.conf" `
      "LANG=C.UTF-8 dnf -yq install e2fsprogs" `
      "chattr +i /etc/resolv.conf" `
      "echo -e '[network]\ngenerateResolvConf = false' > /etc/wsl.conf"
  }

  Run-WSLScript `
    "curl -fsSLo /tmp/dasel https://github.com/TomWright/dasel/releases/download/v1.21.2/dasel_linux_amd64" `
    "install /tmp/dasel /usr/local/bin" `
    "rm -rf /tmp/dasel"
}

Function Install-Podman {
  Param($Nameserver, $HttpProxy, $HttpsProxy)
  Write-Output "Installing podman"
  Run-WSLScript "LANG=C.UTF-8 dnf -yq install podman podman-docker"

  if (-not [String]::IsNullOrWhiteSpace($HttpProxy)) {
    Set-ContainerConf -Path '.engine.env.[]' -Value "http_proxy=$HttpProxy"
  }

  if (-not [String]::IsNullOrWhiteSpace($HttpsProxy)) {
    Set-ContainerConf -Path '.engine.env.[]' -Value "https_proxy=$HttpsProxy"
  }
}

Function Set-ContainerConf {
  Param($Path, $Value)
  Run-WSLScript "dasel put string -f /usr/share/containers/containers.conf -p toml -s '$Path' '$Value'"
}

#
# Main logic
#

$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

$packageParams = Get-PackageParameters
$httpProxy = Get-Proxy('http://example.com/')
$httpsProxy = Get-Proxy('https://example.com/')

Write-Output 'Configuring WSL'

$wsl2Available = $false
if (Get-Command wsl.exe -ErrorAction Ignore) {
  wsl --set-default-version 2 | Out-Null
  $wsl2Available = $?
}

if ($wsl2Available) {
  Install-Linux -Nameserver $packageParams['Nameserver'] -HttpProxy $httpProxy -HttpsProxy $httpsProxy
  Install-Podman -HttpProxy $httpProxy -HttpsProxy $httpsProxy
} else {
  throw 'This package requires WSL2 to be installed manually. Run "choco install wsl2", reboot, then try again.'
}
