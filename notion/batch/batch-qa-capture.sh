#!/bin/bash

# Batch QA Capture - Extract Feedbucket URLs and page URLs for QA verification
# Uses Chrome MCP for screenshot capture
#
# Usage:
#   ./batch-qa-capture.sh --project "#hs-figma" --range "1470-1568" --extract
#   ./batch-qa-capture.sh --project "#hs-figma" --range "1470-1568" --capture
#   ./batch-qa-capture.sh --ticket TICK-1470 --capture

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
QA_CAPTURE_FILE="$RESULTS_DIR/qa_capture_queue.json"

# Load Notion credentials
source ~/.bash_profile 2>/dev/null || true

if [ -z "$NOTION_API_KEY" ]; then
    echo -e "${RED}Error: NOTION_API_KEY not set${NC}"
    exit 1
fi

TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Extract URLs and capture QA screenshots for completed tickets"
    echo ""
    echo "Options:"
    echo "  --project PROJECT    Filter by project tag (e.g., '#hs-figma')"
    echo "  --range MIN-MAX      Filter by ticket range (e.g., '1470-1568')"
    echo "  --ticket TICK-###    Process single ticket"
    echo "  --extract            Extract URLs from tickets (creates qa_capture_queue.json)"
    echo "  --capture            Capture screenshots using Chrome MCP"
    echo "  --status             Show current queue status"
    echo "  --help               Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --project '#hs-figma' --range '1470-1568' --extract"
    echo "  $0 --capture"
    exit 0
}

# Extract page URL from ticket blocks
extract_page_url() {
    local PAGE_ID="$1"

    curl -s -X GET "https://api.notion.com/v1/blocks/$PAGE_ID/children?page_size=100" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" | jq -r '
        [.results[] |
         select(.type == "paragraph") |
         .paragraph.rich_text[]? |
         select(.text.link.url != null) |
         select(.text.link.url | test("store\\.figma\\.com|shopify"; "i")) |
         .text.link.url
        ] | first // empty
    ' | sed 's/\?feedbucketIssue=[0-9]*//'
}

