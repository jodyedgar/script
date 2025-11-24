#!/bin/bash
# Enhanced Notion ticket fetch with directory lookup
# Usage: ./fetch-and-navigate.sh TICK-###

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"
CLIENT_MAP="$HOME/.client-map"

if [ -z "$1" ]; then
    echo -e "${RED}Usage: $0 TICKET-ID${NC}"
    echo "Example: $0 TICK-940"
    exit 1
fi

TICKET_ID="$1"
TICKET_NUMBER=$(echo "$TICKET_ID" | sed -E 's/[Tt][Ii][Cc][Kk]-//')

# Check for API key
if [ -z "$NOTION_API_KEY" ]; then
    if [ -f "$HOME/.bash_profile" ]; then
        source "$HOME/.bash_profile"
    fi
    if [ -z "$NOTION_API_KEY" ]; then
        echo -e "${RED}Error: NOTION_API_KEY not set${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}Fetching ticket: $TICKET_ID${NC}"

# Fetch ticket from Notion
TICKET_RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d "{
    \"filter\": {
      \"property\": \"ID\",
      \"unique_id\": {
        \"equals\": $TICKET_NUMBER
      }
    }
  }")

# Check if ticket found
RESULTS_COUNT=$(echo "$TICKET_RESPONSE" | jq -r '.results | length')
if [ "$RESULTS_COUNT" -eq 0 ]; then
    echo -e "${RED}Ticket not found: $TICKET_ID${NC}"
    exit 1
fi

# Extract title and client relation
TITLE=$(echo "$TICKET_RESPONSE" | jq -r '.results[0].properties.Name.title[0].plain_text // "No title"')
CLIENT_ID=$(echo "$TICKET_RESPONSE" | jq -r '.results[0].properties.Client.relation[0].id // empty')

echo -e "${GREEN}✓ Found ticket:${NC} $TITLE"

if [ -z "$CLIENT_ID" ]; then
    echo -e "${YELLOW}⚠ No client assigned to ticket${NC}"
    exit 0
fi

# Fetch client page to get slack channel name
echo -e "${BLUE}Fetching client details...${NC}"
CLIENT_RESPONSE=$(curl -s -X GET "https://api.notion.com/v1/pages/$CLIENT_ID" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28")

SLACK_CHANNEL=$(echo "$CLIENT_RESPONSE" | jq -r '.properties.Name.title[0].plain_text // empty')

if [ -z "$SLACK_CHANNEL" ]; then
    echo -e "${YELLOW}⚠ No slack channel found for client${NC}"
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
    echo -e "${YELLOW}⚠ Channel '$SLACK_CHANNEL' not in client map${NC}"
    echo ""
    echo "Add to ~/.client-map:"
    echo "$SLACK_CHANNEL=~/Dropbox/wwwroot/DOMAIN/path"
    exit 1
fi

# Check if needs setup
if [ "$TARGET_DIR" = "NEEDS_SETUP" ]; then
    echo -e "${YELLOW}⚠ Directory not configured for $SLACK_CHANNEL${NC}"
    echo ""
    read -p "Enter full path to store directory: " NEW_PATH
    # Update client map
    sed -i.bak "s|$SLACK_CHANNEL=NEEDS_SETUP|$SLACK_CHANNEL=$NEW_PATH|" "$CLIENT_MAP"
    echo -e "${GREEN}✓ Updated client map${NC}"
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
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Ready to work on $TICKET_ID${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Copy and run this command:${NC}"
echo ""
echo "cd $TARGET_DIR && git checkout -b fix-$TICKET_ID && claude"
echo ""
