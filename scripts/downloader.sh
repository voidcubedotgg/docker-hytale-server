# shellcheck shell=bash
DOWNLOADER_AUTH_CACHE_FILE=${DOWNLOADER_AUTH_CACHE_FILE:-".hytale-downloader-credentials.json"}
DOWNLOADER_GAME_VERSION_CACHE_FILE=${DOWNLOADER_GAME_VERSION_CACHE_FILE:-".game_version"}
DOWNLOADER_ENABLED=${DOWNLOADER_ENABLED:-"1"}
DOWNLOADER_CMD=${DOWNLOADER_CMD:-"hytale-downloader"}

# Check for updates
downloader_check_for_updates() {
    if [ ! -f "$DOWNLOADER_AUTH_CACHE_FILE" ]; then
        log_info "Downloader authentication file not found."
        return 0
    fi

    if [ ! -f "$DOWNLOADER_GAME_VERSION_CACHE_FILE" ]; then
        log_info "Game version file not found."
        return 0
    fi

    GAME_VERSION=$($DOWNLOADER_CMD -print-version)
    if [ "$(cat "$DOWNLOADER_GAME_VERSION_CACHE_FILE")" != "$GAME_VERSION" ]; then
        log_info "Game version is outdated!"
        return 0
    fi

    log_info "Game version is up to date"
    return 1
}

# Save current release version into file
downloader_save_game_version() {
   GAME_VERSION=$($DOWNLOADER_CMD -print-version)
   echo "$GAME_VERSION" > "$DOWNLOADER_GAME_VERSION_CACHE_FILE"
   log_info "Game version saved successfully!"
}

# Get Hytale files from CDN
downloader_download_files() {
    if [ "$DOWNLOADER_ENABLED" == "1" ]; then
        rm -f server.zip
        log_info "Starting Hytale downloader..."
        $DOWNLOADER_CMD -download-path server.zip
    fi
}

# Function to extract downloaded server files
downloader_extract_server_files() {
    log_info "Extracting server files..."
    SERVER_ZIP="server.zip"

    if [ -f "$SERVER_ZIP" ]; then
        log_info "Found server archive: $SERVER_ZIP"

        # Extract to current directory
        if ! unzip -o "$SERVER_ZIP"; then
            log_die "Failed to extract $SERVER_ZIP"
        fi

        log_info "Extraction completed successfully."

        # Move contents from Server folder to current directory
        if [ -d "Server" ]; then
            log_info "Moving server files from Server directory..."
            cp -r Server/* .
            rm -r Server
            log_info "Server files moved to root directory."
        fi

        # Clean up the zip file
        log_info "Cleaning up archive file..."
        rm "$SERVER_ZIP"
        log_info "Archive removed."
    else
        log_die "Server archive not found at $SERVER_ZIP"
    fi
}