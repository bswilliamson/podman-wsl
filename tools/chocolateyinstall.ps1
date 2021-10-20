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
  Param($Command)
  wsl -d podman -u root -e /bin/bash --login -c "$Command"
}

Function Install-Linux {
  Param($Nameserver, $HttpProxy, $HttpsProxy)

  Write-Output "Installing linux"

  $name = "podman-wsl-rootfs"
  $path = "$env:temp\$name"
  $hash = "47ccf9a773fb2e23c0b762c8d42748834e3dc06317eca7c23238ac962e31ddbe"

  Write-Debug "Downloading fedora image"
  Get-ChocolateyWebFile `
    -PackageName '$name' `
    -FileFullPath "$path.tar.xz" `
    -ChecksumType 'sha256' `
    -Checksum $hash `
    -Url64Bit 'https://kojipkgs.fedoraproject.org/packages/Fedora-Container-Base/35/20211014.n.0/images/Fedora-Container-Base-35-20211014.n.0.x86_64.tar.xz'
  
  Remove-Item -Recurse "$path"

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
    Run-WSLScript "rm /etc/resolv.conf;
      echo nameserver $Nameserver > /etc/resolv.conf;
      LANG=C.UTF-8 dnf -y install e2fsprogs;
      chattr +i /etc/resolv.conf;
      echo -e '[network]\ngenerateResolvConf = false' > /etc/wsl.conf"
  }
}

Function Install-Podman {
  Write-Output "Installing podman"
  Run-WSLScript "LANG=C.UTF-8 dnf -y install podman"
}

Function Add-RetryAtLogin {
  Param($command)

  $action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoExit -Command '$command; Unregister-ScheduledTask -TaskName InstallPodman -Confirm:$false'"
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:UserName
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries 

  Register-ScheduledTask `
    -TaskName 'InstallPodman' `
    -Action $action -Trigger $trigger `
    -RunLevel Highest `
    -Settings $settings -Force
}

#
# Main logic
#

$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

$packageParams = Get-PackageParameters
$httpProxy = Get-Proxy('http://example.com/')
$httpsProxy = Get-Proxy('https://example.com/')

Write-Output 'Configuring WSL'

if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
  Install-Linux -Nameserver $packageParams['Nameserver'] -HttpProxy $httpProxy -HttpsProxy $httpsProxy
  Install-Podman
} else {
  Write-Output 'WSL not yet available -- scheduling task for next login'

  $installCommand = "choco install podman-wsl"
  if (-not [String]::IsNullOrWhiteSpace($packageParams['InstallCommand'])) {
    $installCommand = $packageParams['InstallCommand']
  }
  
  Add-RetryAtLogin -Command "$installCommand"

  throw 'Restart required to complete installation. The installation will automatically run again on the next login.'
}
