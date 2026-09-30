#!/bin/bash

# Find the directory where this script is located
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

if [ -f "$DIR/.env" ]; then
    set -a
    source "$DIR/.env"
    set +a
fi

# Map the master key from your .env file to what the PHP script expects
export LITELLM_API_KEY="${LITELLM_API_KEY}"
export LITELLM_API_BASE="${LITELLM_API_BASE}"
export LITELLM_MODEL="${LITELLM_MODEL}"

# --- FILE IMPORT LOGIC ADDED HERE ---
# Verify required text files exist before executing
for FILE in data/system.txt data/user.txt data/data.txt; do
    if [ ! -f "$DIR/$FILE" ]; then
        echo " Error: Required file missing -> $DIR/$FILE" >&2
        exit 1
    fi
done

# Read file contents into environment variables
export LITELLM_SYSTEM="$(cat "$DIR/data/system.txt")"
export LITELLM_USER_PROMPT="$(cat "$DIR/data/user.txt")"
export LITELLM_DATA_CONTENT="$(cat "$DIR/data/data.txt")"
# ------------------------------------

# Execute the PHP script, passing all arguments along
php "$DIR/agent.php"
