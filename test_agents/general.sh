#!/bin/bash

# Find the directory where this script is located
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

if [ -f "$DIR/.env" ]; then
    # Export variables, ignoring comments
    export $(grep -v '^#' "$DIR/.env" | xargs)
fi

# Fallback defaults if not set in .env or environment
export LITELLM_API_KEY="${LITELLM_API_KEY:-${LITELLM_MASTER_KEY}}"
export LITELLM_API_BASE="${LITELLM_API_BASE:-http://localhost:4000/v1}"
export LITELLM_MODEL="${LITELLM_MODEL:-general-ai}"

# Execute the PHP script, passing all arguments along
php "$DIR/agent.php" "$@"
