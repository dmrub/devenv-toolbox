# For backward compatibility with PowerShell versions less than 3.0
if (!(Test-Path Variable:PSScriptRoot)) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

$scriptsDir = Join-Path $PSScriptRoot "scripts"

# Load Initialization Script
. (Join-Path $scriptsDir "init-env.ps1")

function local:BuildDockerImage {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true)]
        [string] $ImageName,

        [Parameter(Mandatory = $false)]
        [string[]]
        $DockerBuildArguments
    )
    $dockerArgs = New-Object System.Collections.ArrayList

    if ($DockerBuildArguments -and $DockerBuildArguments.Count -gt 0) {
        [void] $dockerArgs.AddRange($DockerBuildArguments)
    }

    Write-Verbose "docker build $($dockerArgs -join ' ') -t ""$ImageName"" ""$PSScriptRoot"""

    & docker build $dockerArgs -t "$ImageName" "$PSScriptRoot"
    $result = $?
    if (-not $result) {
        Write-Error "Could not built docker image $ImageName, exit code $lastExitCode, aborting" -ErrorAction Stop
    }
    Write-Output "Built docker image $ImageName"
}

function local:EnsureDockerImage {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true)]
        [string] $ImageName,

        [Parameter(Mandatory = $false)]
        [string[]]
        $DockerBuildArguments
    )

    if (-not (Test-DockerImage $ImageName)) {
        Write-Output "No docker image $ImageName, building it"
        BuildDockerImage $ImageName -DockerBuildArguments $DockerBuildArguments
        $result = $?
        if (-not $result) {
            Write-Error "Could not built docker image $ImageName, exit code $lastExitCode, aborting" -ErrorAction Stop
        }
        Write-Output "Built docker image $ImageName"
    }
    else {
        Write-Verbose "Docker image $ImageName exists"
    }
}

function local:CleanupContainer($Name) {
    Write-Verbose "Stopping container with id $Name"
    & docker stop $Name
    $result = $?
    if (-not $result) {
        Write-Error "Could not stop docker container $Name, exit code $lastExitCode, aborting" -ErrorAction Stop
    }
    Write-Verbose "Removing container with id $Name"
    & docker rm $Name
    $result = $?
    if (-not $result) {
        Write-Error "Could not remove docker container $Name, exit code $lastExitCode, aborting" -ErrorAction Stop
    }
}

function local:CleanupNotRunningContainer($Name) {
    # Cleanup exited or dead containers
    $notRunningContainers = @(Get-DockerContainer -Name $Name)
    foreach ($container in $notRunningContainers) {
        CleanupContainer $container.Id
    }
}

