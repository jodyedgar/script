#!/bin/bash
# quote-fetch-ticket.sh - Read-only ticket fetch for quote analysis (Firestore-backed)
# Does NOT change ticket status - just retrieves title and description
#
# Usage: ./quote-fetch-ticket.sh TICK-###
# Output: JSON with ticket title and description

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_firestore-lib.sh"

if [ -z "$1" ]; then
    echo '{"error": "no_ticket_id"}'
    exit 1
fi

TICKET_INPUT="$1"
TICKET_ID=$(echo "$TICKET_INPUT" | tr '[:lower:]' '[:upper:]')

# Query Firestore
QUERY_RESULT=$(query_ticket "$TICKET_ID")

DOC_NAME=$(echo "$QUERY_RESULT" | jq -r '.[0].document.name // empty')

if [ -z "$DOC_NAME" ]; then
    echo "{\"ticket\": \"$TICKET_ID\", \"error\": \"not_found\"}"
    exit 0
fi

# Extract fields
TITLE=$(fs_string "$QUERY_RESULT" "name")
STATUS=$(fs_string "$QUERY_RESULT" "status")
TYPE=$(fs_string "$QUERY_RESULT" "ticketComplexity")
CONTENT=$(fs_string "$QUERY_RESULT" "content")

# Truncate description to 1000 chars
DESCRIPTION=$(echo "$CONTENT" | head -c 1000)

# Output JSON
jq -n \
    --arg ticket "$TICKET_ID" \
    --arg title "$TITLE" \
    --arg status "$STATUS" \
    --arg type "$TYPE" \
    --arg description "$DESCRIPTION" \
    '{ticket: $ticket, title: $title, status: $status, type: $type, description: $description}'
