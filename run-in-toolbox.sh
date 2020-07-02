#!/bin/bash

set -eou pipefail
export LC_ALL=C
unset CDPATH

THIS_DIR=$( (cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P))

# Source shell library
# shellcheck source=scripts/init-env.sh
. "$THIS_DIR/scripts/init-env.sh"


print-usage() {
    echo "Usage: $1 [<options-1>] [command] [<options-2>] [<command-args>]

If no arguments provided /bin/sh is started in interactive mode.
Storage is mounted to docker.containerMountDir = ${DOCKER_CONTAINERMOUNTDIR-} directory.

commands:
    start                      Start container
    stop                       Stop container
    exec                       Execute command in container, this command is used by default
    logs                       Output container logs
    build                      Build container
    install <directory>
                               Install run-in-toolbox script to the specified directory

options-1 and 2:
    -h, --help                 Display this help and exit
    -v, --verbose              Verbose output
    -c, --config=CONFIG_FILE   Path to configuration file

options-2:
    --                         End of options

current user-defined configuration:
"
    print-config
    echo ""
}

build-docker-image() {
    local name docker_fn exit_code
    name=$1
    shift
    if [[ "$DOCKER_FILE" = /* ]]; then
        docker_fn=$DOCKER_FILE
    else
        docker_fn=$ROOT_DIR/$DOCKER_FILE
    fi
    set +e
    (
        set -x
        docker build \
            "$@" \
            -t "$name" \
            -f "$docker_fn" \
            "$ROOT_DIR"
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
    local name dockerResult status
    # Cleanup exited or dead containers
    name=$1
    for status in exited dead created; do
        while IFS=$'\t' read -r -a dockerResult; do
            if [[ "${dockerResult[1]}" = "$name" ]]; then
                cleanup-container "${dockerResult[0]}"
            fi
        done < <(docker ps --filter=status="$status" --no-trunc --all --format "{{.ID}}\t{{.Names}}")
    done
    echo-verbose "Finished cleanup for container $name"
}

is-command-require-container() {
    case "$1" in
        start | exec) return 0 ;;
        *) return 1 ;;
    esac
}

CONFIG_FILE=$THIS_DIR/toolbox-config.ini
HELP=

# options before command
while [[ $# -gt 0 ]]; do
    case "$1" in
    -c|--config)
        CONFIG_FILE=$2
        shift 2
        ;;
    --config=*)
        CONFIG_FILE=${1#*=}
        shift
        ;;
    --help)
        HELP=true
        shift
        break
        ;;
    -v|--verbose)
        VERBOSE=true
        shift
        ;;
    *)
        break
        ;;
    esac
done

# command
if [[ $# -gt 0 && "$1" != -* ]]; then
    COMMAND=$1
    shift
else
    COMMAND="exec"
fi

case "$COMMAND" in
    start | stop | exec | logs | build | install) ;;
    *) fatal "$0: Unsupported command: $COMMAND" ;;
esac

# options after command
while [[ $# -gt 0 ]]; do
    case "$1" in
    -c|--config)
        CONFIG_FILE=$2
        shift 2
        ;;
    --config=*)
        CONFIG_FILE=${1#*=}
        shift
        ;;
    --help)
        HELP=true
        shift
        break
        ;;
    -v|--verbose)
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

if [[ -e "$CONFIG_FILE" ]]; then
    # update default volume directory
    if [[ "$DOCKER_VOLUMEDIR" = "$DEFAULT_DOCKER_VOLUMEDIR" ]]; then
        # if docker volume directory is not changed (e.g. by command line options)
        # use directory of the config file
        DOCKER_VOLUMEDIR=$(dirname -- "${CONFIG_FILE}")
    fi
    if SHELL_CONFIG=$(parse-config "$CONFIG_FILE"); then
        eval "$SHELL_CONFIG"
    fi
fi

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

if [[ "$COMMAND" = "install" ]]; then
    if [[ $# -ne 1 ]]; then
        fatal "install command require destination directory argument"
    fi
    INSTALL_DIR=$1
    shift

    if [[ ! -d "$INSTALL_DIR" ]]; then
        fatal "$INSTALL_DIR is not a directory"
    fi

    INSTALL_DIR=$(abspath "$INSTALL_DIR")
    CONTAINER_NAME=$(basename -- "$INSTALL_DIR")
    THIS_SCRIPT=$(abspath "${BASH_SOURCE[0]}")

    echo "#!/bin/bash
set -eou pipefail
export LC_ALL=C
unset CDPATH

THIS_DIR=\$( (cd \"\$(dirname -- \"\${BASH_SOURCE[0]}\")\" && pwd -P))
exec \"${THIS_SCRIPT}\" -c \"\$THIS_DIR/toolbox-config.ini\"  \"\${@}\"" > "$INSTALL_DIR/run-in-toolbox.sh"
    chmod +x "$INSTALL_DIR/run-in-toolbox.sh"
    if [[ ! -e "$INSTALL_DIR/toolbox-config.ini" ]]; then
        echo "[docker]
containerName=devenv-toolbox-$CONTAINER_NAME
" > "$INSTALL_DIR/toolbox-config.ini"
    else
        echo-warning "Configuration file $INSTALL_DIR/toolbox-config.ini already exists !"
    fi
    message "Installed run-in-toolbox.sh script to the directory $INSTALL_DIR"
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
while IFS=$'\t' read -r -a dockerResult; do
    if [[ "${dockerResult[1]}" = "$DOCKER_CONTAINERNAME" ]]; then
        runningContainers+=("${dockerResult[0]}")
        echo-verbose "Running container with name ${dockerResult[1]} and ID ${dockerResult[0]}"
    fi
done < <(docker ps --filter=status=running --no-trunc --format "{{.ID}}\t{{.Names}}")

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
            "--volume=$DOCKER_VOLUMEDIR:$DOCKER_CONTAINERMOUNTDIR:Z"
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
        while IFS=$'\t' read -r -a dockerResult; do
            if [[ "${dockerResult[1]}" = "$DOCKER_CONTAINERNAME" ]]; then
                runningContainers+=("${dockerResult[0]}")
                echo-verbose "Running container with name ${dockerResult[1]} and ID ${dockerResult[0]}"
            fi
        done < <(docker ps --filter=status=running --no-trunc --format "{{.ID}}\t{{.Names}}")
        if [[ ${#runningContainers[@]} -eq 0 ]]; then
            fatal "Could not find running container $DOCKER_IMAGENAME"
        fi
        runningContainer=${runningContainers[0]}
    fi
fi

case "$COMMAND" in
    exec)
        if [[ $# -eq 0 ]]; then
            message "Info: $DOCKER_VOLUMEDIR is mounted to $DOCKER_CONTAINERMOUNTDIR"
        fi
        echo-verbose "docker exec -ti \"$runningContainer\" ${DOCKER_EXECARGS[*]} $*"
        docker exec -ti "$runningContainer" "${DOCKER_EXECARGS[@]}" "$@"
        ;;
    stop)
        if [[ -n "$runningContainer" ]]; then
            cleanup-container "$runningContainer"
        fi
        cleanup-not-running-container "$DOCKER_CONTAINERNAME"
        ;;
    start)
        # Container already started
        ;;
    logs)
        if [[ -n "$runningContainer" ]]; then
            docker logs "$runningContainer" "$@"
        else
            echo-warning "No running container $DOCKER_CONTAINERNAME"
        fi
        ;;
esac
