#!/bin/bash

# Record QA verification results with Firebase Storage integration (Firestore-backed)
# Usage:
#   ./ticket-qa.sh TICK-### --before                    # Extract Feedbucket -> QA Before
#   ./ticket-qa.sh TICK-### --after ./screenshot.png    # Upload screenshot -> QA After
#   ./ticket-qa.sh TICK-### --status passed --by "Name"
#   ./ticket-qa.sh TICK-### --status failed --notes "Button misaligned"
#   ./ticket-qa.sh --batch pdp-P1-QuickWins --status passed
#
# Firebase Storage: Screenshots uploaded to bucky-app-355a3 bucket
# Firestore: QA data stored in ticket document (qaBefore/qaAfter arrays)

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_firestore-lib.sh"

# QA scripts directory
QA_DIR="$SCRIPT_DIR/qa"
BATCH_RESULTS_DIR="$SCRIPT_DIR/batch/results"

show_usage() {
    echo "Usage: $0 TICKET-ID [OPTIONS]"
    echo "       $0 --batch BATCH_KEY [OPTIONS]"
    echo ""
    echo "Record QA verification results with Firebase Storage integration."
    echo ""
    echo "Screenshot Options (Firebase Storage):"
    echo "  --before                Extract Feedbucket image -> QA Before field"
    echo "  --after FILE            Upload screenshot file -> QA After field"
    echo "  --after-url URL         Use URL directly for QA After"
    echo "  --capture-after         Capture Chrome screenshot automatically -> QA After"
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
    echo "  $0 TICK-1234 --before"
    echo "  $0 TICK-1234 --after ./screenshot.png --status passed"
    echo "  $0 TICK-1234 --before --after ./screenshot.png --status passed --by 'QA Team'"
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
QA_STATUS_DISPLAY=""
QA_STATUS_LOWER=""
if [ -n "$QA_STATUS" ]; then
    QA_STATUS_LOWER=$(echo "$QA_STATUS" | tr '[:upper:]' '[:lower:]')
    case "$QA_STATUS_LOWER" in
        passed|pass|approved|ok)
            QA_STATUS_DISPLAY="QA Passed"
            ;;
        failed|fail|rejected)
            QA_STATUS_DISPLAY="QA Failed"
            ;;
        pending|waiting)
            QA_STATUS_DISPLAY="Pending QA"
            ;;
        skipped|skip|na)
            QA_STATUS_DISPLAY="QA Skipped"
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

# Check if Node.js dependencies are installed
check_node_deps() {
    if [ ! -d "$QA_DIR/node_modules" ]; then
        echo -e "${YELLOW}Installing Node.js dependencies...${NC}"
        (cd "$QA_DIR" && npm install --silent)
    fi
}

# Extract Feedbucket URL from ticket content field
extract_feedbucket_url_from_content() {
    local CONTENT="$1"
    local SCREENSHOTS="$2"

    # Search content for Feedbucket URLs
    local URL=""
    if [ -n "$CONTENT" ]; then
        URL=$(echo "$CONTENT" | grep -oE 'https://[^ ]*(feedbucket|fb-media|cdn\.feedbucket)[^ ]*' | head -1 || true)
    fi

    # Fallback: check screenshots array
    if [ -z "$URL" ] && [ -n "$SCREENSHOTS" ]; then
        URL=$(echo "$SCREENSHOTS" | grep -i "feedbucket\|fb-media" | head -1 || true)
    fi

    echo "$URL"
}

