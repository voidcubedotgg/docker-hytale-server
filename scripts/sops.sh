SOPS_AGE_KEY=${SOPS_AGE_KEY:-""}
SOPS_AGE_RECIPIENT=${SOPS_AGE_RECIPIENT:-""}
SOPS_ENABLED=${SOPS_ENABLED:-0}
SOPS_CMD=${SOPS_CMD:-"sops"}

export SOPS_AGE_KEY

if [[ -n "$SOPS_AGE_KEY" && -n "$SOPS_AGE_RECIPIENT" ]]; then
    SOPS_ENABLED=1
fi

# Encrypt file using AGE encryption
sops_encrypt_file() {
    file=$1
    if [[ $SOPS_ENABLED == 1 && -n $file && -f /data/${file} ]]; then
        if [ -z "$SOPS_AGE_RECIPIENT" ]; then
            echo "✗ SOPS_AGE_RECIPIENT (age public key) not set, cannot encrypt $file" >&2
            return 1
        fi
        if $SOPS_CMD filestatus "/data/${file}" | grep -q '"encrypted":true'; then
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
    file=$1
    if [[ $SOPS_ENABLED == 1 && -n $file && -f /data/${file} ]]; then
        if ! $SOPS_CMD filestatus "/data/${file}" | grep -q '"encrypted":true'; then
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