#!/bin/bash
# quote-batch-fetch.sh - Batch fetch ticket details for quote analysis (Firestore-backed)
# Usage: ./quote-batch-fetch.sh [ticket_list_file]
# Default: /tmp/quote-analysis/not_completed.txt

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_firestore-lib.sh"

OUTPUT_DIR="/tmp/quote-analysis"
TICKET_LIST="${1:-$OUTPUT_DIR/not_completed.txt}"
FETCHED_DIR="$OUTPUT_DIR/fetched_tickets"
COMPLETED_COMMITS="$OUTPUT_DIR/completed_commits.txt"

mkdir -p "$FETCHED_DIR"

if [ ! -f "$TICKET_LIST" ]; then
    echo -e "${RED}Error: Ticket list not found: $TICKET_LIST${NC}"
    echo "Run quote-analyzer.sh first to generate the list."
    exit 1
fi

TOTAL=$(wc -l < "$TICKET_LIST" | tr -d ' ')
CURRENT=0

echo -e "${BLUE}=== Quote Batch Fetch ===${NC}"
echo "Fetching $TOTAL tickets from Firestore..."
echo "Output directory: $FETCHED_DIR"
echo ""

# Keywords extracted from completed commits for similarity matching
KEYWORDS_FILE="$OUTPUT_DIR/keywords.txt"
if [ -f "$COMPLETED_COMMITS" ]; then
    cat "$COMPLETED_COMMITS" | tr '[:upper:]' '[:lower:]' | \
        grep -oE '\b(padding|margin|spacing|font|size|mobile|desktop|hover|button|cart|bag|checkout|header|footer|nav|menu|filter|sort|grid|layout|breadcrumb|pdp|product|collection|hero|animation|faq|contact|newsletter|color|opacity|width|height|quick.add|sold.out|carousel|gallery|swipe|banner|badge|editorial|responsive|centering|alignment|gap|underline|icon)\b' | \
        sort | uniq -c | sort -rn > "$KEYWORDS_FILE"

    echo "Keywords extracted from completed work:"
    head -20 "$KEYWORDS_FILE"
    echo ""
fi

while IFS= read -r TICKET; do
    ((CURRENT++))
    OUTFILE="$FETCHED_DIR/${TICKET}.json"

    echo -ne "\r${CYAN}[$CURRENT/$TOTAL]${NC} Fetching $TICKET...          "

    # Skip if already fetched
    if [ -f "$OUTFILE" ] && [ -s "$OUTFILE" ]; then
        echo -ne "\r${CYAN}[$CURRENT/$TOTAL]${NC} $TICKET - ${YELLOW}cached${NC}          "
        continue
    fi

    # Fetch using read-only quote-fetch-ticket.sh (Firestore-backed)
    if "$SCRIPT_DIR/quote-fetch-ticket.sh" "$TICKET" > "$OUTFILE" 2>/dev/null; then
        # Verify we got valid JSON
        if ! jq -e . "$OUTFILE" >/dev/null 2>&1; then
            echo "{\"ticket\": \"$TICKET\", \"error\": \"invalid_json\"}" > "$OUTFILE"
        fi
    else
        echo "{\"ticket\": \"$TICKET\", \"error\": \"fetch_failed\"}" > "$OUTFILE"
    fi

    # Small delay to be nice to Firestore
    sleep 0.1

done < "$TICKET_LIST"

echo ""
echo ""
echo -e "${GREEN}=== Fetch Complete ===${NC}"
echo "Fetched tickets saved to: $FETCHED_DIR"
echo ""
echo "Next step: Run quote-compare.sh to analyze similarities"
