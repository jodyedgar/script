#!/bin/bash

# Ticket Time Estimator with Credit System
# Usage: ./ticket-time-estimator.sh START_NUM END_NUM
# Example: ./ticket-time-estimator.sh 975 1001

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check arguments
if [ "$#" -ne 2 ]; then
    echo -e "${RED}Usage: $0 START_NUM END_NUM${NC}"
    echo "Example: $0 975 1001"
    exit 1
fi

START=$1
END=$2

# Validate numbers
if ! [[ "$START" =~ ^[0-9]+$ ]] || ! [[ "$END" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: START and END must be numbers${NC}"
    exit 1
fi

if [ "$START" -gt "$END" ]; then
    echo -e "${RED}Error: START must be less than or equal to END${NC}"
    exit 1
fi

# Credit mapping
QUICK_CREDITS=1
SMALL_CREDITS=2
MEDIUM_CREDITS=4
LARGE_CREDITS=5

# Temporary file to store ticket data
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        TICKET TIME ESTIMATOR WITH CREDIT SYSTEM            ║${NC}"
echo -e "${CYAN}║                  TICK-$START to TICK-$END                        ║${NC}"
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo ""
echo -e "${YELLOW}Fetching tickets...${NC}"
echo ""

# Fetch all tickets
for i in $(seq $START $END); do
    TICKET_ID="TICK-$i"
    echo -ne "${BLUE}Fetching $TICKET_ID...${NC}\r"

    # Fetch ticket data (suppress status updates)
    TICKET_DATA=$(~/Dropbox/scripts/notion/fetch-notion-ticket.sh "$TICKET_ID" 2>&1)

    # Extract title and status
    TITLE=$(echo "$TICKET_DATA" | grep "^Title:" | sed 's/^Title: //')
    STATUS=$(echo "$TICKET_DATA" | grep "^Status:" | sed 's/^Status: //')

    # Store in temp file
    echo "$i|$TITLE|$STATUS" >> "$TEMP_FILE"
done

echo -e "\n${GREEN}✓ Fetched $(wc -l < $TEMP_FILE) tickets${NC}\n"

# Initialize counters
TOTAL_CREDITS=0
COMPLETED_CREDITS=0
QUICK_COUNT=0
SMALL_COUNT=0
MEDIUM_COUNT=0
LARGE_COUNT=0
COMPLETED_COUNT=0

# Display header
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Ticket  │ Credits │  Time   │ Status      │ Title                            ║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════════════════════════╣${NC}"

# Process each ticket
while IFS='|' read -r NUM TITLE STATUS; do
    TICKET_ID="TICK-$NUM"

    # Truncate title if too long
    TITLE_SHORT=$(echo "$TITLE" | cut -c1-35)

    # Determine complexity based on title keywords
    CREDITS=0
    TIME=""
    COMPLEXITY=""

    # Check if completed
    if [[ "$STATUS" == "Complete" ]] || [[ "$STATUS" == "Done" ]]; then
        COMPLEXITY="✅ Done"
        TIME="--"
        CREDITS=0
        ((COMPLETED_COUNT++))
    # Quick fixes (simple text/icon changes)
    elif [[ "$TITLE" =~ (get rid of|remove|should be|change.*to) ]] && [[ ! "$TITLE" =~ (page|template|incorrect header) ]]; then
        COMPLEXITY="⚡ Quick"
        CREDITS=$QUICK_CREDITS
        TIME="5-15m"
        ((QUICK_COUNT++))
        ((TOTAL_CREDITS += CREDITS))
    # Small tasks (CSS/spacing/font fixes)
    elif [[ "$TITLE" =~ (spacing|white space|font|color|breadcrumb|disappears) ]]; then
        COMPLEXITY="🔧 Small"
        CREDITS=$SMALL_CREDITS
        TIME="15-30m"
        ((SMALL_COUNT++))
        ((TOTAL_CREDITS += CREDITS))
    # Large tasks (pages, templates, major features)
    elif [[ "$TITLE" =~ (page not done|Search feature|incorrect header.*template|account pages|renderings vs lifestyle) ]]; then
        COMPLEXITY="🏗️ Large"
        CREDITS=$LARGE_CREDITS
        TIME="1-2h"
        ((LARGE_COUNT++))
        ((TOTAL_CREDITS += CREDITS))
    # Medium tasks (everything else)
    else
        COMPLEXITY="📄 Medium"
        CREDITS=$MEDIUM_CREDITS
        TIME="30-60m"
        ((MEDIUM_COUNT++))
        ((TOTAL_CREDITS += CREDITS))
    fi

    # Format output
    printf "${CYAN}║${NC} %-8s │ %-7s │ %-7s │ %-11s │ %-36s ${CYAN}║${NC}\n" \
        "$TICKET_ID" "$CREDITS" "$TIME" "$COMPLEXITY" "$TITLE_SHORT"

done < "$TEMP_FILE"

echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Calculate totals
TOTAL_TICKETS=$((COMPLETED_COUNT + QUICK_COUNT + SMALL_COUNT + MEDIUM_COUNT + LARGE_COUNT))
REMAINING_TICKETS=$((TOTAL_TICKETS - COMPLETED_COUNT))

# Summary
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                      CREDIT SUMMARY                        ║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║${NC} %-58s ${CYAN}║${NC}\n" "Total Tickets: $TOTAL_TICKETS"
printf "${CYAN}║${NC} %-58s ${CYAN}║${NC}\n" "  ✅ Completed: $COMPLETED_COUNT tickets"
printf "${CYAN}║${NC} %-58s ${CYAN}║${NC}\n" "  📋 Remaining: $REMAINING_TICKETS tickets"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║${NC} ${GREEN}%-56s${NC} ${CYAN}║${NC}\n" "Remaining by Complexity:"
printf "${CYAN}║${NC}   ⚡ Quick fixes:  %-2d tickets × 1 credit = %-3d credits  ${CYAN}║${NC}\n" $QUICK_COUNT $((QUICK_COUNT * QUICK_CREDITS))
printf "${CYAN}║${NC}   🔧 Small tasks:  %-2d tickets × 2 credits = %-3d credits ${CYAN}║${NC}\n" $SMALL_COUNT $((SMALL_COUNT * SMALL_CREDITS))
printf "${CYAN}║${NC}   📄 Medium tasks: %-2d tickets × 4 credits = %-3d credits ${CYAN}║${NC}\n" $MEDIUM_COUNT $((MEDIUM_COUNT * MEDIUM_CREDITS))
printf "${CYAN}║${NC}   🏗️  Large tasks:  %-2d tickets × 5 credits = %-3d credits ${CYAN}║${NC}\n" $LARGE_COUNT $((LARGE_COUNT * LARGE_CREDITS))
echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║${NC} ${YELLOW}%-56s${NC} ${CYAN}║${NC}\n" "TOTAL CREDITS REMAINING: $TOTAL_CREDITS"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Time estimates
QUICK_TIME=$((QUICK_COUNT * 10))
SMALL_TIME=$((SMALL_COUNT * 22))
MEDIUM_TIME=$((MEDIUM_COUNT * 45))
LARGE_TIME=$((LARGE_COUNT * 90))
TOTAL_MINUTES=$((QUICK_TIME + SMALL_TIME + MEDIUM_TIME + LARGE_TIME))
TOTAL_HOURS=$((TOTAL_MINUTES / 60))
REMAINING_MINUTES=$((TOTAL_MINUTES % 60))

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    TIME ESTIMATES                          ║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║${NC} %-58s ${CYAN}║${NC}\n" "  ⚡ Quick fixes:  ~${QUICK_TIME} minutes"
printf "${CYAN}║${NC} %-58s ${CYAN}║${NC}\n" "  🔧 Small tasks:  ~$((SMALL_TIME / 60))h $((SMALL_TIME % 60))m"
printf "${CYAN}║${NC} %-58s ${CYAN}║${NC}\n" "  📄 Medium tasks: ~$((MEDIUM_TIME / 60))h $((MEDIUM_TIME % 60))m"
printf "${CYAN}║${NC} %-58s ${CYAN}║${NC}\n" "  🏗️  Large tasks:  ~$((LARGE_TIME / 60))h $((LARGE_TIME % 60))m"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║${NC} ${YELLOW}%-56s${NC} ${CYAN}║${NC}\n" "TOTAL ESTIMATED TIME: ~${TOTAL_HOURS}h ${REMAINING_MINUTES}m"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Workflow suggestion
echo -e "${GREEN}💡 Suggested Workflow:${NC}"
echo -e "  ${BLUE}Phase 1:${NC} Quick Wins    - $((QUICK_COUNT * QUICK_CREDITS)) credits (~${QUICK_TIME}m)"
echo -e "  ${BLUE}Phase 2:${NC} Small Tasks   - $((SMALL_COUNT * SMALL_CREDITS)) credits (~$((SMALL_TIME / 60))h)"
echo -e "  ${BLUE}Phase 3:${NC} Medium Tasks  - $((MEDIUM_COUNT * MEDIUM_CREDITS)) credits (~$((MEDIUM_TIME / 60))h)"
echo -e "  ${BLUE}Phase 4:${NC} Large Tasks   - $((LARGE_COUNT * LARGE_CREDITS)) credits (~$((LARGE_TIME / 60))h)"
echo ""
echo -e "${GREEN}✓ Report generated successfully!${NC}"
