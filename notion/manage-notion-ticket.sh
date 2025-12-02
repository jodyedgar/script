#!/bin/bash

# Unified script to manage Notion tickets
# Usage: ./manage-notion-ticket.sh TICK-ID [OPTIONS]
#
# Options:
#   --status, -s STATUS          Set ticket status (e.g., "In Review", "In Progress")
#   --pr-url, -p URL            Set GitHub PR URL
#   --theme-id, -t ID           Set Shopify Theme Preview ID
#   --summary, --notes, -n TEXT  Append summary/notes to ticket (supports markdown)
#   --qa-before                  Extract Feedbucket image → upload as QA Before
#   --qa-after                   Capture Chrome screenshot → upload as QA After
#   --qa-after-file FILE         Upload specific file as QA After
#
# Examples:
#   ./manage-notion-ticket.sh TICK-1166 --status "In Review" --summary "Fixed the issue"
#   ./manage-notion-ticket.sh TICK-1166 --pr-url https://github.com/org/repo/pull/123
#   ./manage-notion-ticket.sh TICK-1166 --status "In Progress" --notes "Working on feature X"
#   ./manage-notion-ticket.sh TICK-1166 --theme-id 181781889340
#   ./manage-notion-ticket.sh TICK-1166 --qa-before --qa-after
#   ./manage-notion-ticket.sh TICK-1166 --status "In Review" --qa-before --qa-after-file ./screenshot.png

# Tickets database ID
TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo "Usage: $0 TICKET-ID [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --status, -s STATUS          Set ticket status (e.g., 'In Review', 'In Progress')"
    echo "  --pr-url, -p URL            Set GitHub PR URL"
    echo "  --theme-id, -t ID           Set Shopify Theme Preview ID"
    echo "  --summary, --notes, -n TEXT  Append summary/notes to ticket (supports markdown)"
    echo ""
    echo "QA Screenshot Options:"
    echo "  --qa-before                  Extract Feedbucket image → upload as QA Before"
    echo "  --qa-after                   Capture Chrome screenshot → upload as QA After"
    echo "  --qa-after-file FILE         Upload specific file as QA After"
    echo ""
    echo "Examples:"
    echo "  $0 TICK-1166 --status Complete --summary 'Fixed the issue'"
    echo "  $0 TICK-1166 --pr-url https://github.com/org/repo/pull/123"
    echo "  $0 TICK-1166 --status 'In Progress'"
    echo "  $0 TICK-1166 --theme-id 181781889340"
    echo "  $0 TICK-1166 --status Complete --pr-url https://github.com/org/repo/pull/123 --summary 'Complete description'"
    echo "  $0 TICK-1166 --qa-before --qa-after"
    echo "  $0 TICK-1166 --status Complete --qa-before --qa-after-file ./screenshot.png"
    exit 1
}

# Check for help flag first
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
fi

# Check if ticket ID is provided
if [ -z "$1" ]; then
    show_usage
fi

TICKET_INPUT="$1"
shift

# Initialize variables
NEW_STATUS=""
PR_URL=""
THEME_ID=""
SUMMARY_TEXT=""
QA_BEFORE=false
QA_AFTER=false
QA_AFTER_FILE=""

# Script directory for finding record-qa.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECORD_QA_SCRIPT="$SCRIPT_DIR/record-qa.sh"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --status|-s)
            NEW_STATUS="$2"
            shift 2
            ;;
        --pr-url|-p)
            PR_URL="$2"
            shift 2
            ;;
        --theme-id|-t)
            THEME_ID="$2"
            shift 2
            ;;
        --summary|--notes|-n)
            SUMMARY_TEXT="$2"
            shift 2
            ;;
        --qa-before)
            QA_BEFORE=true
            shift
            ;;
        --qa-after)
            QA_AFTER=true
            shift
            ;;
        --qa-after-file)
            QA_AFTER_FILE="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            show_usage
            ;;
    esac
done

