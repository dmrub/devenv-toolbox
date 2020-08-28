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

is-array() {
    declare -p "$1" &>/dev/null && [[ "$(declare -p "$1")" =~ "declare -a" ]]
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

printf-var() {
    if is-array "$1"; then
        eval "printf-array \"\${$1[@]+\"\${$1[@]}\"}\""
    else
        eval "printf %s \"\${$1-}\""
    fi
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

CONFIG_VARS=(
    docker.imageName "devenv-toolbox"
    docker.containerName "devenv-toolbox"
    docker.containerMountDir "/mnt"
    docker.appUid "$(id -u)"
    docker.appGid "$(id -g)"
    docker.appUser "toolbox"
    docker.appGroup "toolbox"
    docker.appHome "/mnt"
    docker.execArgs '("/usr/local/bin/run-shell.sh")'
    docker.runArgs '()'
    docker.containerArgs '()'
    docker.buildArgs '()'
    docker.volumeDir "$ROOT_DIR"
    docker.file "Dockerfile"
)


CV_PRINT_CONFIG=""
CV_TMP=""
for ((i = 0; i < ${#CONFIG_VARS[@]}; i+=2)); do
    CV_NAME=${CONFIG_VARS[i]}
    CV_SHELL_NAME=${CV_NAME^^}
    CV_SHELL_NAME=${CV_SHELL_NAME//./_}
    CV_DEFAULT_VALUE=${CONFIG_VARS[i+1]}
    CV_SHELL=
    # echo "set $CV_SHELL_NAME to $CV_DEFAULT_VALUE" # DEBUG
    printf -v CV_SHELL "
    DEFAULT_${CV_SHELL_NAME}=%s;
    if is-array DEFAULT_${CV_SHELL_NAME}; then
      ${CV_SHELL_NAME}=(\"\${DEFAULT_${CV_SHELL_NAME}[@]+\"\${DEFAULT_${CV_SHELL_NAME}[@]}\"}\");
    else
      ${CV_SHELL_NAME}=\$DEFAULT_${CV_SHELL_NAME};
    fi;" \
        "$CV_DEFAULT_VALUE"
    eval "$CV_SHELL"
    printf -v CV_TMP "%s = \$(printf-var %s)\n" "$CV_NAME" "$CV_SHELL_NAME"
    CV_PRINT_CONFIG=${CV_PRINT_CONFIG}${CV_TMP}
done

printf -v CV_PRINT_CONFIG "print-config() {\n  echo \"%s\";\n}\n" "$CV_PRINT_CONFIG"
eval "$CV_PRINT_CONFIG"
unset CV_PRINT_CONFIG CV_TMP CV_NAME CV_SHELL_NAME CV_SHELL
