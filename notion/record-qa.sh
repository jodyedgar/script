#!/bin/bash

# Record QA verification results in Notion with Firebase Storage integration
# Usage:
#   ./record-qa.sh TICK-### --before                    # Extract Feedbucket → QA Before field
#   ./record-qa.sh TICK-### --after ./screenshot.png    # Upload screenshot → QA After field
#   ./record-qa.sh TICK-### --status passed --by "Name"
#   ./record-qa.sh TICK-### --status failed --notes "Button misaligned"
#   ./record-qa.sh --batch pdp-P1-QuickWins --status passed
#
# Records QA verification in Notion ticket including:
#   - QA Before (Files & media property - Feedbucket screenshot)
#   - QA After (Files & media property - Chrome MCP screenshot)
#   - QA Status (Status property - Pending/Passed/Failed)
#   - QA Approved By (Person - who performed QA)
#   - QA Completed Time (Date - when QA was done)
#   - Staging preview URL
#   - QA notes/observations
#   - QA environment (browser/device)
#
# Firebase Storage: Screenshots uploaded to bucky-app-355a3 bucket
# Firestore: Metadata stored in qa_screenshots collection

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
QA_DIR="$SCRIPT_DIR/qa"
BATCH_RESULTS_DIR="$SCRIPT_DIR/batch/results"

show_usage() {
    echo "Usage: $0 TICKET-ID [OPTIONS]"
    echo "       $0 --batch BATCH_KEY [OPTIONS]"
    echo ""
    echo "Record QA verification results in Notion with Firebase Storage integration."
    echo ""
    echo "Screenshot Options (Firebase Storage):"
    echo "  --before                Extract Feedbucket image → QA Before field"
    echo "  --after FILE            Upload screenshot file → QA After field"
    echo "  --after-url URL         Use URL directly for QA After"
    echo "  --capture-after         Capture Chrome screenshot automatically → QA After"
    echo ""
    echo "QA Status Options:"
    echo "  --status, -s STATUS     QA status: pending, passed, failed, skipped"
    echo "  --by, -b NAME           Who performed QA (default: current user)"
    echo "  --notes, -n TEXT        QA notes/observations"
    echo "  --env, -e ENV           Environment tested (e.g., 'Chrome 120, macOS')"
    echo "  --preview-url, -u URL   Staging preview URL"
    echo ""
    echo "Batch Options:"
    echo "  --batch BATCH_KEY       Apply to entire batch"
    echo "  --batch-id ID           QA Batch identifier (auto-generated if not provided)"
    echo ""
    echo "Examples:"
    echo "  # Extract Feedbucket image as QA Before"
    echo "  $0 TICK-1234 --before"
    echo ""
    echo "  # Upload Chrome MCP screenshot as QA After and mark passed"
    echo "  $0 TICK-1234 --after ./screenshot.png --status passed"
    echo ""
    echo "  # Full QA workflow"
    echo "  $0 TICK-1234 --before --after ./screenshot.png --status passed --by 'QA Team'"
    echo ""
    echo "  # Batch processing"
    echo "  $0 --batch pdp-P1-QuickWins --before --status passed"
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
QA_BATCH_ID=""
DO_BEFORE="false"
AFTER_FILE=""
AFTER_URL=""
DO_CAPTURE_AFTER="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        TICK-*|tick-*)
            TICKET_ID=$(echo "$1" | tr '[:lower:]' '[:upper:]')
            shift
            ;;
        --before)
            DO_BEFORE="true"
            shift
            ;;
        --after)
            AFTER_FILE="$2"
            shift 2
            ;;
        --after-url)
            AFTER_URL="$2"
            shift 2
            ;;
        --capture-after)
            DO_CAPTURE_AFTER="true"
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

# Status is required unless just doing --before or --after
if [ -z "$QA_STATUS" ] && [ "$DO_BEFORE" = "false" ] && [ -z "$AFTER_FILE" ] && [ -z "$AFTER_URL" ] && [ "$DO_CAPTURE_AFTER" = "false" ]; then
    echo -e "${RED}Error: --status is required (or use --before/--after/--capture-after for screenshots only)${NC}"
    show_usage
