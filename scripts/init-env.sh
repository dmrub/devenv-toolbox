# shellcheck shell=bash
SCRIPTS_DIR=$( (cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P))

# shellcheck disable=SC2034
ROOT_DIR=$SCRIPTS_DIR/..
VERBOSE=
PY=
PY_VERSION=

init-python-3() {
    local i py py_version
    unset PY PY_VERSION
    # Detect python excutable
    for i in python3 python; do
        if command -v "$i" &>/dev/null; then
            py=$(command -v "$i")
            py_version=$("$py" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
            case "$py_version" in
                3.*)
                    PY=$py
                    # shellcheck disable=SC2034
                    PY_VERSION=$py_version
                    break;;
            esac
        fi
    done
    if [[ -n "$PY" ]]; then
        return 0
    else
        return 1
    fi
}

parse-config() {
    if [[ -z "${PY-}" ]]; then
        if ! init-python-3; then
            error "Could not find Python 3 interpreter, configuration cannot be loaded from file $1"
            return 1
        fi
    fi
    "$PY" "$SCRIPTS_DIR/parse-config.py" "$1"
}

# load-script loads script with correctly defined THIS_DIR environment variable
load-script() {
    local SCRIPT_FILE=$1 THIS_DIR
    # shellcheck disable=SC2034
    THIS_DIR=$( (cd "$(dirname -- "${SCRIPT_FILE}")" && pwd -P))
    # shellcheck disable=SC1090
    . "$SCRIPT_FILE"
}

is-true() {
    case "$1" in
        true | yes | 1) return 0 ;;
    esac
    return 1
}

message() {
    echo >&2 "$*"
}

