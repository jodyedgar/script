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

# Load environment variables (Notion API key, etc.)
if [ -f "$NOTION_SCRIPTS/.env" ]; then
    source "$NOTION_SCRIPTS/.env"
elif [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

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
    echo "  --context               Generate context briefing for session handoff"
    echo "  --qa-report             Generate QA verification report (qa_report.json)"
    echo "  --qa-filter FILTER      Query tickets by QA field status (needs-after, needs-before, has-qa)"
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

# Query tickets by QA field status (filter QA Before is_not_empty, QA After is_empty)
query_qa_status() {
    echo "========================================"
    echo "Querying Tickets by QA Field Status"
    echo "========================================"
    echo ""

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

    QA_FILTER="${1:-needs-after}"

    echo "Filter: $QA_FILTER"
    echo ""

    case "$QA_FILTER" in
        needs-after|needs-qa-after)
            # Find tickets with QA Before but missing QA After
            echo "Finding tickets with QA Before but missing QA After..."
            FILTER_JSON='{
                "and": [
                    {
                        "property": "QA Before",
                        "files": {"is_not_empty": true}
                    },
                    {
                        "property": "QA After",
                        "files": {"is_empty": true}
                    }
                ]
            }'
            ;;
        needs-before|needs-qa-before)
            # Find tickets missing QA Before
            echo "Finding tickets missing QA Before..."
            FILTER_JSON='{
                "property": "QA Before",
                "files": {"is_empty": true}
            }'
            ;;
        has-qa|complete-qa)
            # Find tickets with both QA Before and After
            echo "Finding tickets with complete QA (both Before and After)..."
            FILTER_JSON='{
                "and": [
                    {
                        "property": "QA Before",
                        "files": {"is_not_empty": true}
                    },
                    {
                        "property": "QA After",
                        "files": {"is_not_empty": true}
                    }
                ]
            }'
            ;;
        *)
            echo -e "${RED}Unknown filter: $QA_FILTER${NC}"
            echo "Available filters: needs-after, needs-before, has-qa"
            exit 1
            ;;
    esac

    # Query Notion database
    RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d "{\"filter\": $FILTER_JSON, \"page_size\": 20}")

    # Parse and display results
    TICKET_COUNT=$(echo "$RESPONSE" | jq '.results | length')

    if [ "$TICKET_COUNT" -gt 0 ]; then
        echo ""
        echo -e "${GREEN}Found $TICKET_COUNT ticket(s):${NC}"
        echo ""
        echo "$RESPONSE" | jq -r '.results[] |
            "TICK-\(.properties.ID.unique_id.number) | \(.properties.Name.title[0].plain_text // "N/A")[0:50] | \(.properties["Ticket Status"].status.name // "Unknown")"'
    else
        echo ""
        echo -e "${YELLOW}No tickets found matching criteria.${NC}"
    fi

    echo ""
}

