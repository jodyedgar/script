#!/bin/bash

# Fetch tickets by batch/category from categorized results
# Usage:
#   ./fetch-batch.sh --category pdp
#   ./fetch-batch.sh --priority P1-QuickWins
#   ./fetch-batch.sh --batch pdp-P1-QuickWins
#   ./fetch-batch.sh --from-file /path/to/ticket-ids.txt
#   ./fetch-batch.sh --list-categories
#   ./fetch-batch.sh --list-batches
#
# This script integrates with the categorization system to fetch
# multiple tickets at once for batch processing.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CATEGORIZED_FILE="$HOME/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests/results/categorized_tickets.json"
DEFAULT_BATCHES_FILE="$HOME/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests/results/batches.json"

# Notion config
TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Fetch multiple tickets by category, priority, or batch."
    echo ""
    echo "Options:"
    echo "  --category, -c CATEGORY    Fetch all tickets in a category (e.g., pdp, cart, header-nav)"
    echo "  --priority, -p PRIORITY    Fetch all tickets with priority (e.g., P1-QuickWins, P2-Structural)"
    echo "  --batch, -b BATCH_KEY      Fetch tickets by batch key (e.g., pdp-P1-QuickWins)"
    echo "  --from-file, -f FILE       Fetch tickets from file (one TICK-### per line)"
    echo "  --limit, -l NUMBER         Limit number of tickets to fetch (default: all)"
    echo "  --list-categories          List available categories with ticket counts"
    echo "  --list-batches             List available batches with ticket counts"
    echo "  --list-priorities          List available priorities with ticket counts"
    echo "  --output, -o DIR           Output directory for ticket details (default: /tmp/batch-tickets)"
    echo "  --dry-run                  Show what would be fetched without fetching"
    echo "  --json                     Output as JSON instead of human-readable"
    echo "  --categorized-file FILE    Path to categorized_tickets.json"
    echo "  --help, -h                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --list-categories"
    echo "  $0 --category pdp --limit 5"
    echo "  $0 --priority P1-QuickWins"
    echo "  $0 --batch cart-P1-QuickWins --output ./qa-batch"
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
        --category|-c)
            CATEGORY="$2"
            shift 2
            ;;
        --priority|-p)
            PRIORITY="$2"
            shift 2
            ;;
        --batch|-b)
            BATCH_KEY="$2"
            shift 2
            ;;
        --from-file|-f)
            FROM_FILE="$2"
            shift 2
            ;;
        --limit|-l)
            LIMIT="$2"
            shift 2
            ;;
        --list-categories)
            LIST_CATEGORIES=true
            shift
            ;;
        --list-batches)
            LIST_BATCHES=true
            shift
            ;;
        --list-priorities)
            LIST_PRIORITIES=true
            shift
            ;;
        --output|-o)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --categorized-file)
            CATEGORIZED_FILE="$2"
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

# Check if categorized file exists
if [ ! -f "$CATEGORIZED_FILE" ]; then
    echo -e "${RED}Error: Categorized tickets file not found: $CATEGORIZED_FILE${NC}"
    echo "Run the categorization first: ./tests/categorize_tickets.sh"
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
    # Read from file
    if [ ! -f "$FROM_FILE" ]; then
        echo -e "${RED}Error: File not found: $FROM_FILE${NC}"
        exit 1
    fi
    TICKET_IDS=$(cat "$FROM_FILE" | grep -E "^TICK-[0-9]+" | head -n "${LIMIT:-9999}")
