#!/bin/bash

# End-to-End Batch Processing Workflow
# Usage:
#   ./batch_workflow.sh --start pdp-P1-QuickWins
#   ./batch_workflow.sh --qa pdp-P1-QuickWins
#   ./batch_workflow.sh --complete pdp-P1-QuickWins
#   ./batch_workflow.sh --status
#
# This script orchestrates the complete workflow:
#   1. SELECT   - Choose a batch from categorized tickets
#   2. FETCH    - Fetch all ticket details
#   3. WORK     - Process tickets (developer work)
#   4. STAGE    - Push to staging branch
#   5. QA       - Verify changes with Chrome MCP
#   6. RECORD   - Record QA results in Notion
#   7. COMPLETE - Mark tickets as complete

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script locations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NOTION_SCRIPTS="$HOME/Dropbox/Scripts/notion"
SHOPIFY_SCRIPTS="$HOME/Dropbox/Scripts/shopify"

# Results directory
RESULTS_DIR="$SCRIPT_DIR/results"
WORKFLOW_STATE="$RESULTS_DIR/workflow_state.json"

show_usage() {
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo ""
    echo "End-to-end batch processing workflow."
    echo ""
    echo "Commands:"
    echo "  --start, -s BATCH       Start working on a batch"
    echo "  --resume                Resume interrupted batch from saved state"
    echo "  --refresh               Refresh batch status from Notion"
    echo "  --fetch, -f BATCH       Fetch ticket details for batch"
    echo "  --qa BATCH              Run QA verification for batch"
    echo "  --record-qa BATCH       Record QA results (passed/failed)"
    echo "  --complete, -c BATCH    Complete all tickets in batch"
    echo "  --status                Show current workflow status"
    echo "  --list                  List available batches"
    echo "  --reset                 Reset workflow state"
    echo ""
    echo "Options:"
    echo "  --pr-url URL            GitHub PR URL"
    echo "  --qa-status STATUS      QA status: passed, failed"
    echo "  --qa-by NAME            Who performed QA"
    echo "  --summary TEXT          Completion summary"
    echo ""
    echo "Workflow:"
    echo "  1. $0 --list                    # See available batches"
    echo "  2. $0 --start pdp-P1-QuickWins  # Start a batch"
    echo "  3. (do development work)"
    echo "  4. git push origin HEAD         # Push to staging"
    echo "  5. $0 --qa pdp-P1-QuickWins     # QA verification"
    echo "  6. $0 --record-qa pdp-P1-QuickWins --qa-status passed"
    echo "  7. $0 --complete pdp-P1-QuickWins --pr-url <url>"
    echo ""
    echo "Resume interrupted work:"
    echo "  $0 --resume                     # Continue from last state"
    exit 1
}

# Initialize workflow state
init_state() {
    mkdir -p "$RESULTS_DIR"
    if [ ! -f "$WORKFLOW_STATE" ]; then
        echo '{"current_batch": null, "batches": {}}' > "$WORKFLOW_STATE"
    fi
}

# Get current batch
get_current_batch() {
    cat "$WORKFLOW_STATE" | jq -r '.current_batch // empty'
}

# Set current batch
set_current_batch() {
    local batch="$1"
    local tmp=$(mktemp)
    cat "$WORKFLOW_STATE" | jq --arg b "$batch" '.current_batch = $b' > "$tmp"
    mv "$tmp" "$WORKFLOW_STATE"
}

# Update batch state
update_batch_state() {
    local batch="$1"
    local key="$2"
    local value="$3"
    local tmp=$(mktemp)
    cat "$WORKFLOW_STATE" | jq --arg b "$batch" --arg k "$key" --arg v "$value" \
        '.batches[$b][$k] = $v' > "$tmp"
    mv "$tmp" "$WORKFLOW_STATE"
}

