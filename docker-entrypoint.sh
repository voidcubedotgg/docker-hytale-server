#!/bin/bash

set -euo pipefail

# shellcheck source=scripts/logger.sh
source /opt/voidcube/scripts/logger.sh

log_info "Loading scripts..."
# shellcheck source=scripts/utils.sh
source /opt/voidcube/scripts/utils.sh
# shellcheck source=scripts/sops.sh
source /opt/voidcube/scripts/sops.sh
# shellcheck source=scripts/downloader.sh
source /opt/voidcube/scripts/downloader.sh
# shellcheck source=scripts/hytale_auth.sh
source /opt/voidcube/scripts/hytale_auth.sh
log_info "Done scripts loaded!"

HYTALE_DISABLE_UPDATES=${HYTALE_DISABLE_UPDATES:-"1"}
ASSET_PACK=${ASSET_PACK:-"Assets.zip"}
LEVERAGE_AHEAD_OF_TIME_CACHE=${LEVERAGE_AHEAD_OF_TIME_CACHE:-"0"}
AHEAD_OF_TIME_CACHE_PATH=${AOTCACHE_PATH:-"HytaleServer.aot"}
ACCEPT_EARLY_PLUGINS=${ACCEPT_EARLY_PLUGINS:-"0"}
SERVER_MEMORY=${SERVER_MEMORY:-"4096"}
SERVER_JAR_PATH=${SERVER_JAR:-"HytaleServer.jar"}
DISABLE_SENTRY=${DISABLE_SENTRY:-"0"}
ALLOW_OP=${ALLOW_OP:-"1"}
ENABLE_BACKUPS=${ENABLE_BACKUPS:-"0"}
BACKUP_FREQUENCY=${BACKUP_FREQUENCY:-"0"}
BACKUP_DIR_PATH=${BACKUP_DIR:-"./backup"}
JVM_ARGS=${JVM_ARGS:-""}

# Download Hytale files
sops_decrypt_file "$DOWNLOADER_AUTH_CACHE_FILE"
if downloader_check_for_updates; then
    downloader_download_files
    downloader_extract_server_files
    downloader_save_game_version
fi
# Soft-fail: a re-encrypt failure must not abort the entrypoint (would leave creds plaintext + kill server)
sops_encrypt_file "$DOWNLOADER_AUTH_CACHE_FILE" || log_warn "failed to re-encrypt $DOWNLOADER_AUTH_CACHE_FILE"

# Create Hytale game session
if hytale_auth_enabled; then
    if hytale_auth_check_cached_tokens && hytale_auth_load_cached_tokens; then
        log_info "Using cached authentication - skipping login prompt"
        hytale_auth_refresh_authentication
    else
        hytale_auth_perform_device_flow
    fi
    hytale_auth_create_game_session
fi

# Don't pass SOPS envs to java process
sops_unset_envs

log_info "Starting Hytale server..."

# Export automatic updates setting to Java process
export HYTALE_DISABLE_UPDATES=${HYTALE_DISABLE_UPDATES}

# Build the Java command
JAVA_CMD="java"

# Add AOT cache if enabled
if [ "${LEVERAGE_AHEAD_OF_TIME_CACHE}" = "1" ]; then
    JAVA_CMD="${JAVA_CMD} -XX:AOTCache=${AHEAD_OF_TIME_CACHE_PATH}"
fi

# Add max memory if set and greater than 0
if [ -n "${SERVER_MEMORY}" ] && [ "${SERVER_MEMORY}" -gt 0 ] 2>/dev/null; then
    JAVA_CMD="${JAVA_CMD} -Xms${SERVER_MEMORY}M -Xmx${SERVER_MEMORY}M"
fi

# Add JVM arguments if set
if [ -n "${JVM_ARGS}" ]; then
    JAVA_CMD="${JAVA_CMD} ${JVM_ARGS}"
fi

JAVA_CMD="${JAVA_CMD} -jar ${SERVER_JAR_PATH}"

# Add assets parameter if set and ends with .zip
if [ -n "${ASSET_PACK}" ] && [[ "${ASSET_PACK}" == *.zip ]]; then
    JAVA_CMD="${JAVA_CMD} --assets ${ASSET_PACK}"
fi

# Add accept-early-plugins flag if variable is set
if [ "${ACCEPT_EARLY_PLUGINS}" = "1" ]; then
    JAVA_CMD="${JAVA_CMD} --accept-early-plugins"
fi

# Add allow-op flag if variable is set
if [ "${ALLOW_OP}" = "1" ]; then
    JAVA_CMD="${JAVA_CMD} --allow-op"
fi

# Add disable-sentry flag if enabled
if [ "${DISABLE_SENTRY}" = "1" ]; then
    JAVA_CMD="${JAVA_CMD} --disable-sentry"
fi

# Add backup parameters if enabled
if [ "${ENABLE_BACKUPS}" = "1" ]; then
    JAVA_CMD="${JAVA_CMD} --backup --backup-dir ${BACKUP_DIR_PATH} --backup-frequency ${BACKUP_FREQUENCY}"
fi

# Add session tokens and owner UUID
if [ ! -z "${SESSION_TOKEN}" ] && [ ! -z "${IDENTITY_TOKEN}" ] && [ ! -z "${PROFILE_UUID}" ]; then
JAVA_CMD="${JAVA_CMD} --session-token ${SESSION_TOKEN}"
JAVA_CMD="${JAVA_CMD} --identity-token ${IDENTITY_TOKEN}"
JAVA_CMD="${JAVA_CMD} --owner-uuid ${PROFILE_UUID}"
fi

# Add bind address
JAVA_CMD="${JAVA_CMD} --bind 0.0.0.0:${SERVER_PORT:-5520}"

# Execute the command
exec $JAVA_CMD