# Extract Feedbucket image URL from ticket blocks
extract_feedbucket_url() {
    local PAGE_ID="$1"

    curl -s -X GET "https://api.notion.com/v1/blocks/$PAGE_ID/children?page_size=100" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" | jq -r '
        [.results[] |
         select(.type == "image") |
         (.image.external.url // .image.file.url)
        ] | first // empty
    '
}

# Get completed tickets needing QA
get_tickets_needing_qa() {
    local PROJECT="$1"
    local RANGE_MIN="$2"
    local RANGE_MAX="$3"

    # Build filter
    local FILTER='{"and": [
        {"property": "QA Before", "files": {"is_empty": true}},
        {"property": "Ticket Status", "status": {"equals": "Complete"}}'

    if [ -n "$PROJECT" ]; then
        FILTER="$FILTER, {\"property\": \"Name\", \"title\": {\"contains\": \"$PROJECT\"}}"
    fi

    if [ -n "$RANGE_MIN" ] && [ -n "$RANGE_MAX" ]; then
        FILTER="$FILTER, {\"property\": \"ID\", \"unique_id\": {\"greater_than_or_equal_to\": $RANGE_MIN}}"
        FILTER="$FILTER, {\"property\": \"ID\", \"unique_id\": {\"less_than_or_equal_to\": $RANGE_MAX}}"
    fi

    FILTER="$FILTER]}"

    curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d "{\"filter\": $FILTER, \"page_size\": 100}" | jq -r '
        .results[] | {
            ticket_id: "TICK-\(.properties.ID.unique_id.number)",
            ticket_number: .properties.ID.unique_id.number,
            name: .properties.Name.title[0].plain_text,
            page_id: .id,
            status: .properties["Ticket Status"].status.name
        }
    '
}

# Extract URLs for all tickets and save to queue
extract_urls() {
    local PROJECT="$1"
    local RANGE_MIN="$2"
    local RANGE_MAX="$3"

    echo -e "${BLUE}Extracting URLs for QA capture...${NC}"
    echo ""

    # Get tickets
    TICKETS=$(get_tickets_needing_qa "$PROJECT" "$RANGE_MIN" "$RANGE_MAX")
    TICKET_COUNT=$(echo "$TICKETS" | jq -s 'length')

    echo -e "Found ${GREEN}$TICKET_COUNT${NC} completed tickets needing QA"
    echo ""

    # Process each ticket
    QUEUE="[]"
    PROCESSED=0

    echo "$TICKETS" | jq -c '.' | while read -r ticket; do
        TICKET_ID=$(echo "$ticket" | jq -r '.ticket_id')
        NAME=$(echo "$ticket" | jq -r '.name')
        PAGE_ID=$(echo "$ticket" | jq -r '.page_id' | tr -d '-')

        echo -ne "  Processing $TICKET_ID... "

        # Extract URLs
        FEEDBUCKET_URL=$(extract_feedbucket_url "$PAGE_ID")
        PAGE_URL=$(extract_page_url "$PAGE_ID")

        if [ -n "$FEEDBUCKET_URL" ] && [ -n "$PAGE_URL" ]; then
            echo -e "${GREEN}✓${NC} $PAGE_URL"

            # Append to queue file
            jq -n \
                --arg ticket_id "$TICKET_ID" \
                --arg name "$NAME" \
                --arg page_id "$PAGE_ID" \
                --arg feedbucket_url "$FEEDBUCKET_URL" \
                --arg page_url "$PAGE_URL" \
                --arg status "pending" \
                '{
                    ticket_id: $ticket_id,
                    name: $name,
                    page_id: $page_id,
                    feedbucket_url: $feedbucket_url,
                    page_url: $page_url,
                    status: $status
                }' >> "$RESULTS_DIR/qa_capture_queue.tmp"
        elif [ -z "$FEEDBUCKET_URL" ]; then
            echo -e "${YELLOW}⚠ No Feedbucket image${NC}"
        else
            echo -e "${YELLOW}⚠ No page URL found${NC}"
        fi

        PROCESSED=$((PROCESSED + 1))
    done

    # Combine into JSON array
    if [ -f "$RESULTS_DIR/qa_capture_queue.tmp" ]; then
        jq -s '.' "$RESULTS_DIR/qa_capture_queue.tmp" > "$QA_CAPTURE_FILE"
        rm "$RESULTS_DIR/qa_capture_queue.tmp"

        QUEUE_COUNT=$(jq 'length' "$QA_CAPTURE_FILE")
        echo ""
        echo -e "${GREEN}✓ Queue saved: $QA_CAPTURE_FILE${NC}"
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
PROJECT=""
RANGE=""
RANGE_MIN=""
RANGE_MAX=""
TICKET=""
DO_EXTRACT="false"
DO_CAPTURE="false"
DO_STATUS="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --range)
            RANGE="$2"
            RANGE_MIN=$(echo "$2" | cut -d'-' -f1)
            RANGE_MAX=$(echo "$2" | cut -d'-' -f2)
            shift 2
            ;;
        --ticket)
            TICKET="$2"
            shift 2
            ;;
        --extract)
            DO_EXTRACT="true"
            shift
            ;;
        --capture)
            DO_CAPTURE="true"
            shift
            ;;
        --status)
            DO_STATUS="true"
            shift
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

# Execute commands
if [ "$DO_STATUS" = "true" ]; then
    show_status
    exit 0
fi

if [ "$DO_EXTRACT" = "true" ]; then
    extract_urls "$PROJECT" "$RANGE_MIN" "$RANGE_MAX"
    exit 0
fi

if [ "$DO_CAPTURE" = "true" ]; then
    echo -e "${YELLOW}Capture mode requires Chrome MCP integration.${NC}"
    echo ""
    echo "To capture screenshots, use Claude Code with Chrome MCP:"
    echo ""
    echo "1. Run: ./batch-qa-capture.sh --extract"
    echo "2. Ask Claude Code to process the queue using Chrome MCP"
    echo ""
    show_status
    exit 0
fi

# Default: show usage
show_usage