# Check if at least one action is specified
if [ -z "$NEW_STATUS" ] && [ -z "$PR_URL" ] && [ -z "$THEME_ID" ] && [ -z "$SUMMARY_TEXT" ] && [ "$QA_BEFORE" = false ] && [ "$QA_AFTER" = false ] && [ -z "$QA_AFTER_FILE" ]; then
    echo -e "${RED}Error: At least one option must be specified${NC}"
    show_usage
fi

# Validate QA script exists if QA options are used
if [ "$QA_BEFORE" = true ] || [ "$QA_AFTER" = true ] || [ -n "$QA_AFTER_FILE" ]; then
    if [ ! -x "$RECORD_QA_SCRIPT" ]; then
        echo -e "${RED}Error: record-qa.sh not found or not executable at $RECORD_QA_SCRIPT${NC}"
        exit 1
    fi
fi

# Check if NOTION_API_KEY is set, if not try to load from bash_profile
if [ -z "$NOTION_API_KEY" ]; then
    if [ -f "$HOME/.bash_profile" ]; then
        source "$HOME/.bash_profile"
    fi

    if [ -z "$NOTION_API_KEY" ]; then
        echo -e "${RED}Error: NOTION_API_KEY environment variable is not set${NC}"
        echo "Set it with: export NOTION_API_KEY='your-api-key'"
        exit 1
    fi
fi

# Determine if input is a ticket ID or page ID
if [[ "$TICKET_INPUT" =~ ^TICK- ]]; then
    # It's a ticket ID, need to look up the page ID
    TICKET_NUMBER=$(echo "$TICKET_INPUT" | sed 's/TICK-//')

    echo "Looking up ticket: $TICKET_INPUT (number: $TICKET_NUMBER)"

    # Query the tickets database
    DATABASE_QUERY=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
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

    # Extract page ID
    PAGE_ID=$(echo "$DATABASE_QUERY" | jq -r '.results[0].id // empty' | tr -d '-')

    if [ -z "$PAGE_ID" ]; then
        echo -e "${RED}Error: Ticket not found in Tickets database${NC}"
        exit 1
    fi

    echo "Found page ID: $PAGE_ID"
else
    # Assume it's already a page ID
    PAGE_ID=$(echo "$TICKET_INPUT" | tr -d '-')
    echo "Using page ID: $PAGE_ID"
fi

# If theme ID not provided, try to get it from git config for current branch
if [ -z "$THEME_ID" ]; then
    # Check if we're in a git repository
    if git rev-parse --git-dir > /dev/null 2>&1; then
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [ -n "$CURRENT_BRANCH" ]; then
            STORED_THEME_ID=$(git config "branch.$CURRENT_BRANCH.themeId" 2>/dev/null)
            if [ -n "$STORED_THEME_ID" ]; then
                THEME_ID="$STORED_THEME_ID"
                echo "Auto-detected Theme ID from git config: $THEME_ID"
            fi
        fi
    fi
fi

echo ""
echo "Updating ticket..."

# Build the properties update payload
PROPERTIES="{"
FIRST_PROPERTY=true

# Add status if provided
if [ -n "$NEW_STATUS" ]; then
    CHECKIN_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    PROPERTIES="$PROPERTIES\"Ticket Status\": {
      \"status\": {
        \"name\": \"$NEW_STATUS\"
      }
    },
    \"Checkin Time\": {
      \"date\": {
        \"start\": \"$CHECKIN_TIME\"
      }
    }"
    FIRST_PROPERTY=false
fi

# Add PR URL if provided
if [ -n "$PR_URL" ]; then
    if [ "$FIRST_PROPERTY" = false ]; then
        PROPERTIES="$PROPERTIES,"
    fi
    PROPERTIES="$PROPERTIES\"GitHub Pull Request URL\": {
      \"url\": \"$PR_URL\"
    }"
    FIRST_PROPERTY=false
fi

