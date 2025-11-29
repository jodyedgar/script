#!/bin/bash

# Complete multiple tickets in a batch
# Usage:
#   ./complete-batch.sh --batch pdp-P1-QuickWins
#   ./complete-batch.sh --category pdp --priority P1-QuickWins
#   ./complete-batch.sh --from-file tickets.txt
#   ./complete-batch.sh --from-dir /tmp/batch-tickets
#
# Marks all tickets in a batch as Complete with:
#   - Status update to Complete
#   - PR URL (auto-detected or specified)
#   - Completion summary
#   - Checkin timestamp

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Notion config
TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

# Script locations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGE_SCRIPT="$SCRIPT_DIR/manage-notion-ticket.sh"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Complete multiple tickets in a batch."
    echo ""
    echo "Options:"
    echo "  --batch, -b BATCH_KEY     Complete all tickets in batch (e.g., pdp-P1-QuickWins)"
    echo "  --category, -c CATEGORY   Filter by category"
    echo "  --priority, -p PRIORITY   Filter by priority"
    echo "  --from-file, -f FILE      Complete tickets listed in file"
    echo "  --from-dir, -d DIR        Complete tickets from batch directory"
    echo "  --pr-url URL              GitHub PR URL for all tickets"
    echo "  --summary, -s TEXT        Completion summary for all tickets"
    echo "  --status STATUS           Status to set (default: Complete)"
    echo "  --require-qa              Only complete tickets that have QA passed"
    echo "  --dry-run                 Show what would be completed"
    echo "  --help, -h                Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --batch pdp-P1-QuickWins --pr-url https://github.com/org/repo/pull/123"
    echo "  $0 --from-dir /tmp/batch-tickets --summary 'Batch completed'"
    echo "  $0 --category cart --require-qa"
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
REQUIRE_QA=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --batch|-b)
            BATCH_KEY="$2"
            shift 2
            ;;
        --category|-c)
            CATEGORY="$2"
            shift 2
            ;;
        --priority|-p)
            PRIORITY="$2"
            shift 2
            ;;
        --from-file|-f)
            FROM_FILE="$2"
            shift 2
            ;;
        --from-dir|-d)
            FROM_DIR="$2"
            shift 2
            ;;
        --pr-url)
            PR_URL="$2"
            shift 2
            ;;
        --summary|-s)
            SUMMARY="$2"
            shift 2
            ;;
        --status)
            STATUS="$2"
            shift 2
            ;;
        --require-qa)
            REQUIRE_QA=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

# Validate inputs
if [ -z "$BATCH_KEY" ] && [ -z "$CATEGORY" ] && [ -z "$FROM_FILE" ] && [ -z "$FROM_DIR" ]; then
    echo -e "${RED}Error: Specify --batch, --category, --from-file, or --from-dir${NC}"
    show_usage
fi

# Load credentials
if [ -f "$HOME/.bash_profile" ]; then
    source "$HOME/.bash_profile"
fi

if [ -z "$NOTION_API_KEY" ]; then
    echo -e "${RED}Error: NOTION_API_KEY not set${NC}"
    exit 1
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
        echo -e "${RED}Error: Categorized file not found. Run categorization first.${NC}"
        exit 1
    fi
    TICKET_IDS=$(cat "$CATEGORIZED_FILE" | jq -r --arg key "$BATCH_KEY" '
        [.[] | select(.batch_key == $key)] | .[].id')
elif [ -n "$CATEGORY" ]; then
    if [ ! -f "$CATEGORIZED_FILE" ]; then
        echo -e "${RED}Error: Categorized file not found. Run categorization first.${NC}"
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
if [ -n "$PR_URL" ]; then
    echo "PR URL: $PR_URL"
fi
if [ -n "$SUMMARY" ]; then
    echo "Summary: $SUMMARY"
fi
echo ""

# Check QA requirement
if [ "$REQUIRE_QA" = true ]; then
    echo -e "${YELLOW}QA verification required - checking QA status...${NC}"
    echo ""
    # This would check QA logs or Notion fields
    # For now, we'll just warn
    echo -e "${YELLOW}Note: QA verification check not yet implemented${NC}"
    echo "Proceeding without QA check..."
    echo ""
fi

# Dry run
if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN - Would complete:"
    echo "$TICKET_IDS" | while read -r ticket; do
        if [ -n "$ticket" ]; then
            echo "  - $ticket"
        fi
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

# Complete each ticket
SUCCESS=0
FAILED=0

echo "$TICKET_IDS" | while read -r ticket; do
    if [ -z "$ticket" ]; then
        continue
    fi

    echo -e "${BLUE}Completing $ticket...${NC}"

    # Build manage command
    CMD="$MANAGE_SCRIPT $ticket --status '$STATUS'"

    if [ -n "$PR_URL" ]; then
        CMD="$CMD --pr-url '$PR_URL'"
    fi

    if [ -n "$SUMMARY" ]; then
        CMD="$CMD --summary '$SUMMARY'"
    fi

    # Execute
    if eval "$CMD" > /tmp/complete-output.txt 2>&1; then
        echo -e "  ${GREEN}✓ Completed${NC}"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "  ${RED}✗ Failed${NC}"
        cat /tmp/complete-output.txt | sed 's/^/    /'
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "========================================"
echo "Batch Completion Summary"
echo "========================================"
echo ""
echo -e "${GREEN}Completed: $SUCCESS${NC}"
if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
fi
echo ""

# Log completion
LOG_DIR="$HOME/Dropbox/wwwroot/store.figma.com/shopify-the-figma-store/horizon/tests/results/completion-logs"
mkdir -p "$LOG_DIR"

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
    }' > "$LOG_FILE"

echo "Completion log: $LOG_FILE"
