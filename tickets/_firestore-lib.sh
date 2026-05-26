#!/bin/bash
# Shared Firestore helper library for ticket management scripts
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/_firestore-lib.sh"

# Firebase project
FIREBASE_PROJECT="bucky-app-355a3"
FIRESTORE_BASE="https://firestore.googleapis.com/v1/projects/$FIREBASE_PROJECT/databases/(default)/documents"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Metadata cache directory
METADATA_CACHE_DIR="/tmp/notion-ticket-metadata"
mkdir -p "$METADATA_CACHE_DIR"

# Get auth token (cached for this invocation)
get_auth_token() {
    if [ -z "$_CACHED_TOKEN" ]; then
        _CACHED_TOKEN=$(gcloud auth print-access-token 2>/dev/null)
        if [ -z "$_CACHED_TOKEN" ]; then
            echo -e "${RED}Error: Could not get auth token. Run 'gcloud auth login' first.${NC}" >&2
            exit 1
        fi
    fi
    echo "$_CACHED_TOKEN"
}

# Query Firestore for a ticket by displayId
# Returns the full document JSON (array)
query_ticket() {
    local DISPLAY_ID="$1"
    local TOKEN=$(get_auth_token)

    curl -s -X POST "$FIRESTORE_BASE:runQuery" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"structuredQuery\": {
                \"from\": [{\"collectionId\": \"tickets\"}],
                \"where\": {
                    \"fieldFilter\": {
                        \"field\": {\"fieldPath\": \"displayId\"},
                        \"op\": \"EQUAL\",
                        \"value\": {\"stringValue\": \"$DISPLAY_ID\"}
                    }
                },
                \"limit\": 1
            }
        }"
}

# Query tickets by status
# Returns array of matching documents
query_tickets_by_status() {
    local STATUS="$1"
    local LIMIT="${2:-100}"
    local TOKEN=$(get_auth_token)

    curl -s -X POST "$FIRESTORE_BASE:runQuery" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"structuredQuery\": {
                \"from\": [{\"collectionId\": \"tickets\"}],
                \"where\": {
                    \"fieldFilter\": {
                        \"field\": {\"fieldPath\": \"status\"},
                        \"op\": \"EQUAL\",
                        \"value\": {\"stringValue\": \"$STATUS\"}
                    }
                },
                \"limit\": $LIMIT
            }
        }"
}

# Query tickets by project ID
query_tickets_by_project() {
    local PROJECT_ID="$1"
    local LIMIT="${2:-100}"
    local TOKEN=$(get_auth_token)

    curl -s -X POST "$FIRESTORE_BASE:runQuery" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"structuredQuery\": {
                \"from\": [{\"collectionId\": \"tickets\"}],
                \"where\": {
                    \"fieldFilter\": {
                        \"field\": {\"fieldPath\": \"projectId\"},
                        \"op\": \"EQUAL\",
                        \"value\": {\"stringValue\": \"$PROJECT_ID\"}
                    }
                },
                \"limit\": $LIMIT
            }
        }"
}

# Query tickets by ticketNumber range (for credit/estimator scripts)
# Returns tickets where ticketNumber >= START and ticketNumber <= END
query_tickets_range() {
    local START_NUM="$1"
    local END_NUM="$2"
    local TOKEN=$(get_auth_token)

    curl -s -X POST "$FIRESTORE_BASE:runQuery" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"structuredQuery\": {
                \"from\": [{\"collectionId\": \"tickets\"}],
                \"where\": {
                    \"compositeFilter\": {
                        \"op\": \"AND\",
                        \"filters\": [
                            {
                                \"fieldFilter\": {
                                    \"field\": {\"fieldPath\": \"ticketNumber\"},
                                    \"op\": \"GREATER_THAN_OR_EQUAL\",
                                    \"value\": {\"integerValue\": \"$START_NUM\"}
                                }
                            },
                            {
                                \"fieldFilter\": {
                                    \"field\": {\"fieldPath\": \"ticketNumber\"},
                                    \"op\": \"LESS_THAN_OR_EQUAL\",
                                    \"value\": {\"integerValue\": \"$END_NUM\"}
                                }
                            }
                        ]
                    }
                },
                \"orderBy\": [{\"field\": {\"fieldPath\": \"ticketNumber\"}, \"direction\": \"ASCENDING\"}],
                \"limit\": 500
            }
        }"
}

# Extract a string field from Firestore document fields JSON
fs_string() {
    echo "$1" | jq -r ".[0].document.fields.$2.stringValue // empty" 2>/dev/null
}

fs_number() {
    echo "$1" | jq -r ".[0].document.fields.$2.integerValue // .[0].document.fields.$2.doubleValue // empty" 2>/dev/null
}

fs_bool() {
    echo "$1" | jq -r ".[0].document.fields.$2.booleanValue // empty" 2>/dev/null
}

# Extract string field from a single document (not query result array)
fs_doc_string() {
    echo "$1" | jq -r ".fields.$2.stringValue // empty" 2>/dev/null
}

fs_doc_number() {
    echo "$1" | jq -r ".fields.$2.integerValue // .fields.$2.doubleValue // empty" 2>/dev/null
}

# Extract array field values (e.g., qaBefore, qaAfter, screenshots)
fs_array() {
    echo "$1" | jq -r ".[0].document.fields.$2.arrayValue.values[]?.stringValue // empty" 2>/dev/null
}

