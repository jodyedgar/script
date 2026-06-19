#!/bin/bash

# Batch QA Capture - Extract Feedbucket URLs and page URLs for QA (Firestore-backed)
#
# Usage:
#   ./qa-capture.sh --status Complete --extract
#   ./qa-capture.sh --range "1470-1568" --extract
#   ./qa-capture.sh --ticket TICK-1470 --capture
#   ./qa-capture.sh --status

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_firestore-lib.sh"

# Results directory
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"
QA_CAPTURE_FILE="$RESULTS_DIR/qa_capture_queue.json"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Extract URLs and capture QA screenshots for completed tickets"
    echo ""
    echo "Options:"
    echo "  --range MIN-MAX      Filter by ticket range (e.g., '1470-1568')"
    echo "  --ticket TICK-###    Process single ticket"
    echo "  --extract            Extract URLs from tickets (creates qa_capture_queue.json)"
    echo "  --capture            Capture screenshots using Chrome MCP"
    echo "  --status             Show current queue status"
    echo "  --help               Show this help"
    exit 0
}

# Extract page URL and Feedbucket URL from ticket content
extract_urls_from_content() {
    local CONTENT="$1"
    local PAGE_URL=""
    local FB_URL=""

    if [ -n "$CONTENT" ]; then
        PAGE_URL=$(echo "$CONTENT" | grep -oE 'Page:\s*https?://[^ ]+' | grep -oE 'https?://[^ ]+' | head -1 || true)
        FB_URL=$(echo "$CONTENT" | grep -oE 'https://[^ ]*(feedbucket|fb-media|cdn\.feedbucket)[^ ]*' | head -1 || true)
    fi

    jq -n --arg page_url "$PAGE_URL" --arg fb_url "$FB_URL" '{page_url: $page_url, feedbucket_url: $fb_url}'
}

# Extract URLs for tickets in range
extract_urls() {
    local RANGE_MIN="$1"
    local RANGE_MAX="$2"

    echo -e "${BLUE}Extracting URLs for QA capture...${NC}"
    echo ""

    # Fetch tickets from Firestore
    echo "Querying Firestore for tickets $RANGE_MIN-$RANGE_MAX..."
    TICKETS=$(query_tickets_range "$RANGE_MIN" "$RANGE_MAX")

    TICKET_COUNT=$(echo "$TICKETS" | jq '[.[] | select(.document != null)] | length')
    echo -e "Found ${GREEN}$TICKET_COUNT${NC} tickets"
    echo ""

    # Process each ticket
    rm -f "$RESULTS_DIR/qa_capture_queue.tmp"

    echo "$TICKETS" | jq -c '.[] | select(.document != null) | .document' | while read -r doc; do
        TICKET_NUM=$(echo "$doc" | jq -r '.fields.ticketNumber.integerValue // "0"')
        TICKET_ID="TICK-$TICKET_NUM"
        NAME=$(echo "$doc" | jq -r '.fields.name.stringValue // "Untitled"')
        STATUS=$(echo "$doc" | jq -r '.fields.status.stringValue // "Unknown"')
        CONTENT=$(echo "$doc" | jq -r '.fields.content.stringValue // ""')
        DOC_PATH=$(echo "$doc" | jq -r '.name' | sed "s|.*/documents/||")

        # Check if QA Before already exists
        QA_BEFORE=$(echo "$doc" | jq -r '.fields.qaBefore.arrayValue.values[0].stringValue // empty')

        # Only process completed tickets without QA Before
        if [[ "$STATUS" != "Complete" ]] && [[ "$STATUS" != "Done" ]]; then
            continue
        fi

        if [ -n "$QA_BEFORE" ]; then
            continue
        fi

        echo -ne "  Processing $TICKET_ID... "

        # Extract URLs from content
        URLS=$(extract_urls_from_content "$CONTENT")
        FB_URL=$(echo "$URLS" | jq -r '.feedbucket_url')
        PAGE_URL=$(echo "$URLS" | jq -r '.page_url')

        if [ -n "$FB_URL" ] && [ -n "$PAGE_URL" ]; then
            echo -e "${GREEN}${NC} $PAGE_URL"

            jq -n \
                --arg ticket_id "$TICKET_ID" \
                --arg name "$NAME" \
                --arg doc_path "$DOC_PATH" \
                --arg feedbucket_url "$FB_URL" \
                --arg page_url "$PAGE_URL" \
                --arg status "pending" \
                '{
                    ticket_id: $ticket_id,
                    name: $name,
                    doc_path: $doc_path,
                    feedbucket_url: $feedbucket_url,
                    page_url: $page_url,
                    status: $status
                }' >> "$RESULTS_DIR/qa_capture_queue.tmp"
        elif [ -z "$FB_URL" ]; then
            echo -e "${YELLOW}No Feedbucket image${NC}"
        else
            echo -e "${YELLOW}No page URL found${NC}"
        fi
    done

    # Combine into JSON array
    if [ -f "$RESULTS_DIR/qa_capture_queue.tmp" ]; then
        jq -s '.' "$RESULTS_DIR/qa_capture_queue.tmp" > "$QA_CAPTURE_FILE"
        rm "$RESULTS_DIR/qa_capture_queue.tmp"

        QUEUE_COUNT=$(jq 'length' "$QA_CAPTURE_FILE")
        echo ""
        echo -e "${GREEN}Queue saved: $QA_CAPTURE_FILE${NC}"
        echo -e "  ${BLUE}$QUEUE_COUNT${NC} tickets ready for capture"
    else
        echo ""
        echo -e "${YELLOW}No tickets with valid URLs found${NC}"
    fi
}