elif [ -n "$BATCH_KEY" ]; then
    # Filter by batch key
    TICKET_IDS=$(cat "$CATEGORIZED_FILE" | jq -r --arg key "$BATCH_KEY" '
        [.[] | select(.batch_key == $key)] |
        .[0:'"${LIMIT:-9999}"'] |
        .[].id')
elif [ -n "$CATEGORY" ]; then
    # Filter by category
    TICKET_IDS=$(cat "$CATEGORIZED_FILE" | jq -r --arg cat "$CATEGORY" '
        [.[] | select(.category == $cat)] |
        .[0:'"${LIMIT:-9999}"'] |
        .[].id')
elif [ -n "$PRIORITY" ]; then
    # Filter by priority
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

# Dry run - just show what would be fetched
if [ "$DRY_RUN" = true ]; then
    echo "Would fetch:"
    echo "$TICKET_IDS" | while read -r ticket_id; do
        if [ -n "$ticket_id" ]; then
            # Get ticket name from categorized file
            NAME=$(cat "$CATEGORIZED_FILE" | jq -r --arg id "$ticket_id" '.[] | select(.id == $id) | .name')
            echo "  - $ticket_id: $NAME"
        fi
    done
    exit 0
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Load Notion credentials
if [ -f "$HOME/.bash_profile" ]; then
    source "$HOME/.bash_profile"
fi

if [ -z "$NOTION_API_KEY" ]; then
    echo -e "${RED}Error: NOTION_API_KEY not set${NC}"
    exit 1
fi

# JSON output mode
if [ "$JSON_OUTPUT" = true ]; then
    RESULTS="[]"
fi

# Fetch each ticket
FETCHED=0
echo "$TICKET_IDS" | while read -r ticket_id; do
    if [ -z "$ticket_id" ]; then
        continue
    fi

    FETCHED=$((FETCHED + 1))
    echo -e "${GREEN}[$FETCHED/$TICKET_COUNT]${NC} Fetching $ticket_id..."

    # Extract ticket number
    TICKET_NUMBER=$(echo "$ticket_id" | sed 's/TICK-//')

    # Query Notion
    RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d "{\"filter\": {\"property\": \"ID\", \"unique_id\": {\"equals\": $TICKET_NUMBER}}}")

    PAGE_ID=$(echo "$RESPONSE" | jq -r '.results[0].id // empty')

    if [ -z "$PAGE_ID" ]; then
        echo -e "  ${RED}✗ Not found${NC}"
        continue
    fi

    # Get page details
    PAGE_DETAILS=$(curl -s -X GET "https://api.notion.com/v1/pages/$PAGE_ID" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28")

    # Get page content
    PAGE_CONTENT=$(curl -s -X GET "https://api.notion.com/v1/blocks/$PAGE_ID/children" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28")

    # Extract key info
    TITLE=$(echo "$PAGE_DETAILS" | jq -r '.properties.Name.title[0].plain_text // "Untitled"')
    STATUS=$(echo "$PAGE_DETAILS" | jq -r '.properties["Ticket Status"].status.name // "Unknown"')
    COMPLEXITY=$(echo "$PAGE_DETAILS" | jq -r '.properties["Ticket Complexity"].select.name // "Unknown"')
    URL=$(echo "$PAGE_DETAILS" | jq -r '.url')

    echo "  Title: $TITLE"
    echo "  Status: $STATUS | Complexity: $COMPLEXITY"

    # Save to output directory
    TICKET_DIR="$OUTPUT_DIR/$ticket_id"
    mkdir -p "$TICKET_DIR"
    echo "$PAGE_DETAILS" > "$TICKET_DIR/details.json"
    echo "$PAGE_CONTENT" > "$TICKET_DIR/content.json"

    # Create summary file
    cat > "$TICKET_DIR/summary.txt" << EOF
Ticket: $ticket_id
Title: $TITLE
Status: $STATUS
Complexity: $COMPLEXITY
URL: $URL
Fetched: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    # Extract images
    IMAGES=$(echo "$PAGE_CONTENT" | jq -r '.results[] | select(.type == "image") | .image.external.url // .image.file.url // empty')
    if [ -n "$IMAGES" ]; then
        echo "  Images found - downloading..."
        IMG_COUNT=0
        echo "$IMAGES" | while read -r img_url; do
            if [ -n "$img_url" ]; then
                IMG_COUNT=$((IMG_COUNT + 1))
                curl -sL "$img_url" -o "$TICKET_DIR/image_$IMG_COUNT.png" 2>/dev/null || true
            fi
        done
    fi

    echo -e "  ${GREEN}✓ Saved to $TICKET_DIR${NC}"
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
echo "  3. Run: complete-batch.sh --from-dir $OUTPUT_DIR"
