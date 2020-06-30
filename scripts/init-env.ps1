Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# For backward compatibility with PowerShell versions less than 3.0
if (!(Test-Path Variable:PSScriptRoot)) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

# Write-Output "Initializing PowerShell Library..."

# Load PowerShell Library
. (Join-Path $PSScriptRoot "pslib.ps1")

# Write-Output "Done"

$rootDir = Resolve-FullPath (Join-Path $PSScriptRoot "..")
$configFile = Join-Path $rootDir "config.ini"

$default_docker_imageName = "devenv-toolbox"
$default_docker_containerName = "devenv-toolbox"
$default_docker_containerMountDir = "/mnt"
if ($PSVersionTable.ContainsKey("Platform") -and $PSVersionTable.Platform -eq "Unix") {
    $default_docker_appUid = "$(id -u)"
    $default_docker_appGid = "$(id -g)"
} else {
    $default_docker_appUid = "6000" # FIXME what to do on Windows ?
    $default_docker_appGid = "6000" # FIXME what to do on Windows ?
}
$default_docker_appGroup = "toolbox"
$default_docker_appUser = "toolbox"
$default_docker_appHome = "/mnt"

$default_docker = @{
    "imageName"=$default_docker_imageName;
    "containerName"=$default_docker_containerName;
    "containerMountDir"=$default_docker_containerMountDir;
    "appUid"=$default_docker_appUid;
    "appGid"=$default_docker_appGid;
    "appGroup"=$default_docker_appGroup;
    "appUser"=$default_docker_appUser;
    "appHome"=$default_docker_appHome;
}
$default_config = @{"docker"=$default_docker}

if (!(Test-Path -Path $configFile)) {
    Write-Output "No configuration file: $configFile"
    Write-Output "Creating default configuration file"
    $config = $default_config.Clone()
    Out-IniFile -InputObject $config -FilePath $configFile -Encoding "UTF8"
} else {
    $config = Get-IniContent -FilePath $configFile
    $config = Merge-Hashtables -First $default_config -Second $config
}