# Extract Feedbucket metadata (viewport, page URL) from content field
extract_feedbucket_metadata_from_content() {
    local CONTENT="$1"

    local VIEWPORT=""
    local PAGE_URL_VAL=""
    local IMAGE_URL=""

    if [ -n "$CONTENT" ]; then
        # Extract viewport
        VIEWPORT=$(echo "$CONTENT" | grep -oE 'Viewport:?\s*\n?\s*[0-9]+\s*x\s*[0-9]+' | grep -oE '[0-9]+x[0-9]+' | head -1 || true)
        # Extract page URL
        PAGE_URL_VAL=$(echo "$CONTENT" | grep -oE 'Page:\s*https?://[^ ]+' | grep -oE 'https?://[^ ]+' | head -1 || true)
        # Extract Feedbucket image URL
        IMAGE_URL=$(echo "$CONTENT" | grep -oE 'https://[^ ]*(feedbucket|fb-media|cdn\.feedbucket)[^ ]*' | head -1 || true)
    fi

    jq -n \
        --arg viewport "$VIEWPORT" \
        --arg page_url "$PAGE_URL_VAL" \
        --arg image_url "$IMAGE_URL" \
        '{viewport: $viewport, page_url: $page_url, image_url: $image_url}'
}

# Upload file to Firebase Storage via Node.js script
upload_to_firebase() {
    local FILE_OR_URL="$1"
    local TICKET_ID="$2"
    local TYPE="$3"  # "before" or "after"

    check_node_deps

    # Build arguments array
    local -a UPLOAD_ARGS=("--ticket" "$TICKET_ID" "--type" "$TYPE")

    if [[ "$FILE_OR_URL" == http* ]]; then
        UPLOAD_ARGS+=("--url" "$FILE_OR_URL")
    else
        UPLOAD_ARGS+=("--file" "$FILE_OR_URL")
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

# Function to record QA for a single ticket
record_qa_for_ticket() {
    local TICKET="$1"

    echo -e "${BLUE}Recording QA for $TICKET...${NC}"

    # Look up ticket in Firestore
    QUERY_RESULT=$(query_ticket "$TICKET")
    DOC_NAME=$(echo "$QUERY_RESULT" | jq -r '.[0].document.name // empty')

    if [ -z "$DOC_NAME" ]; then
        echo -e "  ${RED}Ticket not found${NC}"
        return 1
    fi

    DOC_PATH=$(echo "$DOC_NAME" | sed "s|.*/documents/||")

    # Extract content and screenshots for Feedbucket parsing
    CONTENT=$(fs_string "$QUERY_RESULT" "content")
    SCREENSHOTS=$(fs_array "$QUERY_RESULT" "screenshots")

    # Handle QA Before (Feedbucket extraction)
    if [ "$DO_BEFORE" = "true" ]; then
        echo -e "  ${BLUE}Extracting Feedbucket image...${NC}"
        FEEDBUCKET_URL=$(extract_feedbucket_url_from_content "$CONTENT" "$SCREENSHOTS")

        if [ -z "$FEEDBUCKET_URL" ]; then
            echo -e "  ${YELLOW}No Feedbucket media found${NC}"
        else
            echo -e "  ${GREEN}Found Feedbucket image${NC}"
            # Upload to Firebase and update Firestore
            BEFORE_URL=$(upload_to_firebase "$FEEDBUCKET_URL" "$TICKET" "before")
            if [ -n "$BEFORE_URL" ]; then
                update_ticket_array "$DOC_PATH" "qaBefore" "$BEFORE_URL"
                echo -e "  ${GREEN}QA Before uploaded: $BEFORE_URL${NC}"
            fi
        fi
    fi

    # Handle QA After (local file upload)
    if [ -n "$AFTER_FILE" ]; then
        if [ ! -f "$AFTER_FILE" ]; then
            echo -e "  ${RED}File not found: $AFTER_FILE${NC}"
        else
            echo -e "  ${BLUE}Uploading QA After screenshot...${NC}"
            AFTER_UPLOAD_URL=$(upload_to_firebase "$AFTER_FILE" "$TICKET" "after")
            if [ -n "$AFTER_UPLOAD_URL" ]; then
                update_ticket_array "$DOC_PATH" "qaAfter" "$AFTER_UPLOAD_URL"
                echo -e "  ${GREEN}QA After uploaded: $AFTER_UPLOAD_URL${NC}"
            fi
        fi
    fi

    # Handle QA After (direct URL)
    if [ -n "$AFTER_URL" ]; then
        echo -e "  ${BLUE}Setting QA After URL...${NC}"
        AFTER_UPLOAD_URL=$(upload_to_firebase "$AFTER_URL" "$TICKET" "after")
        if [ -n "$AFTER_UPLOAD_URL" ]; then
            update_ticket_array "$DOC_PATH" "qaAfter" "$AFTER_UPLOAD_URL"
            echo -e "  ${GREEN}QA After set: $AFTER_UPLOAD_URL${NC}"
        fi
    fi

    # Handle QA After (capture via Browserless Cloud Function)
    if [ "$DO_CAPTURE_AFTER" = "true" ]; then
        echo -e "  ${BLUE}Capturing screenshot via Browserless...${NC}"

        # Extract Feedbucket metadata from content
        FB_METADATA=$(extract_feedbucket_metadata_from_content "$CONTENT")
        FB_VIEWPORT=$(echo "$FB_METADATA" | jq -r '.viewport // empty')
        FB_PAGE_URL=$(echo "$FB_METADATA" | jq -r '.page_url // empty')

        # Get pixel ratio and theme ID from cached metadata
        PIXEL_RATIO=$(jq -r '.pixel_ratio // "2"' "$METADATA_CACHE_DIR/$TICKET.json" 2>/dev/null || echo "2")
        THEME_ID=$(jq -r '.theme_id // empty' "$METADATA_CACHE_DIR/$TICKET.json" 2>/dev/null || echo "")

        # If theme ID not in cache, fetch from Firestore ticket or project
        if [ -z "$THEME_ID" ] || [ "$THEME_ID" = "null" ]; then
            echo -e "  ${BLUE}Theme ID not cached, checking Firestore...${NC}"
            THEME_ID=$(fs_string "$QUERY_RESULT" "shopifyThemeId")

            # If still empty, check the related Project
            if [ -z "$THEME_ID" ] || [ "$THEME_ID" = "null" ]; then
                PROJECT_ID=$(fs_string "$QUERY_RESULT" "projectId")
                if [ -n "$PROJECT_ID" ]; then
                    PROJECT_DOC=$(get_project_by_id "$PROJECT_ID")
                    THEME_ID=$(echo "$PROJECT_DOC" | jq -r '.fields.shopifyThemeId.stringValue // empty' 2>/dev/null)
                fi
            fi

            # Update cache if we found it
            if [ -n "$THEME_ID" ] && [ "$THEME_ID" != "null" ] && [ -f "$METADATA_CACHE_DIR/$TICKET.json" ]; then
                TMP_CACHE=$(mktemp)
                jq --arg tid "$THEME_ID" '.theme_id = $tid' "$METADATA_CACHE_DIR/$TICKET.json" > "$TMP_CACHE" && mv "$TMP_CACHE" "$METADATA_CACHE_DIR/$TICKET.json"
                echo -e "  ${GREEN}Found theme ID: $THEME_ID (cache updated)${NC}"
            fi
        fi

        # Parse viewport dimensions
        VIEWPORT_WIDTH=$(echo "$FB_VIEWPORT" | cut -d'x' -f1)
        VIEWPORT_HEIGHT=$(echo "$FB_VIEWPORT" | cut -d'x' -f2)

        if [ -z "$FB_PAGE_URL" ]; then
            echo -e "  ${RED}No page URL found in ticket${NC}"
        elif [ -z "$VIEWPORT_WIDTH" ] || [ -z "$VIEWPORT_HEIGHT" ]; then
            echo -e "  ${RED}No viewport found in ticket${NC}"
        else
            # Build capture URL with preview theme ID if available
            CAPTURE_URL="$FB_PAGE_URL"
            if [ -n "$THEME_ID" ] && [ "$THEME_ID" != "null" ]; then
                if [[ "$CAPTURE_URL" == *"?"* ]]; then
                    CAPTURE_URL="${CAPTURE_URL}&preview_theme_id=${THEME_ID}&pb=0"
                else
                    CAPTURE_URL="${CAPTURE_URL}?preview_theme_id=${THEME_ID}&pb=0"
                fi
                echo -e "  ${GREEN}URL: $CAPTURE_URL${NC}"
                echo -e "  ${GREEN}Theme ID: $THEME_ID (preview mode)${NC}"
            else
                echo -e "  ${YELLOW}No theme ID - capturing live site${NC}"
                echo -e "  ${GREEN}URL: $CAPTURE_URL${NC}"
            fi
            echo -e "  ${GREEN}Viewport: ${VIEWPORT_WIDTH}x${VIEWPORT_HEIGHT} @ ${PIXEL_RATIO}x${NC}"

            # Call Firebase function
            echo -e "  ${BLUE}Calling captureQAScreenshot function...${NC}"
            CAPTURE_RESULT=$(curl -s -X POST \
                "https://us-central1-bucky-app-355a3.cloudfunctions.net/captureQAScreenshot" \
                -H "Content-Type: application/json" \
                -d "{
                    \"data\": {
                        \"url\": \"$CAPTURE_URL\",
                        \"viewport\": {\"width\": $VIEWPORT_WIDTH, \"height\": $VIEWPORT_HEIGHT},
                        \"pixelRatio\": $PIXEL_RATIO,
                        \"ticketId\": \"$TICKET\"
                    }
                }")

            # Parse response
            if echo "$CAPTURE_RESULT" | jq -e '.result.success == true' > /dev/null 2>&1; then
                AFTER_UPLOAD_URL=$(echo "$CAPTURE_RESULT" | jq -r '.result.url')
                echo -e "  ${GREEN}Screenshot captured: $AFTER_UPLOAD_URL${NC}"

                # Update Firestore
                update_ticket_array "$DOC_PATH" "qaAfter" "$AFTER_UPLOAD_URL"
                echo -e "  ${GREEN}QA After updated in Firestore${NC}"
            else
                ERROR_MSG=$(echo "$CAPTURE_RESULT" | jq -r '.error.message // .error // "Unknown error"')
                echo -e "  ${RED}Capture failed: $ERROR_MSG${NC}"
                echo -e "  ${YELLOW}Response: $CAPTURE_RESULT${NC}"
            fi
        fi
    fi

    # If only doing screenshots (no status), return here
    if [ -z "$QA_STATUS" ]; then
        echo -e "  ${GREEN}Screenshot processing complete${NC}"
        return 0
    fi

    # Build QA summary and write to summary field
    QA_SUMMARY="QA: $QA_STATUS_DISPLAY | By: $QA_BY | Date: $QA_TIMESTAMP_DISPLAY | Batch: $QA_BATCH_ID"

    if [ -n "$QA_ENV" ]; then
        QA_SUMMARY="$QA_SUMMARY | Env: $QA_ENV"
    fi

    if [ -n "$PREVIEW_URL" ]; then
        QA_SUMMARY="$QA_SUMMARY | Preview: $PREVIEW_URL"
    fi

    if [ -n "$QA_NOTES" ]; then
        QA_SUMMARY="$QA_SUMMARY | Notes: $QA_NOTES"
    fi

    # Write to summary field
    update_ticket "$DOC_PATH" "summary" "$QA_SUMMARY" "string" > /dev/null
    echo -e "  ${GREEN}QA recorded: $QA_STATUS_DISPLAY${NC}"

    # If QA passed, update ticket status
    if [ "$QA_STATUS_LOWER" = "passed" ] || [ "$QA_STATUS_LOWER" = "pass" ]; then
        update_ticket "$DOC_PATH" "qaApproved" "true" "bool" > /dev/null 2>&1 || true
    fi

    return 0
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
mkdir -p "$QA_LOG_DIR" 2>/dev/null || true

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
    }' > "$QA_LOG_FILE" 2>/dev/null || true

echo ""
echo "QA log saved: $QA_LOG_FILE"
