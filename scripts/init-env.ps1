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
$configFile = Join-Path $rootDir "toolbox-config.ini"

if ($PSVersionTable.ContainsKey("Platform") -and $PSVersionTable.Platform -eq "Unix") {
    $default_docker_appUid = "$(id -u)"
    $default_docker_appGid = "$(id -g)"
}
else {
    $default_docker_appUid = "6000" # FIXME what to do on Windows ?
    $default_docker_appGid = "6000" # FIXME what to do on Windows ?
}

$configVars = [ordered]@{
    "docker.imageName"         = "devenv-toolbox";
    "docker.containerName"     = "devenv-toolbox";
    "docker.containerMountDir" = "/mnt";
    "docker.appUid"            = $default_docker_appUid;
    "docker.appGid"            = $default_docker_appGid;
    "docker.appUser"           = "toolbox";
    "docker.appGroup"          = "toolbox";
    "docker.appHome"           = "/mnt";
    "docker.execArgs"          = @("/usr/local/bin/run-shell.sh");
    "docker.runArgs"           = @();
    "docker.containerArgs"     = @();
    "docker.buildArgs"         = @();
    "docker.volumeDir"         = "$rootDir";
    "docker.file"              = "Dockerfile"
}

$default_config = @{}

foreach ($kv in $configVars.GetEnumerator()) {
    $keyParts = $kv.Name -split '.', 2, "simplematch"
    if ($keyParts.Count -ne 2) {
        Write-Error "Default configuration key $($kv.Name) is not in format <SECTION>.<KEY>" -ErrorAction Stop
    }
    if ($default_config.ContainsKey($keyParts[0])) {
        $sectionDict = $default_config[$keyParts[0]]
    } else {
        $sectionDict = @{}
        $default_config[$keyParts[0]] = $sectionDict
    }
    $sectionDict[$keyParts[1]] = $kv.Value
}

if (!(Test-Path -Path $configFile)) {
    Write-Output "No configuration file: $configFile"
    Write-Output "Creating default configuration file"
    $config = $default_config.Clone()
    Out-IniFile -InputObject $config -FilePath $configFile -Encoding "UTF8"
}
else {
    $config = Get-IniContent -FilePath $configFile
    $config = Merge-Hashtables -First $default_config -Second $config
}

# ConvertTo-Json $config | Write-Host # DEBUG