# Show workflow status
show_status() {
    echo "========================================"
    echo "Workflow Status"
    echo "========================================"
    echo ""

    CURRENT=$(get_current_batch)
    if [ -n "$CURRENT" ]; then
        echo -e "Current batch: ${GREEN}$CURRENT${NC}"
        echo ""

        # Show batch details
        if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
            BATCH_INFO=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$CURRENT" '
                [.[] | select(.batch_key == $b)] |
                {
                    count: length,
                    category: .[0].category,
                    priority: .[0].priority_label
                }')

            echo "Batch info:"
            echo "$BATCH_INFO" | jq -r '"  Category: \(.category)\n  Priority: \(.priority)\n  Tickets: \(.count)"'
        fi

        echo ""
        echo "Batch state:"
        cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b] // {} | to_entries[] | "  \(.key): \(.value)"'
    else
        echo "No batch currently in progress."
        echo ""
        echo "Start with: $0 --start <batch-key>"
        echo "List batches: $0 --list"
    fi
}

# List available batches
list_batches() {
    echo "========================================"
    echo "Available Batches"
    echo "========================================"
    echo ""

    if [ ! -f "$RESULTS_DIR/categorized_tickets.json" ]; then
        echo -e "${YELLOW}No categorized tickets found.${NC}"
        echo "Run: ./categorize_tickets.sh"
        return
    fi

    echo -e "${BLUE}By Priority:${NC}"
    echo ""

    # P1 - Quick Wins
    echo -e "${GREEN}P1-QuickWins (do these first):${NC}"
    cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '
        [.[] | select(.priority_label == "P1-QuickWins")] |
        group_by(.category) |
        map({batch_key: (.[0].category + "-P1-QuickWins"), category: .[0].category, count: length}) |
        sort_by(-.count) |
        .[] |
        "  \(.batch_key): \(.count) tickets"'

    echo ""
    echo -e "${BLUE}P2-Structural:${NC}"
    cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '
        [.[] | select(.priority_label == "P2-Structural")] |
        group_by(.category) |
        map({batch_key: (.[0].category + "-P2-Structural"), category: .[0].category, count: length}) |
        sort_by(-.count) |
        .[] |
        "  \(.batch_key): \(.count) tickets"'

    echo ""
    echo -e "${YELLOW}P3-CrossCutting:${NC}"
    cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '
        [.[] | select(.priority_label == "P3-CrossCutting")] |
        group_by(.category) |
        map({batch_key: (.[0].category + "-P3-CrossCutting"), category: .[0].category, count: length}) |
        sort_by(-.count) |
        .[] |
        "  \(.batch_key): \(.count) tickets"' 2>/dev/null || echo "  (none)"

    echo ""
    echo -e "${CYAN}P4-Responsive:${NC}"
    cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '
        [.[] | select(.priority_label == "P4-Responsive")] |
        group_by(.category) |
        map({batch_key: (.[0].category + "-P4-Responsive"), category: .[0].category, count: length}) |
        sort_by(-.count) |
        .[] |
        "  \(.batch_key): \(.count) tickets"' 2>/dev/null || echo "  (none)"
}

