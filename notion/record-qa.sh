#!/bin/bash

# Record QA verification results in Notion
# Usage:
#   ./record-qa.sh TICK-### --status passed --by "Name"
#   ./record-qa.sh TICK-### --status failed --notes "Button misaligned"
#   ./record-qa.sh --batch pdp-P1-QuickWins --status passed
#
# Records QA verification in Notion ticket including:
#   - QA Status (Pending/Passed/Failed)
#   - QA performed by
#   - QA timestamp
#   - Staging preview URL
#   - QA notes/observations
#   - QA environment (browser/device)
#   - Screenshots (optional)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Notion config
TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo "Usage: $0 TICKET-ID [OPTIONS]"
    echo "       $0 --batch BATCH_KEY [OPTIONS]"
    echo ""
    echo "Record QA verification results in Notion."
    echo ""
    echo "Options:"
    echo "  --status, -s STATUS     QA status: pending, passed, failed, skipped"
    echo "  --by, -b NAME           Who performed QA (default: current user)"
    echo "  --notes, -n TEXT        QA notes/observations"
    echo "  --env, -e ENV           Environment tested (e.g., 'Chrome 120, macOS')"
    echo "  --preview-url, -u URL   Staging preview URL"
    echo "  --screenshot, -i FILE   Path to screenshot file"
    echo "  --batch BATCH_KEY       Apply QA status to entire batch"
    echo "  --batch-id ID           QA Batch identifier (auto-generated if not provided)"
    echo "  --help, -h              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 TICK-1234 --status passed --by 'John Doe'"
    echo "  $0 TICK-1234 --status failed --notes 'Button color wrong'"
    echo "  $0 --batch pdp-P1-QuickWins --status passed --by 'QA Team'"
    exit 1
}

# Parse arguments
TICKET_ID=""
BATCH_KEY=""
QA_STATUS=""
QA_BY=""
QA_NOTES=""
QA_ENV=""
PREVIEW_URL=""
SCREENSHOT=""
QA_BATCH_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        TICK-*)
            TICKET_ID="$1"
            shift
            ;;
        --status|-s)
            QA_STATUS="$2"
            shift 2
            ;;
        --by|-b)
            QA_BY="$2"
            shift 2
            ;;
        --notes|-n)
            QA_NOTES="$2"
            shift 2
            ;;
        --env|-e)
            QA_ENV="$2"
            shift 2
            ;;
        --preview-url|-u)
            PREVIEW_URL="$2"
            shift 2
            ;;
        --screenshot|-i)
            SCREENSHOT="$2"
            shift 2
            ;;
        --batch)
            BATCH_KEY="$2"
            shift 2
            ;;
        --batch-id)
            QA_BATCH_ID="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            ;;
    esac
done

# Validate inputs
if [ -z "$TICKET_ID" ] && [ -z "$BATCH_KEY" ]; then
    echo -e "${RED}Error: Specify TICKET-ID or --batch${NC}"
    show_usage
fi

if [ -z "$QA_STATUS" ]; then
    echo -e "${RED}Error: --status is required${NC}"
    show_usage
fi

# Normalize status
QA_STATUS_LOWER=$(echo "$QA_STATUS" | tr '[:upper:]' '[:lower:]')
case "$QA_STATUS_LOWER" in
    passed|pass|approved|ok)
        QA_STATUS_DISPLAY="QA Passed"
        QA_STATUS_EMOJI="✅"
        ;;
    failed|fail|rejected)
        QA_STATUS_DISPLAY="QA Failed"
        QA_STATUS_EMOJI="❌"
        ;;
    pending|waiting)
        QA_STATUS_DISPLAY="Pending QA"
        QA_STATUS_EMOJI="⏳"
        ;;
    skipped|skip|na)
        QA_STATUS_DISPLAY="QA Skipped"
        QA_STATUS_EMOJI="⏭️"
        ;;
    *)
        echo -e "${RED}Invalid status: $QA_STATUS${NC}"
        echo "Valid statuses: pending, passed, failed, skipped"
        exit 1
        ;;
esac

# Default QA by to current user
if [ -z "$QA_BY" ]; then
    QA_BY=$(whoami)
fi

# Generate QA batch ID if not provided
if [ -z "$QA_BATCH_ID" ]; then
    QA_BATCH_ID="QA-$(date +%Y%m%d-%H%M%S)"
