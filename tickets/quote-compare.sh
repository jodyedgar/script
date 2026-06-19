#!/bin/bash
# quote-compare.sh - Compare fetched tickets against completed work
# Usage: ./quote-compare.sh [--project TAG]
# Example: ./quote-compare.sh --project hs-figma

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

OUTPUT_DIR="/tmp/quote-analysis"
FETCHED_DIR="$OUTPUT_DIR/fetched_tickets"
COMPLETED_COMMITS="$OUTPUT_DIR/completed_commits.txt"
COMPLETED_TICKETS="$OUTPUT_DIR/completed_tickets.txt"
FINAL_REPORT="$OUTPUT_DIR/QUOTE-REPORT-$(date +%Y%m%d-%H%M%S).md"

# Parse arguments
PROJECT_FILTER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --project|-p)
            PROJECT_FILTER="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "${BLUE}=== Quote Comparison Analysis ===${NC}"
if [ -n "$PROJECT_FILTER" ]; then
    echo -e "Filtering by project: ${CYAN}#$PROJECT_FILTER${NC}"
fi
echo ""

# Check prerequisites
if [ ! -d "$FETCHED_DIR" ]; then
    echo -e "${RED}Error: No fetched tickets found. Run quote-batch-fetch.sh first.${NC}"
    exit 1
fi

