#!/bin/bash

# Extract Feedbucket image URL from a ticket (Firestore-backed)
# Usage: ./extract-feedbucket.sh TICK-### [--download] [--output FILE]
#
# Returns the Feedbucket image URL for use in QA Before workflow
# With --download, saves the image to a local file

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_firestore-lib.sh"

show_usage() {
    echo "Usage: $0 TICKET-ID [OPTIONS]"
    echo ""
    echo "Extract Feedbucket image URL from a ticket."
    echo ""
    echo "Options:"
    echo "  --download, -d       Download the image to local file"
    echo "  --output, -o FILE    Output file path (default: ./{ticket}-feedbucket.{ext})"
    echo "  --json, -j           Output as JSON"
    echo "  --help, -h           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 TICK-1234                           # Print URL only"
    echo "  $0 TICK-1234 --download                # Download to TICK-1234-feedbucket.png"
    echo "  $0 TICK-1234 -d -o ./before.png        # Download to specific file"
    echo "  $0 TICK-1234 --json                    # Output JSON with metadata"
    exit 1
}

# Parse arguments
TICKET_ID=""
DO_DOWNLOAD="false"
OUTPUT_FILE=""
OUTPUT_JSON="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        TICK-*|tick-*)
            TICKET_ID=$(echo "$1" | tr '[:lower:]' '[:upper:]')
            shift
            ;;
        --download|-d)
            DO_DOWNLOAD="true"
            shift
            ;;
        --output|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --json|-j)
            OUTPUT_JSON="true"
            shift
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            show_usage
            ;;
    esac
done

if [ -z "$TICKET_ID" ]; then
    echo -e "${RED}Error: TICKET-ID required${NC}" >&2
    show_usage
fi

# Query Firestore
QUERY_RESULT=$(query_ticket "$TICKET_ID")

DOC_NAME=$(echo "$QUERY_RESULT" | jq -r '.[0].document.name // empty')

if [ -z "$DOC_NAME" ]; then
    if [ "$OUTPUT_JSON" = "true" ]; then
        echo '{"error": "Ticket not found", "ticket": "'"$TICKET_ID"'"}'
    else
        echo -e "${RED}Error: Ticket $TICKET_ID not found${NC}" >&2
    fi
    exit 1
fi

DOC_PATH=$(echo "$DOC_NAME" | sed "s|.*/documents/||")

# Get content and screenshots fields
CONTENT=$(fs_string "$QUERY_RESULT" "content")
SCREENSHOTS=$(fs_array "$QUERY_RESULT" "screenshots")

# Look for Feedbucket URLs in content
FEEDBUCKET_URL=""
if [ -n "$CONTENT" ]; then
    FEEDBUCKET_URL=$(echo "$CONTENT" | grep -oE 'https://[^ ]*(feedbucket|fb-media|cdn\.feedbucket)[^ ]*' | head -1 || true)
fi

# Fallback: check screenshots array
if [ -z "$FEEDBUCKET_URL" ] && [ -n "$SCREENSHOTS" ]; then
    FEEDBUCKET_URL=$(echo "$SCREENSHOTS" | grep -i "feedbucket\|fb-media" | head -1 || true)
fi

MEDIA_TYPE="image"

# Check for video content
if [ -n "$FEEDBUCKET_URL" ] && echo "$FEEDBUCKET_URL" | grep -qi "\.mp4\|\.webm\|\.mov\|video"; then
    MEDIA_TYPE="video"
fi

if [ -z "$FEEDBUCKET_URL" ]; then
    if [ "$OUTPUT_JSON" = "true" ]; then
        echo '{"error": "No Feedbucket media found", "ticket": "'"$TICKET_ID"'", "doc_path": "'"$DOC_PATH"'"}'
    else
        echo -e "${RED}Error: No Feedbucket media found in $TICKET_ID${NC}" >&2
    fi
    exit 1
fi

# Determine file extension from URL
EXT="png"
if echo "$FEEDBUCKET_URL" | grep -qi "\.jpg\|\.jpeg"; then
    EXT="jpg"
elif echo "$FEEDBUCKET_URL" | grep -qi "\.gif"; then
    EXT="gif"
elif echo "$FEEDBUCKET_URL" | grep -qi "\.webp"; then
    EXT="webp"
elif echo "$FEEDBUCKET_URL" | grep -qi "\.mp4"; then
    EXT="mp4"
elif echo "$FEEDBUCKET_URL" | grep -qi "\.webm"; then
    EXT="webm"
fi

# Download if requested
if [ "$DO_DOWNLOAD" = "true" ]; then
    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="./${TICKET_ID}-feedbucket.${EXT}"
    fi

    curl -s -L -o "$OUTPUT_FILE" "$FEEDBUCKET_URL"

    if [ -f "$OUTPUT_FILE" ]; then
        FILE_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null)
        if [ "$OUTPUT_JSON" = "true" ]; then
            echo '{"success": true, "url": "'"$FEEDBUCKET_URL"'", "file": "'"$OUTPUT_FILE"'", "size": '"$FILE_SIZE"', "type": "'"$MEDIA_TYPE"'", "ticket": "'"$TICKET_ID"'"}'
        else
            echo -e "${GREEN}Downloaded: $OUTPUT_FILE ($FILE_SIZE bytes)${NC}"
        fi
    else
        if [ "$OUTPUT_JSON" = "true" ]; then
            echo '{"error": "Download failed", "url": "'"$FEEDBUCKET_URL"'"}'
        else
            echo -e "${RED}Error: Download failed${NC}" >&2
        fi
        exit 1
    fi
else
    # Just output the URL
    if [ "$OUTPUT_JSON" = "true" ]; then
        echo '{"url": "'"$FEEDBUCKET_URL"'", "type": "'"$MEDIA_TYPE"'", "ticket": "'"$TICKET_ID"'", "doc_path": "'"$DOC_PATH"'"}'
    else
        echo "$FEEDBUCKET_URL"
    fi
fi
