#!/bin/bash

# Compare QA Before/After screenshots for a ticket (Firestore-backed)
# Usage: ./compare-screenshots.sh TICK-###
#
# Opens both QA Before and QA After screenshots for visual comparison

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_firestore-lib.sh"

show_usage() {
    echo "Usage: $0 TICKET-ID [OPTIONS]"
    echo ""
    echo "Compare QA Before/After screenshots from ticket."
    echo ""
    echo "Options:"
    echo "  --open, -o         Open images in browser/viewer"
    echo "  --json, -j         Output as JSON"
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

# Query Firestore
QUERY_RESULT=$(query_ticket "$TICKET_ID")

DOC_NAME=$(echo "$QUERY_RESULT" | jq -r '.[0].document.name // empty')

if [ -z "$DOC_NAME" ]; then
    if [ "$OUTPUT_JSON" = "true" ]; then
        echo '{"error": "Ticket not found", "ticket": "'"$TICKET_ID"'"}'
    else
        echo -e "${RED}Error: Ticket $TICKET_ID not found${NC}" >&2
    fi
    exit 1
fi

DOC_PATH=$(echo "$DOC_NAME" | sed "s|.*/documents/||")

# Extract fields
TITLE=$(fs_string "$QUERY_RESULT" "name")

# Extract QA Before/After from array fields
QA_BEFORE=$(echo "$QUERY_RESULT" | jq -r '.[0].document.fields.qaBefore.arrayValue.values[0].stringValue // empty' 2>/dev/null)
QA_AFTER=$(echo "$QUERY_RESULT" | jq -r '.[0].document.fields.qaAfter.arrayValue.values[0].stringValue // empty' 2>/dev/null)

# Output results
if [ "$OUTPUT_JSON" = "true" ]; then
    jq -n \
        --arg ticket "$TICKET_ID" \
        --arg title "$TITLE" \
        --arg before "$QA_BEFORE" \
        --arg after "$QA_AFTER" \
        --arg doc_path "$DOC_PATH" \
        '{
            ticket: $ticket,
            title: $title,
            qa_before: (if $before == "" then null else $before end),
            qa_after: (if $after == "" then null else $after end),
            doc_path: $doc_path,
            comparison_ready: ($before != "" and $after != "")
        }'
else
    echo -e "${BLUE}QA Comparison: $TICKET_ID${NC}"
    echo "Title: $TITLE"
    echo ""

    if [ -n "$QA_BEFORE" ]; then
        echo -e "${GREEN}QA Before:${NC} $QA_BEFORE"
    else
        echo -e "${YELLOW}QA Before:${NC} Not set"
    fi

    if [ -n "$QA_AFTER" ]; then
        echo -e "${GREEN}QA After:${NC} $QA_AFTER"
    else
        echo -e "${YELLOW}QA After:${NC} Not set"
    fi

    echo ""

    if [ -n "$QA_BEFORE" ] && [ -n "$QA_AFTER" ]; then
        echo -e "${GREEN}Ready for comparison${NC}"
    elif [ -z "$QA_BEFORE" ] && [ -z "$QA_AFTER" ]; then
        echo -e "${RED}No QA images available${NC}"
    else
        echo -e "${YELLOW}Partial QA - one image missing${NC}"
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
