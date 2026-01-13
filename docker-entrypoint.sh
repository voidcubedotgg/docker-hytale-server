#!/bin/sh

DOWNLOADER="hytale-downloader"
AUTH_CACHE_FILE=".hytale-auth-tokens.json"
ASSET_PACK="Assets.zip"

# Function to extract downloaded server files
extract_server_files() {
    echo "Extracting server files..."
    SERVER_ZIP="server.zip"

    if [ -f "$SERVER_ZIP" ]; then
        echo "Found server archive: $SERVER_ZIP"

        # Extract to current directory
        unzip -o "$SERVER_ZIP"

        if [ $? -ne 0 ]; then
            echo "Error: Failed to extract $SERVER_ZIP"
            exit 1
        fi

        echo "Extraction completed successfully."

        # Move contents from Server folder to current directory
        if [ -d "Server" ]; then
            echo "Moving server files from Server directory..."
            mv Server/* .
            rmdir Server
            echo "✓ Server files moved to root directory."
        fi

        # Clean up the zip file
        echo "Cleaning up archive file..."
        rm "$SERVER_ZIP"
        echo "✓ Archive removed."
    else
        echo "Error: Server archive not found at $SERVER_ZIP"
        exit 1
    fi
}

# Function to check if cached tokens exist
check_cached_tokens() {
    if [ -f "$AUTH_CACHE_FILE" ]; then
        # Check if jq is available
        if ! command -v jq &> /dev/null; then
            echo "Warning: jq not found, cannot use cached tokens"
            return 1
        fi

        # Validate JSON format
        if ! jq empty "$AUTH_CACHE_FILE" 2>/dev/null; then
            echo "Warning: Invalid cached token file, removing..."
            rm "$AUTH_CACHE_FILE"
            return 1
        fi

        echo "✓ Found cached authentication tokens"
        return 0
    fi
    return 1
}

# Function to load cached tokens
load_cached_tokens() {
    ACCESS_TOKEN=$(jq -r '.access_token' "$AUTH_CACHE_FILE")
    SESSION_TOKEN=$(jq -r '.session_token' "$AUTH_CACHE_FILE")
    IDENTITY_TOKEN=$(jq -r '.identity_token' "$AUTH_CACHE_FILE")
    PROFILE_UUID=$(jq -r '.profile_uuid' "$AUTH_CACHE_FILE")
    
    # Validate all required tokens are present
    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ] || \
       [ -z "$SESSION_TOKEN" ] || [ "$SESSION_TOKEN" = "null" ] || \
       [ -z "$IDENTITY_TOKEN" ] || [ "$IDENTITY_TOKEN" = "null" ] || \
       [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
        echo "Error: Incomplete cached tokens, re-authenticating..."
        rm "$AUTH_CACHE_FILE"
        return 1
    fi
    
    echo "✓ Loaded cached authentication tokens"
    return 0
}

# Function to save authentication tokens
save_auth_tokens() {
    cat > "$AUTH_CACHE_FILE" << EOF
{
  "access_token": "$ACCESS_TOKEN",
  "session_token": "$SESSION_TOKEN",
  "identity_token": "$IDENTITY_TOKEN",
  "profile_uuid": "$PROFILE_UUID",
  "timestamp": $(date +%s)
}
EOF
    echo "✓ Authentication tokens cached for future use"
}

# Function to perform full authentication
perform_authentication() {
    echo "Obtaining authentication tokens..."

    # Step 1: Request device code
    AUTH_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/device/auth" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "client_id=hytale-server" \
      -d "scope=openid offline auth:server")

    # Extract device_code and verification_uri_complete using jq
    DEVICE_CODE=$(echo "$AUTH_RESPONSE" | jq -r '.device_code')
    VERIFICATION_URI=$(echo "$AUTH_RESPONSE" | jq -r '.verification_uri_complete')
    POLL_INTERVAL=$(echo "$AUTH_RESPONSE" | jq -r '.interval')

    # Display authentication banner
    echo ""
    echo "╔═════════════════════════════════════════════════════════════════════════════╗"
    echo "║                       HYTALE SERVER AUTHENTICATION REQUIRED                 ║"
    echo "╠═════════════════════════════════════════════════════════════════════════════╣"
    echo "║                                                                             ║"
    echo "║  Please authenticate the server by visiting the following URL:              ║"
    echo "║                                                                             ║"
    echo "║  $VERIFICATION_URI  ║"
    echo "║                                                                             ║"
    echo "║  1. Click the link above or copy it to your browser                         ║"
    echo "║  2. Sign in with your Hytale account                                        ║"
    echo "║  3. Authorize the server                                                    ║"
    echo "║                                                                             ║"
    echo "║  Waiting for authentication...                                              ║"
    echo "║                                                                             ║"
    echo "╚═════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Step 2: Poll for access token
    ACCESS_TOKEN=""
    while [ -z "$ACCESS_TOKEN" ]; do
        sleep $POLL_INTERVAL

        TOKEN_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "client_id=hytale-server" \
          -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
          -d "device_code=$DEVICE_CODE")

        # Check if we got an error
        ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')

        if [ "$ERROR" = "authorization_pending" ]; then
            echo "Still waiting for authentication..."
            continue
        elif [ -n "$ERROR" ]; then
            echo "Authentication error: $ERROR"
            exit 1
        else
            # Successfully authenticated
            ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
            echo ""
            echo "✓ Authentication successful!"
            echo ""
        fi
    done

    # Fetch available game profiles
    echo "Fetching game profiles..."

    PROFILES_RESPONSE=$(curl -s -X GET "https://account-data.hytale.com/my-account/get-profiles" \
      -H "Authorization: Bearer $ACCESS_TOKEN")

    # Check if profiles list is empty
    PROFILES_COUNT=$(echo "$PROFILES_RESPONSE" | jq '.profiles | length')

    if [ "$PROFILES_COUNT" -eq 0 ]; then
        echo "Error: No game profiles found. You need to purchase Hytale to run a server."
        exit 1
    fi

    # Select profile based on GAME_PROFILE variable
    if [ -n "$GAME_PROFILE" ]; then
        # User specified a profile username, find matching UUID
        echo "Looking for profile: $GAME_PROFILE"
        PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | jq -r ".profiles[] | select(.username == \"$GAME_PROFILE\") | .uuid")

        if [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
            echo "Error: Profile '$GAME_PROFILE' not found."
            echo "Available profiles:"
            echo "$PROFILES_RESPONSE" | jq -r '.profiles[] | "  - \(.username)"'
            exit 1
        fi

        echo "✓ Using profile: $GAME_PROFILE (UUID: $PROFILE_UUID)"
    else
        # Use first profile from the list
        PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].uuid')
        PROFILE_USERNAME=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].username')

        echo "✓ Using default profile: $PROFILE_USERNAME (UUID: $PROFILE_UUID)"
    fi

    echo ""

    # Create game server session
    echo "Creating game server session..."

    SESSION_RESPONSE=$(curl -s -X POST "https://sessions.hytale.com/game-session/new" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"uuid\": \"${PROFILE_UUID}\"}")

    # Validate JSON response
    if ! echo "$SESSION_RESPONSE" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON response from game session creation"
        echo "Response: $SESSION_RESPONSE"
        exit 1
    fi

    # Extract session and identity tokens
    SESSION_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.sessionToken')
    IDENTITY_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.identityToken')

    if [ -z "$SESSION_TOKEN" ] || [ "$SESSION_TOKEN" = "null" ]; then
        echo "Error: Failed to create game server session"
        echo "Response: $SESSION_RESPONSE"
        exit 1
    fi

    echo "✓ Game server session created successfully!"
    echo ""
    
    # Save tokens for future use
    save_auth_tokens
}

# Check if credentials file exists, if not run the updater
if [ ! -f ".hytale-downloader-credentials.json" ]; then
    echo "Credentials file not found, running initial setup..."
    echo "Starting Hytale downloader..."
    $DOWNLOADER -download-path server.zip
    extract_server_files
fi



 Check if server files were downloaded correctly
if [ ! -f "HytaleServer.jar" ]; then
    echo "Error: HytaleServer.jar not found!"
    echo "Server files were not downloaded correctly."
    echo "Starting Hytale downloader..."
    $DOWNLOADER -download-path server.zip
    extract_server_files
fi

# Check for cached authentication tokens
if check_cached_tokens && load_cached_tokens; then
    echo "Using cached authentication - skipping login prompt"
else
    # Perform full authentication if no valid cache exists
    perform_authentication
fi

echo "Starting Hytale server..."

export HYTALE_SERVER_SESSION_TOKEN=${SESSION_TOKEN}
export HYTALE_SERVER_IDENTITY_TOKEN=${IDENTITY_TOKEN}

# Build the Java command
JAVA_CMD="java"

# Add AOT cache if enabled
if [ "${LEVERAGE_AHEAD_OF_TIME_CACHE}" = "1" ]; then
    JAVA_CMD="${JAVA_CMD} -XX:AOTCache=HytaleServer.aot"
fi

# Add max memory if set and greater than 0
if [ -n "${SERVER_MEMORY}" ] && [ "${SERVER_MEMORY}" -gt 0 ] 2>/dev/null; then
    JAVA_CMD="${JAVA_CMD} -Xms${SERVER_MEMORY}M -Xmx${SERVER_MEMORY}M"
fi

# Add JVM arguments if set
if [ -n "${JVM_ARGS}" ]; then
    JAVA_CMD="${JAVA_CMD} ${JVM_ARGS}"
fi

JAVA_CMD="${JAVA_CMD} -jar HytaleServer.jar"

# Add assets parameter if set and ends with .zip
if [ -n "${ASSET_PACK}" ] && [[ "${ASSET_PACK}" == *.zip ]]; then
    JAVA_CMD="${JAVA_CMD} --assets ${ASSET_PACK}"
fi

# Add accept-early-plugins flag if variable is set
if [ "${ACCEPT_EARLY_PLUGINS}" = "1" ]; then
    JAVA_CMD="${JAVA_CMD} --accept-early-plugins"
fi

#JAVA_CMD="${JAVA_CMD} --auth-mode ${AUTH_MODE}"

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
    JAVA_CMD="${JAVA_CMD} --backup --backup-dir ./backup --backup-frequency ${BACKUP_FREQUENCY}"
fi

# Add session tokens and owner UUID
#JAVA_CMD="${JAVA_CMD} --session-token ${SESSION_TOKEN}"
#JAVA_CMD="${JAVA_CMD} --identity-token ${IDENTITY_TOKEN}"
#JAVA_CMD="${JAVA_CMD} --owner-uuid ${PROFILE_UUID}"

# Add bind address
JAVA_CMD="${JAVA_CMD} --bind '0.0.0.0:${SERVER_PORT:-5520}'"

echo $JAVA_CMD

# Execute the command
eval $JAVA_CMD