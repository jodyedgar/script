#!/bin/bash

# Fetch tickets by batch/category from categorized results (Firestore-backed)
# Usage:
#   ./ticket-batch-fetch.sh --category pdp
#   ./ticket-batch-fetch.sh --priority P1-QuickWins
#   ./ticket-batch-fetch.sh --batch pdp-P1-QuickWins
#   ./ticket-batch-fetch.sh --from-file /path/to/ticket-ids.txt
#   ./ticket-batch-fetch.sh --list-categories

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_firestore-lib.sh"

# Default paths
DEFAULT_CATEGORIZED_FILE="$HOME/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests/results/categorized_tickets.json"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Fetch multiple tickets by category, priority, or batch."
    echo ""
    echo "Options:"
    echo "  --category, -c CATEGORY    Fetch all tickets in a category"
    echo "  --priority, -p PRIORITY    Fetch all tickets with priority"
    echo "  --batch, -b BATCH_KEY      Fetch tickets by batch key"
    echo "  --from-file, -f FILE       Fetch tickets from file (one TICK-### per line)"
    echo "  --limit, -l NUMBER         Limit number of tickets to fetch"
    echo "  --list-categories          List available categories"
    echo "  --list-batches             List available batches"
    echo "  --list-priorities          List available priorities"
    echo "  --output, -o DIR           Output directory (default: /tmp/batch-tickets)"
    echo "  --dry-run                  Show what would be fetched"
    echo "  --json                     Output as JSON"
    echo "  --categorized-file FILE    Path to categorized_tickets.json"
    echo "  --help, -h                 Show this help"
    exit 1
}

# Parse arguments
CATEGORY=""
PRIORITY=""
BATCH_KEY=""
FROM_FILE=""
LIMIT=""
LIST_CATEGORIES=false
LIST_BATCHES=false
LIST_PRIORITIES=false
OUTPUT_DIR="/tmp/batch-tickets"
DRY_RUN=false
JSON_OUTPUT=false
CATEGORIZED_FILE="$DEFAULT_CATEGORIZED_FILE"

while [[ $# -gt 0 ]]; do
    case $1 in
        --category|-c) CATEGORY="$2"; shift 2 ;;
        --priority|-p) PRIORITY="$2"; shift 2 ;;
        --batch|-b) BATCH_KEY="$2"; shift 2 ;;
        --from-file|-f) FROM_FILE="$2"; shift 2 ;;
        --limit|-l) LIMIT="$2"; shift 2 ;;
        --list-categories) LIST_CATEGORIES=true; shift ;;
        --list-batches) LIST_BATCHES=true; shift ;;
        --list-priorities) LIST_PRIORITIES=true; shift ;;
        --output|-o) OUTPUT_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --json) JSON_OUTPUT=true; shift ;;
        --categorized-file) CATEGORIZED_FILE="$2"; shift 2 ;;
        --help|-h) show_usage ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; show_usage ;;
    esac
done

# Check if categorized file exists
if [ ! -f "$CATEGORIZED_FILE" ]; then
    echo -e "${RED}Error: Categorized tickets file not found: $CATEGORIZED_FILE${NC}"
    echo "Run the categorization first."
    exit 1
fi

# List categories
if [ "$LIST_CATEGORIES" = true ]; then
    echo -e "${BLUE}Available Categories:${NC}"
    echo ""
    cat "$CATEGORIZED_FILE" | jq -r '
        group_by(.category) |
        map({category: .[0].category, count: length}) |
        sort_by(-.count) |
        .[] |
        "  \(.category): \(.count) tickets"'
    exit 0
fi

# List batches
if [ "$LIST_BATCHES" = true ]; then
    echo -e "${BLUE}Available Batches:${NC}"
    echo ""
    cat "$CATEGORIZED_FILE" | jq -r '
        group_by(.batch_key) |
        map({batch_key: .[0].batch_key, category: .[0].category, priority: .[0].priority_label, count: length}) |
        sort_by(.priority, .category) |
        .[] |
        "  \(.batch_key): \(.count) tickets (\(.priority))"'
    exit 0
fi

# List priorities
if [ "$LIST_PRIORITIES" = true ]; then
    echo -e "${BLUE}Available Priorities:${NC}"
    echo ""
    cat "$CATEGORIZED_FILE" | jq -r '
        group_by(.priority_label) |
        map({priority: .[0].priority_label, count: length}) |
        sort_by(.priority) |
        .[] |
        "  \(.priority): \(.count) tickets"'
    exit 0
fi

