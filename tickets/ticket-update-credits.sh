#!/bin/bash

# Update Ticket Credits in Firestore
# Updates creditsMin and creditsMax fields for tickets
# Usage: ./ticket-update-credits.sh START_NUM END_NUM
# Example: ./ticket-update-credits.sh 975 1001

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_firestore-lib.sh"

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
QUICK_MAX=1
SMALL_MAX=2
MEDIUM_MAX=4
LARGE_MAX=5

QUICK_MIN=1
SMALL_MIN=1
MEDIUM_MIN=2
LARGE_MIN=3

echo -e "${CYAN}===========================================================${NC}"
echo -e "${CYAN}  UPDATE TICKET CREDITS IN FIRESTORE${NC}"
echo -e "${CYAN}  TICK-$START to TICK-$END${NC}"
echo -e "${CYAN}===========================================================${NC}"
echo ""

# Function to determine complexity from title
determine_complexity() {
    local TITLE="$1"

    if [[ "$TITLE" =~ (get\ rid\ of|remove|should\ be|change.*to) ]] && [[ ! "$TITLE" =~ (page|template|incorrect\ header) ]]; then
        echo "QUICK"
    elif [[ "$TITLE" =~ (spacing|white\ space|font|color|breadcrumb|disappears) ]]; then
        echo "SMALL"
    elif [[ "$TITLE" =~ (page\ not\ done|Search\ feature|incorrect\ header.*template|account\ pages|renderings\ vs\ lifestyle) ]]; then
        echo "LARGE"
    else
        echo "MEDIUM"
    fi
}

# Batch fetch all tickets in range
echo -e "${YELLOW}Fetching tickets from Firestore...${NC}"
RANGE_RESULT=$(query_tickets_range "$START" "$END")
echo ""

# Process tickets
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

echo -e "${YELLOW}Processing tickets...${NC}"
echo ""

echo "$RANGE_RESULT" | jq -c '.[] | select(.document != null) | .document' | while read -r doc; do
    TICKET_NUM=$(echo "$doc" | jq -r '.fields.ticketNumber.integerValue // "0"')
    TITLE=$(echo "$doc" | jq -r '.fields.name.stringValue // "Untitled"')
    STATUS=$(echo "$doc" | jq -r '.fields.status.stringValue // "Unknown"')
    DOC_PATH=$(echo "$doc" | jq -r '.name' | sed "s|.*/documents/||")
    TICKET_ID="TICK-$TICKET_NUM"

    echo -ne "${BLUE}Processing $TICKET_ID...${NC}"

    # Check if completed
    if [[ "$STATUS" == "Complete" ]] || [[ "$STATUS" == "Done" ]]; then
        echo -e "\r${CYAN}  $TICKET_ID - Skipped (completed)${NC}"
        continue
    fi

    # Determine complexity
    COMPLEXITY=$(determine_complexity "$TITLE")

    # Set credits based on complexity
    case "$COMPLEXITY" in
        "QUICK")
            MIN_CREDITS=$QUICK_MIN
            MAX_CREDITS=$QUICK_MAX
            LABEL="Quick"
            ;;
        "SMALL")
            MIN_CREDITS=$SMALL_MIN
            MAX_CREDITS=$SMALL_MAX
            LABEL="Small"
            ;;
        "MEDIUM")
            MIN_CREDITS=$MEDIUM_MIN
            MAX_CREDITS=$MEDIUM_MAX
            LABEL="Medium"
            ;;
        "LARGE")
            MIN_CREDITS=$LARGE_MIN
            MAX_CREDITS=$LARGE_MAX
            LABEL="Large"
            ;;
    esac

    # Update credits in Firestore
    RESULT=$(update_ticket "$DOC_PATH" \
        "creditsMin" "$MIN_CREDITS" "number" \
        "creditsMax" "$MAX_CREDITS" "number" 2>/dev/null)

    if echo "$RESULT" | jq -e '.fields' > /dev/null 2>&1; then
        echo -e "\r${GREEN}  $TICKET_ID - Updated to $MIN_CREDITS-$MAX_CREDITS credits ($LABEL)${NC}"
    else
        echo -e "\r${RED}  $TICKET_ID - Failed to update${NC}"
    fi

    # Small delay to avoid rate limiting
    sleep 0.1
done

echo ""
echo -e "${GREEN}Credits update complete!${NC}"
