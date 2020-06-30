#!/bin/bash

set -eou pipefail
export LC_ALL=C
unset CDPATH

env >&2

message() {
    echo >&2 "[entrypoint.sh] $*"
}

info() {
    message "info: $*"
}

error() {
    echo >&2 "* [entrypoint.sh] Error: $*"
}

fatal() {
    error "$@"
    exit 1
}

message "info: EUID=$EUID args: $*"

if [[ $EUID -ne 0 ]]; then
    # user is not root, change it back to root
    if [[ -x /usr/local/bin/su-entrypoint ]]; then
        exec /usr/local/bin/su-entrypoint --app-user="$(id -un)" "$@"
    else
        exec /usr/bin/sudo -E "$0" --app-user="$(id -un)" "$@"
    fi
fi

ENTRYPOINT_CONFIG="/entrypoint-config.sh"
APP_GROUP=${APP_GROUP:-toolbox}
APP_USER=${APP_USER:-toolbox}
APP_HOME=${APP_HOME:-/mnt}
APP_UID=${APP_UID:-0}
APP_GID=${APP_GID:-0}
APP_CONFIG=()

# Step down from host root to well-known nobody/nogroup user

if [ "$APP_UID" -eq 0 ]; then
    APP_UID=65534
fi
if [ "$APP_GID" -eq 0 ]; then
    APP_GID=65534
fi

usage() {
    echo "Entrypoint Script"
    echo
    echo "This script will perform following steps:"
    echo " * Override application user if --app-user option is specified"
    echo " * Create application configuration in /config.sh file from"
    echo "   --app-config options"
    echo " * Load configuration from ${ENTRYPOINT_CONFIG} file"
    echo ""
    echo "$0 [options]"
    echo "options:"
    echo "      --app-user=            Run application with specified user"
    echo "                             (default $APP_USER)"
    echo "      --app-config=          Add configuration option to config.sh"
    echo "      --entrypoint-config=   Load entrypoint configuration from"
    echo "                             specified file (default: $ENTRYPOINT_CONFIG)"
    echo "      --help-entrypoint      Display this help and exit"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-user)
            APP_USER="$2"
            shift 2
            ;;
        --app-user=*)
            APP_USER="${1#*=}"
            shift
            ;;
        --app-config)
            APP_CONFIG+=("$2")
            shift 2
            ;;
        --app-config=*)
            APP_CONFIG+=("${1#*=}")
            shift
            ;;
        --help-entrypoint)
            usage
            exit
            ;;
        --)
            shift
            break
            ;;
        -*)
            break
            ;;
        *)
            break
            ;;
    esac
done

info "APP_USER=$APP_USER"
info "APP_GROUP=$APP_GROUP"
info "APP_UID=$APP_UID"
info "APP_GID=$APP_GID"
info "APP_CONFIG=(${APP_CONFIG[*]})"
info "ENTRYPOINT_CONFIG=$ENTRYPOINT_CONFIG"

for ((i = 0; i < ${#APP_CONFIG[@]}; i++)); do
    echo "${APP_CONFIG[i]}" >> /config.sh || exit 1
done

if [[ -f "${ENTRYPOINT_CONFIG}" ]]; then
    # shellcheck disable=SC1090
    . "${ENTRYPOINT_CONFIG}"
fi

# Initialization

# Fix permissions for /tmp directory
chmod 0777 /tmp

if [[ -n "$APP_USER" ]] && command -v setfacl &> /dev/null; then
    # Workaround for Ubuntu Bug
    # https://bugs.launchpad.net/ubuntu/+source/xinit/+bug/1562219
    setfacl -m "u:$APP_USER:rw" /dev/tty*
fi

groupadd -o -g "$APP_GID" "$APP_GROUP" &>/dev/null ||
groupmod -o -g "$APP_GID" "$APP_GROUP" &>/dev/null || : ;
useradd -o -u "$APP_UID" -g "$APP_GROUP" -s "$SHELL" -d "$APP_HOME" "$APP_USER" &>/dev/null ||
usermod -o -u "$APP_UID" -g "$APP_GROUP" -s "$SHELL" -d "$APP_HOME" "$APP_USER" &>/dev/null || : ;
#mkhomedir_helper "$APP_USER"

printf \
    "APP_GROUP=%q\nAPP_USER=%q\nAPP_HOME=%q\nAPP_UID=%q\nAPP_GID=%q\n" \
    "$APP_GROUP" \
    "$APP_USER" \
    "$APP_HOME" \
    "$APP_UID" \
    "$APP_GID" > /etc/toolbox-config.sh

if ! grep -q "^${APP_USER}"; then
    chmod 0660 /etc/sudoers;
    echo "${APP_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers;
    chmod 0440 /etc/sudoers;
fi

echo "#!/bin/bash
set -eou pipefail

export TOOLBOX_INITIALIZED=true
. /etc/toolbox-config.sh
export HOME=\$APP_HOME
export USER=\$APP_USER
if [[ -n \"\$APP_HOME\" && -e \"\$APP_HOME\" ]]; then
    if ! err=\$(ls -lA \"\$APP_HOME\" 2>&1 >/dev/null); then
        echo >&2 \"
-----------------------------------------------------------------------------
Error accessing the directory \$APP_HOME:
\$err

If you are using Docker for Windows please check if this directory is shared.
See also: https://docs.docker.com/docker-for-windows/#file-sharing
-----------------------------------------------------------------------------
\"
    fi
fi
if [[ -z \"\${1-}\" ]]; then
    set -- \"\$SHELL\" -l
    cd \"\$APP_HOME\"
fi
exec su-exec \"\$APP_USER:\$APP_GROUP\" \"\$@\"
" > /usr/local/bin/run-shell.sh
chmod +x /usr/local/bin/run-shell.sh

if [[ -n "$APP_USER" && "$APP_USER" != "root" ]]; then
    set -xe
    exec /usr/local/bin/tini -- /usr/local/bin/su-exec "$APP_USER" "$@"
else
    set -xe
    exec /usr/local/bin/tini -- "$@"
fi