# Start working on a batch
start_batch() {
    local batch="$1"

    echo "========================================"
    echo "Starting Batch: $batch"
    echo "========================================"
    echo ""

    # Check if batch exists
    if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
        BATCH_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$batch" '
            [.[] | select(.batch_key == $b)] | length')

        if [ "$BATCH_COUNT" -eq 0 ]; then
            echo -e "${RED}Batch not found: $batch${NC}"
            echo ""
            echo "Available batches:"
            list_batches
            exit 1
        fi

        echo "Found $BATCH_COUNT tickets in batch"
    fi

    # Set as current batch
    set_current_batch "$batch"
    update_batch_state "$batch" "started" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    update_batch_state "$batch" "status" "in_progress"

    echo ""
    echo -e "${GREEN}✓ Batch started${NC}"
    echo ""

    # Fetch tickets
    echo "Fetching ticket details..."
    echo ""

    if [ -x "$NOTION_SCRIPTS/fetch-batch.sh" ]; then
        "$NOTION_SCRIPTS/fetch-batch.sh" --batch "$batch" --output "$RESULTS_DIR/batch-$batch"
        update_batch_state "$batch" "fetched" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    else
        echo -e "${YELLOW}fetch-batch.sh not found or not executable${NC}"
    fi

    # Get staging URL
    echo ""
    echo "Staging preview URL:"
    if [ -x "$SHOPIFY_SCRIPTS/get-staging-url.sh" ]; then
        STAGING_URL=$("$SHOPIFY_SCRIPTS/get-staging-url.sh" 2>/dev/null || echo "")
        if [ -n "$STAGING_URL" ]; then
            echo "  $STAGING_URL"
            update_batch_state "$batch" "staging_url" "$STAGING_URL"
        else
            echo "  (not available - set theme ID first)"
        fi
    fi

    echo ""
    echo "========================================"
    echo "Next Steps"
    echo "========================================"
    echo ""
    echo "1. Review tickets in: $RESULTS_DIR/batch-$batch/"
    echo "2. Do development work"
    echo "3. Commit and push to staging"
    echo "4. Run QA: $0 --qa $batch"
}