fi

# Get QA timestamp
QA_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
QA_TIMESTAMP_DISPLAY=$(date +"%Y-%m-%d %H:%M")

# Auto-detect preview URL if not provided
if [ -z "$PREVIEW_URL" ]; then
    if [ -f "$SCRIPT_DIR/../shopify/get-staging-url.sh" ]; then
        PREVIEW_URL=$("$SCRIPT_DIR/../shopify/get-staging-url.sh" 2>/dev/null || true)
    fi
fi

# Load Notion credentials
if [ -f "$HOME/.bash_profile" ]; then
    source "$HOME/.bash_profile"
fi

if [ -z "$NOTION_API_KEY" ]; then
    echo -e "${RED}Error: NOTION_API_KEY not set${NC}"
    exit 1
fi

# Function to record QA for a single ticket
record_qa_for_ticket() {
    local TICKET="$1"
    local TICKET_NUMBER=$(echo "$TICKET" | sed 's/TICK-//')

    echo -e "${BLUE}Recording QA for $TICKET...${NC}"

    # Look up page ID
    DATABASE_QUERY=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d "{\"filter\": {\"property\": \"ID\", \"unique_id\": {\"equals\": $TICKET_NUMBER}}}")

    PAGE_ID=$(echo "$DATABASE_QUERY" | jq -r '.results[0].id // empty' | tr -d '-')

    if [ -z "$PAGE_ID" ]; then
        echo -e "  ${RED}✗ Ticket not found${NC}"
        return 1
    fi

    # Build QA summary block content
    QA_SUMMARY="$QA_STATUS_EMOJI **QA $QA_STATUS_DISPLAY**

**QA Details:**
- Status: $QA_STATUS_DISPLAY
- Performed by: $QA_BY
- Date: $QA_TIMESTAMP_DISPLAY
- Batch ID: $QA_BATCH_ID"

    if [ -n "$QA_ENV" ]; then
        QA_SUMMARY="$QA_SUMMARY
- Environment: $QA_ENV"
    fi

    if [ -n "$PREVIEW_URL" ]; then
        QA_SUMMARY="$QA_SUMMARY
- Preview URL: $PREVIEW_URL"
    fi

    if [ -n "$QA_NOTES" ]; then
        QA_SUMMARY="$QA_SUMMARY

**Notes:** $QA_NOTES"
    fi

    # Append QA block to the ticket page
    # Build blocks JSON
    BLOCKS='[
      {
        "type": "divider",
        "divider": {}
      },
      {
        "type": "heading_2",
        "heading_2": {
          "rich_text": [{"type": "text", "text": {"content": "'"$QA_STATUS_EMOJI QA Verification"'"}}]
        }
      },
      {
        "type": "paragraph",
        "paragraph": {
          "rich_text": [{"type": "text", "text": {"content": "Status: '"$QA_STATUS_DISPLAY"'"}}]
        }
      },
      {
        "type": "bulleted_list_item",
        "bulleted_list_item": {
          "rich_text": [{"type": "text", "text": {"content": "Performed by: '"$QA_BY"'"}}]
        }
      },
      {
        "type": "bulleted_list_item",
        "bulleted_list_item": {
          "rich_text": [{"type": "text", "text": {"content": "Date: '"$QA_TIMESTAMP_DISPLAY"'"}}]
        }
      },
      {
        "type": "bulleted_list_item",
        "bulleted_list_item": {
          "rich_text": [{"type": "text", "text": {"content": "Batch ID: '"$QA_BATCH_ID"'"}}]
        }
      }'

    if [ -n "$QA_ENV" ]; then
        BLOCKS="$BLOCKS,"'{
          "type": "bulleted_list_item",
          "bulleted_list_item": {
            "rich_text": [{"type": "text", "text": {"content": "Environment: '"$QA_ENV"'"}}]
          }
        }'
    fi

    if [ -n "$PREVIEW_URL" ]; then
        BLOCKS="$BLOCKS,"'{
          "type": "bulleted_list_item",
          "bulleted_list_item": {
            "rich_text": [{"type": "text", "text": {"content": "Preview: '"$PREVIEW_URL"'"}}]
          }
        }'
    fi

    if [ -n "$QA_NOTES" ]; then
        BLOCKS="$BLOCKS,"'{
          "type": "paragraph",
          "paragraph": {
            "rich_text": [
              {"type": "text", "text": {"content": "Notes: ", "link": null}, "annotations": {"bold": true}},
              {"type": "text", "text": {"content": "'"$QA_NOTES"'"}}
            ]
          }
        }'
    fi

    BLOCKS="$BLOCKS]"

    # Append blocks to page
    APPEND_RESPONSE=$(curl -s -X PATCH "https://api.notion.com/v1/blocks/$PAGE_ID/children" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d "{\"children\": $BLOCKS}")

    if echo "$APPEND_RESPONSE" | jq -e '.object == "list"' > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ QA recorded: $QA_STATUS_DISPLAY${NC}"

        # If QA passed, update ticket sub-status
        if [ "$QA_STATUS_LOWER" = "passed" ] || [ "$QA_STATUS_LOWER" = "pass" ]; then
            # Update sub-status to indicate QA complete
            UPDATE_RESPONSE=$(curl -s -X PATCH "https://api.notion.com/v1/pages/$PAGE_ID" \
                -H "Authorization: Bearer $NOTION_API_KEY" \
                -H "Notion-Version: 2022-06-28" \
                -H "Content-Type: application/json" \
                -d '{
                    "properties": {
                        "Ticket Sub-status": {
                            "status": {
                                "name": "QA Approved"
                            }
                        }
                    }
                }' 2>/dev/null || true)

            # Note: This will fail if "QA Approved" sub-status doesn't exist
            # That's okay - the content block is the main record
        fi

        return 0
    else
        echo -e "  ${RED}✗ Failed to record QA${NC}"
        echo "$APPEND_RESPONSE" | jq '.message // .' >&2
        return 1
    fi
}