# Generate QA report with summary statistics
generate_qa_report() {
    local project_filter="${QA_PROJECT:-}"
    local range_filter="${QA_RANGE:-}"
    local range_min=""
    local range_max=""
    local report_title="QA Verification Report"
    local filter_desc=""

    echo "========================================"
    echo "Generating QA Report"
    echo "========================================"
    echo ""

    # Check for API key
    if [ -z "$NOTION_API_KEY" ]; then
        echo -e "${RED}Error: NOTION_API_KEY not set${NC}"
        echo "Export NOTION_API_KEY or set in .env file"
        exit 1
    fi

    # Database ID for tickets
    TICKETS_DATABASE_ID="1abc197b3ae7808fa454dd0c0e96ca6f"

    # Parse range filter (format: 1470-1568)
    if [ -n "$range_filter" ]; then
        range_min=$(echo "$range_filter" | cut -d'-' -f1)
        range_max=$(echo "$range_filter" | cut -d'-' -f2)
        echo -e "${BLUE}Filtering by ticket range: TICK-$range_min to TICK-$range_max${NC}"
        filter_desc="Tickets $range_min-$range_max"
    fi

    # Parse project filter
    if [ -n "$project_filter" ]; then
        echo -e "${BLUE}Filtering by project: $project_filter${NC}"
        if [ -n "$filter_desc" ]; then
            filter_desc="$filter_desc | Project: $project_filter"
        else
            filter_desc="Project: $project_filter"
        fi
        report_title="QA Report: $project_filter"
    fi

    QA_REPORT_JSON="$RESULTS_DIR/qa_report.json"
    QA_REPORT_MD="$RESULTS_DIR/qa_report.md"
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo -e "${BLUE}Querying Notion for QA status...${NC}"
    echo ""

    # Build dynamic filter based on project and range
    build_filter() {
        local base_conditions="$1"
        local filter_parts=()

        # Add base conditions
        filter_parts+=("$base_conditions")

        # Add project filter if specified
        if [ -n "$project_filter" ]; then
            filter_parts+=("{\"property\": \"Name\", \"title\": {\"contains\": \"$project_filter\"}}")
        fi

        # Add range filter if specified
        if [ -n "$range_min" ] && [ -n "$range_max" ]; then
            filter_parts+=("{\"property\": \"ID\", \"unique_id\": {\"greater_than_or_equal_to\": $range_min}}")
            filter_parts+=("{\"property\": \"ID\", \"unique_id\": {\"less_than_or_equal_to\": $range_max}}")
        fi

        # Join all conditions with commas
        local joined=""
        for part in "${filter_parts[@]}"; do
            if [ -n "$joined" ]; then
                joined="$joined, $part"
            else
                joined="$part"
            fi
        done

        echo "{\"and\": [$joined]}"
    }

    # Query tickets with complete QA (both Before and After)
    echo "  Checking tickets with complete QA..."
    COMPLETE_FILTER=$(build_filter '{"property": "QA Before", "files": {"is_not_empty": true}}, {"property": "QA After", "files": {"is_not_empty": true}}')
    COMPLETE_QA_RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d "{
            \"filter\": $COMPLETE_FILTER,
            \"page_size\": 100
        }")

    # Query tickets needing QA After (have Before, missing After)
    echo "  Checking tickets needing QA After..."
    NEEDS_AFTER_FILTER=$(build_filter '{"property": "QA Before", "files": {"is_not_empty": true}}, {"property": "QA After", "files": {"is_empty": true}}')
    NEEDS_AFTER_RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d "{
            \"filter\": $NEEDS_AFTER_FILTER,
            \"page_size\": 100
        }")

    # Query tickets missing QA Before (only non-complete for full report, or all for filtered)
    echo "  Checking tickets missing QA Before..."
    if [ -n "$project_filter" ] || [ -n "$range_filter" ]; then
        # For filtered reports, show all tickets missing QA Before in the filter range
        NEEDS_BEFORE_FILTER=$(build_filter '{"property": "QA Before", "files": {"is_empty": true}}')
    else
        # For full reports, only show non-complete tickets
        NEEDS_BEFORE_FILTER=$(build_filter '{"property": "QA Before", "files": {"is_empty": true}}, {"property": "Ticket Status", "status": {"does_not_equal": "Complete"}}')
    fi
    NEEDS_BEFORE_RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$TICKETS_DATABASE_ID/query" \
        -H "Authorization: Bearer $NOTION_API_KEY" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d "{
            \"filter\": $NEEDS_BEFORE_FILTER,
            \"page_size\": 100
        }")

    echo ""

    # Check for API errors and handle gracefully
    check_api_error() {
        local response="$1"
        local query_name="$2"
        if echo "$response" | jq -e '.object == "error"' > /dev/null 2>&1; then
            local error_msg=$(echo "$response" | jq -r '.message // "Unknown error"')
            echo -e "  ${YELLOW}Warning: $query_name query failed: $error_msg${NC}"
            echo "[]"
            return 1
        fi
        echo "$response"
        return 0
    }

    # Validate responses (handle null/error cases)
    COMPLETE_QA_RESPONSE=$(check_api_error "$COMPLETE_QA_RESPONSE" "Complete QA")
    NEEDS_AFTER_RESPONSE=$(check_api_error "$NEEDS_AFTER_RESPONSE" "Needs QA After")
    NEEDS_BEFORE_RESPONSE=$(check_api_error "$NEEDS_BEFORE_RESPONSE" "Needs QA Before")

    # Extract counts with null handling
    COMPLETE_COUNT=$(echo "$COMPLETE_QA_RESPONSE" | jq '.results | length // 0' 2>/dev/null || echo "0")
    NEEDS_AFTER_COUNT=$(echo "$NEEDS_AFTER_RESPONSE" | jq '.results | length // 0' 2>/dev/null || echo "0")
    NEEDS_BEFORE_COUNT=$(echo "$NEEDS_BEFORE_RESPONSE" | jq '.results | length // 0' 2>/dev/null || echo "0")
    TOTAL_QA_TOUCHED=$((COMPLETE_COUNT + NEEDS_AFTER_COUNT))

    # Extract ticket details for complete QA (with null handling)
    COMPLETE_TICKETS=$(echo "$COMPLETE_QA_RESPONSE" | jq '[(.results // [])[] | {
        id: "TICK-\(.properties.ID.unique_id.number // 0)",
        name: (.properties.Name.title[0].plain_text // "N/A"),
        status: (.properties["Ticket Status"].status.name // "Unknown"),
        qa_before: (.properties["QA Before"].files[0].external.url // .properties["QA Before"].files[0].file.url // null),
        qa_after: (.properties["QA After"].files[0].external.url // .properties["QA After"].files[0].file.url // null)
    }]' 2>/dev/null || echo "[]")

    # Extract ticket details for needs after (with null handling)
    NEEDS_AFTER_TICKETS=$(echo "$NEEDS_AFTER_RESPONSE" | jq '[(.results // [])[] | {
        id: "TICK-\(.properties.ID.unique_id.number // 0)",
        name: (.properties.Name.title[0].plain_text // "N/A"),
        status: (.properties["Ticket Status"].status.name // "Unknown"),
        qa_before: (.properties["QA Before"].files[0].external.url // .properties["QA Before"].files[0].file.url // null)
    }]' 2>/dev/null || echo "[]")

    # Extract ticket details for needs before (with null handling)
    NEEDS_BEFORE_TICKETS=$(echo "$NEEDS_BEFORE_RESPONSE" | jq '[(.results // [])[] | {
        id: "TICK-\(.properties.ID.unique_id.number // 0)",
        name: (.properties.Name.title[0].plain_text // "N/A"),
        status: (.properties["Ticket Status"].status.name // "Unknown")
    }]' 2>/dev/null || echo "[]")

    # Build JSON report
    local filter_json=""
    if [ -n "$project_filter" ] || [ -n "$range_filter" ]; then
        filter_json='"filter": {'
        local filter_parts=()
        [ -n "$project_filter" ] && filter_parts+=("\"project\": \"$project_filter\"")
        [ -n "$range_min" ] && filter_parts+=("\"range_min\": $range_min")
        [ -n "$range_max" ] && filter_parts+=("\"range_max\": $range_max")
        filter_json+=$(IFS=,; echo "${filter_parts[*]}")
        filter_json+='},'
    fi

    cat > "$QA_REPORT_JSON" << EOF
{
  "generated": "$TIMESTAMP",
  ${filter_json}
  "summary": {
    "total_with_qa": $TOTAL_QA_TOUCHED,
    "qa_complete": $COMPLETE_COUNT,
    "needs_qa_after": $NEEDS_AFTER_COUNT,
    "needs_qa_before": $NEEDS_BEFORE_COUNT,
    "completion_rate": $(echo "scale=1; $COMPLETE_COUNT * 100 / ($TOTAL_QA_TOUCHED + 1)" | bc 2>/dev/null || echo "0")
  },
  "tickets": {
    "complete": $COMPLETE_TICKETS,
    "needs_after": $NEEDS_AFTER_TICKETS,
    "needs_before": $NEEDS_BEFORE_TICKETS
  }
}
EOF

    # Build markdown report
    cat > "$QA_REPORT_MD" << EOF
# $report_title

**Generated:** $TIMESTAMP
EOF

    # Add filter description if filtering was applied
    if [ -n "$filter_desc" ]; then
        echo "**Filter:** $filter_desc" >> "$QA_REPORT_MD"
    fi

    cat >> "$QA_REPORT_MD" << EOF

---

## Summary

| Metric | Count |
|--------|-------|
| QA Complete (Before + After) | $COMPLETE_COUNT |
| Needs QA After | $NEEDS_AFTER_COUNT |
| Needs QA Before | $NEEDS_BEFORE_COUNT |
| **Total Tickets Touched** | $TOTAL_QA_TOUCHED |

---

## QA Complete ($COMPLETE_COUNT tickets)

These tickets have both QA Before and QA After screenshots recorded.

EOF

    # Add complete tickets to markdown
    if [ "$COMPLETE_COUNT" -gt 0 ]; then
        echo "$COMPLETE_TICKETS" | jq -r '.[] | "- **\(.id)**: \(.name[0:50])"' >> "$QA_REPORT_MD"
    else
        echo "_No tickets with complete QA_" >> "$QA_REPORT_MD"
    fi

    cat >> "$QA_REPORT_MD" << EOF

---

## Needs QA After ($NEEDS_AFTER_COUNT tickets)

These tickets have QA Before but are missing QA After verification.

EOF

    # Add needs-after tickets to markdown
    if [ "$NEEDS_AFTER_COUNT" -gt 0 ]; then
        echo "$NEEDS_AFTER_TICKETS" | jq -r '.[] | "- **\(.id)**: \(.name[0:50]) - Status: \(.status)"' >> "$QA_REPORT_MD"
    else
        echo "_No tickets pending QA After_" >> "$QA_REPORT_MD"
    fi

    cat >> "$QA_REPORT_MD" << EOF

---

## Needs QA Before ($NEEDS_BEFORE_COUNT tickets)

These tickets haven't started QA process yet.

EOF

    # Add needs-before tickets to markdown (first 10)
    if [ "$NEEDS_BEFORE_COUNT" -gt 0 ]; then
        echo "$NEEDS_BEFORE_TICKETS" | jq -r '.[:10][] | "- **\(.id)**: \(.name[0:50]) - Status: \(.status)"' >> "$QA_REPORT_MD"
        if [ "$NEEDS_BEFORE_COUNT" -gt 10 ]; then
            echo "" >> "$QA_REPORT_MD"
            echo "_...and $((NEEDS_BEFORE_COUNT - 10)) more tickets_" >> "$QA_REPORT_MD"
        fi
    else
        echo "_All tickets have QA Before recorded_" >> "$QA_REPORT_MD"
    fi

    cat >> "$QA_REPORT_MD" << EOF

---

## Next Actions

EOF

    if [ "$NEEDS_AFTER_COUNT" -gt 0 ]; then
        echo "1. **Run QA verification** on $NEEDS_AFTER_COUNT tickets with QA Before:" >> "$QA_REPORT_MD"
        echo '   ```bash' >> "$QA_REPORT_MD"
        echo '   ./batch_workflow.sh --qa-filter needs-after' >> "$QA_REPORT_MD"
        echo '   ```' >> "$QA_REPORT_MD"
        echo "" >> "$QA_REPORT_MD"
    fi

    if [ "$NEEDS_BEFORE_COUNT" -gt 0 ]; then
        echo "2. **Record QA Before** for $NEEDS_BEFORE_COUNT tickets:" >> "$QA_REPORT_MD"
        echo '   ```bash' >> "$QA_REPORT_MD"
        echo '   ./record-qa.sh TICK-### --before' >> "$QA_REPORT_MD"
        echo '   ```' >> "$QA_REPORT_MD"
    fi

    echo "" >> "$QA_REPORT_MD"
    echo "---" >> "$QA_REPORT_MD"
    echo "" >> "$QA_REPORT_MD"
    echo "*Report files: \`$QA_REPORT_JSON\` and \`$QA_REPORT_MD\`*" >> "$QA_REPORT_MD"

    # Display summary
    echo "========================================"
    echo "QA REPORT SUMMARY"
    echo "========================================"
    echo ""
    echo -e "  QA Complete:      ${GREEN}$COMPLETE_COUNT${NC}"
    echo -e "  Needs QA After:   ${YELLOW}$NEEDS_AFTER_COUNT${NC}"
    echo -e "  Needs QA Before:  ${BLUE}$NEEDS_BEFORE_COUNT${NC}"
    echo ""
    echo -e "  Total touched:    $TOTAL_QA_TOUCHED"
    echo ""
    echo -e "${GREEN}✓ Reports saved:${NC}"
    echo "  JSON: $QA_REPORT_JSON"
    echo "  Markdown: $QA_REPORT_MD"
    echo ""
}

# Generate context briefing for session handoff
generate_context() {
    echo "========================================"
    echo "Generating Context Briefing"
    echo "========================================"
    echo ""

    CONTEXT_FILE="$RESULTS_DIR/batch_context.md"
    BATCHES_DIR="$RESULTS_DIR/batches"

    # Create batches cache directory
    mkdir -p "$BATCHES_DIR"

    # Get current batch
    CURRENT=$(get_current_batch)
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Start building context file
    cat > "$CONTEXT_FILE" << EOF
# Batch Workflow Context Briefing

**Generated:** $TIMESTAMP
**Purpose:** Resume context after Claude session handoff

---

## Current State

EOF

    if [ -n "$CURRENT" ]; then
        # Get batch state details
        BATCH_STATUS=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b].status // "unknown"')
        STARTED=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b].started // "unknown"')
        QA_STATUS=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b].qa_status // "not started"')
        LAST_REFRESH=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b].last_refresh // "never"')

        cat >> "$CONTEXT_FILE" << EOF
**Active Batch:** \`$CURRENT\`
- Status: $BATCH_STATUS
- Started: $STARTED
- QA Status: $QA_STATUS
- Last Refresh: $LAST_REFRESH

EOF

        # Add tickets to context
        if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
            TICKET_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$CURRENT" '
                [.[] | select(.batch_key == $b)] | length')

            cat >> "$CONTEXT_FILE" << EOF
## Tickets in Batch ($TICKET_COUNT total)

| ID | Name | Category |
|----|------|----------|
EOF

            # Add ticket rows
            cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$CURRENT" '
                [.[] | select(.batch_key == $b)] |
                .[] |
                "| \(.id) | \(.name | .[0:50]) | \(.category) |"' >> "$CONTEXT_FILE"

            # Cache individual ticket data
            echo ""
            echo "Caching ticket data..."
            while IFS= read -r ticket; do
                TICKET_ID=$(echo "$ticket" | jq -r '.id')
                echo "$ticket" > "$BATCHES_DIR/${TICKET_ID}.json"
            done < <(jq -c --arg b "$CURRENT" '.[] | select(.batch_key == $b)' "$RESULTS_DIR/categorized_tickets.json")
            CACHED_COUNT=$(ls "$BATCHES_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
            echo "  Cached $CACHED_COUNT ticket files"
        fi

        # Determine next action
        cat >> "$CONTEXT_FILE" << EOF

## Recommended Next Action

EOF

        if [ "$BATCH_STATUS" = "completed" ]; then
            echo "Start a new batch: \`./batch_workflow.sh --list\`" >> "$CONTEXT_FILE"
        elif [ "$QA_STATUS" = "passed" ]; then
            echo "Complete the batch: \`./batch_workflow.sh --complete $CURRENT --pr-url <url>\`" >> "$CONTEXT_FILE"
        elif [ "$QA_STATUS" = "failed" ]; then
            echo "Fix issues and re-run QA: \`./batch_workflow.sh --qa $CURRENT\`" >> "$CONTEXT_FILE"
        else
            cat >> "$CONTEXT_FILE" << EOF
1. Continue development work on tickets
2. Run QA: \`./batch_workflow.sh --qa $CURRENT\`
3. Record results: \`./batch_workflow.sh --record-qa $CURRENT --qa-status passed\`
EOF
        fi

    else
        cat >> "$CONTEXT_FILE" << EOF
**No active batch**

Start a new batch:
\`\`\`bash
./batch_workflow.sh --list      # See available batches
./batch_workflow.sh --start <batch-key>
\`\`\`
EOF
        # Cache all categorized tickets even when no active batch
        if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
            echo ""
            echo "Caching all categorized ticket data..."
            while IFS= read -r ticket; do
                TICKET_ID=$(echo "$ticket" | jq -r '.id')
                echo "$ticket" > "$BATCHES_DIR/${TICKET_ID}.json"
            done < <(jq -c '.[]' "$RESULTS_DIR/categorized_tickets.json")
            CACHED_COUNT=$(ls "$BATCHES_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
            echo "  Cached $CACHED_COUNT ticket files"

            # Add summary of available tickets to context
            TOTAL_TICKETS=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq 'length')
            cat >> "$CONTEXT_FILE" << EOF

## Available Tickets ($TOTAL_TICKETS total)

Categorized tickets cached in \`$BATCHES_DIR/\`
Run \`./batch_workflow.sh --list\` to see batches by category.
EOF
        fi
    fi

    # Add workflow state dump
    cat >> "$CONTEXT_FILE" << EOF

---

## Workflow Commands

\`\`\`bash
./batch_workflow.sh --status    # Check current status
./batch_workflow.sh --resume    # Resume from saved state
./batch_workflow.sh --refresh   # Sync with Notion
./batch_workflow.sh --context   # Regenerate this briefing
\`\`\`

## File Locations

- Workflow state: \`$WORKFLOW_STATE\`
- Categorized tickets: \`$RESULTS_DIR/categorized_tickets.json\`
- Cached tickets: \`$BATCHES_DIR/\`
- This briefing: \`$CONTEXT_FILE\`

---

*Load this file at the start of a new Claude session to restore context.*
EOF

    echo ""
    echo -e "${GREEN}✓ Context briefing generated${NC}"
    echo ""
    echo "Files created:"
    echo "  - $CONTEXT_FILE"
    echo "  - $BATCHES_DIR/ (ticket cache)"
    echo ""
    echo "========================================"
    echo "BRIEFING SUMMARY (copy to new session)"
    echo "========================================"
    echo ""

    # Output a compact summary for easy copy/paste
    if [ -n "$CURRENT" ]; then
        echo "I'm working on batch '$CURRENT' ($BATCH_STATUS)."
        echo "QA Status: $QA_STATUS"
        if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
            echo "Tickets: $TICKET_COUNT in batch"
        fi
        echo ""
        echo "Key files:"
        echo "  - $RESULTS_DIR/batch_context.md (full briefing)"
        echo "  - $RESULTS_DIR/categorized_tickets.json"
    else
        echo "No batch currently in progress."
        echo "Run: ./batch_workflow.sh --list"
    fi
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
        --context|--briefing|--dump-state)
            COMMAND="context"
            shift
            ;;
        --qa-report)
            COMMAND="qa-report"
            shift
            ;;
        --project)
            QA_PROJECT="$2"
            shift 2
            ;;
        --range)
            QA_RANGE="$2"
            shift 2
            ;;
        --qa-filter|--qa-query)
            COMMAND="qa-filter"
            QA_FILTER_TYPE="$2"
            shift 2
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
    context)
        generate_context
        ;;
    qa-report)
        generate_qa_report
        ;;
    qa-filter)
        query_qa_status "${QA_FILTER_TYPE:-needs-after}"
        ;;
    *)
        show_usage
        ;;
esac