FETCHED_COUNT=$(ls -1 "$FETCHED_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
if [ "$FETCHED_COUNT" -eq 0 ]; then
    echo -e "${RED}Error: No ticket files found in $FETCHED_DIR${NC}"
    exit 1
fi

echo "Analyzing $FETCHED_COUNT fetched tickets..."

# Create keyword index from completed commits
echo "Building keyword index from completed work..."

# Initialize report
cat > "$FINAL_REPORT" << 'HEADER'
# Quote Analysis - Final Report

**Generated:** REPORT_DATE

## Overview

This report identifies tickets that may be duplicates of already-completed work.
Review flagged items carefully before including in quotes.

---

## Quick Reference

| Status | Description | Action |
|--------|-------------|--------|
| DUPLICATE | Exact ticket number in git history | DO NOT BILL |
| HIGH SIMILARITY | Strong keyword match (>50%) | REVIEW - likely duplicate |
| MEDIUM SIMILARITY | Moderate match (25-50%) | REVIEW - may be related |
| LOW SIMILARITY | Minor match (<25%) | Likely NEW WORK |
| NEW | No matches found | BILLABLE |

---

HEADER

sed -i '' "s/REPORT_DATE/$(date '+%Y-%m-%d %H:%M:%S')/" "$FINAL_REPORT"

# Counters
DUPLICATE=0
HIGH_SIM=0
MEDIUM_SIM=0
LOW_SIM=0
NEW_WORK=0
FAILED=0
SKIPPED=0
ALREADY_DONE=0

# Content holders
ALREADY_DONE_CONTENT=""

# Build keyword arrays from completed commits
declare -a COMMIT_KEYWORDS
while IFS= read -r line; do
    # Extract keywords from each commit message
    keywords=$(echo "$line" | tr '[:upper:]' '[:lower:]' | \
        grep -oE '\b[a-z]{4,}\b' | sort -u | tr '\n' ' ')
    COMMIT_KEYWORDS+=("$keywords")
done < "$COMPLETED_COMMITS"

# Function to calculate similarity
calculate_similarity() {
    local ticket_text="$1"
    local max_score=0
    local best_match=""

    # Normalize ticket text
    local ticket_words=$(echo "$ticket_text" | tr '[:upper:]' '[:lower:]' | \
        grep -oE '\b[a-z]{4,}\b' | sort -u)

    while IFS= read -r commit; do
        local commit_words=$(echo "$commit" | tr '[:upper:]' '[:lower:]' | \
            grep -oE '\b[a-z]{4,}\b' | sort -u)

        # Count matching words
        local matches=0
        local total_commit_words=$(echo "$commit_words" | wc -w | tr -d ' ')

        for word in $ticket_words; do
            if echo "$commit_words" | grep -qw "$word"; then
                ((matches++))
            fi
        done

        # Calculate score (percentage of commit words matched)
        if [ "$total_commit_words" -gt 0 ]; then
            local score=$((matches * 100 / total_commit_words))
            if [ "$score" -gt "$max_score" ]; then
                max_score=$score
                best_match="$commit"
            fi
        fi
    done < "$COMPLETED_COMMITS"

    echo "$max_score|$best_match"
}

# Process sections
echo "" >> "$FINAL_REPORT"
echo "## Detailed Analysis" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"

HIGH_SIM_CONTENT=""

# Section: Medium similarity
MEDIUM_SIM_CONTENT=""

# Section: Low similarity / New work
LOW_SIM_CONTENT=""
NEW_CONTENT=""

echo "Processing tickets..."

for file in "$FETCHED_DIR"/*.json; do
    TICKET=$(basename "$file" .json)

    # Check for fetch errors
    if grep -q '"error"' "$file" 2>/dev/null; then
        ((FAILED++))
        continue
    fi

    # Extract fields from JSON using jq
    TITLE=$(jq -r '.title // ""' "$file" 2>/dev/null)
    DESC=$(jq -r '.description // ""' "$file" 2>/dev/null)
    STATUS=$(jq -r '.status // ""' "$file" 2>/dev/null)

    # Extract project tag from title (e.g., #hs-figma)
    PROJECT_TAG=$(echo "$TITLE" | grep -oE '#[a-zA-Z0-9-]+' | head -1 | tr -d '#')

    # Filter by project if specified
    if [ -n "$PROJECT_FILTER" ] && [ "$PROJECT_TAG" != "$PROJECT_FILTER" ]; then
        ((SKIPPED++))
        continue
    fi

    # Check if already marked Complete in Notion (may already be billed)
    if [[ "$STATUS" == "Complete" || "$STATUS" == "Done" ]]; then
        ALREADY_DONE_CONTENT+="| $TICKET | $TITLE | $STATUS |\n"
        ((ALREADY_DONE++))
        continue
    fi

    # Clean title for comparison (remove project tag)
    CLEAN_TITLE=$(echo "$TITLE" | sed 's/#[a-zA-Z0-9-]* *//')

    # Combine for analysis
    TICKET_TEXT="$CLEAN_TITLE $DESC"

    # Calculate similarity
    RESULT=$(calculate_similarity "$TICKET_TEXT")
    SCORE=$(echo "$RESULT" | cut -d'|' -f1)
    BEST_MATCH=$(echo "$RESULT" | cut -d'|' -f2)

    echo -ne "\r  Processing $TICKET (similarity: $SCORE%)...          "

    if [ "$SCORE" -ge 50 ]; then
        HIGH_SIM_CONTENT+="| $TICKET | $TITLE | $SCORE% | $BEST_MATCH |\n"
        ((HIGH_SIM++))
    elif [ "$SCORE" -ge 25 ]; then
        MEDIUM_SIM_CONTENT+="| $TICKET | $TITLE | $SCORE% | $BEST_MATCH |\n"
        ((MEDIUM_SIM++))
    elif [ "$SCORE" -ge 10 ]; then
        LOW_SIM_CONTENT+="| $TICKET | $TITLE | $SCORE% |\n"
        ((LOW_SIM++))
    else
        NEW_CONTENT+="| $TICKET | $TITLE |\n"
        ((NEW_WORK++))
    fi

done

echo ""
echo ""

# Write sections to report

# First: Already Complete in Notion
echo "### ALREADY COMPLETE IN NOTION" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"
echo "These tickets are marked Complete/Done in Notion (may already be billed):" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"
if [ -n "$ALREADY_DONE_CONTENT" ]; then
    echo "| Ticket | Title | Status |" >> "$FINAL_REPORT"
    echo "|--------|-------|--------|" >> "$FINAL_REPORT"
    echo -e "$ALREADY_DONE_CONTENT" >> "$FINAL_REPORT"
else
    echo "*No tickets marked complete in Notion*" >> "$FINAL_REPORT"
fi

echo "" >> "$FINAL_REPORT"

# High similarity
echo "### HIGH SIMILARITY - Review Carefully" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"
echo "These tickets have strong keyword overlap with completed work:" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"
if [ -n "$HIGH_SIM_CONTENT" ]; then
    echo "| Ticket | Title | Match % | Similar To |" >> "$FINAL_REPORT"
    echo "|--------|-------|---------|------------|" >> "$FINAL_REPORT"
    echo -e "$HIGH_SIM_CONTENT" >> "$FINAL_REPORT"
else
    echo "*No high similarity matches found*" >> "$FINAL_REPORT"
fi

echo "" >> "$FINAL_REPORT"
echo "### MEDIUM SIMILARITY - May Be Related" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"

if [ -n "$MEDIUM_SIM_CONTENT" ]; then
    echo "| Ticket | Title | Match % | Similar To |" >> "$FINAL_REPORT"
    echo "|--------|-------|---------|------------|" >> "$FINAL_REPORT"
    echo -e "$MEDIUM_SIM_CONTENT" >> "$FINAL_REPORT"
else
    echo "*No medium similarity matches found*" >> "$FINAL_REPORT"
fi

echo "" >> "$FINAL_REPORT"
echo "### LOW SIMILARITY - Likely New Work" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"

if [ -n "$LOW_SIM_CONTENT" ]; then
    echo "| Ticket | Title | Match % |" >> "$FINAL_REPORT"
    echo "|--------|-------|---------|" >> "$FINAL_REPORT"
    echo -e "$LOW_SIM_CONTENT" >> "$FINAL_REPORT"
else
    echo "*No low similarity matches*" >> "$FINAL_REPORT"
fi

echo "" >> "$FINAL_REPORT"
echo "### NEW WORK - Billable" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"

if [ -n "$NEW_CONTENT" ]; then
    echo "| Ticket | Title |" >> "$FINAL_REPORT"
    echo "|--------|-------|" >> "$FINAL_REPORT"
    echo -e "$NEW_CONTENT" >> "$FINAL_REPORT"
else
    echo "*All tickets matched existing work*" >> "$FINAL_REPORT"
fi

# Summary section
echo "" >> "$FINAL_REPORT"
echo "---" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"
echo "## Summary" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"
echo "| Category | Count | Billing Status |" >> "$FINAL_REPORT"
echo "|----------|-------|----------------|" >> "$FINAL_REPORT"
echo "| Already Complete in Notion | $ALREADY_DONE | Check if billed |" >> "$FINAL_REPORT"
echo "| High Similarity | $HIGH_SIM | REVIEW |" >> "$FINAL_REPORT"
echo "| Medium Similarity | $MEDIUM_SIM | REVIEW |" >> "$FINAL_REPORT"
echo "| Low Similarity | $LOW_SIM | Likely Billable |" >> "$FINAL_REPORT"
echo "| New Work | $NEW_WORK | Billable |" >> "$FINAL_REPORT"
echo "| Skipped (other project) | $SKIPPED | N/A |" >> "$FINAL_REPORT"
echo "| Fetch Failed | $FAILED | Unknown |" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"
echo "**Total Analyzed:** $((ALREADY_DONE + HIGH_SIM + MEDIUM_SIM + LOW_SIM + NEW_WORK))" >> "$FINAL_REPORT"
echo "**Total Skipped:** $SKIPPED" >> "$FINAL_REPORT"
echo "" >> "$FINAL_REPORT"

echo -e "${GREEN}=== Analysis Complete ===${NC}"
echo ""
echo -e "Report saved to: ${BLUE}$FINAL_REPORT${NC}"
echo ""
echo "Summary:"
echo "  Already Complete in Notion: $ALREADY_DONE"
echo "  High Similarity (review):   $HIGH_SIM"
echo "  Medium Similarity (review): $MEDIUM_SIM"
echo "  Low Similarity (likely new): $LOW_SIM"
echo "  New Work (billable):        $NEW_WORK"
echo "  Skipped (other project):    $SKIPPED"
echo "  Fetch Failed:               $FAILED"
echo ""
echo -e "${YELLOW}Next: Review the HIGH and MEDIUM similarity tickets manually${NC}"