# Process single ticket or batch
if [ -n "$TICKET_ID" ]; then
    # Single ticket
    record_qa_for_ticket "$TICKET_ID"
else
    # Batch mode
    echo -e "${BLUE}Recording QA for batch: $BATCH_KEY${NC}"
    echo "QA Batch ID: $QA_BATCH_ID"
    echo ""

    # Get tickets from categorized file
    CATEGORIZED_FILE="$HOME/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests/results/categorized_tickets.json"

    if [ ! -f "$CATEGORIZED_FILE" ]; then
        echo -e "${RED}Error: Categorized tickets file not found${NC}"
        exit 1
    fi

    TICKET_IDS=$(cat "$CATEGORIZED_FILE" | jq -r --arg key "$BATCH_KEY" '
        [.[] | select(.batch_key == $key)] | .[].id')

    TICKET_COUNT=$(echo "$TICKET_IDS" | grep -c "TICK-" || echo "0")

    if [ "$TICKET_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No tickets found in batch: $BATCH_KEY${NC}"
        exit 0
    fi

    echo "Found $TICKET_COUNT tickets in batch"
    echo ""

    SUCCESS=0
    FAILED=0

    echo "$TICKET_IDS" | while read -r ticket; do
        if [ -n "$ticket" ]; then
            if record_qa_for_ticket "$ticket"; then
                SUCCESS=$((SUCCESS + 1))
            else
                FAILED=$((FAILED + 1))
            fi
        fi
    done

    echo ""
    echo -e "${GREEN}Batch QA recording complete${NC}"
    echo "QA Batch ID: $QA_BATCH_ID"
fi

# Save QA record to local log
QA_LOG_DIR="$HOME/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests/results/qa-logs"
mkdir -p "$QA_LOG_DIR"

QA_LOG_FILE="$QA_LOG_DIR/$QA_BATCH_ID.json"

jq -n \
    --arg batch_id "$QA_BATCH_ID" \
    --arg status "$QA_STATUS_DISPLAY" \
    --arg by "$QA_BY" \
    --arg timestamp "$QA_TIMESTAMP" \
    --arg env "$QA_ENV" \
    --arg preview "$PREVIEW_URL" \
    --arg notes "$QA_NOTES" \
    --arg ticket "$TICKET_ID" \
    --arg batch_key "$BATCH_KEY" \
    '{
        qa_batch_id: $batch_id,
        status: $status,
        performed_by: $by,
        timestamp: $timestamp,
        environment: $env,
        preview_url: $preview,
        notes: $notes,
        ticket_id: $ticket,
        batch_key: $batch_key
    }' > "$QA_LOG_FILE"

echo ""
echo "QA log saved: $QA_LOG_FILE"
