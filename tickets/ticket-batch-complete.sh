#!/bin/bash

# Complete multiple tickets in a batch (Firestore-backed)
# Usage:
#   ./ticket-batch-complete.sh --batch pdp-P1-QuickWins
#   ./ticket-batch-complete.sh --category pdp --priority P1-QuickWins
#   ./ticket-batch-complete.sh --from-file tickets.txt
#   ./ticket-batch-complete.sh --from-dir /tmp/batch-tickets

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_firestore-lib.sh"

# Use ticket.sh for individual updates
TICKET_SCRIPT="$SCRIPT_DIR/ticket.sh"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Complete multiple tickets in a batch."
    echo ""
    echo "Options:"
    echo "  --batch, -b BATCH_KEY     Complete all tickets in batch"
    echo "  --category, -c CATEGORY   Filter by category"
    echo "  --priority, -p PRIORITY   Filter by priority"
    echo "  --from-file, -f FILE      Complete tickets listed in file"
    echo "  --from-dir, -d DIR        Complete tickets from batch directory"
    echo "  --pr-url URL              GitHub PR URL for all tickets"
    echo "  --summary, -s TEXT        Completion summary for all tickets"
    echo "  --status STATUS           Status to set (default: Complete)"
    echo "  --dry-run                 Show what would be completed"
    echo "  --help, -h                Show this help"
    exit 1
}

# Parse arguments
BATCH_KEY=""
CATEGORY=""
PRIORITY=""
FROM_FILE=""
FROM_DIR=""
PR_URL=""
SUMMARY=""
STATUS="Complete"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --batch|-b) BATCH_KEY="$2"; shift 2 ;;
        --category|-c) CATEGORY="$2"; shift 2 ;;
        --priority|-p) PRIORITY="$2"; shift 2 ;;
        --from-file|-f) FROM_FILE="$2"; shift 2 ;;
        --from-dir|-d) FROM_DIR="$2"; shift 2 ;;
        --pr-url) PR_URL="$2"; shift 2 ;;
        --summary|-s) SUMMARY="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h) show_usage ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; show_usage ;;
    esac
done

# Validate inputs
if [ -z "$BATCH_KEY" ] && [ -z "$CATEGORY" ] && [ -z "$FROM_FILE" ] && [ -z "$FROM_DIR" ]; then
    echo -e "${RED}Error: Specify --batch, --category, --from-file, or --from-dir${NC}"
    show_usage
fi

# Auto-detect PR URL from git
if [ -z "$PR_URL" ]; then
    if command -v gh &> /dev/null; then
        PR_URL=$(gh pr view --json url -q '.url' 2>/dev/null || true)
        if [ -n "$PR_URL" ]; then
            echo -e "${BLUE}Auto-detected PR URL: $PR_URL${NC}"
        fi
    fi
fi

# Build ticket list
TICKET_IDS=""
CATEGORIZED_FILE="$HOME/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests/results/categorized_tickets.json"

if [ -n "$FROM_FILE" ]; then
    if [ ! -f "$FROM_FILE" ]; then
        echo -e "${RED}Error: File not found: $FROM_FILE${NC}"
        exit 1
    fi
    TICKET_IDS=$(cat "$FROM_FILE" | grep -E "^TICK-[0-9]+")
elif [ -n "$FROM_DIR" ]; then
    if [ ! -d "$FROM_DIR" ]; then
        echo -e "${RED}Error: Directory not found: $FROM_DIR${NC}"
        exit 1
    fi
    TICKET_IDS=$(ls "$FROM_DIR" | grep -E "^TICK-[0-9]+")
elif [ -n "$BATCH_KEY" ]; then
    if [ ! -f "$CATEGORIZED_FILE" ]; then
        echo -e "${RED}Error: Categorized file not found.${NC}"
        exit 1
    fi
    TICKET_IDS=$(cat "$CATEGORIZED_FILE" | jq -r --arg key "$BATCH_KEY" '
        [.[] | select(.batch_key == $key)] | .[].id')
elif [ -n "$CATEGORY" ]; then
    if [ ! -f "$CATEGORIZED_FILE" ]; then
        echo -e "${RED}Error: Categorized file not found.${NC}"
        exit 1
    fi

    JQ_FILTER=".category == \"$CATEGORY\""
    if [ -n "$PRIORITY" ]; then
        JQ_FILTER="$JQ_FILTER and .priority_label == \"$PRIORITY\""
    fi

    TICKET_IDS=$(cat "$CATEGORIZED_FILE" | jq -r "
        [.[] | select($JQ_FILTER)] | .[].id")
fi

TICKET_COUNT=$(echo "$TICKET_IDS" | grep -c "TICK-" || echo "0")

if [ "$TICKET_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No tickets found to complete${NC}"
    exit 0
fi

echo "========================================"
echo "Batch Completion"
echo "========================================"
echo ""
echo "Tickets to complete: $TICKET_COUNT"
echo "Status: $STATUS"
[ -n "$PR_URL" ] && echo "PR URL: $PR_URL"
[ -n "$SUMMARY" ] && echo "Summary: $SUMMARY"
echo ""

# Dry run
if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN - Would complete:"
    echo "$TICKET_IDS" | while read -r ticket; do
        [ -n "$ticket" ] && echo "  - $ticket"
    done
    exit 0
fi

# Confirm
echo -e "${YELLOW}This will mark $TICKET_COUNT tickets as '$STATUS'.${NC}"
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""

# Complete each ticket using ticket.sh
SUCCESS=0
FAILED=0

echo "$TICKET_IDS" | while read -r ticket; do
    if [ -z "$ticket" ]; then
        continue
    fi

    echo -e "${BLUE}Completing $ticket...${NC}"

    # Build args for ticket.sh
    ARGS=("$ticket" "--status" "$STATUS")
    [ -n "$SUMMARY" ] && ARGS+=("--summary" "$SUMMARY")

    # Execute
    if "$TICKET_SCRIPT" "${ARGS[@]}" > /tmp/complete-output.txt 2>&1; then
        echo -e "  ${GREEN}Completed${NC}"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "  ${RED}Failed${NC}"
        cat /tmp/complete-output.txt | sed 's/^/    /'
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "========================================"
echo "Batch Completion Summary"
echo "========================================"
echo ""
echo -e "${GREEN}Done${NC}"

# Log completion
LOG_DIR="$HOME/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests/results/completion-logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true

LOG_FILE="$LOG_DIR/batch-$(date +%Y%m%d-%H%M%S).json"

jq -n \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg batch_key "$BATCH_KEY" \
    --arg category "$CATEGORY" \
    --arg priority "$PRIORITY" \
    --arg status "$STATUS" \
    --arg pr_url "$PR_URL" \
    --argjson count "$TICKET_COUNT" \
    '{
        timestamp: $timestamp,
        batch_key: $batch_key,
        category: $category,
        priority: $priority,
        status: $status,
        pr_url: $pr_url,
        ticket_count: $count
    }' > "$LOG_FILE" 2>/dev/null || true

echo "Completion log: $LOG_FILE"
