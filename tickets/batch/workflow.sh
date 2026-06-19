#!/bin/bash

# End-to-End Batch Processing Workflow (Firestore-backed)
# Usage:
#   ./workflow.sh --start pdp-P1-QuickWins
#   ./workflow.sh --qa pdp-P1-QuickWins
#   ./workflow.sh --complete pdp-P1-QuickWins
#   ./workflow.sh --status

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_firestore-lib.sh"

# Script locations
TICKETS_SCRIPTS="$SCRIPT_DIR/.."
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
    echo "  --resume                Resume interrupted batch"
    echo "  --refresh               Refresh batch status from Firestore"
    echo "  --context               Generate context briefing"
    echo "  --fetch, -f BATCH       Fetch ticket details for batch"
    echo "  --qa BATCH              Run QA verification for batch"
    echo "  --record-qa BATCH       Record QA results"
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
    exit 1
}

# Initialize workflow state
init_state() {
    mkdir -p "$RESULTS_DIR"
    if [ ! -f "$WORKFLOW_STATE" ]; then
        echo '{"current_batch": null, "batches": {}}' > "$WORKFLOW_STATE"
    fi
}

get_current_batch() {
    cat "$WORKFLOW_STATE" | jq -r '.current_batch // empty'
}

set_current_batch() {
    local batch="$1"
    local tmp=$(mktemp)
    cat "$WORKFLOW_STATE" | jq --arg b "$batch" '.current_batch = $b' > "$tmp"
    mv "$tmp" "$WORKFLOW_STATE"
}

update_batch_state() {
    local batch="$1"
    local key="$2"
    local value="$3"
    local tmp=$(mktemp)
    cat "$WORKFLOW_STATE" | jq --arg b "$batch" --arg k "$key" --arg v "$value" \
        '.batches[$b][$k] = $v' > "$tmp"
    mv "$tmp" "$WORKFLOW_STATE"
}

