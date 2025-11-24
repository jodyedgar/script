#!/bin/bash

# Update Ticket Credits in Notion
# Updates Credits Min and Credits Max fields for tickets
# Usage: ./update-ticket-credits.sh START_NUM END_NUM
# Example: ./update-ticket-credits.sh 975 1001

set -e

# Notion API Configuration
TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

# Check if NOTION_API_KEY is set
if [ -z "$NOTION_API_KEY" ]; then
    echo "Error: NOTION_API_KEY environment variable is not set"
    echo "Set it with: export NOTION_API_KEY='your-api-key'"
    exit 1
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check arguments
if [ "$#" -ne 2 ]; then
    echo -e "${RED}Usage: $0 START_NUM END_NUM${NC}"
    echo "Example: $0 975 1001"
    exit 1
fi

START=$1
END=$2

# Validate numbers
if ! [[ "$START" =~ ^[0-9]+$ ]] || ! [[ "$END" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: START and END must be numbers${NC}"
    exit 1
fi

if [ "$START" -gt "$END" ]; then
    echo -e "${RED}Error: START must be less than or equal to END${NC}"
    exit 1
fi

# Credit mapping
# Max credits (from original system)
QUICK_MAX=1
SMALL_MAX=2
MEDIUM_MAX=4
LARGE_MAX=5

# Min credits (new requirements)
QUICK_MIN=1
SMALL_MIN=1
MEDIUM_MIN=2
LARGE_MIN=3

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           UPDATE TICKET CREDITS IN NOTION                  ║${NC}"
echo -e "${CYAN}║                  TICK-$START to TICK-$END                        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to determine complexity from title
determine_complexity() {
    local TITLE="$1"

    # Quick fixes (simple text/icon changes)
    if [[ "$TITLE" =~ (get rid of|remove|should be|change.*to) ]] && [[ ! "$TITLE" =~ (page|template|incorrect header) ]]; then
        echo "QUICK"
    # Small tasks (CSS/spacing/font fixes)
    elif [[ "$TITLE" =~ (spacing|white space|font|color|breadcrumb|disappears) ]]; then
        echo "SMALL"
    # Large tasks (pages, templates, major features)
    elif [[ "$TITLE" =~ (page not done|Search feature|incorrect header.*template|account pages|renderings vs lifestyle) ]]; then
        echo "LARGE"
    # Medium tasks (everything else)
    else
        echo "MEDIUM"
    fi
}

# Function to update credits in Notion
update_credits_in_notion() {
    local TICKET_ID="$1"
    local PAGE_ID="$2"
    local MIN_CREDITS="$3"
    local MAX_CREDITS="$4"

    # Build the JSON payload
    local PAYLOAD=$(cat <<EOF
{
  "properties": {
    "Credits Min": {
      "number": $MIN_CREDITS
    },
    "Credits Max": {
      "number": $MAX_CREDITS
    }
  }
}
EOF
)

    # Update the page in Notion
    RESPONSE=$(curl -s -X PATCH "https://api.notion.com/v1/pages/$PAGE_ID" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Content-Type: application/json" \
        -H "Notion-Version: 2022-06-28" \
        -d "$PAYLOAD")

    # Check if update was successful
    if echo "$RESPONSE" | grep -q '"object":"page"'; then
        return 0
    else
        echo "$RESPONSE" >&2
        return 1
    fi
}

# Function to get page ID for a ticket
get_page_id() {
    local TICKET_ID="$1"
    local TICKET_NUM="${TICKET_ID#TICK-}"

    # Search for the ticket in Notion
    local SEARCH_PAYLOAD=$(cat <<EOF
{
  "filter": {
    "property": "Ticket Number",
    "number": {
      "equals": $TICKET_NUM
    }
  }
}
EOF
)

    RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$NOTION_DATABASE_ID/query" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Content-Type: application/json" \
        -H "Notion-Version: 2022-06-28" \
        -d "$SEARCH_PAYLOAD")

    # Extract page ID from response
    PAGE_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$PAGE_ID" ]; then
        return 1
    fi

    echo "$PAGE_ID"
    return 0
}

# Function to get ticket title
get_ticket_title() {
    local PAGE_ID="$1"

    RESPONSE=$(curl -s -X GET "https://api.notion.com/v1/pages/$PAGE_ID" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28")

    # Extract title - this is a simplified version, might need adjustment based on actual API response
    TITLE=$(echo "$RESPONSE" | grep -o '"Name":{[^}]*}' | grep -o '"plain_text":"[^"]*"' | head -1 | cut -d'"' -f4)

    echo "$TITLE"
}

# Process tickets
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

echo -e "${YELLOW}Processing tickets...${NC}\n"

for i in $(seq $START $END); do
    TICKET_ID="TICK-$i"

    echo -ne "${BLUE}Processing $TICKET_ID...${NC}"

    # Get page ID from fetch script output
    FETCH_OUTPUT=$(~/Dropbox/scripts/notion/fetch-notion-ticket.sh "$TICKET_ID" 2>&1)
    PAGE_ID=$(echo "$FETCH_OUTPUT" | grep "Found page ID:" | awk '{print $4}')

    if [ -z "$PAGE_ID" ]; then
        echo -e "\r${RED}✗ $TICKET_ID - Page not found${NC}"
        ((FAIL_COUNT++))
        continue
    fi

    # Get title
    TITLE=$(echo "$FETCH_OUTPUT" | grep "^Title:" | sed 's/^Title: //')

    # Check if completed
    STATUS=$(echo "$FETCH_OUTPUT" | grep "^Status:" | sed 's/^Status: //')

    if [[ "$STATUS" == "Complete" ]] || [[ "$STATUS" == "Done" ]]; then
        echo -e "\r${CYAN}○ $TICKET_ID - Skipped (completed)${NC}"
        ((SKIP_COUNT++))
        continue
    fi

    # Determine complexity
    COMPLEXITY=$(determine_complexity "$TITLE")

    # Set credits based on complexity
    case "$COMPLEXITY" in
        "QUICK")
            MIN_CREDITS=$QUICK_MIN
            MAX_CREDITS=$QUICK_MAX
            LABEL="⚡ Quick"
            ;;
        "SMALL")
            MIN_CREDITS=$SMALL_MIN
            MAX_CREDITS=$SMALL_MAX
            LABEL="🔧 Small"
            ;;
        "MEDIUM")
            MIN_CREDITS=$MEDIUM_MIN
            MAX_CREDITS=$MEDIUM_MAX
            LABEL="📄 Medium"
            ;;
        "LARGE")
            MIN_CREDITS=$LARGE_MIN
            MAX_CREDITS=$LARGE_MAX
            LABEL="🏗️ Large"
            ;;
    esac

    # Update credits in Notion
    if update_credits_in_notion "$TICKET_ID" "$PAGE_ID" "$MIN_CREDITS" "$MAX_CREDITS" 2>/dev/null; then
        echo -e "\r${GREEN}✓ $TICKET_ID - Updated to $MIN_CREDITS-$MAX_CREDITS credits ($LABEL)${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "\r${RED}✗ $TICKET_ID - Failed to update${NC}"
        ((FAIL_COUNT++))
    fi

    # Small delay to avoid rate limiting
    sleep 0.3
done

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                        SUMMARY                             ║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║${NC} ${GREEN}✓ Successfully updated: %-2d tickets                      ${NC}${CYAN}║${NC}\n" $SUCCESS_COUNT
printf "${CYAN}║${NC} ${CYAN}○ Skipped (completed):  %-2d tickets                      ${NC}${CYAN}║${NC}\n" $SKIP_COUNT
printf "${CYAN}║${NC} ${RED}✗ Failed:               %-2d tickets                      ${NC}${CYAN}║${NC}\n" $FAIL_COUNT
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo -e "${GREEN}✓ Credits updated successfully!${NC}"
fi

if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${YELLOW}⚠ Some tickets failed to update. Check the output above for details.${NC}"
fi