function Main {
    $scriptName = $script:MyInvocation.MyCommand.Name

    if ($args.Count -gt 0 -and -not $args[0].StartsWith("-")) {
        $command = $args[0]
        if ($args.Count -eq 1) {
            $args = @()
        }
        else {
            $args = $args[1..$($args.Count - 1)]
        }
    }
    else {
        $command = "exec"
    }

    $allCommands = @("start", "stop", "exec", "build")
    $commandsThatRequireContainer = @("start", "exec")

    if (-not $allCommands.Contains($command)) {
        Write-Output "${scriptName}: Unsupported command: $command";
        exit 1
    }

    $opt, $restArgs, $err = getopt $args 'hv' 'help', 'verbose'
    if ($err) {
        Write-Output "${scriptName}: $err";
        exit 1
    }

    $help = ($opt.ContainsKey("h") -or $opt.ContainsKey("help"))
    $verbose = ($opt.ContainsKey("v") -or $opt.ContainsKey("verbose"))
    $dockerImageName = $config.docker.imageName
    $dockerContainerName = $config.docker.containerName
    $dockerContainerMountDir = $config.docker.containerMountDir
    $dockerAppUser = $config.docker.appUser
    $dockerAppGroup = $config.docker.appGroup
    $dockerAppUid = $config.docker.appUid
    $dockerAppGid = $config.docker.appGid
    $dockerAppHome = $config.docker.appHome
    $dockerContainerArgs = @("/bin/sh", "-c", "trap exit INT TERM; while true; do sleep 10000000; done")
    $dockerBuildArgs = @("--build-arg", "APP_USER=$dockerAppUser",
                         "--build-arg", "APP_GROUP=$dockerAppGroup",
                         "--build-arg", "APP_UID=$dockerAppUid",
                         "--build-arg", "APP_GID=$dockerAppGid"
                         "--build-arg", "APP_HOME=$dockerAppHome"
                         )
    $dockerExecArgs = @("/usr/local/bin/run-shell.sh")

    $volumeDir = (("$PSScriptRoot" -replace '^([A-Za-z]):\\', '//$1/') -replace '\\', '/')

    if ($help) {
        Write-Output "Usage: ${scriptName} [command] [<args>]

If no arguments provided /bin/sh is started in interactive mode.
Storage is mounted to /mnt directory.

commands:
      start                      Start container
      stop                       Stop container
      exec                       Execute command in container, this command is used by default
      build                      Build container

options:
      -h, --help                 Display this help and exit
      -v, --verbose              Verbose output
      --, ---                    End of options (--- is reserved for Powershell before 6)

current configuration:

docker.imageName = $dockerImageName
docker.containerName = $dockerContainerName
docker.containerMountDir = $dockerContainerMountDir
docker.appUser = $dockerAppUser
docker.appGroup = $dockerAppGroup
docker.appUid = $dockerAppUid
docker.appGid = $dockerAppGid
docker.appHome = $dockerAppHome
"
        exit 0
    }

    if ($verbose) {
        $PSDefaultParameterValues['*:Verbose'] = $true
    }

    if ($command -eq "build") {
        #try {
            BuildDockerImage $dockerImageName -DockerBuildArguments $dockerBuildArgs
        #}
        #catch {
        #    Write-Error "Failed to build container image $dockerImageName, error code: $lastExitCode" -ErrorAction Stop
        #}
        exit 0
    }

    EnsureDockerImage $dockerImageName -DockerBuildArguments $dockerBuildArgs

    $runningContainer = $null
    $runningContainers = @(Get-DockerContainer -Name $dockerContainerName -Status running)
    if ($runningContainers.Count -ge 1) {
        if ($runningContainers.Count -gt 1) {
            Write-Warning "more than one running container"
        }
        $runningContainer = $runningContainers[0]
    }
    else {
        if ($commandsThatRequireContainer.Contains($command)) {
            # Cleanup exited or dead containers
            CleanupNotRunningContainer $dockerContainerName
            # Start new container
            try {
                # FIXME add missing environment variables APP_*
                $containerId = New-DockerContainer `
                    -Image $dockerImageName `
                    -Name $dockerContainerName `
                    -Volumes @{$volumeDir = $dockerContainerMountDir } `
                    -Detach `
                    -ContainerArguments $dockerContainerArgs `
                    -Verbose
            }
            catch {
                Write-Error "Failed to run container with image $dockerImageName, error code: $lastExitCode" -ErrorAction Stop
            }
            $runningContainers = @(Get-DockerContainer -Name $dockerContainerName -Status running)
            if ($runningContainers.Count -eq 0) {
                Write-Error "Could not find running container $dockerImageName" -ErrorAction Stop
            }
            $runningContainer = $runningContainers[0]
        }
    }

    switch ($command) {
        "exec" {
            if (-not $restArgs -or $restArgs.Count -eq 0) {
                Write-Output "Info: $volumeDir is mounted to $dockerContainerMountDir"
            }
            #docker run -ti --rm --name devenv --volume "${volumeDir}:/app" devenv /bin/bash
            Write-Verbose "docker exec -ti $($runningContainer.Id) $($dockerExecArgs -join ' ') $($restArgs -join ' ')"
            & docker exec -ti $runningContainer.Id $dockerExecArgs $restArgs
            break;
        }
        "stop" {
            if ($runningContainer) {
                CleanupContainer $runningContainer.Id
            }
            break;
        }
        "start" {
            # Container already started
            break;
        }
    }
}

# WARNING: The following code does not work in all cases, do not use it
# Powershell versions before 6 eat -- parameters
# C# Environment.GetCommandLineArgs returns all arguments and the name of the powershell executable and script
# The following only works if powershell is explicitly specified on the command line
#$csArgs = [Environment]::GetCommandLineArgs()
#if ($csArgs.Count -gt $args.Count + 2) {
#    $myargs = $csArgs[2..$($csArgs.Count - 1)]
#} else {
#    $myargs = $args
#}
if ($MyInvocation.ExpectingInput) { $input | Main @args } else { Main @args }
