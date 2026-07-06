# shellcheck shell=bash
HYTALE_SERVER_SESSION_TOKEN=${HYTALE_SERVER_SESSION_TOKEN:-""}
HYTALE_SERVER_IDENTITY_TOKEN=${HYTALE_SERVER_IDENTITY_TOKEN:-""}
HYTALE_AUTH_CACHE_FILE=${HYTALE_AUTH_CACHE_FILE:-".hytale-auth-tokens.json"}
HYTALE_AUTH_ENABLED=${HYTALE_AUTH_ENABLED-:-"1"}

if [[ -n "${HYTALE_SERVER_SESSION_TOKEN}" && -n "${HYTALE_SERVER_IDENTITY_TOKEN}" ]]; then
    HYTALE_AUTH_ENABLED=0
fi

hytale_auth_enabled() {
    if [ "$HYTALE_AUTH_ENABLED" == "0" ]; then
        return 1
    fi
    return 0
}

# Function to check if cached tokens exist
hytale_auth_check_cached_tokens() {
    if [ -f "$HYTALE_AUTH_CACHE_FILE" ]; then
        # Validate JSON format
        if ! jq empty "$HYTALE_AUTH_CACHE_FILE" 2>/dev/null; then
            log_warn "Invalid cached token file, removing..."
            rm "$HYTALE_AUTH_CACHE_FILE"
            return 1
        fi
        log_info "Found cached authentication tokens"
        return 0
    fi
    return 1
}


# Function to load cached tokens
hytale_auth_load_cached_tokens() {
    sops_decrypt_file "$HYTALE_AUTH_CACHE_FILE"
    ACCESS_TOKEN=$(jq -r '.access_token' "$HYTALE_AUTH_CACHE_FILE")
    REFRESH_TOKEN=$(jq -r '.refresh_token' "$HYTALE_AUTH_CACHE_FILE")
    PROFILE_UUID=$(jq -r '.profile_uuid' "$HYTALE_AUTH_CACHE_FILE")
    
    # Validate all required tokens are present
    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ] || \
       [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
        log_error "Incomplete cached tokens, re-authenticating..."
        rm "$HYTALE_AUTH_CACHE_FILE"
        return 1
    fi

    log_info "Loaded cached authentication tokens"
    return 0
}

# Function to save authentication tokens
hytale_auth_save_tokens() {
    cat > "$HYTALE_AUTH_CACHE_FILE" << EOF
{
  "access_token": "$ACCESS_TOKEN",
  "refresh_token": "$REFRESH_TOKEN",
  "profile_uuid": "$PROFILE_UUID",
  "timestamp": $(date +%s)
}
EOF
    sops_encrypt_file "$HYTALE_AUTH_CACHE_FILE"
    log_info "Authentication tokens cached for future use"
}

hytale_auth_refresh_authentication() {
    if is_jwt_token_expired "$ACCESS_TOKEN"; then
        log_info "Refreshing Access Token"
       TOKEN_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=hytale-server" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=$REFRESH_TOKEN")

        ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r ".access_token")
        REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r ".refresh_token")

        log_info "Access token refreshed successfully!"
    fi

    hytale_auth_save_tokens
}

hytale_auth_create_game_session() {
    log_info "Creating Game session"
    SESSION_RESPONSE=$(curl -s -X POST "https://sessions.hytale.com/game-session/new" \
       -H "Authorization: Bearer $ACCESS_TOKEN" \
       -H "Content-Type: application/json" \
       -d "{\"uuid\": \"${PROFILE_UUID}\"}")
    
    # Validate JSON response
    if ! echo "$SESSION_RESPONSE" | jq empty 2>/dev/null; then
        log_error "Invalid JSON response from game session refresh"
        log_error "Response: $SESSION_RESPONSE"
    fi
    # Extract session and identity tokens
    SESSION_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.sessionToken')
    IDENTITY_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.identityToken')
    if [ -z "$SESSION_TOKEN" ] || [ "$SESSION_TOKEN" = "null" ] || [ -z "$IDENTITY_TOKEN" ] || [ "$IDENTITY_TOKEN" == "null" ]; then
        log_error "Failed to refresh game server session"
        log_error "Response: $SESSION_RESPONSE"
        exit 1
    fi
    log_info "Game session created successfully!"
}

# Function to perform full device flow authentication
hytale_auth_perform_device_flow() {
    log_info "Obtaining authentication tokens..."

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
        sleep "$POLL_INTERVAL"

        TOKEN_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "client_id=hytale-server" \
          -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
          -d "device_code=$DEVICE_CODE")

        # Check if we got an error
        ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')

        if [ "$ERROR" = "authorization_pending" ]; then
            log_info "Still waiting for authentication..."
            continue
        elif [ -n "$ERROR" ]; then
            log_die "Authentication error: $ERROR"
        else
            # Successfully authenticated
            ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
            REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')
            log_info "Authentication successful!"
        fi
    done

    # Fetch available game profiles
    log_info "Fetching game profiles..."

    PROFILES_RESPONSE=$(curl -s -X GET "https://account-data.hytale.com/my-account/get-profiles" \
      -H "Authorization: Bearer $ACCESS_TOKEN")

    # Check if profiles list is empty
    PROFILES_COUNT=$(echo "$PROFILES_RESPONSE" | jq '.profiles | length')

    if [ "$PROFILES_COUNT" -eq 0 ]; then
        log_die "No game profiles found. You need to purchase Hytale to run a server."
    fi

    # Select profile based on GAME_PROFILE variable
    if [ -n "$GAME_PROFILE" ]; then
        # User specified a profile username, find matching UUID
        log_info "Looking for profile: $GAME_PROFILE"
        PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | jq -r ".profiles[] | select(.username == \"$GAME_PROFILE\") | .uuid")

        if [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
            log_error "Profile '$GAME_PROFILE' not found."
            log_error "Available profiles:"
            echo "$PROFILES_RESPONSE" | jq -r '.profiles[] | "  - \(.username)"' >&2
            exit 1
        fi

        log_info "Using profile: $GAME_PROFILE (UUID: $PROFILE_UUID)"
    else
        # Use first profile from the list
        PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].uuid')
        PROFILE_USERNAME=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].username')

        log_info "Using default profile: $PROFILE_USERNAME (UUID: $PROFILE_UUID)"
    fi

    # Save tokens for future use
    hytale_auth_save_tokens
}