# Add Theme ID if provided
if [ -n "$THEME_ID" ]; then
    if [ "$FIRST_PROPERTY" = false ]; then
        PROPERTIES="$PROPERTIES,"
    fi
    PROPERTIES="$PROPERTIES\"Shopify Theme ID\": {
      \"number\": $THEME_ID
    }"
    FIRST_PROPERTY=false
fi

PROPERTIES="$PROPERTIES}"

# Only update properties if there are any to update
if [ "$FIRST_PROPERTY" = false ]; then
    UPDATE_RESPONSE=$(curl -s -X PATCH "https://api.notion.com/v1/pages/$PAGE_ID" \
      -H "Authorization: Bearer $NOTION_API_KEY" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d "{\"properties\": $PROPERTIES}")

    # Check if update was successful
    if echo "$UPDATE_RESPONSE" | jq -e '.object == "page"' > /dev/null 2>&1; then
        if [ -n "$NEW_STATUS" ]; then
            echo -e "${GREEN}✓ Status updated to '$NEW_STATUS'${NC}"
            echo -e "${GREEN}✓ Checkin Time set to $CHECKIN_TIME${NC}"
        fi

        if [ -n "$PR_URL" ]; then
            echo -e "${GREEN}✓ PR URL updated to $PR_URL${NC}"
        fi

        if [ -n "$THEME_ID" ]; then
            echo -e "${GREEN}✓ Shopify Theme ID updated to $THEME_ID${NC}"
        fi

        # Extract ticket details for final display
        TICKET_ID=$(echo "$UPDATE_RESPONSE" | jq -r '.properties.ID.unique_id.prefix + "-" + (.properties.ID.unique_id.number | tostring)')
        TICKET_TITLE=$(echo "$UPDATE_RESPONSE" | jq -r '.properties.Name.title[0].plain_text // "N/A"')
        TICKET_URL=$(echo "$UPDATE_RESPONSE" | jq -r '.url')
    else
        echo -e "${RED}Error updating ticket properties:${NC}"
        echo "$UPDATE_RESPONSE" | jq '.'
        exit 1
    fi
fi

