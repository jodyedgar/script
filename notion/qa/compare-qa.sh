#!/bin/bash

# Compare QA Before/After screenshots for a ticket
# Usage: ./compare-qa.sh TICK-###
#
# Opens both QA Before and QA After screenshots for visual comparison

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Notion config
TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

show_usage() {
    echo "Usage: $0 TICKET-ID [OPTIONS]"
    echo ""
    echo "Compare QA Before/After screenshots from Notion ticket."
    echo ""
    echo "Options:"
    echo "  --open, -o         Open images in browser/viewer"
    echo "  --json, -j         Output as JSON"
    echo "  --side-by-side     Download and create side-by-side comparison"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 TICK-1234           # Show URLs"
    echo "  $0 TICK-1234 --open    # Open in browser"
    echo "  $0 TICK-1234 --json    # JSON output"
    exit 1
}

# Parse arguments
TICKET_ID=""
DO_OPEN="false"
OUTPUT_JSON="false"
SIDE_BY_SIDE="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        TICK-*|tick-*)
            TICKET_ID=$(echo "$1" | tr '[:lower:]' '[:upper:]')
            shift
            ;;
        --open|-o)
            DO_OPEN="true"
            shift
            ;;
        --json|-j)
            OUTPUT_JSON="true"
            shift
            ;;
        --side-by-side)
            SIDE_BY_SIDE="true"
            shift
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            show_usage
            ;;
    esac
done

if [ -z "$TICKET_ID" ]; then
    echo -e "${RED}Error: TICKET-ID required${NC}" >&2
    show_usage
fi

# Load Notion credentials
if [ -f "$HOME/.bash_profile" ]; then
    source "$HOME/.bash_profile"
fi

if [ -z "$NOTION_API_KEY" ]; then
    echo -e "${RED}Error: NOTION_API_KEY not set${NC}" >&2
    exit 1
fi

TICKET_NUMBER=$(echo "$TICKET_ID" | sed 's/TICK-//')

# Look up page
DATABASE_QUERY=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
    -H "Authorization: Bearer $NOTION_API_KEY" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d "{\"filter\": {\"property\": \"ID\", \"unique_id\": {\"equals\": $TICKET_NUMBER}}}")

PAGE_ID=$(echo "$DATABASE_QUERY" | jq -r '.results[0].id // empty')

if [ -z "$PAGE_ID" ]; then
    if [ "$OUTPUT_JSON" = "true" ]; then
        echo '{"error": "Ticket not found", "ticket": "'"$TICKET_ID"'"}'
    else
        echo -e "${RED}Error: Ticket $TICKET_ID not found${NC}" >&2
    fi
    exit 1
fi

# Get page with properties
PAGE_DATA=$(curl -s -X GET "https://api.notion.com/v1/pages/$PAGE_ID" \
    -H "Authorization: Bearer $NOTION_API_KEY" \
    -H "Notion-Version: 2022-06-28")

# Extract QA Before URL
QA_BEFORE=$(echo "$PAGE_DATA" | jq -r '
    .properties["QA Before"].files[0].external.url //
    .properties["QA Before"].files[0].file.url //
    empty
')

# Extract QA After URL
QA_AFTER=$(echo "$PAGE_DATA" | jq -r '
    .properties["QA After"].files[0].external.url //
    .properties["QA After"].files[0].file.url //
    empty
')

# Get ticket title
TITLE=$(echo "$PAGE_DATA" | jq -r '.properties["Ticket Summary"].title[0].plain_text // .properties.Name.title[0].plain_text // "Unknown"')

# Output results
if [ "$OUTPUT_JSON" = "true" ]; then
    jq -n \
        --arg ticket "$TICKET_ID" \
        --arg title "$TITLE" \
        --arg before "$QA_BEFORE" \
        --arg after "$QA_AFTER" \
        --arg page_id "$PAGE_ID" \
        '{
            ticket: $ticket,
            title: $title,
            qa_before: (if $before == "" then null else $before end),
            qa_after: (if $after == "" then null else $after end),
            page_id: $page_id,
            comparison_ready: ($before != "" and $after != "")
        }'
else
    echo -e "${BLUE}QA Comparison: $TICKET_ID${NC}"
    echo "Title: $TITLE"
    echo ""

    if [ -n "$QA_BEFORE" ]; then
        echo -e "${GREEN}✓ QA Before:${NC} $QA_BEFORE"
    else
        echo -e "${YELLOW}⚠ QA Before:${NC} Not set"
    fi

    if [ -n "$QA_AFTER" ]; then
        echo -e "${GREEN}✓ QA After:${NC} $QA_AFTER"
    else
        echo -e "${YELLOW}⚠ QA After:${NC} Not set"
    fi

    echo ""

    if [ -n "$QA_BEFORE" ] && [ -n "$QA_AFTER" ]; then
        echo -e "${GREEN}✓ Ready for comparison${NC}"
    elif [ -z "$QA_BEFORE" ] && [ -z "$QA_AFTER" ]; then
        echo -e "${RED}✗ No QA images available${NC}"
    else
        echo -e "${YELLOW}⚠ Partial QA - one image missing${NC}"
    fi
fi

# Open in browser if requested
if [ "$DO_OPEN" = "true" ]; then
    if [ -n "$QA_BEFORE" ]; then
        open "$QA_BEFORE" 2>/dev/null || xdg-open "$QA_BEFORE" 2>/dev/null || true
    fi
    if [ -n "$QA_AFTER" ]; then
        open "$QA_AFTER" 2>/dev/null || xdg-open "$QA_AFTER" 2>/dev/null || true
    fi
fi