fi

# Normalize status (only if status is provided)
if [ -n "$QA_STATUS" ]; then
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
fi

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

# Check if Node.js dependencies are installed
check_node_deps() {
    if [ ! -d "$QA_DIR/node_modules" ]; then
        echo -e "${YELLOW}Installing Node.js dependencies...${NC}"
        (cd "$QA_DIR" && npm install --silent)
    fi
}

# Extract Feedbucket image URL from ticket
extract_feedbucket_url() {
    local PAGE_ID="$1"

    # Get page content blocks to find Feedbucket media
    BLOCKS_RESPONSE=$(curl -s -X GET "https://api.notion.com/v1/blocks/$PAGE_ID/children?page_size=100" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28")

    # Look for image blocks or file blocks with Feedbucket URLs
    FEEDBUCKET_URL=$(echo "$BLOCKS_RESPONSE" | jq -r '
        .results[] |
        select(.type == "image" or .type == "file" or .type == "video") |
        if .type == "image" then
            (.image.external.url // .image.file.url)
        elif .type == "video" then
            (.video.external.url // .video.file.url)
        else
            (.file.external.url // .file.file.url)
        end
    ' | grep -i "feedbucket\|fb-media\|feedback" | head -1)

    # If not found in blocks, check the Feedbucket Media property
    if [ -z "$FEEDBUCKET_URL" ]; then
        PAGE_RESPONSE=$(curl -s -X GET "https://api.notion.com/v1/pages/$PAGE_ID" \
            -H "Authorization: Bearer $NOTION_API_KEY" \
            -H "Notion-Version: 2022-06-28")

        FEEDBUCKET_URL=$(echo "$PAGE_RESPONSE" | jq -r '
            .properties["Feedbucket Media"].files[0].external.url //
            .properties["Feedbucket Media"].files[0].file.url //
            .properties["Screenshot"].files[0].external.url //
            .properties["Screenshot"].files[0].file.url //
            empty
        ')
    fi

    echo "$FEEDBUCKET_URL"
}

# Upload file to Firebase Storage via Node.js script
upload_to_firebase() {
    local FILE_OR_URL="$1"
    local TICKET_ID="$2"
    local TYPE="$3"  # "before" or "after"
    local PAGE_ID="$4"

    check_node_deps

    # Build arguments array to handle spaces/special chars properly
    local -a UPLOAD_ARGS=("--ticket" "$TICKET_ID" "--type" "$TYPE")

    if [[ "$FILE_OR_URL" == http* ]]; then
        UPLOAD_ARGS+=("--url" "$FILE_OR_URL")
    else
        UPLOAD_ARGS+=("--file" "$FILE_OR_URL")
    fi

    if [ -n "$PAGE_ID" ]; then
        UPLOAD_ARGS+=("--notion-page-id" "$PAGE_ID")
    fi

    # Run Node.js upload script
    UPLOAD_RESULT=$(cd "$QA_DIR" && node upload-screenshot.js "${UPLOAD_ARGS[@]}" 2>&1)

    if echo "$UPLOAD_RESULT" | jq -e '.success == true' > /dev/null 2>&1; then
        echo "$UPLOAD_RESULT" | jq -r '.url'
    else
        echo -e "${RED}Upload failed: $(echo "$UPLOAD_RESULT" | jq -r '.error // .')${NC}" >&2
        return 1
    fi
}

# Update Notion QA Before/After fields (Files & media properties)
update_notion_qa_fields() {
    local PAGE_ID="$1"
    local FIELD_NAME="$2"  # "QA Before" or "QA After"
    local FILE_URL="$3"
    local FILE_NAME="$4"

    if [ -z "$FILE_NAME" ]; then
        FILE_NAME="$FIELD_NAME screenshot"
    fi

    # Build the update payload for Files & media property
    local UPDATE_PAYLOAD=$(jq -n \
        --arg field "$FIELD_NAME" \
        --arg url "$FILE_URL" \
        --arg name "$FILE_NAME" \
        '{
            properties: {
                ($field): {
                    files: [{
                        type: "external",
                        name: $name,
                        external: {
                            url: $url
                        }
                    }]
                }
            }
        }')

    UPDATE_RESPONSE=$(curl -s -X PATCH "https://api.notion.com/v1/pages/$PAGE_ID" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d "$UPDATE_PAYLOAD")

    if echo "$UPDATE_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
        return 0
    else
        echo -e "${RED}Failed to update $FIELD_NAME: $(echo "$UPDATE_RESPONSE" | jq -r '.message // .')${NC}" >&2
        return 1
    fi
}

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

    # Handle QA Before (Feedbucket extraction)
    if [ "$DO_BEFORE" = "true" ]; then
        echo -e "  ${BLUE}Extracting Feedbucket image...${NC}"
        FEEDBUCKET_URL=$(extract_feedbucket_url "$PAGE_ID")

        if [ -z "$FEEDBUCKET_URL" ]; then
            echo -e "  ${YELLOW}⚠ No Feedbucket media found${NC}"
        else
            echo -e "  ${GREEN}✓ Found Feedbucket image${NC}"
            # Upload to Firebase and update Notion
            BEFORE_URL=$(upload_to_firebase "$FEEDBUCKET_URL" "$TICKET" "before" "$PAGE_ID")
            if [ -n "$BEFORE_URL" ]; then
                update_notion_qa_fields "$PAGE_ID" "QA Before" "$BEFORE_URL" "$TICKET-before"
                echo -e "  ${GREEN}✓ QA Before uploaded: $BEFORE_URL${NC}"
            fi
        fi
    fi

    # Handle QA After (local file upload)
    if [ -n "$AFTER_FILE" ]; then
        if [ ! -f "$AFTER_FILE" ]; then
            echo -e "  ${RED}✗ File not found: $AFTER_FILE${NC}"
        else
            echo -e "  ${BLUE}Uploading QA After screenshot...${NC}"
            AFTER_UPLOAD_URL=$(upload_to_firebase "$AFTER_FILE" "$TICKET" "after" "$PAGE_ID")
            if [ -n "$AFTER_UPLOAD_URL" ]; then
                update_notion_qa_fields "$PAGE_ID" "QA After" "$AFTER_UPLOAD_URL" "$TICKET-after"
                echo -e "  ${GREEN}✓ QA After uploaded: $AFTER_UPLOAD_URL${NC}"
            fi
        fi
    fi

    # Handle QA After (direct URL)
    if [ -n "$AFTER_URL" ]; then
        echo -e "  ${BLUE}Setting QA After URL...${NC}"
        AFTER_UPLOAD_URL=$(upload_to_firebase "$AFTER_URL" "$TICKET" "after" "$PAGE_ID")
        if [ -n "$AFTER_UPLOAD_URL" ]; then
            update_notion_qa_fields "$PAGE_ID" "QA After" "$AFTER_UPLOAD_URL" "$TICKET-after"
            echo -e "  ${GREEN}✓ QA After set: $AFTER_UPLOAD_URL${NC}"
        fi
    fi

    # Handle QA After (capture from Chrome)
    if [ "$DO_CAPTURE_AFTER" = "true" ]; then
        echo -e "  ${BLUE}Capturing Chrome screenshot...${NC}"

        # Create temp file for screenshot
        CAPTURE_FILE="/tmp/qa-capture-${TICKET}-$(date +%s).png"

        # Run capture script
        CAPTURE_RESULT=$(cd "$QA_DIR" && node capture-screenshot.js --output "$CAPTURE_FILE" 2>&1)

        if [ -f "$CAPTURE_FILE" ]; then
            # Parse capture result for page info
            PAGE_TITLE=$(echo "$CAPTURE_RESULT" | grep -o '"title":"[^"]*"' | cut -d'"' -f4 || echo "Chrome")
            echo -e "  ${GREEN}✓ Captured: $PAGE_TITLE${NC}"

            # Upload to Firebase
            AFTER_UPLOAD_URL=$(upload_to_firebase "$CAPTURE_FILE" "$TICKET" "after" "$PAGE_ID")
            if [ -n "$AFTER_UPLOAD_URL" ]; then
                update_notion_qa_fields "$PAGE_ID" "QA After" "$AFTER_UPLOAD_URL" "$TICKET-after"
                echo -e "  ${GREEN}✓ QA After uploaded: $AFTER_UPLOAD_URL${NC}"
            fi

            # Clean up temp file
            rm -f "$CAPTURE_FILE"
        else
            echo -e "  ${RED}✗ Chrome capture failed${NC}"
            # Show error details
            if echo "$CAPTURE_RESULT" | jq -e '.error' > /dev/null 2>&1; then
                echo -e "  ${YELLOW}$(echo "$CAPTURE_RESULT" | jq -r '.error')${NC}"
                echo -e "  ${YELLOW}$(echo "$CAPTURE_RESULT" | jq -r '.hint // empty')${NC}"
            else
                echo -e "  ${YELLOW}$CAPTURE_RESULT${NC}"
            fi
        fi
    fi

    # If only doing screenshots (no status), return here
    if [ -z "$QA_STATUS" ]; then
        echo -e "  ${GREEN}✓ Screenshot processing complete${NC}"
        return 0
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

    # Append QA block to the ticket page using jq for proper JSON construction
    # Build base blocks array
    BLOCKS_JSON=$(jq -n \
        --arg heading "$QA_STATUS_EMOJI QA Verification" \
        --arg status "Status: $QA_STATUS_DISPLAY" \
        --arg by "Performed by: $QA_BY" \
        --arg date "Date: $QA_TIMESTAMP_DISPLAY" \
        --arg batch "Batch ID: $QA_BATCH_ID" \
        '[
            { "type": "divider", "divider": {} },
            { "type": "heading_2", "heading_2": { "rich_text": [{ "type": "text", "text": { "content": $heading } }] } },
            { "type": "paragraph", "paragraph": { "rich_text": [{ "type": "text", "text": { "content": $status } }] } },
            { "type": "bulleted_list_item", "bulleted_list_item": { "rich_text": [{ "type": "text", "text": { "content": $by } }] } },
            { "type": "bulleted_list_item", "bulleted_list_item": { "rich_text": [{ "type": "text", "text": { "content": $date } }] } },
            { "type": "bulleted_list_item", "bulleted_list_item": { "rich_text": [{ "type": "text", "text": { "content": $batch } }] } }
        ]')

    # Add optional blocks
    if [ -n "$QA_ENV" ]; then
        BLOCKS_JSON=$(echo "$BLOCKS_JSON" | jq --arg env "Environment: $QA_ENV" \
            '. + [{ "type": "bulleted_list_item", "bulleted_list_item": { "rich_text": [{ "type": "text", "text": { "content": $env } }] } }]')
    fi

    if [ -n "$PREVIEW_URL" ]; then
        BLOCKS_JSON=$(echo "$BLOCKS_JSON" | jq --arg preview "Preview: $PREVIEW_URL" \
            '. + [{ "type": "bulleted_list_item", "bulleted_list_item": { "rich_text": [{ "type": "text", "text": { "content": $preview } }] } }]')
    fi

    if [ -n "$QA_NOTES" ]; then
        BLOCKS_JSON=$(echo "$BLOCKS_JSON" | jq --arg notes "$QA_NOTES" \
            '. + [{ "type": "paragraph", "paragraph": { "rich_text": [{ "type": "text", "text": { "content": "Notes: " }, "annotations": { "bold": true } }, { "type": "text", "text": { "content": $notes } }] } }]')
    fi

    # Wrap in children object
    BLOCKS_JSON=$(echo "$BLOCKS_JSON" | jq '{ "children": . }')

    # Append blocks to page
    APPEND_RESPONSE=$(curl -s -X PATCH "https://api.notion.com/v1/blocks/$PAGE_ID/children" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d "$BLOCKS_JSON")

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