# Append summary/notes if provided
if [ -n "$SUMMARY_TEXT" ]; then
    echo ""
    echo "Appending content to ticket page..."

    # Parse summary text and build Notion blocks
    BLOCKS='[
      {
        "type": "divider",
        "divider": {}
      },
      {
        "type": "heading_2",
        "heading_2": {
          "rich_text": [{"type": "text", "text": {"content": "Summary"}}]
        }
      }'

    # Process each line of the summary
    while IFS= read -r line; do
        # Skip empty lines
        if [ -z "$line" ]; then
            continue
        fi

        # Check for ## headers (convert to heading_3)
        if [[ "$line" =~ ^##[[:space:]](.+)$ ]]; then
            HEADING_TEXT="${BASH_REMATCH[1]}"
            # Add emojis based on heading content
            case "$HEADING_TEXT" in
                *"What was built"*|*"Features"*|*"Implemented"*)
                    HEADING_TEXT="✨ $HEADING_TEXT"
                    ;;
                *"Technical"*|*"Implementation"*)
                    HEADING_TEXT="🔧 $HEADING_TEXT"
                    ;;
                *"Key decision"*|*"Decision"*)
                    HEADING_TEXT="💡 $HEADING_TEXT"
                    ;;
                *"Commit"*|*"Changes"*)
                    HEADING_TEXT="📝 $HEADING_TEXT"
                    ;;
                *"Note"*|*"Issue"*|*"Problem"*)
                    HEADING_TEXT="⚠️ $HEADING_TEXT"
                    ;;
                *"Test"*|*"Testing"*)
                    HEADING_TEXT="🧪 $HEADING_TEXT"
                    ;;
                *"Fix"*|*"Bug"*)
                    HEADING_TEXT="🐛 $HEADING_TEXT"
                    ;;
            esac
            BLOCKS="$BLOCKS,$(jq -n --arg text "$HEADING_TEXT" '{
              "type": "heading_3",
              "heading_3": {
                "rich_text": [{"type": "text", "text": {"content": $text}}]
              }
            }')"
        # Check for bullet points (- )
        elif [[ "$line" =~ ^-[[:space:]](.+)$ ]]; then
            BULLET_TEXT="${BASH_REMATCH[1]}"
            # Truncate to 2000 chars to avoid Notion API limit
            if [ ${#BULLET_TEXT} -gt 1900 ]; then
                BULLET_TEXT="${BULLET_TEXT:0:1900}..."
            fi
            BLOCKS="$BLOCKS,$(jq -n --arg text "$BULLET_TEXT" '{
              "type": "bulleted_list_item",
              "bulleted_list_item": {
                "rich_text": [{"type": "text", "text": {"content": $text}}]
              }
            }')"
        # Regular paragraph
        else
            # Truncate to 2000 chars to avoid Notion API limit
            PARA_TEXT="$line"
            if [ ${#PARA_TEXT} -gt 1900 ]; then
                PARA_TEXT="${PARA_TEXT:0:1900}..."
            fi
            BLOCKS="$BLOCKS,$(jq -n --arg text "$PARA_TEXT" '{
              "type": "paragraph",
              "paragraph": {
                "rich_text": [{"type": "text", "text": {"content": $text}}]
              }
            }')"
        fi
    done <<< "$SUMMARY_TEXT"

    BLOCKS="$BLOCKS]"

    # Build final JSON payload
    JSON_PAYLOAD=$(jq -n --argjson blocks "$BLOCKS" '{"children": $blocks}')

    # Append blocks to the page
    APPEND_RESPONSE=$(curl -s -X PATCH "https://api.notion.com/v1/blocks/$PAGE_ID/children" \
      -H "Authorization: Bearer $NOTION_API_KEY" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d "$JSON_PAYLOAD")

    if echo "$APPEND_RESPONSE" | jq -e '.object == "list" or .object == "block"' > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Content appended to ticket page${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Could not append content to page${NC}"
        echo "$APPEND_RESPONSE" | jq '.'
    fi
fi

# Execute QA Before if requested
if [ "$QA_BEFORE" = true ]; then
    echo ""
    echo "Processing QA Before screenshot..."
    if "$RECORD_QA_SCRIPT" "$TICKET_INPUT" --before; then
        echo -e "${GREEN}✓ QA Before screenshot uploaded${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: QA Before screenshot failed${NC}"
    fi
fi

# Execute QA After if requested (capture from Chrome)
if [ "$QA_AFTER" = true ]; then
    echo ""
    echo "Processing QA After screenshot (Chrome capture)..."
    if "$RECORD_QA_SCRIPT" "$TICKET_INPUT" --capture-after; then
        echo -e "${GREEN}✓ QA After screenshot captured and uploaded${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: QA After screenshot capture failed${NC}"
    fi
fi

# Execute QA After with specific file if requested
if [ -n "$QA_AFTER_FILE" ]; then
    echo ""
    echo "Processing QA After screenshot from file..."
    if [ ! -f "$QA_AFTER_FILE" ]; then
        echo -e "${RED}Error: QA After file not found: $QA_AFTER_FILE${NC}"
    elif "$RECORD_QA_SCRIPT" "$TICKET_INPUT" --after "$QA_AFTER_FILE"; then
        echo -e "${GREEN}✓ QA After screenshot uploaded from $QA_AFTER_FILE${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: QA After screenshot upload failed${NC}"
    fi
fi

# Final summary
echo ""
echo -e "${GREEN}✓ Ticket updated successfully!${NC}"
if [ -n "$TICKET_ID" ]; then
    echo "  ID: $TICKET_ID"
    echo "  Title: $TICKET_TITLE"
    echo "  URL: $TICKET_URL"
else
    echo "  View ticket: https://www.notion.so/$PAGE_ID"
fi