# Extract document path from query result
get_doc_path() {
    local DOC_NAME
    DOC_NAME=$(echo "$1" | jq -r '.[0].document.name // empty')
    [ -z "$DOC_NAME" ] && return 1
    echo "$DOC_NAME" | sed "s|.*/documents/||"
}

# Update Firestore document fields
# Usage: update_ticket DOC_PATH KEY1 VALUE1 TYPE1 [KEY2 VALUE2 TYPE2 ...]
update_ticket() {
    local DOC_PATH="$1"
    shift
    local TOKEN=$(get_auth_token)

    # Build update mask and fields from key=value pairs
    local FIELDS="{"
    local MASK=""
    local FIRST=true

    while [[ $# -gt 0 ]]; do
        local KEY="$1"
        local VALUE="$2"
        local TYPE="${3:-string}"
        shift 3

        [ "$FIRST" = false ] && FIELDS="$FIELDS," && MASK="$MASK,"
        FIRST=false

        case "$TYPE" in
            string)
                # JSON-escape the value (handles newlines, quotes, backslashes)
                # so multi-line summaries don't break the downstream jq parse.
                local ESCAPED_VALUE=$(printf '%s' "$VALUE" | jq -Rs '.')
                FIELDS="$FIELDS\"$KEY\":{\"stringValue\":$ESCAPED_VALUE}"
                ;;
            number)
                FIELDS="$FIELDS\"$KEY\":{\"integerValue\":\"$VALUE\"}"
                ;;
            bool)
                FIELDS="$FIELDS\"$KEY\":{\"booleanValue\":$VALUE}"
                ;;
            timestamp)
                FIELDS="$FIELDS\"$KEY\":{\"timestampValue\":\"$VALUE\"}"
                ;;
            null)
                FIELDS="$FIELDS\"$KEY\":{\"nullValue\":null}"
                ;;
        esac
        MASK="$MASK$KEY"
    done

    FIELDS="$FIELDS}"

    # Add updatedAt
    local NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000000Z")
    FIELDS=$(echo "$FIELDS" | jq --arg now "$NOW" '. + {"updatedAt": {"timestampValue": $now}}')
    MASK="$MASK,updatedAt"

    local MASK_PARAMS=$(echo "$MASK" | sed 's/,/\&updateMask.fieldPaths=/g')

    curl -s -X PATCH "$FIRESTORE_BASE/$DOC_PATH?updateMask.fieldPaths=$MASK_PARAMS" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"fields\": $FIELDS}"
}

# Append text to ticket content field
append_content() {
    local DOC_PATH="$1"
    local NEW_TEXT="$2"
    local TOKEN=$(get_auth_token)

    # Read current content
    local DOC=$(curl -s "$FIRESTORE_BASE/$DOC_PATH" -H "Authorization: Bearer $TOKEN")
    local CURRENT=$(echo "$DOC" | jq -r '.fields.content.stringValue // ""')

    local UPDATED
    if [ -n "$CURRENT" ]; then
        UPDATED="$CURRENT

$NEW_TEXT"
    else
        UPDATED="$NEW_TEXT"
    fi

    # Write back
    local ESCAPED=$(echo "$UPDATED" | jq -Rs '.')
    curl -s -X PATCH "$FIRESTORE_BASE/$DOC_PATH?updateMask.fieldPaths=content&updateMask.fieldPaths=updatedAt" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"fields\":{\"content\":{\"stringValue\":$ESCAPED},\"updatedAt\":{\"timestampValue\":\"$(date -u +"%Y-%m-%dT%H:%M:%S.000000Z")\"}}}" > /dev/null
}

# Append a URL to an array field (qaBefore, qaAfter, screenshots)
update_ticket_array() {
    local DOC_PATH="$1"
    local FIELD="$2"
    local URL="$3"
    local TOKEN=$(get_auth_token)

    # Read current array
    local DOC=$(curl -s "$FIRESTORE_BASE/$DOC_PATH" -H "Authorization: Bearer $TOKEN")
    local CURRENT_ARRAY=$(echo "$DOC" | jq -c ".fields.${FIELD}.arrayValue.values // []")

    # Append new URL
    local NEW_ARRAY=$(echo "$CURRENT_ARRAY" | jq --arg url "$URL" '. + [{"stringValue": $url}]')

    # Write back
    local NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000000Z")
    curl -s -X PATCH "$FIRESTORE_BASE/$DOC_PATH?updateMask.fieldPaths=${FIELD}&updateMask.fieldPaths=updatedAt" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"fields\":{\"${FIELD}\":{\"arrayValue\":{\"values\":$NEW_ARRAY}},\"updatedAt\":{\"timestampValue\":\"$NOW\"}}}" > /dev/null
}

# Get a document from clientProjects collection by Firestore doc ID
get_project_by_id() {
    local PROJECT_ID="$1"
    local TOKEN=$(get_auth_token)

    curl -s "$FIRESTORE_BASE/clientProjects/$PROJECT_ID" \
        -H "Authorization: Bearer $TOKEN"
}

# Get a document from clients collection by Firestore doc ID
get_client_by_id() {
    local CLIENT_ID="$1"
    local TOKEN=$(get_auth_token)

    curl -s "$FIRESTORE_BASE/clients/$CLIENT_ID" \
        -H "Authorization: Bearer $TOKEN"
}

# Get a full document by its doc path
get_document() {
    local DOC_PATH="$1"
    local TOKEN=$(get_auth_token)

    curl -s "$FIRESTORE_BASE/$DOC_PATH" \
        -H "Authorization: Bearer $TOKEN"
}
