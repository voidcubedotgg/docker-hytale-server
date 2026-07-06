# shellcheck shell=bash
# Decode base64 url
base64url_decode() {
  local b64="$1"
  while (( ${#b64} % 4 != 0 )); do b64+="="; done
  echo "$b64" | tr '_-' '/+' | base64 -d 2>/dev/null
}

# Validate is JWT token expired
is_jwt_token_expired() {
    local token="$1"

    if [ -z "$token" ]; then
        log_error "Cannot validate token expiry. Token not provided."
        return 0
    fi

    local payload
    IFS='.' read -r _ payload _ <<< "$token"

    local payload_json exp now
    payload_json=$(base64url_decode "$payload")
    exp=$(echo "$payload_json" | jq -r '.exp // empty')

    if ! [[ "$exp" =~ ^[0-9]+$ ]]; then
        log_warn "Token has no valid exp claim, treating as expired."
        return 0
    fi

    now=$(date +%s)
    if [ "$((now + 5*60))" -lt "$exp" ]; then
        return 1    # valid
    else
        return 0    # expired
    fi
}