# Run QA verification
run_qa() {
    local batch="$1"

    echo "========================================"
    echo "QA Verification: $batch"
    echo "========================================"
    echo ""

    # Get staging URL
    STAGING_URL=""
    if [ -x "$SHOPIFY_SCRIPTS/get-staging-url.sh" ]; then
        STAGING_URL=$("$SHOPIFY_SCRIPTS/get-staging-url.sh" 2>/dev/null || echo "")
    fi

    if [ -z "$STAGING_URL" ]; then
        echo -e "${YELLOW}No staging URL available${NC}"
        echo "Set theme ID with: git config branch.<branch>.themeId <ID>"
        echo ""
    else
        echo "Staging URL: $STAGING_URL"
        echo ""
    fi

    # List tickets in batch for QA
    echo "Tickets to verify:"
    cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$batch" '
        [.[] | select(.batch_key == $b)] |
        .[] |
        "  □ \(.id): \(.name)"' | head -20

    TICKET_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$batch" '
        [.[] | select(.batch_key == $b)] | length')

    if [ "$TICKET_COUNT" -gt 20 ]; then
        echo "  ... and $((TICKET_COUNT - 20)) more"
    fi

    echo ""
    echo "========================================"
    echo "QA Checklist"
    echo "========================================"
    echo ""
    echo "  □ Visual inspection matches requirements"
    echo "  □ Tested on desktop (Chrome)"
    echo "  □ Tested on mobile viewport"
    echo "  □ No console errors"
    echo "  □ No layout breaks"
    echo ""

    # Prompt for Chrome MCP
    echo -e "${BLUE}Opening staging URL in browser...${NC}"
    if [ -n "$STAGING_URL" ]; then
        # Try to open URL
        if command -v open &> /dev/null; then
            open "$STAGING_URL" 2>/dev/null || true
        fi
    fi

    echo ""
    echo "After QA verification, run:"
    echo "  $0 --record-qa $batch --qa-status passed"
    echo "  $0 --record-qa $batch --qa-status failed --summary 'Issue description'"

    update_batch_state "$batch" "qa_started" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

# Record QA results
record_qa_results() {
    local batch="$1"
    local qa_status="$2"
    local qa_by="$3"
    local summary="$4"

    echo "========================================"
    echo "Recording QA Results: $batch"
    echo "========================================"
    echo ""

    if [ -z "$qa_status" ]; then
        echo -e "${RED}Error: --qa-status required (passed/failed)${NC}"
        exit 1
    fi

    if [ -x "$NOTION_SCRIPTS/record-qa.sh" ]; then
        CMD="$NOTION_SCRIPTS/record-qa.sh --batch $batch --status $qa_status"

        if [ -n "$qa_by" ]; then
            CMD="$CMD --by '$qa_by'"
        fi

        if [ -n "$summary" ]; then
            CMD="$CMD --notes '$summary'"
        fi

        eval "$CMD"

        update_batch_state "$batch" "qa_status" "$qa_status"
        update_batch_state "$batch" "qa_completed" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    else
        echo -e "${YELLOW}record-qa.sh not found${NC}"
    fi

    echo ""
    if [ "$qa_status" = "passed" ]; then
        echo -e "${GREEN}QA Passed!${NC}"
        echo ""
        echo "Ready to complete batch:"
        echo "  $0 --complete $batch"
    else
        echo -e "${RED}QA Failed${NC}"
        echo ""
        echo "Fix issues and re-run QA:"
        echo "  $0 --qa $batch"
    fi
}

# Complete batch
complete_batch() {
    local batch="$1"
    local pr_url="$2"
    local summary="$3"

    echo "========================================"
    echo "Completing Batch: $batch"
    echo "========================================"
    echo ""

    # Check QA status
    QA_STATUS=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$batch" '.batches[$b].qa_status // empty')

    if [ "$QA_STATUS" != "passed" ]; then
        echo -e "${YELLOW}Warning: QA status is not 'passed' (current: $QA_STATUS)${NC}"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Run QA first: $0 --qa $batch"
            exit 1
        fi
    fi

    if [ -x "$NOTION_SCRIPTS/complete-batch.sh" ]; then
        CMD="$NOTION_SCRIPTS/complete-batch.sh --batch $batch"

        if [ -n "$pr_url" ]; then
            CMD="$CMD --pr-url '$pr_url'"
        fi

        if [ -n "$summary" ]; then
            CMD="$CMD --summary '$summary'"
        fi

        eval "$CMD"

        update_batch_state "$batch" "completed" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        update_batch_state "$batch" "status" "completed"

        # Clear current batch
        set_current_batch ""
    else
        echo -e "${YELLOW}complete-batch.sh not found${NC}"
    fi

    echo ""
    echo -e "${GREEN}Batch completed!${NC}"
    echo ""
    echo "Start next batch:"
    echo "  $0 --list"
    echo "  $0 --start <next-batch>"
}

# Reset workflow
reset_workflow() {
    echo "Resetting workflow state..."
    rm -f "$WORKFLOW_STATE"
    init_state
    echo -e "${GREEN}✓ Workflow state reset${NC}"
}

# Resume interrupted batch
resume_batch() {
    echo "========================================"
    echo "Resuming Batch Workflow"
    echo "========================================"
    echo ""

    # Check for saved state
    if [ ! -f "$WORKFLOW_STATE" ]; then
        echo -e "${YELLOW}No saved workflow state found.${NC}"
        echo ""
        echo "Start a new batch with: $0 --start <batch-key>"
        exit 1
    fi

    # Get current batch
    CURRENT=$(get_current_batch)
    if [ -z "$CURRENT" ]; then
        echo -e "${YELLOW}No batch currently in progress.${NC}"
        echo ""
        echo "Start a new batch with: $0 --start <batch-key>"
        echo "Available batches: $0 --list"
        exit 1
    fi

    echo -e "Resuming batch: ${GREEN}$CURRENT${NC}"
    echo ""

    # Get batch state
    BATCH_STATUS=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b].status // "unknown"')
    STARTED=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b].started // "unknown"')
    QA_STATUS=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b].qa_status // empty')
    QA_STARTED=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b].qa_started // empty')

    echo "Batch state:"
    echo "  Status: $BATCH_STATUS"
    echo "  Started: $STARTED"
    if [ -n "$QA_STATUS" ]; then
        echo "  QA Status: $QA_STATUS"
    fi
    echo ""

    # Determine next action based on state
    echo "========================================"
    echo "Recommended Next Action"
    echo "========================================"
    echo ""

    if [ "$BATCH_STATUS" = "completed" ]; then
        echo -e "${GREEN}This batch is already completed!${NC}"
        echo ""
        echo "Start a new batch:"
        echo "  $0 --list"
        echo "  $0 --start <batch-key>"

    elif [ "$QA_STATUS" = "passed" ]; then
        echo -e "${GREEN}QA passed - ready to complete batch${NC}"
        echo ""
        echo "Complete the batch:"
        echo "  $0 --complete $CURRENT --pr-url <github-pr-url>"

    elif [ "$QA_STATUS" = "failed" ]; then
        echo -e "${YELLOW}QA failed - fix issues and re-run QA${NC}"
        echo ""
        echo "After fixing issues:"
        echo "  $0 --qa $CURRENT"

    elif [ -n "$QA_STARTED" ]; then
        echo -e "${BLUE}QA in progress - awaiting results${NC}"
        echo ""
        echo "Record QA results:"
        echo "  $0 --record-qa $CURRENT --qa-status passed"
        echo "  $0 --record-qa $CURRENT --qa-status failed --summary 'Issue description'"

    elif [ "$BATCH_STATUS" = "in_progress" ]; then
        echo -e "${BLUE}Batch in progress - development phase${NC}"
        echo ""
        echo "After completing development:"
        echo "  1. Commit and push changes"
        echo "  2. $0 --qa $CURRENT"

    else
        echo -e "${YELLOW}Unknown state - showing status${NC}"
        show_status
    fi

    echo ""

    # Show ticket summary if available
    if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
        TICKET_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$CURRENT" '
            [.[] | select(.batch_key == $b)] | length')
        echo "Tickets in batch: $TICKET_COUNT"

        # Show ticket list
        echo ""
        echo "Tickets:"
        cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$CURRENT" '
            [.[] | select(.batch_key == $b)] |
            .[] |
            "  \(.id): \(.name)"' | head -10

        if [ "$TICKET_COUNT" -gt 10 ]; then
            echo "  ... and $((TICKET_COUNT - 10)) more"
        fi
    fi

    # Show batch directory if exists
    if [ -d "$RESULTS_DIR/batch-$CURRENT" ]; then
        echo ""
        echo "Batch files: $RESULTS_DIR/batch-$CURRENT/"
    fi
}