# Validate that at least one filter is specified
if [ -z "$CATEGORY" ] && [ -z "$PRIORITY" ] && [ -z "$BATCH_KEY" ] && [ -z "$FROM_FILE" ]; then
    echo -e "${RED}Error: Specify --category, --priority, --batch, or --from-file${NC}"
    show_usage
fi

# Build ticket list based on filter
TICKET_IDS=""

if [ -n "$FROM_FILE" ]; then
    if [ ! -f "$FROM_FILE" ]; then
        echo -e "${RED}Error: File not found: $FROM_FILE${NC}"
        exit 1
    fi
    TICKET_IDS=$(cat "$FROM_FILE" | grep -E "^TICK-[0-9]+" | head -n "${LIMIT:-9999}")
elif [ -n "$BATCH_KEY" ]; then
    TICKET_IDS=$(cat "$CATEGORIZED_FILE" | jq -r --arg key "$BATCH_KEY" '
        [.[] | select(.batch_key == $key)] |
        .[0:'"${LIMIT:-9999}"'] |
        .[].id')
elif [ -n "$CATEGORY" ]; then
    TICKET_IDS=$(cat "$CATEGORIZED_FILE" | jq -r --arg cat "$CATEGORY" '
        [.[] | select(.category == $cat)] |
        .[0:'"${LIMIT:-9999}"'] |
        .[].id')
elif [ -n "$PRIORITY" ]; then
    TICKET_IDS=$(cat "$CATEGORIZED_FILE" | jq -r --arg pri "$PRIORITY" '
        [.[] | select(.priority_label == $pri)] |
        .[0:'"${LIMIT:-9999}"'] |
        .[].id')
fi

# Count tickets
TICKET_COUNT=$(echo "$TICKET_IDS" | grep -c "TICK-" || echo "0")

if [ "$TICKET_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No tickets found matching the filter${NC}"
    exit 0
fi

echo -e "${BLUE}Found $TICKET_COUNT tickets to fetch${NC}"
echo ""

# Dry run
if [ "$DRY_RUN" = true ]; then
    echo "Would fetch:"
    echo "$TICKET_IDS" | while read -r ticket_id; do
        if [ -n "$ticket_id" ]; then
            NAME=$(cat "$CATEGORIZED_FILE" | jq -r --arg id "$ticket_id" '.[] | select(.id == $id) | .name')
            echo "  - $ticket_id: $NAME"
        fi
    done
    exit 0
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Fetch each ticket from Firestore
FETCHED=0
echo "$TICKET_IDS" | while read -r ticket_id; do
    if [ -z "$ticket_id" ]; then
        continue
    fi

    FETCHED=$((FETCHED + 1))
    echo -e "${GREEN}[$FETCHED/$TICKET_COUNT]${NC} Fetching $ticket_id..."

    # Query Firestore
    RESULT=$(query_ticket "$ticket_id")
    DOC_NAME=$(echo "$RESULT" | jq -r '.[0].document.name // empty')

    if [ -z "$DOC_NAME" ]; then
        echo -e "  ${RED}Not found${NC}"
        continue
    fi

    # Extract fields
    TITLE=$(fs_string "$RESULT" "name")
    STATUS=$(fs_string "$RESULT" "status")
    COMPLEXITY=$(fs_string "$RESULT" "ticketComplexity")
    CONTENT=$(fs_string "$RESULT" "content")

    echo "  Title: $TITLE"
    echo "  Status: $STATUS | Complexity: $COMPLEXITY"

    # Save to output directory
    TICKET_DIR="$OUTPUT_DIR/$ticket_id"
    mkdir -p "$TICKET_DIR"

    # Save full query result
    echo "$RESULT" > "$TICKET_DIR/details.json"

    # Create summary file
    cat > "$TICKET_DIR/summary.txt" << EOF
Ticket: $ticket_id
Title: $TITLE
Status: $STATUS
Complexity: $COMPLEXITY
Fetched: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    # Save content
    if [ -n "$CONTENT" ]; then
        echo "$CONTENT" > "$TICKET_DIR/content.txt"
    fi

    echo -e "  ${GREEN}Saved to $TICKET_DIR${NC}"
    echo ""
done

# Create batch summary
echo -e "${GREEN}Batch fetch complete!${NC}"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo "Tickets fetched: $TICKET_COUNT"
echo ""
echo "Next steps:"
echo "  1. Review tickets in $OUTPUT_DIR"
echo "  2. Process the batch"
echo "  3. Run: ticket-batch-complete.sh --from-dir $OUTPUT_DIR"
