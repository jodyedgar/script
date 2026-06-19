#!/bin/bash
# Ticket fetch with directory lookup (Firestore-backed)
# Usage: ./ticket-navigate.sh TICK-###

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_firestore-lib.sh"

CLIENT_MAP="$HOME/.client-map"

if [ -z "$1" ]; then
    echo -e "${RED}Usage: $0 TICKET-ID${NC}"
    echo "Example: $0 TICK-940"
    exit 1
fi

TICKET_ID=$(echo "$1" | tr '[:lower:]' '[:upper:]')

echo -e "${BLUE}Fetching ticket: $TICKET_ID${NC}"

# Query Firestore
QUERY_RESULT=$(query_ticket "$TICKET_ID")

DOC_NAME=$(echo "$QUERY_RESULT" | jq -r '.[0].document.name // empty')

if [ -z "$DOC_NAME" ]; then
    echo -e "${RED}Ticket not found: $TICKET_ID${NC}"
    exit 1
fi

# Extract title and client info
TITLE=$(fs_string "$QUERY_RESULT" "name")
CLIENT_ID=$(fs_string "$QUERY_RESULT" "clientId")
CLIENT_NAME=$(fs_string "$QUERY_RESULT" "clientName")

echo -e "${GREEN}Found ticket:${NC} $TITLE"

if [ -z "$CLIENT_ID" ]; then
    echo -e "${YELLOW}No client assigned to ticket${NC}"
    exit 0
fi

# Get client details from Firestore for Slack channel
echo -e "${BLUE}Fetching client details...${NC}"
CLIENT_DOC=$(get_client_by_id "$CLIENT_ID")
SLACK_CHANNEL=$(echo "$CLIENT_DOC" | jq -r '.fields.slackChannel.stringValue // empty')

# Fall back to client name if no slack channel
if [ -z "$SLACK_CHANNEL" ]; then
    SLACK_CHANNEL="$CLIENT_NAME"
fi

if [ -z "$SLACK_CHANNEL" ]; then
    echo -e "${YELLOW}No slack channel found for client${NC}"
    exit 0
fi

# Strip # symbol if present
SLACK_CHANNEL=$(echo "$SLACK_CHANNEL" | sed 's/^#//')

echo -e "${BLUE}Slack channel:${NC} #$SLACK_CHANNEL"

# Look up directory in client map
if [ ! -f "$CLIENT_MAP" ]; then
    echo -e "${RED}Error: Client map not found at $CLIENT_MAP${NC}"
    exit 1
fi

# Find matching directory (ignore comment lines)
TARGET_DIR=$(grep "^$SLACK_CHANNEL=" "$CLIENT_MAP" | cut -d'=' -f2)

if [ -z "$TARGET_DIR" ]; then
    echo -e "${YELLOW}Channel '$SLACK_CHANNEL' not in client map${NC}"
    echo ""
    echo "Add to ~/.client-map:"
    echo "$SLACK_CHANNEL=~/Dropbox/wwwroot/DOMAIN/path"
    exit 1
fi

# Check if needs setup
if [ "$TARGET_DIR" = "NEEDS_SETUP" ]; then
    echo -e "${YELLOW}Directory not configured for $SLACK_CHANNEL${NC}"
    echo ""
    read -p "Enter full path to store directory: " NEW_PATH
    # Update client map
    sed -i.bak "s|$SLACK_CHANNEL=NEEDS_SETUP|$SLACK_CHANNEL=$NEW_PATH|" "$CLIENT_MAP"
    echo -e "${GREEN}Updated client map${NC}"
    TARGET_DIR="$NEW_PATH"
fi

# Expand tilde
TARGET_DIR="${TARGET_DIR/#\~/$HOME}"

# Verify directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}Error: Directory doesn't exist: $TARGET_DIR${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Ready to work on $TICKET_ID${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Copy and run this command:${NC}"
echo ""
echo "cd $TARGET_DIR && git checkout -b fix-$TICKET_ID && claude"
echo ""
