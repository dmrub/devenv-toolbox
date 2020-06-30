#!/bin/bash

set -eou pipefail
export LC_ALL=C
unset CDPATH

THIS_DIR=$( (cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P))

# Source shell library
# shellcheck source=scripts/init-env.sh
. "$THIS_DIR/scripts/init-env.sh"


print-usage() {
    echo "Usage: $1 [command] [<args>]

If no arguments provided /bin/sh is started in interactive mode.
Storage is mounted to /mnt directory.

commands:
    start                      Start container
    stop                       Stop container
    exec                       Execute command in container, this command is used by default
    build                      Build container

options:
    --help                 Display this help and exit
    -h, --help                 Display this help and exit
    -v, --verbose              Verbose output
    --                         End of options

current user-defined configuration:

docker.imageName = $DOCKER_IMAGENAME
docker.containerName = $DOCKER_CONTAINERNAME
docker.containerMountDir = $DOCKER_CONTAINERMOUNTDIR
docker.appUser = $DOCKER_APPUSER
docker.appGroup = $DOCKER_APPGROUP
docker.appUid = $DOCKER_APPUID
docker.appGid = $DOCKER_APPGID
docker.appHome = $DOCKER_APPHOME
docker.execArgs = $(printf-array "${DOCKER_EXECARGS[@]}")
docker.runArgs = $(printf-array "${DOCKER_RUNARGS[@]}")
docker.containerArgs = $(printf-array "${DOCKER_CONTAINERARGS[@]}")
docker.buildArgs = $(printf-array "${DOCKER_BUILDARGS[@]}")
"
}

build-docker-image() {
    local name exit_code
    name=$1
    shift
    set +e
    (
        set -x
        docker build \
            "$@" \
            -t "$name" "$ROOT_DIR"
    )
    exit_code=$?
    set -e
    if [[ $exit_code -ne 0 ]]; then
        fatal "Could not built docker image $name, exit code $exit_code, aborting"
    fi
}

ensure-docker-image() {
    local name exit_code
    name=$1
    shift
    if ! test-docker-image "$name"; then
        echo "No docker image $name, building it"
        build-docker-image "$name" "$@"
    else
        echo-verbose "Docker image $name exists"
    fi
}

cleanup-container() {
    local name exit_code
    name=$1
    shift
    echo-verbose "Stopping container with id $name"
    set +e
    docker stop "$name" &>/dev/null
    exit_code=$?
    set -e
    if [[ $exit_code -ne 0 ]]; then
        fatal "Could not stop docker container $name, exit code $exit_code, aborting"
    fi
    echo-verbose "Removing container with id $name"
    set +e
    docker rm "$name" &>/dev/null
    exit_code=$?
    set -e
    if [[ $exit_code -ne 0 ]]; then
        fatal "Could not remove docker container $name, exit code $exit_code, aborting"
    fi
}

cleanup-not-running-container() {
    local name cid status
    # Cleanup exited or dead containers
    name=$1
    for status in exited dead; do
        while IFS='' read -r cid; do
            cleanup-container "$cid"
        done < <(docker ps --filter=name="$name" --filter=status="$status" --all --quiet)
    done
}

if [[ $# -gt 0 && "$1" != -* ]]; then
    COMMAND=$1
    shift
else
    COMMAND="exec"
fi

case "$COMMAND" in
    start | stop | exec | build) ;;
    *) fatal "$0: Unsupported command: $COMMAND" ;;
esac

is-command-require-container() {
    case "$1" in
        start | exec) return 0 ;;
        *) return 1 ;;
    esac
}

DOCKER_IMAGENAME=$DEFAULT_DOCKER_IMAGENAME
DOCKER_CONTAINERNAME=$DEFAULT_DOCKER_CONTAINERNAME
DOCKER_CONTAINERMOUNTDIR=$DEFAULT_DOCKER_CONTAINERMOUNTDIR
DOCKER_APPUSER=$DEFAULT_DOCKER_APPUSER
DOCKER_APPGROUP=$DEFAULT_DOCKER_APPGROUP
DOCKER_APPUID=$DEFAULT_DOCKER_APPUID
DOCKER_APPGID=$DEFAULT_DOCKER_APPGID
DOCKER_APPHOME=$DEFAULT_DOCKER_APPHOME
DOCKER_EXECARGS=("${DEFAULT_DOCKER_EXECARGS[@]}")
DOCKER_RUNARGS=("${DEFAULT_DOCKER_RUNARGS[@]}")
DOCKER_CONTAINERARGS=("${DEFAULT_DOCKER_CONTAINERARGS[@]}")
DOCKER_BUILDARGS=("${DEFAULT_DOCKER_BUILDARGS[@]}")

CONFIG_FILE=$THIS_DIR/config.ini