# Show queue status
show_status() {
    if [ ! -f "$QA_CAPTURE_FILE" ]; then
        echo -e "${YELLOW}No capture queue found. Run --extract first.${NC}"
        exit 1
    fi

    echo -e "${BLUE}QA Capture Queue Status${NC}"
    echo "========================"
    echo ""

    TOTAL=$(jq 'length' "$QA_CAPTURE_FILE")
    PENDING=$(jq '[.[] | select(.status == "pending")] | length' "$QA_CAPTURE_FILE")
    CAPTURED=$(jq '[.[] | select(.status == "captured")] | length' "$QA_CAPTURE_FILE")
    UPLOADED=$(jq '[.[] | select(.status == "uploaded")] | length' "$QA_CAPTURE_FILE")
    FAILED=$(jq '[.[] | select(.status == "failed")] | length' "$QA_CAPTURE_FILE")

    echo "Total:    $TOTAL"
    echo "Pending:  $PENDING"
    echo "Captured: $CAPTURED"
    echo "Uploaded: $UPLOADED"
    echo "Failed:   $FAILED"
    echo ""

    if [ "$PENDING" -gt 0 ]; then
        echo "Next tickets to capture:"
        jq -r '.[] | select(.status == "pending") | "  \(.ticket_id): \(.page_url)"' "$QA_CAPTURE_FILE" | head -5
    fi
}

# Parse arguments
RANGE=""
RANGE_MIN=""
RANGE_MAX=""
TICKET=""
DO_EXTRACT="false"
DO_CAPTURE="false"
DO_STATUS="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --range)
            RANGE="$2"
            RANGE_MIN=$(echo "$2" | cut -d'-' -f1)
            RANGE_MAX=$(echo "$2" | cut -d'-' -f2)
            shift 2
            ;;
        --ticket) TICKET="$2"; shift 2 ;;
        --extract) DO_EXTRACT="true"; shift ;;
        --capture) DO_CAPTURE="true"; shift ;;
        --status) DO_STATUS="true"; shift ;;
        --help|-h) show_usage ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; show_usage ;;
    esac
done

# Execute commands
if [ "$DO_STATUS" = "true" ]; then
    show_status
    exit 0
fi

if [ "$DO_EXTRACT" = "true" ]; then
    if [ -z "$RANGE_MIN" ] || [ -z "$RANGE_MAX" ]; then
        echo -e "${RED}Error: --range required with --extract${NC}"
        exit 1
    fi
    extract_urls "$RANGE_MIN" "$RANGE_MAX"
    exit 0
fi

if [ "$DO_CAPTURE" = "true" ]; then
    echo -e "${YELLOW}Capture mode requires Chrome MCP integration.${NC}"
    echo ""
    echo "To capture screenshots, use Claude Code with Chrome MCP:"
    echo ""
    echo "1. Run: $0 --extract --range MIN-MAX"
    echo "2. Ask Claude Code to process the queue using Chrome MCP"
    echo ""
    show_status
    exit 0
fi

show_usage