show_status() {
    echo "========================================"
    echo "Workflow Status"
    echo "========================================"
    echo ""

    CURRENT=$(get_current_batch)
    if [ -n "$CURRENT" ]; then
        echo -e "Current batch: ${GREEN}$CURRENT${NC}"
        echo ""

        if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
            BATCH_INFO=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$CURRENT" '
                [.[] | select(.batch_key == $b)] |
                {count: length, category: .[0].category, priority: .[0].priority_label}')

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

list_batches() {
    echo "========================================"
    echo "Available Batches"
    echo "========================================"
    echo ""

    if [ ! -f "$RESULTS_DIR/categorized_tickets.json" ]; then
        echo -e "${YELLOW}No categorized tickets found.${NC}"
        return
    fi

    echo -e "${BLUE}By Priority:${NC}"
    echo ""

    for PRIORITY in "P1-QuickWins" "P2-Structural" "P3-CrossCutting" "P4-Responsive"; do
        echo -e "${GREEN}$PRIORITY:${NC}"
        cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg p "$PRIORITY" '
            [.[] | select(.priority_label == $p)] |
            group_by(.category) |
            map({batch_key: (.[0].category + "-" + $p), category: .[0].category, count: length}) |
            sort_by(-.count) |
            .[] |
            "  \(.batch_key): \(.count) tickets"' 2>/dev/null || echo "  (none)"
        echo ""
    done
}

start_batch() {
    local batch="$1"

    echo "========================================"
    echo "Starting Batch: $batch"
    echo "========================================"
    echo ""

    if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
        BATCH_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$batch" '
            [.[] | select(.batch_key == $b)] | length')

        if [ "$BATCH_COUNT" -eq 0 ]; then
            echo -e "${RED}Batch not found: $batch${NC}"
            list_batches
            exit 1
        fi

        echo "Found $BATCH_COUNT tickets in batch"
    fi

    set_current_batch "$batch"
    update_batch_state "$batch" "started" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    update_batch_state "$batch" "status" "in_progress"

    echo ""
    echo -e "${GREEN}Batch started${NC}"
    echo ""

    # Fetch tickets
    echo "Fetching ticket details..."
    echo ""

    if [ -x "$TICKETS_SCRIPTS/ticket-batch-fetch.sh" ]; then
        "$TICKETS_SCRIPTS/ticket-batch-fetch.sh" --batch "$batch" --output "$RESULTS_DIR/batch-$batch"
        update_batch_state "$batch" "fetched" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
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

run_qa() {
    local batch="$1"

    echo "========================================"
    echo "QA Verification: $batch"
    echo "========================================"
    echo ""

    # List tickets in batch
    echo "Tickets to verify:"
    cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$batch" '
        [.[] | select(.batch_key == $b)] |
        .[] |
        "  \(.id): \(.name)"' | head -20

    TICKET_COUNT=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$batch" '
        [.[] | select(.batch_key == $b)] | length')

    if [ "$TICKET_COUNT" -gt 20 ]; then
        echo "  ... and $((TICKET_COUNT - 20)) more"
    fi

    echo ""
    echo "After QA verification, run:"
    echo "  $0 --record-qa $batch --qa-status passed"
    echo "  $0 --record-qa $batch --qa-status failed --summary 'Issue description'"

    update_batch_state "$batch" "qa_started" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

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

    if [ -x "$TICKETS_SCRIPTS/ticket-qa.sh" ]; then
        CMD=("$TICKETS_SCRIPTS/ticket-qa.sh" "--batch" "$batch" "--status" "$qa_status")
        [ -n "$qa_by" ] && CMD+=("--by" "$qa_by")
        [ -n "$summary" ] && CMD+=("--notes" "$summary")

        "${CMD[@]}"

        update_batch_state "$batch" "qa_status" "$qa_status"
        update_batch_state "$batch" "qa_completed" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    fi

    echo ""
    if [ "$qa_status" = "passed" ]; then
        echo -e "${GREEN}QA Passed!${NC}"
        echo "Complete the batch: $0 --complete $batch"
    else
        echo -e "${RED}QA Failed${NC}"
        echo "Fix issues and re-run: $0 --qa $batch"
    fi
}

complete_batch() {
    local batch="$1"
    local pr_url="$2"
    local summary="$3"

    echo "========================================"
    echo "Completing Batch: $batch"
    echo "========================================"
    echo ""

    QA_STATUS=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$batch" '.batches[$b].qa_status // empty')

    if [ "$QA_STATUS" != "passed" ]; then
        echo -e "${YELLOW}Warning: QA status is not 'passed' (current: $QA_STATUS)${NC}"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    if [ -x "$TICKETS_SCRIPTS/ticket-batch-complete.sh" ]; then
        CMD=("$TICKETS_SCRIPTS/ticket-batch-complete.sh" "--batch" "$batch")
        [ -n "$pr_url" ] && CMD+=("--pr-url" "$pr_url")
        [ -n "$summary" ] && CMD+=("--summary" "$summary")

        "${CMD[@]}"

        update_batch_state "$batch" "completed" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        update_batch_state "$batch" "status" "completed"
        set_current_batch ""
    fi

    echo ""
    echo -e "${GREEN}Batch completed!${NC}"
}

refresh_batch() {
    echo "========================================"
    echo "Refreshing Batch Status from Firestore"
    echo "========================================"
    echo ""

    CURRENT=$(get_current_batch)
    if [ -z "$CURRENT" ]; then
        echo -e "${YELLOW}No batch currently in progress.${NC}"
        return
    fi

    echo "Current batch: $CURRENT"
    echo ""

    if [ -f "$RESULTS_DIR/categorized_tickets.json" ]; then
        # Get ticket IDs for this batch
        TICKET_IDS=$(cat "$RESULTS_DIR/categorized_tickets.json" | jq -r --arg b "$CURRENT" '
            [.[] | select(.batch_key == $b)] | .[].id' | head -20)

        COMPLETED=0
        IN_PROGRESS=0
        BACKLOG=0
        TOTAL=0

        for TICK in $TICKET_IDS; do
            TOTAL=$((TOTAL + 1))
            RESULT=$(query_ticket "$TICK")
            STATUS=$(fs_string "$RESULT" "status")

            case "$STATUS" in
                "Complete"|"Completed"|"Done")
                    COMPLETED=$((COMPLETED + 1))
                    ;;
                "In Progress")
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

        update_batch_state "$CURRENT" "last_refresh" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        update_batch_state "$CURRENT" "completed_count" "$COMPLETED"

        if [ "$COMPLETED" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
            echo ""
            echo -e "${GREEN}All tickets completed!${NC}"
            echo "Ready to finalize: $0 --complete $CURRENT"
        fi
    fi

    echo ""
    echo -e "${GREEN}Refresh complete${NC}"
}

resume_batch() {
    CURRENT=$(get_current_batch)
    if [ -z "$CURRENT" ]; then
        echo -e "${YELLOW}No batch currently in progress.${NC}"
        echo "Start with: $0 --start <batch-key>"
        exit 1
    fi

    echo -e "Resuming batch: ${GREEN}$CURRENT${NC}"
    echo ""

    BATCH_STATUS=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b].status // "unknown"')
    QA_STATUS=$(cat "$WORKFLOW_STATE" | jq -r --arg b "$CURRENT" '.batches[$b].qa_status // empty')

    echo "Status: $BATCH_STATUS"
    [ -n "$QA_STATUS" ] && echo "QA: $QA_STATUS"
    echo ""

    if [ "$QA_STATUS" = "passed" ]; then
        echo "Ready to complete: $0 --complete $CURRENT"
    elif [ "$QA_STATUS" = "failed" ]; then
        echo "Fix issues then: $0 --qa $CURRENT"
    else
        echo "Continue development, then: $0 --qa $CURRENT"
    fi
}

reset_workflow() {
    rm -f "$WORKFLOW_STATE"
    init_state
    echo -e "${GREEN}Workflow state reset${NC}"
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
        --start|-s) COMMAND="start"; BATCH="$2"; shift 2 ;;
        --fetch|-f) COMMAND="fetch"; BATCH="$2"; shift 2 ;;
        --qa) COMMAND="qa"; BATCH="$2"; shift 2 ;;
        --record-qa) COMMAND="record-qa"; BATCH="$2"; shift 2 ;;
        --complete|-c) COMMAND="complete"; BATCH="$2"; shift 2 ;;
        --status) COMMAND="status"; shift ;;
        --list) COMMAND="list"; shift ;;
        --reset) COMMAND="reset"; shift ;;
        --resume) COMMAND="resume"; shift ;;
        --refresh) COMMAND="refresh"; shift ;;
        --context) COMMAND="context"; shift ;;
        --pr-url) PR_URL="$2"; shift 2 ;;
        --qa-status) QA_STATUS="$2"; shift 2 ;;
        --qa-by) QA_BY="$2"; shift 2 ;;
        --summary) SUMMARY="$2"; shift 2 ;;
        --help|-h) show_usage ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; show_usage ;;
    esac
done

case "$COMMAND" in
    start) start_batch "$BATCH" ;;
    fetch)
        if [ -x "$TICKETS_SCRIPTS/ticket-batch-fetch.sh" ]; then
            "$TICKETS_SCRIPTS/ticket-batch-fetch.sh" --batch "$BATCH" --output "$RESULTS_DIR/batch-$BATCH"
        fi
        ;;
    qa) run_qa "$BATCH" ;;
    record-qa) record_qa_results "$BATCH" "$QA_STATUS" "$QA_BY" "$SUMMARY" ;;
    complete) complete_batch "$BATCH" "$PR_URL" "$SUMMARY" ;;
    status) show_status ;;
    list) list_batches ;;
    reset) reset_workflow ;;
    resume) resume_batch ;;
    refresh) refresh_batch ;;
    *) show_usage ;;
esac
