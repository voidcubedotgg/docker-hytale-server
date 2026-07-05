SOPS_AGE_KEY=${SOPS_AGE_KEY:-""}
SOPS_AGE_RECIPIENT=${SOPS_AGE_RECIPIENT:-""}
SOPS_ENABLED=${SOPS_ENABLED:-""}
SOPS_CMD=${SOPS_CMD:-"sops"}

export SOPS_AGE_KEY

# Honor an explicit SOPS_ENABLED; otherwise auto-enable only when both keys present
if [ -z "$SOPS_ENABLED" ]; then
    if [[ -n "$SOPS_AGE_KEY" && -n "$SOPS_AGE_RECIPIENT" ]]; then
        SOPS_ENABLED=1
    else
        SOPS_ENABLED=0
    fi
fi

# Return 0 if the given /data file is sops-encrypted (whitespace-tolerant JSON parse)
sops_is_encrypted() {
    [ "$($SOPS_CMD filestatus "$1" | jq -r '.encrypted')" = "true" ]
}

# Encrypt file using AGE encryption
sops_encrypt_file() {
    local file="$1"
    if [[ $SOPS_ENABLED == 1 && -n $file && -f /data/${file} ]]; then
        if [ -z "$SOPS_AGE_RECIPIENT" ]; then
            echo "✗ SOPS_AGE_RECIPIENT (age public key) not set, cannot encrypt $file" >&2
            return 1
        fi
        if sops_is_encrypted "/data/${file}"; then
            echo "• File $file already encrypted, skipping"
        elif $SOPS_CMD encrypt --age "$SOPS_AGE_RECIPIENT" --in-place "/data/${file}"; then
            echo "✓ File $file encrypted"
        else
            echo "✗ Encrypt failed for $file" >&2
            return 1
        fi
    fi
}

# Decrypt file using AGE encryption
sops_decrypt_file() {
    local file="$1"
    if [[ $SOPS_ENABLED == 1 && -n $file && -f /data/${file} ]]; then
        if ! sops_is_encrypted "/data/${file}"; then
            echo "• File $file not encrypted, skipping"
        elif $SOPS_CMD decrypt --in-place "/data/${file}"; then
            echo "✓ File $file decrypted"
        else
            echo "✗ Decrypt failed for $file" >&2
            return 1
        fi
    fi
}

# Unset AGE key env vars before handing off to the server process
sops_unset_envs() {
    unset SOPS_AGE_RECIPIENT
    unset SOPS_AGE_KEY
}