# Refresh batch status from Notion
refresh_batch() {
    echo "========================================"
    echo "Refreshing Batch Status from Notion"
    echo "========================================"
    echo ""

    # Get current batch
    CURRENT=$(get_current_batch)
    if [ -z "$CURRENT" ]; then
        echo -e "${YELLOW}No batch currently in progress.${NC}"
        echo "Refreshing all categorized tickets..."
        echo ""
    else
        echo "Current batch: $CURRENT"
        echo ""
    fi

    # Load credentials
    if [ -f "$HOME/.bash_profile" ]; then
        source "$HOME/.bash_profile"
    fi

    if [ -z "$NOTION_API_KEY" ]; then
        echo -e "${RED}Error: NOTION_API_KEY not set${NC}"
        exit 1
    fi

    # Notion database ID
    TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

    echo "Fetching current ticket statuses from Notion..."
    echo ""

    # If we have categorized tickets, refresh their status
    if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
        TICKET_IDS=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq -r '.[].page_id' | head -20)

        COMPLETED=0
        IN_PROGRESS=0
        BACKLOG=0
        TOTAL=0

        for PAGE_ID in $TICKET_IDS; do
            TOTAL=$((TOTAL + 1))

            # Fetch ticket status from Notion
            STATUS=$(curl -s "https://api.notion.com/v1/pages/$PAGE_ID" \
                -H "Authorization: Bearer $NOTION_API_KEY" \
                -H "Notion-Version: 2022-06-28" | \
                jq -r '.properties["Ticket Status"].status.name // "Unknown"')

            case "$STATUS" in
                "Complete"|"Completed")
                    COMPLETED=$((COMPLETED + 1))
                    ;;
                "In Progress"|"InProgress")
                    IN_PROGRESS=$((IN_PROGRESS + 1))
                    ;;
                *)
                    BACKLOG=$((BACKLOG + 1))
                    ;;
            esac
        done

        echo "Ticket Status Summary (first 20):"
        echo "  Completed:   $COMPLETED"
        echo "  In Progress: $IN_PROGRESS"
        echo "  Backlog:     $BACKLOG"
        echo "  Total:       $TOTAL"
        echo ""

        # Update workflow state with refresh timestamp
        if [ -n "$CURRENT" ]; then
            update_batch_state "$CURRENT" "last_refresh" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            update_batch_state "$CURRENT" "completed_count" "$COMPLETED"
            update_batch_state "$CURRENT" "in_progress_count" "$IN_PROGRESS"
            update_batch_state "$CURRENT" "backlog_count" "$BACKLOG"
        fi

        if [ "$COMPLETED" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
            echo -e "${GREEN}All tickets completed!${NC}"
            echo ""
            echo "Ready to finalize batch:"
            echo "  $0 --complete $CURRENT"
        elif [ "$COMPLETED" -gt 0 ]; then
            REMAINING=$((TOTAL - COMPLETED))
            echo -e "${BLUE}Progress: $COMPLETED/$TOTAL completed ($REMAINING remaining)${NC}"
        fi
    else
        echo -e "${YELLOW}No categorized tickets found.${NC}"
        echo "Run: ./categorize_tickets.sh"
    fi

    echo ""
    echo -e "${GREEN}✓ Refresh complete${NC}"
}