if [[ -e "$CONFIG_FILE" ]]; then
    if SHELL_CONFIG=$(load-config "$CONFIG_FILE"); then
        eval "$SHELL_CONFIG"
    fi
fi

VOLUME_DIR=$THIS_DIR
HELP=

while [[ $# -gt 0 ]]; do
    case "$1" in
    --help)
        HELP=true
        shift
        break
        ;;
    -v | --verbose)
        VERBOSE=true
        shift
        ;;
    --)
        shift
        break
        ;;
    -*)
        fatal "Unknown option $1"
        ;;
    *)
        break
        ;;
    esac
done

if [[ "$DOCKER_APPUID" -eq 0 ]]; then
    DOCKER_APPUID=65535
fi
if [[ "$DOCKER_APPGID" -eq 0 ]]; then
    DOCKER_APPGID=65535
fi

if is-true "$HELP"; then
    print-usage "$0"
    exit 0
fi

DOCKER_BUILDARGS+=(
    --build-arg "APP_USER=$DOCKER_APPUSER"
    --build-arg "APP_GROUP=$DOCKER_APPGROUP"
    --build-arg "APP_UID=$DOCKER_APPUID"
    --build-arg "APP_GID=$DOCKER_APPGID"
    --build-arg "APP_HOME=$DOCKER_APPHOME"
)

if ! docker_output=$(docker info 2>&1); then
    fatal "Could not run 'docker info', aborting:
---
$docker_output
---
    "
fi

if [[ "$COMMAND" = "build" ]]; then
    build-docker-image "$DOCKER_IMAGENAME" "${DOCKER_BUILDARGS[@]}"
    exit 0
fi

ensure-docker-image "$DOCKER_IMAGENAME" "${DOCKER_BUILDARGS[@]}"

runningContainer=
runningContainers=()
while IFS='' read -r line; do runningContainers+=("$line"); done < <(docker ps --filter=name="$DOCKER_CONTAINERNAME" --filter=status=running --quiet)

if [[ ${#runningContainers[@]} -ge 1 ]]; then
    if [[ ${#runningContainers[@]} -gt 1 ]]; then
        echo-warning "more than one running container"
    fi
    runningContainer=${runningContainers[0]}
else
    if is-command-require-container "$COMMAND"; then
        # Cleanup exited or dead containers
        cleanup-not-running-container "$DOCKER_CONTAINERNAME"
        # Start new container
        dockerArgs=(
            "--name=$DOCKER_CONTAINERNAME"
            "--volume=$VOLUME_DIR:$DOCKER_CONTAINERMOUNTDIR:Z"
            "--env=APP_USER=$DOCKER_APPUSER"
            "--env=APP_GROUP=$DOCKER_APPGROUP"
            "--env=APP_UID=$DOCKER_APPUID"
            "--env=APP_GID=$DOCKER_APPGID"
            "--env=APP_HOME=$DOCKER_APPHOME"
        )
        for dockerArg in "${DOCKER_RUNARGS[@]}"; do
            dockerArgs+=("$dockerArg")
        done
        dockerArgs+=(
            "--detach"
            "$DOCKER_IMAGENAME"
        )
        for dockerArg in "${DOCKER_CONTAINERARGS[@]}"; do
            dockerArgs+=("$dockerArg")
        done
        echo-verbose "docker run ${dockerArgs[*]}"
        set +e
        # shellcheck disable=SC2034
        containerId=$(docker run "${dockerArgs[@]}")
        exit_code=$?
        set -e
        if [[ $exit_code -ne 0 ]]; then
            error "Could not run docker container: docker run ${dockerArgs[*]}"
            fatal "Failed to run container with image $DOCKER_IMAGENAME, error code: $exit_code"
        fi
        runningContainers=()
        while IFS='' read -r cid; do
            runningContainers+=("$cid");
        done < <(docker ps --filter=name="$DOCKER_CONTAINERNAME" --filter=status=running --quiet)
        if [[ ${#runningContainers[@]} -eq 0 ]]; then
            fatal "Could not find running container $DOCKER_IMAGENAME"
        fi
        runningContainer=${runningContainers[0]}
    fi
fi

case "$COMMAND" in
    exec)
        if [[ $# -eq 0 ]]; then
            message "Info: $VOLUME_DIR is mounted to $DOCKER_CONTAINERMOUNTDIR"
        fi
        echo-verbose "docker exec -ti \"$runningContainer\" ${DOCKER_EXECARGS[*]} $*"
        docker exec -ti "$runningContainer" "${DOCKER_EXECARGS[@]}" "$@"
        ;;
    stop)
        if [[ -n "$runningContainer" ]]; then
            cleanup-container "$runningContainer"
        fi
        ;;
    start)
        # Container already started
        ;;
esac