init-colors() {
    local ncolors
    if command -v tput >/dev/null 2>&1; then
        ncolors=$(tput colors)
    fi
    if [ -t 1 ] && [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
        CRED="$(tput setaf 1)"
        CGREEN="$(tput setaf 2)"
        CYELLOW="$(tput setaf 3)"
        CBLUE="$(tput setaf 4)"
        CBOLD="$(tput bold)"
        CNORMAL="$(tput sgr0)"
    else
        # shellcheck disable=SC2034
        CRED=""
        # shellcheck disable=SC2034
        CGREEN=""
        # shellcheck disable=SC2034
        CYELLOW=""
        # shellcheck disable=SC2034
        CBLUE=""
        # shellcheck disable=SC2034
        CBOLD=""
        # shellcheck disable=SC2034
        CNORMAL=""
    fi
}

echo-verbose() {
    if [ -z ${CYELLOW+x} ]; then
        init-colors
    fi
    if is-true "$VERBOSE"; then
        echo >&2 "${CYELLOW}VERBOSE: $*${CNORMAL}"
    fi
}

echo-warning() {
    if [ -z ${CYELLOW+x} ]; then
        init-colors
    fi
    echo >&2 "${CYELLOW}Warning: $*${CNORMAL}"
}

printf-array() {
    local arg r s
    r=""
    s=""
    for arg in "$@"; do
        printf -v s "%q" "$arg"
        if [[ -z "$r" ]]; then
            r=$s
        else
            r="$r $s"
        fi
    done
    printf "( %s )" "$r"
}


info() {
    echo >&2 "info: $*"
}

error() {
    if [ -z ${CRED+x} ]; then
        init-colors
    fi
    echo >&2 "${CRED}Error: $*${CNORMAL}"
}

fatal() {
    if [ -z ${CRED+x} ]; then
        init-colors
    fi
    echo >&2 "${CRED}Fatal: $*${CNORMAL}"
    exit 1
}

# https://www.linuxjournal.com/content/normalizing-path-names-bash

normpath() {
    # Remove all /./ sequences.
    local path=${1//\/.\//\/}

    # Remove dir/.. sequences.
    while [[ $path =~ ([^/][^/]*/\.\./) ]]; do
        path=${path/${BASH_REMATCH[0]}/}
    done
    echo "$path"
}

if test -x /usr/bin/realpath; then
    abspath() {
        if [[ -d "$1" || -d "$(dirname "$1")" ]]; then
            /usr/bin/realpath "$1"
        else
            case "$1" in
                "" | ".") echo "$PWD";;
                /*) normpath "$1";;
                *)  normpath "$PWD/$1";;
            esac
        fi
    }
else
    abspath() {
        if [[ -d "$1" ]]; then
            (cd "$1" || exit 1; pwd)
        else
            case "$1" in
                "" | ".") echo "$PWD";;
                /*) normpath "$1";;
                *)  normpath "$PWD/$1";;
            esac
        fi
    }
fi

ROOT_DIR=$(abspath "$ROOT_DIR")

test-docker-image() {
    if [[ -n "$(docker images -q "$1")" ]]; then
        return 0
    else
        return 1
    fi
}

# Set defaults

DEFAULT_DOCKER_IMAGENAME=devenv-toolbox
# shellcheck disable=SC2034
DEFAULT_DOCKER_CONTAINERNAME=devenv-toolbox
# shellcheck disable=SC2034
DEFAULT_DOCKER_CONTAINERMOUNTDIR=/mnt
# shellcheck disable=SC2034
DEFAULT_DOCKER_APPUID=$(id -u)
# shellcheck disable=SC2034
DEFAULT_DOCKER_APPGID=$(id -g)
# shellcheck disable=SC2034
DEFAULT_DOCKER_APPGROUP=toolbox
# shellcheck disable=SC2034
DEFAULT_DOCKER_APPUSER=toolbox
# shellcheck disable=SC2034
DEFAULT_DOCKER_APPHOME=/mnt
# shellcheck disable=SC2034
DEFAULT_DOCKER_EXECARGS=("/usr/local/bin/run-shell.sh")
# shellcheck disable=SC2034
DEFAULT_DOCKER_RUNARGS=()
# shellcheck disable=SC2034
DEFAULT_DOCKER_CONTAINERARGS=()
# shellcheck disable=SC2034
DEFAULT_DOCKER_BUILDARGS=()
# shellcheck disable=SC2034
DEFAULT_DOCKER_VOLUMEDIR=$ROOT_DIR
# shellcheck disable=SC2034
DEFAULT_DOCKER_FILE=Dockerfile

# Define configuration variables with defauts
# shellcheck disable=SC2034
DOCKER_IMAGENAME=$DEFAULT_DOCKER_IMAGENAME
# shellcheck disable=SC2034
DOCKER_CONTAINERNAME=$DEFAULT_DOCKER_CONTAINERNAME
# shellcheck disable=SC2034
DOCKER_CONTAINERMOUNTDIR=$DEFAULT_DOCKER_CONTAINERMOUNTDIR
# shellcheck disable=SC2034
DOCKER_APPUSER=$DEFAULT_DOCKER_APPUSER
# shellcheck disable=SC2034
DOCKER_APPGROUP=$DEFAULT_DOCKER_APPGROUP
# shellcheck disable=SC2034
DOCKER_APPUID=$DEFAULT_DOCKER_APPUID
# shellcheck disable=SC2034
DOCKER_APPGID=$DEFAULT_DOCKER_APPGID
# shellcheck disable=SC2034
DOCKER_APPHOME=$DEFAULT_DOCKER_APPHOME
# shellcheck disable=SC2034
DOCKER_EXECARGS=("${DEFAULT_DOCKER_EXECARGS[@]}")
# shellcheck disable=SC2034
DOCKER_RUNARGS=("${DEFAULT_DOCKER_RUNARGS[@]}")
# shellcheck disable=SC2034
DOCKER_CONTAINERARGS=("${DEFAULT_DOCKER_CONTAINERARGS[@]}")
# shellcheck disable=SC2034
DOCKER_BUILDARGS=("${DEFAULT_DOCKER_BUILDARGS[@]}")
# shellcheck disable=SC2034
DOCKER_VOLUMEDIR=$DEFAULT_DOCKER_VOLUMEDIR
# shellcheck disable=SC2034
DOCKER_FILE=$DEFAULT_DOCKER_FILE

# Load configuration
# load-script "$ROOT_DIR/settings.cfg"
print-config() {
    echo "docker.imageName = $DOCKER_IMAGENAME
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
docker.volumeDir = $DOCKER_VOLUMEDIR
docker.file = $DOCKER_FILE"
}
