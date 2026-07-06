# shellcheck shell=bash
LOG_LEVEL=${LOG_LEVEL:-"info"}

# Map level name -> numeric severity
_log_level_num() {
    case "$1" in
        debug) echo 0 ;;
        info)  echo 1 ;;
        warn)  echo 2 ;;
        error) echo 3 ;;
        *)     echo 1 ;;
    esac
}

# Colors: enable only for an interactive TTY unless explicitly disabled
if [ "${LOG_NO_COLOR:-0}" != "1" ] && [ -t 2 ]; then
    _LOG_C_RESET=$'\033[0m'
    _LOG_C_DEBUG=$'\033[2;37m'   # dim gray
    _LOG_C_INFO=$'\033[0;36m'    # cyan
    _LOG_C_WARN=$'\033[0;33m'    # yellow
    _LOG_C_ERROR=$'\033[0;31m'   # red
else
    _LOG_C_RESET=""
    _LOG_C_DEBUG=""
    _LOG_C_INFO=""
    _LOG_C_WARN=""
    _LOG_C_ERROR=""
fi

# _log <level> <color> <label> <message...>
_log() {
    local level="$1" color="$2" label="$3"
    shift 3

    local threshold current
    threshold=$(_log_level_num "$LOG_LEVEL")
    current=$(_log_level_num "$level")
    if [ "$current" -lt "$threshold" ]; then
        return 0
    fi

    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '%s%s [%s] %s%s\n' "$color" "$ts" "$label" "$*" "$_LOG_C_RESET" >&2
}

log_debug() { _log debug "$_LOG_C_DEBUG" "DEBUG" "$@"; }
log_info()  { _log info  "$_LOG_C_INFO"  "INFO " "$@"; }
log_warn()  { _log warn  "$_LOG_C_WARN"  "WARN " "$@"; }
log_error() { _log error "$_LOG_C_ERROR" "ERROR" "$@"; }

# Log at error level, then exit
log_die() {
    log_error "$@"
    exit 1
}