# Initialize
init_state

# Parse command
COMMAND=""
BATCH=""
PR_URL=""
QA_STATUS=""
QA_BY=""
SUMMARY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --start|-s)
            COMMAND="start"
            BATCH="$2"
            shift 2
            ;;
        --fetch|-f)
            COMMAND="fetch"
            BATCH="$2"
            shift 2
            ;;
        --qa)
            COMMAND="qa"
            BATCH="$2"
            shift 2
            ;;
        --record-qa)
            COMMAND="record-qa"
            BATCH="$2"
            shift 2
            ;;
        --complete|-c)
            COMMAND="complete"
            BATCH="$2"
            shift 2
            ;;
        --status)
            COMMAND="status"
            shift
            ;;
        --list)
            COMMAND="list"
            shift
            ;;
        --reset)
            COMMAND="reset"
            shift
            ;;
        --resume)
            COMMAND="resume"
            shift
            ;;
        --refresh|--sync|--reassess)
            COMMAND="refresh"
            shift
            ;;
        --pr-url)
            PR_URL="$2"
            shift 2
            ;;
        --qa-status)
            QA_STATUS="$2"
            shift 2
            ;;
        --qa-by)
            QA_BY="$2"
            shift 2
            ;;
        --summary)
            SUMMARY="$2"
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

# Execute command
case "$COMMAND" in
    start)
        start_batch "$BATCH"
        ;;
    fetch)
        if [ -x "$NOTION_SCRIPTS/fetch-batch.sh" ]; then
            "$NOTION_SCRIPTS/fetch-batch.sh" --batch "$BATCH" --output "$RESULTS_DIR/batch-$BATCH"
        fi
        ;;
    qa)
        run_qa "$BATCH"
        ;;
    record-qa)
        record_qa_results "$BATCH" "$QA_STATUS" "$QA_BY" "$SUMMARY"
        ;;
    complete)
        complete_batch "$BATCH" "$PR_URL" "$SUMMARY"
        ;;
    status)
        show_status
        ;;
    list)
        list_batches
        ;;
    reset)
        reset_workflow
        ;;
    resume)
        resume_batch
        ;;
    refresh)
        refresh_batch
        ;;
    *)
        show_usage
        ;;
esac
