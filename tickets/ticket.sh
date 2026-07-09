#!/bin/bash

# Unified Ticket Management Script (Firestore-backed)
# Replaces notion-ticket.sh with shared library
#
# Usage:
#   ./ticket.sh TICK-### [OPTIONS]
#
# When called with just a ticket ID:
#   - Fetches and displays ticket details from Firestore
#   - Sets status to "In Progress"
#   - Saves viewport metadata for QA screenshots
#
# When called with options:
#   - Updates ticket properties (status, PR URL, etc.)
#   - Handles QA Before/After screenshots with automatic viewport matching
#
# Options:
#   --status, -s STATUS          Set ticket status (e.g., 'Complete', 'In Progress')
#   --pr-url, -p URL            Set GitHub PR URL
#   --theme-id, -t ID           Set Shopify Theme Preview ID (manual)
#   --page-url, -u URL           Set the page being worked on (defaults to store URL)
#   --auto-theme                 Auto-detect Theme ID from git branch name
#   --summary, --notes, -n TEXT  Set ticket summary field
#
# QA Screenshot Options:
#   --qa-before                  Extract Feedbucket image -> upload as QA Before
#   --qa-after                   Capture FULL PAGE Chrome screenshot (auto viewport) -> QA After
#   --qa-after-file FILE         Upload specific file as QA After (must be FULL PAGE screenshot)
#
# Job Report Options (senior-dev cycle pickup — AI video job reports):
#   --job-report                 Submit this ticket to the job-report pipeline. Writes the
#                                same Firestore contract as Bucky QA (agentQa + qa_pass),
#                                which triggers: Gemini transcript -> Jody-voice audio ->
#                                GIF+audio MP4 with captions. Review & approve in the
#                                Job Reports admin screen (approve moves it to In Review).
#   --gif FILE_OR_URL            REQUIRED with --job-report. Screen-capture GIF showing the
#                                change working. Local files upload to Storage automatically.
#                                Loops for the whole ~45s video: aim for a 10-20s clean loop.
#   --qa-notes TEXT              What you verified, in PLAIN CLIENT language — this text
#                                feeds the client-facing voiceover. Falls back to --summary.
#   --job-report-status          Show the ticket's job report (transcript, video, status).
#
# Examples:
#   # Start working on a ticket (fetch details, set In Progress)
#   ./ticket.sh TICK-1234
#
#   # Complete ticket with QA screenshots
#   ./ticket.sh TICK-1234 --status "In Review" --qa-before --qa-after --summary "Fixed the issue"
#
#   # Senior-dev cycle pickup: submit for an AI video job report
#   ./ticket.sh TICK-1234 --job-report --gif ~/Desktop/fix-demo.gif \
#       --qa-notes "The announcement bar stays pinned while scrolling on desktop and mobile"

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_firestore-lib.sh"

# QA script
RECORD_QA_SCRIPT="$SCRIPT_DIR/ticket-qa.sh"

# Look up Shopify theme ID by matching git branch name to theme name
get_theme_id_from_branch() {
    local OVERRIDE_STORE="$1"
    local BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    [ -z "$BRANCH" ] && echo "" && return

    local STORE=""
    [ -n "$OVERRIDE_STORE" ] && STORE="$OVERRIDE_STORE"
    [ -z "$STORE" ] && [ -f ".shopify/shop" ] && STORE=$(cat .shopify/shop 2>/dev/null || true)
    if [ -z "$STORE" ]; then
        for dir in themes/*/.shopify; do
            [ -d "$dir" ] && [ -f "$dir/shop" ] && STORE=$(cat "$dir/shop" 2>/dev/null || true) && break
        done 2>/dev/null
    fi
    if [ -z "$STORE" ]; then
        for dir in themes/*.myshopify.com; do
            [ -d "$dir" ] && STORE=$(basename "$dir") && break
        done 2>/dev/null
    fi
    [ -z "$STORE" ] && echo "" && return

    command -v shopify &>/dev/null || { echo ""; return; }
    local THEME_JSON=$(shopify theme list --name "$BRANCH" --json --store "$STORE" 2>&1)
    echo "$THEME_JSON" | jq -e '.' >/dev/null 2>&1 || { echo ""; return; }
    echo "$THEME_JSON" | jq -r '.[0].id // empty' 2>/dev/null || true
}

# ============================================================
# JOB REPORT INTEGRATION (senior-dev cycle pickup)
# Writes the same Firestore contract as the Bucky QA agent — see
# runner/QA-AGENT-CONTRACT.md in the Bucky repo. The onTicketQaPassed
# trigger then generates transcript -> audio -> MP4 server-side.
# ============================================================

STORAGE_BUCKET="bucky-app-355a3.firebasestorage.app"

# Print a job report doc's status/transcript/video. $1 = ticket doc id.
check_job_report() {
    local TICKET_DOC_ID="$1"
    local REPORT=$(get_document "ticketJobReports/$TICKET_DOC_ID")
    local JR_STATUS=$(echo "$REPORT" | jq -r '.fields.status.stringValue // empty')

    if [ -z "$JR_STATUS" ]; then
        echo -e "${YELLOW}No job report exists for this ticket yet.${NC}"
        echo "Submit one with: $0 $TICKET_ID --job-report --gif <file-or-url> --qa-notes '...'"
        return 1
    fi

    echo -e "${BLUE}JOB REPORT:${NC}"
    echo "----------------------------------------"
    echo -e "Status: ${GREEN}$JR_STATUS${NC}"
    local TRANSCRIPT=$(echo "$REPORT" | jq -r '.fields.transcript.stringValue // empty')
    local VIDEO_URL=$(echo "$REPORT" | jq -r '.fields.video.mapValue.fields.publicUrl.stringValue // empty')
    local VIDEO_ERR=$(echo "$REPORT" | jq -r '.fields.video.mapValue.fields.error.stringValue // empty')
    local AUDIO_ERR=$(echo "$REPORT" | jq -r '.fields.audio.mapValue.fields.error.stringValue // empty')
    local TOP_ERR=$(echo "$REPORT" | jq -r '.fields.error.stringValue // empty')
    local APPROVED_BY=$(echo "$REPORT" | jq -r '.fields.approvedBy.stringValue // empty')
    [ -n "$TRANSCRIPT" ] && echo "" && echo "Transcript:" && echo "$TRANSCRIPT"
    [ -n "$VIDEO_URL" ] && echo "" && echo -e "Video: ${GREEN}$VIDEO_URL${NC}"
    [ -n "$VIDEO_ERR" ] && echo -e "${RED}Video error: $VIDEO_ERR${NC}"
    [ -n "$AUDIO_ERR" ] && echo -e "${RED}Audio error: $AUDIO_ERR${NC}"
    [ -n "$TOP_ERR" ] && echo -e "${RED}Pipeline error: $TOP_ERR${NC}"
    [ -n "$APPROVED_BY" ] && echo -e "Approved by: $APPROVED_BY"
    if [ "$JR_STATUS" = "draft" ]; then
        echo ""
        echo -e "Review & approve in the ${CYAN}Job Reports${NC} screen: https://bucky.sunbowl.ca (Admin > Job Reports)"
    fi
    return 0
}

# Submit the job-report contract for a ticket.
# Uses: DOC_PATH, TICKET_ID, JR_GIF, JR_NOTES (globals set by the caller).
submit_job_report() {
    local TICKET_DOC_ID=$(echo "$DOC_PATH" | sed 's|.*/||')
    local TOKEN=$(get_auth_token)

    # ---- Notes (feed the client-facing voiceover) ----
    local NOTES="${JR_NOTES:-$SUMMARY_TEXT}"
    if [ -z "$NOTES" ]; then
        echo -e "${RED}Error: --job-report needs --qa-notes (or --summary).${NC}"
        echo "Describe WHAT you verified in plain client language — it feeds the voiceover."
        return 1
    fi

    # ---- GIF: upload local file, or accept an https URL ----
    local GIF_URL=""
    local GIF_GS_PATH=""
    if [ -z "$JR_GIF" ]; then
        echo -e "${RED}Error: --job-report needs --gif <file-or-url>.${NC}"
        return 1
    fi
    if [[ "$JR_GIF" =~ ^https?:// ]]; then
        GIF_URL="$JR_GIF"
    elif [ -f "$JR_GIF" ]; then
        if ! command -v gsutil >/dev/null 2>&1; then
            echo -e "${RED}Error: gsutil not found (needed to upload the GIF).${NC}"
            return 1
        fi
        local OBJ="qa_screenshots/$TICKET_ID/jobreport-$(date +%s).gif"
        echo "Uploading GIF to Storage..."
        if ! gsutil -q cp "$JR_GIF" "gs://$STORAGE_BUCKET/$OBJ"; then
            echo -e "${RED}GIF upload failed${NC}"
            return 1
        fi
        gsutil -q acl ch -u AllUsers:R "gs://$STORAGE_BUCKET/$OBJ"
        GIF_URL="https://storage.googleapis.com/$STORAGE_BUCKET/$OBJ"
        GIF_GS_PATH="gs://$STORAGE_BUCKET/$OBJ"
        echo -e "${GREEN}GIF uploaded: $GIF_URL${NC}"
    else
        echo -e "${RED}Error: --gif '$JR_GIF' is neither a file nor an https URL${NC}"
        return 1
    fi

    # ---- Attempt: increment past any previous QA round ----
    local TICKET_DOC=$(get_document "$DOC_PATH")
    local PREV_ATTEMPT=$(echo "$TICKET_DOC" | jq -r '.fields.agentQa.mapValue.fields.attempt.integerValue // "0"')
    local ATTEMPT=$((PREV_ATTEMPT + 1))
    local CURRENT_STATE=$(echo "$TICKET_DOC" | jq -r '.fields.aiPipelineState.stringValue // empty')

    # The trigger fires only on the TRANSITION into qa_pass; if the ticket is
    # already qa_pass (re-submission), step it away first.
    if [ "$CURRENT_STATE" = "qa_pass" ]; then
        update_ticket "$DOC_PATH" "aiPipelineState" "pr_open" "string" > /dev/null
    fi

    # ---- The contract write: agentQa + aiPipelineState in ONE update ----
    local NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000000Z")
    local GIF_PATH_JSON='{"nullValue":null}'
    [ -n "$GIF_GS_PATH" ] && GIF_PATH_JSON="{\"stringValue\":\"$GIF_GS_PATH\"}"
    local NOTES_ESCAPED=$(printf '%s' "$NOTES" | jq -Rs '.')

    local WRITE_RESULT=$(curl -s -X PATCH "$FIRESTORE_BASE/$DOC_PATH?updateMask.fieldPaths=agentQa&updateMask.fieldPaths=aiPipelineState&updateMask.fieldPaths=updatedAt" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"fields\":{
            \"agentQa\":{\"mapValue\":{\"fields\":{
                \"verdict\":{\"stringValue\":\"pass\"},
                \"gifUrl\":{\"stringValue\":\"$GIF_URL\"},
                \"gifStoragePath\":$GIF_PATH_JSON,
                \"notes\":{\"stringValue\":$NOTES_ESCAPED},
                \"runId\":{\"nullValue\":null},
                \"attempt\":{\"integerValue\":\"$ATTEMPT\"},
                \"completedAt\":{\"timestampValue\":\"$NOW\"}
            }}},
            \"aiPipelineState\":{\"stringValue\":\"qa_pass\"},
            \"updatedAt\":{\"timestampValue\":\"$NOW\"}
        }}")

    if ! echo "$WRITE_RESULT" | jq -e '.fields' > /dev/null 2>&1; then
        echo -e "${RED}Contract write failed:${NC}"
        echo "$WRITE_RESULT" | jq '.' 2>/dev/null || echo "$WRITE_RESULT"
        return 1
    fi
    echo -e "${GREEN}Job report submitted (attempt $ATTEMPT) — pipeline is generating...${NC}"
    echo "  (Gemini transcript -> Jody-voice audio -> GIF+audio MP4 with captions)"

    # ---- Poll for the generated report (~30-60s incl. cold start) ----
    local i
    for ((i=0; i<40; i++)); do
        sleep 3
        local REPORT=$(get_document "ticketJobReports/$TICKET_DOC_ID")
        local JR_STATUS=$(echo "$REPORT" | jq -r '.fields.status.stringValue // empty')
        local JR_ATTEMPT=$(echo "$REPORT" | jq -r '.fields.qaAttempt.integerValue // empty')
        if [ "$JR_ATTEMPT" = "$ATTEMPT" ] && { [ "$JR_STATUS" = "draft" ] || [ "$JR_STATUS" = "error" ]; }; then
            echo ""
            check_job_report "$TICKET_DOC_ID"
            return 0
        fi
        printf "."
    done

    echo ""
    echo -e "${YELLOW}Still generating after 2 minutes — check later with:${NC}"
    echo "  $0 $TICKET_ID --job-report-status"
    return 0
}

show_usage() {
    echo "Usage: $0 TICKET-ID [OPTIONS]"
    echo ""
    echo "Ticket management script (Firestore-backed)."
    echo ""
    echo "When called with just a ticket ID:"
    echo "  - Fetches and displays ticket details"
    echo "  - Updates status to 'In Progress'"
    echo "  - Caches viewport metadata for QA screenshots"
    echo ""
    echo "Options:"
    echo "  --status, -s STATUS          Set ticket status"
    echo "  --pr-url, -p URL            Set GitHub PR URL"
    echo "  --theme-id, -t ID           Set Shopify Theme Preview ID"
    echo "  --page-url, -u URL           Set the page being worked on"
    echo "  --auto-theme                 Auto-detect Theme ID from git branch"
    echo "  --store STORE               Shopify store for theme lookup"
    echo "  --summary, --notes, -n TEXT  Set ticket summary"
    echo ""
    echo "QA Screenshot Options:"
    echo "  --qa-before                  Extract Feedbucket image -> upload as QA Before"
    echo "  --qa-after                   Capture FULL PAGE Chrome screenshot"
    echo "  --qa-after-file FILE         Upload file as QA After"
    echo ""
    echo "Job Report Options (AI video job report for the client):"
    echo "  --job-report                 Submit to the job-report pipeline (needs --gif)"
    echo "  --gif FILE_OR_URL            Screen-capture GIF of the change (10-20s clean loop)"
    echo "  --qa-notes TEXT              What you verified, in plain client language"
    echo "                               (feeds the voiceover; falls back to --summary)"
    echo "  --job-report-status          Show this ticket's job report status/video"
    echo ""
    echo "Examples:"
    echo "  $0 TICK-1234"
    echo "  $0 TICK-1234 --status 'In Review' --qa-before --qa-after --summary 'Fixed the bug'"
    echo "  $0 TICK-1234 --job-report --gif ~/Desktop/demo.gif --qa-notes 'Bar stays pinned while scrolling'"
    echo ""
    echo "Create a new ticket:"
    echo "  $0 --create --channel <slack-channel> --name 'Title' [options]"
    echo "  (run '$0 --create --help' for create-mode options)"
    exit 1
}

create_usage() {
    echo "Usage: $0 --create --channel <slack-channel> --name 'Title' [OPTIONS]"
    echo ""
    echo "Create a new ticket in the 'tickets' collection. The client/project is"
    echo "resolved from the Slack channel. TICK-N is minted by the server trigger."
    echo ""
    echo "Required:"
    echo "  --channel, -c CHANNEL    Client Slack channel (with or without '#')"
    echo "  --name, -N TEXT          Ticket title"
    echo ""
    echo "Content:"
    echo "  --description, -d TEXT    Ticket body (plain text)"
    echo "  --description-file, -D F  Read ticket body from file (e.g. a brief)"
    echo ""
    echo "Optional:"
    echo "  --status, -s STATUS      Status (default: Backlog)"
    echo "  --client-id ID           Use this client directly (skip channel lookup / disambiguate)"
    echo "  --project-id ID          Disambiguate when client has multiple projects"
    echo "  --rush                   Mark as a rush order"
    echo "  --page-url URL           Page being worked on"
    echo "  --attach, -a FILE        Upload & attach a file (repeatable; PDF, source, image...)"
    echo "  --dry-run                Resolve + print the payload, write nothing"
    echo ""
    echo "Examples:"
    echo "  $0 --create -c jjbean -N 'Fix mobile header overlap' -d 'Logo overlaps nav under 480px'"
    echo "  $0 --create -c sixhats -N 'New FAQ section' -D ./brief.md -a ./mockup.pdf --rush"
    exit 1
}

# ============================================================
# CREATE MODE
# ============================================================
run_create_mode() {
    local NAME="" CHANNEL="" DESCRIPTION="" DESCRIPTION_FILE=""
    local STATUS="Backlog" PROJECT_ID_OVERRIDE="" CLIENT_ID_OVERRIDE="" PAGE_URL="" RUSH=false DRY_RUN=false
    local ATTACHMENTS=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name|-N) NAME="$2"; shift 2 ;;
            --channel|-c) CHANNEL="$2"; shift 2 ;;
            --description|-d) DESCRIPTION="$2"; shift 2 ;;
            --description-file|-D) DESCRIPTION_FILE="$2"; shift 2 ;;
            --status|-s) STATUS="$2"; shift 2 ;;
            --project-id) PROJECT_ID_OVERRIDE="$2"; shift 2 ;;
            --client-id) CLIENT_ID_OVERRIDE="$2"; shift 2 ;;
            --page-url) PAGE_URL="$2"; shift 2 ;;
            --rush) RUSH=true; shift ;;
            --attach|-a) ATTACHMENTS+=("$2"); shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --help|-h) create_usage ;;
            *) echo -e "${RED}Error: Unknown create option: $1${NC}"; create_usage ;;
        esac
    done

    # Validate required
    [ -z "$CHANNEL" ] && [ -z "$CLIENT_ID_OVERRIDE" ] && echo -e "${RED}Error: --channel (or --client-id) is required${NC}" && create_usage
    [ -z "$NAME" ] && echo -e "${RED}Error: --name is required${NC}" && create_usage

    # Build content (description text + optional file)
    local CONTENT="$DESCRIPTION"
    if [ -n "$DESCRIPTION_FILE" ]; then
        if [ ! -f "$DESCRIPTION_FILE" ]; then
            echo -e "${RED}Error: description file not found: $DESCRIPTION_FILE${NC}"; exit 1
        fi
        local FILE_BODY=$(cat "$DESCRIPTION_FILE")
        if [ -n "$CONTENT" ]; then CONTENT="$CONTENT

$FILE_BODY"; else CONTENT="$FILE_BODY"; fi
    fi

    # Validate attachment files exist up front
    local f
    for f in "${ATTACHMENTS[@]}"; do
        [ ! -f "$f" ] && echo -e "${RED}Error: attachment not found: $f${NC}" && exit 1
    done

    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}Create Ticket${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # ---- Resolve client (by --client-id override, else by Slack channel) ----
    local CLIENT_ID="" CLIENT_NAME="" COMPANY=""
    if [ -n "$CLIENT_ID_OVERRIDE" ]; then
        local CDOC=$(get_client_by_id "$CLIENT_ID_OVERRIDE")
        if ! echo "$CDOC" | jq -e '.fields' >/dev/null 2>&1; then
            echo -e "${RED}Error: client '$CLIENT_ID_OVERRIDE' not found${NC}"; exit 1
        fi
        CLIENT_ID="$CLIENT_ID_OVERRIDE"
        CLIENT_NAME=$(echo "$CDOC" | jq -r '.fields.name.stringValue // empty')
        COMPANY=$(echo "$CDOC" | jq -r '.fields.companyName.stringValue // empty')
    else
        local CH=$(normalize_channel "$CHANNEL")
        echo "Resolving Slack channel: #$CH ..."
        local CLIENT_RESULT=$(query_clients_by_slack_channel "$CH")
        local CLIENT_COUNT=$(echo "$CLIENT_RESULT" | jq -r '[.[] | select(.document)] | length' 2>/dev/null || echo 0)
        if [ "$CLIENT_COUNT" -eq 0 ]; then
            echo -e "${RED}Error: No client found for Slack channel '#$CH'.${NC}"
            echo "Check the channel name, or add it to the client's slackChannels in Bucky."
            exit 1
        elif [ "$CLIENT_COUNT" -gt 1 ]; then
            echo -e "${YELLOW}Channel '#$CH' matches $CLIENT_COUNT clients. Re-run with --client-id <id>:${NC}"
            echo "$CLIENT_RESULT" | jq -r '.[] | select(.document) | .document as $d | "  " + ($d.name | sub(".*/";"")) + "  -  " + (($d.fields.companyName.stringValue // $d.fields.name.stringValue) // "")'
            exit 1
        fi
        CLIENT_ID=$(echo "$CLIENT_RESULT" | jq -r '.[0].document.name | sub(".*/";"")')
        CLIENT_NAME=$(echo "$CLIENT_RESULT" | jq -r '.[0].document.fields.name.stringValue // empty')
        COMPANY=$(echo "$CLIENT_RESULT" | jq -r '.[0].document.fields.companyName.stringValue // empty')
    fi
    echo -e "${GREEN}Client: ${COMPANY:-$CLIENT_NAME} ($CLIENT_ID)${NC}"

    # ---- Resolve project for that client ----
    local PROJ_RESULT=$(query_projects_by_client "$CLIENT_ID")
    # TSV: id \t name \t storeId \t clientName
    local PROJ_TSV=$(echo "$PROJ_RESULT" | jq -r '.[] | select(.document) | .document as $d | ($d.name | sub(".*/";"")) + "\t" + ($d.fields.name.stringValue // "") + "\t" + ($d.fields.shopifyStoreId.stringValue // "") + "\t" + ($d.fields.clientName.stringValue // "")' 2>/dev/null)
    local PROJ_COUNT=$(echo -n "$PROJ_TSV" | grep -c . || true)

    local PROJECT_ID="" PROJECT_NAME="" SHOPIFY_STORE_ID="" PROJ_CLIENT_NAME=""
    if [ "$PROJ_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No projects found for this client. Creating ticket linked to client only.${NC}"
    elif [ -n "$PROJECT_ID_OVERRIDE" ]; then
        local LINE=$(echo "$PROJ_TSV" | awk -F'\t' -v pid="$PROJECT_ID_OVERRIDE" '$1==pid')
        [ -z "$LINE" ] && echo -e "${RED}Error: --project-id $PROJECT_ID_OVERRIDE not found for this client${NC}" && exit 1
        PROJECT_ID=$(echo "$LINE" | cut -f1); PROJECT_NAME=$(echo "$LINE" | cut -f2)
        SHOPIFY_STORE_ID=$(echo "$LINE" | cut -f3); PROJ_CLIENT_NAME=$(echo "$LINE" | cut -f4)
    elif [ "$PROJ_COUNT" -eq 1 ]; then
        PROJECT_ID=$(echo "$PROJ_TSV" | cut -f1); PROJECT_NAME=$(echo "$PROJ_TSV" | cut -f2)
        SHOPIFY_STORE_ID=$(echo "$PROJ_TSV" | cut -f3); PROJ_CLIENT_NAME=$(echo "$PROJ_TSV" | cut -f4)
    else
        echo -e "${YELLOW}This client has $PROJ_COUNT projects. Re-run with --project-id <id>:${NC}"
        echo "$PROJ_TSV" | while IFS=$'\t' read -r id pname sid cname; do
            echo "  $id  -  $pname"
        done
        exit 1
    fi
    [ -n "$PROJECT_ID" ] && echo -e "${GREEN}Project: $PROJECT_NAME ($PROJECT_ID)${NC}"

    # Prefer project's denormalized clientName when available
    [ -n "$PROJ_CLIENT_NAME" ] && CLIENT_NAME="$PROJ_CLIENT_NAME"

    # ---- Resolve Shopify store URL ----
    local SHOPIFY_STORE_URL=""
    if [ -n "$SHOPIFY_STORE_ID" ]; then
        local STORE_DOC=$(get_document "shopifyStores/$SHOPIFY_STORE_ID")
        SHOPIFY_STORE_URL=$(echo "$STORE_DOC" | jq -r '.fields.onlineStoreUrl.stringValue // .fields.myshopifyUrl.stringValue // empty' 2>/dev/null)
        [ -n "$SHOPIFY_STORE_URL" ] && echo -e "${GREEN}Store: $SHOPIFY_STORE_URL${NC}"
    fi

    # ---- Build Firestore fields (omit ticketNumber/displayId -> trigger mints) ----
    local NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000000Z")
    local FIELDS=$(jq -n \
        --arg name "$NAME" \
        --arg status "$STATUS" \
        --arg content "$CONTENT" \
        --arg projectId "$PROJECT_ID" \
        --arg projectName "$PROJECT_NAME" \
        --arg clientId "$CLIENT_ID" \
        --arg clientName "$CLIENT_NAME" \
        --arg storeId "$SHOPIFY_STORE_ID" \
        --arg storeUrl "$SHOPIFY_STORE_URL" \
        --arg pageUrl "$PAGE_URL" \
        --argjson rush "$RUSH" \
        --arg now "$NOW" \
        '
        def s($v): if ($v|length)==0 then {nullValue:null} else {stringValue:$v} end;
        {
          notionPageId: {stringValue: ""},
          name: {stringValue: $name},
          status: {stringValue: $status},
          projectId: s($projectId),
          projectName: s($projectName),
          clientId: s($clientId),
          clientName: s($clientName),
          shopifyStoreId: s($storeId),
          shopifyStoreUrl: s($storeUrl),
          creditsMin: {nullValue:null},
          creditsMax: {nullValue:null},
          pageUrl: s($pageUrl),
          shopifyThemeId: {nullValue:null},
          videoReviewUrl: {nullValue:null},
          internalTimeEstimate: {nullValue:null},
          internalTimeInMins: {nullValue:null},
          ticketComplexity: {nullValue:null},
          dueDate: {nullValue:null},
          promisedDate: {nullValue:null},
          rushOrder: {booleanValue: $rush},
          qaApproved: {booleanValue: false},
          qaBefore: {arrayValue:{values:[]}},
          qaAfter: {arrayValue:{values:[]}},
          content: s($content),
          recurringTemplateId: {nullValue:null},
          screenshots: {arrayValue:{values:[]}},
          attachments: {arrayValue:{values:[]}},
          clientApprover: {nullValue:null},
          qaRequirements: {nullValue:null},
          qaRequirementsDraft: {nullValue:null},
          mergeInfo: {nullValue:null},
          archivedByMerge: {nullValue:null},
          source: {stringValue: "cli"},
          createdAt: {timestampValue: $now},
          updatedAt: {timestampValue: $now}
        }')

    # ---- Dry run ----
    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo -e "${BLUE}DRY RUN - ticket payload (no write):${NC}"
        echo "----------------------------------------"
        echo "Title:   $NAME"
        echo "Status:  $STATUS"
        echo "Rush:    $RUSH"
        [ ${#ATTACHMENTS[@]} -gt 0 ] && echo "Attach:  ${ATTACHMENTS[*]}"
        echo ""
        echo "$FIELDS" | jq '.'
        echo ""
        echo -e "${YELLOW}Dry run only - no ticket created.${NC}"
        return 0
    fi

    # ---- Create the document ----
    echo ""
    echo "Creating ticket..."
    local CREATE_RESULT=$(create_ticket "$FIELDS")
    local NEW_DOC_NAME=$(echo "$CREATE_RESULT" | jq -r '.name // empty' 2>/dev/null)
    if [ -z "$NEW_DOC_NAME" ]; then
        echo -e "${RED}Error creating ticket:${NC}"
        echo "$CREATE_RESULT" | jq '.' 2>/dev/null || echo "$CREATE_RESULT"
        exit 1
    fi
    local DOC_PATH=$(echo "$NEW_DOC_NAME" | sed "s|.*/documents/||")
    echo -e "${GREEN}Document created: $DOC_PATH${NC}"

    # ---- Wait for trigger to mint TICK-N ----
    echo "Waiting for ticket number..."
    local TICKET_ID=$(wait_for_display_id "$DOC_PATH")
    if [ -z "$TICKET_ID" ]; then
        echo -e "${YELLOW}Ticket created but number not minted yet (trigger may be cold).${NC}"
        TICKET_ID="(pending)"
    else
        echo -e "${GREEN}Assigned: $TICKET_ID${NC}"
    fi

    # ---- Upload & attach files ----
    if [ ${#ATTACHMENTS[@]} -gt 0 ]; then
        echo ""
        echo "Uploading ${#ATTACHMENTS[@]} attachment(s)..."
        local QA_DIR="$SCRIPT_DIR/qa"
        local UPLOAD_TICKET="$TICKET_ID"
        [ "$UPLOAD_TICKET" = "(pending)" ] && UPLOAD_TICKET=$(echo "$DOC_PATH" | sed 's|.*/||')
        local ATTACH_TEXT="Attachments:"
        for f in "${ATTACHMENTS[@]}"; do
            local UP=$(cd "$QA_DIR" && node upload-attachment.js --file "$f" --ticket "$UPLOAD_TICKET" 2>&1)
            local URL=$(echo "$UP" | jq -r '.url // empty' 2>/dev/null)
            local FNAME=$(echo "$UP" | jq -r '.name // empty' 2>/dev/null)
            local IS_IMG=$(echo "$UP" | jq -r '.isImage // false' 2>/dev/null)
            if [ -z "$URL" ]; then
                echo -e "  ${YELLOW}Failed: $f${NC}"
                echo "$UP" | jq -r '.error // empty' 2>/dev/null
                continue
            fi
            echo -e "  ${GREEN}$FNAME -> uploaded${NC}"
            update_ticket_array "$DOC_PATH" "attachments" "$URL"
            [ "$IS_IMG" = "true" ] && update_ticket_array "$DOC_PATH" "screenshots" "$URL"
            ATTACH_TEXT="$ATTACH_TEXT
- $FNAME: $URL"
        done
        # Append a human-readable attachments section to the content body
        append_content "$DOC_PATH" "$ATTACH_TEXT"
    fi

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}Created $TICKET_ID${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo "Client:  ${COMPANY:-$CLIENT_NAME}"
    [ -n "$PROJECT_NAME" ] && echo "Project: $PROJECT_NAME"
    echo "Status:  $STATUS"
    echo "View: https://bucky.sunbowl.ca (Databases > Tickets)"
}

# Check for help flag
[ "$1" = "--help" ] || [ "$1" = "-h" ] && show_usage
[ -z "$1" ] && show_usage

# Dispatch: create mode
if [ "$1" = "--create" ] || [ "$1" = "create" ]; then
    shift
    run_create_mode "$@"
    exit $?
fi

TICKET_INPUT="$1"
shift

# Extract ticket number
TICKET_ID=$(echo "$TICKET_INPUT" | tr '[:lower:]' '[:upper:]')
TICKET_NUMBER=$(echo "$TICKET_ID" | sed 's/TICK-//')

# Initialize variables
NEW_STATUS=""
PR_URL=""
THEME_ID=""
NEW_PAGE_URL=""
AUTO_THEME=false
SHOPIFY_STORE=""
SUMMARY_TEXT=""
QA_BEFORE=false
QA_AFTER=false
QA_AFTER_FILE=""
JOB_REPORT=false
JR_GIF=""
JR_NOTES=""
JR_STATUS_ONLY=false
FETCH_ONLY=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --status|-s) NEW_STATUS="$2"; FETCH_ONLY=false; shift 2 ;;
        --pr-url|-p) PR_URL="$2"; FETCH_ONLY=false; shift 2 ;;
        --theme-id|-t) THEME_ID="$2"; FETCH_ONLY=false; shift 2 ;;
        --page-url|-u) NEW_PAGE_URL="$2"; FETCH_ONLY=false; shift 2 ;;
        --auto-theme) AUTO_THEME=true; FETCH_ONLY=false; shift ;;
        --store) SHOPIFY_STORE="$2"; shift 2 ;;
        --summary|--notes|-n) SUMMARY_TEXT="$2"; FETCH_ONLY=false; shift 2 ;;
        --qa-before) QA_BEFORE=true; FETCH_ONLY=false; shift ;;
        --qa-after) QA_AFTER=true; FETCH_ONLY=false; shift ;;
        --qa-after-file) QA_AFTER_FILE="$2"; FETCH_ONLY=false; shift 2 ;;
        --job-report) JOB_REPORT=true; FETCH_ONLY=false; shift ;;
        --gif) JR_GIF="$2"; shift 2 ;;
        --qa-notes) JR_NOTES="$2"; shift 2 ;;
        --job-report-status) JR_STATUS_ONLY=true; FETCH_ONLY=false; shift ;;
        --help|-h) show_usage ;;
        *) echo -e "${RED}Error: Unknown option: $1${NC}"; show_usage ;;
    esac
done

# Validate QA script exists if QA options are used
if [ "$QA_BEFORE" = true ] || [ "$QA_AFTER" = true ] || [ -n "$QA_AFTER_FILE" ]; then
    if [ ! -x "$RECORD_QA_SCRIPT" ]; then
        echo -e "${RED}Error: ticket-qa.sh not found at $RECORD_QA_SCRIPT${NC}"
        exit 1
    fi
fi

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Ticket: $TICKET_ID${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Look up the ticket in Firestore
echo "Looking up ticket in Firestore..."
QUERY_RESULT=$(query_ticket "$TICKET_ID")

# Extract document path
DOC_NAME=$(echo "$QUERY_RESULT" | jq -r '.[0].document.name // empty')

if [ -z "$DOC_NAME" ]; then
    echo -e "${RED}Error: Ticket $TICKET_ID not found${NC}"
    exit 1
fi

# Extract the document path (tickets/XXXXX)
DOC_PATH=$(echo "$DOC_NAME" | sed "s|.*/documents/||")

echo -e "${GREEN}Found: $DOC_PATH${NC}"
echo ""

# Extract ticket fields
TICKET_TITLE=$(fs_string "$QUERY_RESULT" "name")
CURRENT_STATUS=$(fs_string "$QUERY_RESULT" "status")
TICKET_CLIENT=$(fs_string "$QUERY_RESULT" "clientName")
TICKET_PROJECT=$(fs_string "$QUERY_RESULT" "projectName")
TICKET_CONTENT=$(fs_string "$QUERY_RESULT" "content")
PAGE_URL=$(fs_string "$QUERY_RESULT" "pageUrl")
SHOPIFY_THEME=$(fs_string "$QUERY_RESULT" "shopifyThemeId")
CREDITS_MIN=$(fs_number "$QUERY_RESULT" "creditsMin")
CREDITS_MAX=$(fs_number "$QUERY_RESULT" "creditsMax")
COMPLEXITY=$(fs_string "$QUERY_RESULT" "ticketComplexity")
RUSH_ORDER=$(fs_bool "$QUERY_RESULT" "rushOrder")
STORE_URL=$(fs_string "$QUERY_RESULT" "shopifyStoreUrl")

# Extract viewport from content (same pattern as before)
FEEDBUCKET_VIEWPORT=""
FEEDBUCKET_PAGE_URL=""
if [ -n "$TICKET_CONTENT" ]; then
    FEEDBUCKET_VIEWPORT=$(echo "$TICKET_CONTENT" | grep -oE 'Viewport:?\s*\n?\s*[0-9]+\s*x\s*[0-9]+' | grep -oE '[0-9]+x[0-9]+' | head -1 || true)
    FEEDBUCKET_PAGE_URL=$(echo "$TICKET_CONTENT" | grep -oE 'Page:\s*https?://[^ ]+' | grep -oE 'https?://[^ ]+' | head -1 || true)
fi

# Use ticket pageUrl if no feedbucket URL found
[ -z "$FEEDBUCKET_PAGE_URL" ] && [ -n "$PAGE_URL" ] && FEEDBUCKET_PAGE_URL="$PAGE_URL"

# Save metadata to cache
METADATA_FILE="$METADATA_CACHE_DIR/$TICKET_ID.json"
jq -n \
    --arg ticket_id "$TICKET_ID" \
    --arg doc_path "$DOC_PATH" \
    --arg title "$TICKET_TITLE" \
    --arg viewport "$FEEDBUCKET_VIEWPORT" \
    --arg pixel_ratio "2" \
    --arg page_url "$FEEDBUCKET_PAGE_URL" \
    --arg theme_id "$SHOPIFY_THEME" \
    --arg fetched_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
        ticket_id: $ticket_id,
        doc_path: $doc_path,
        title: $title,
        viewport: $viewport,
        pixel_ratio: $pixel_ratio,
        page_url: $page_url,
        theme_id: $theme_id,
        fetched_at: $fetched_at
    }' > "$METADATA_FILE"

# Display ticket details
echo -e "${BLUE}TICKET DETAILS:${NC}"
echo "----------------------------------------"
echo "ID: $TICKET_ID"
echo "Title: $TICKET_TITLE"
echo "Status: $CURRENT_STATUS"
echo "Client: $TICKET_CLIENT"
echo "Project: $TICKET_PROJECT"
[ -n "$CREDITS_MAX" ] && echo "Credits: $CREDITS_MIN - $CREDITS_MAX"
[ -n "$COMPLEXITY" ] && echo "Complexity: $COMPLEXITY"
[ "$RUSH_ORDER" = "true" ] && echo -e "Rush: ${RED}YES${NC}"
[ -n "$PAGE_URL" ] && echo "Page URL: $PAGE_URL"
[ -n "$STORE_URL" ] && echo "Store: $STORE_URL"

if [ -n "$FEEDBUCKET_VIEWPORT" ]; then
    echo ""
    echo -e "${BLUE}VIEWPORT METADATA:${NC}"
    echo "----------------------------------------"
    echo -e "Viewport: ${GREEN}$FEEDBUCKET_VIEWPORT${NC} (saved for QA)"
fi

# FETCH MODE
if [ "$FETCH_ONLY" = true ]; then
    if [ -n "$TICKET_CONTENT" ]; then
        echo ""
        echo -e "${BLUE}CONTENT:${NC}"
        echo "----------------------------------------"
        echo "$TICKET_CONTENT"
    fi

    # Update status to "In Progress" if appropriate
    if [[ "$CURRENT_STATUS" != "Done" && "$CURRENT_STATUS" != "Complete" && "$CURRENT_STATUS" != "In Progress" ]]; then
        echo ""
        echo "Updating status to 'In Progress'..."

        RESULT=$(update_ticket "$DOC_PATH" \
            "status" "In Progress" "string")

        if echo "$RESULT" | jq -e '.fields' > /dev/null 2>&1; then
            echo -e "${GREEN}Status updated to 'In Progress'${NC}"
        else
            echo -e "${RED}Error updating status${NC}"
        fi

        # Also update pageUrl if missing
        if [ -z "$PAGE_URL" ] && [ -n "$FEEDBUCKET_PAGE_URL" ]; then
            update_ticket "$DOC_PATH" "pageUrl" "$FEEDBUCKET_PAGE_URL" "string" > /dev/null
            echo -e "${GREEN}Page URL populated: $FEEDBUCKET_PAGE_URL${NC}"
        fi
    elif [ "$CURRENT_STATUS" = "In Progress" ]; then
        echo ""
        echo -e "${GREEN}Status already 'In Progress'${NC}"
        if [ -z "$PAGE_URL" ] && [ -n "$FEEDBUCKET_PAGE_URL" ]; then
            update_ticket "$DOC_PATH" "pageUrl" "$FEEDBUCKET_PAGE_URL" "string" > /dev/null
            echo -e "${GREEN}Page URL populated: $FEEDBUCKET_PAGE_URL${NC}"
        fi
    else
        echo ""
        echo -e "${YELLOW}Status is '$CURRENT_STATUS' - not updating${NC}"
    fi

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}Metadata cached for QA screenshots${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo "To complete this ticket with QA:"
    echo -e "  ${GREEN}$0 $TICKET_ID --status 'In Review' --qa-before --qa-after --summary 'Your summary'${NC}"

    exit 0
fi

# ============================================================
# UPDATE MODE
# ============================================================

# Status check short-circuits — read-only, no ticket mutation.
if [ "$JR_STATUS_ONLY" = true ]; then
    echo ""
    check_job_report "$(echo "$DOC_PATH" | sed 's|.*/||')"
    exit $?
fi

echo ""
echo -e "${BLUE}Updating ticket...${NC}"

# Auto-detect theme ID if requested
if [ "$AUTO_THEME" = true ] && [ -z "$THEME_ID" ]; then
    echo "Looking up theme ID from git branch..."
    [ -n "$SHOPIFY_STORE" ] && echo "Using store: $SHOPIFY_STORE"
    THEME_ID=$(get_theme_id_from_branch "$SHOPIFY_STORE")
    if [ -n "$THEME_ID" ]; then
        echo -e "${GREEN}Found theme ID: $THEME_ID${NC}"
    else
        echo -e "${YELLOW}Could not auto-detect theme ID${NC}"
    fi
fi

# Build update args
UPDATE_ARGS=()
HAS_UPDATES=false

if [ -n "$NEW_STATUS" ]; then
    UPDATE_ARGS+=("status" "$NEW_STATUS" "string")
    HAS_UPDATES=true
fi

if [ -n "$THEME_ID" ]; then
    UPDATE_ARGS+=("shopifyThemeId" "$THEME_ID" "string")
    HAS_UPDATES=true
fi

if [ -n "$NEW_PAGE_URL" ]; then
    UPDATE_ARGS+=("pageUrl" "$NEW_PAGE_URL" "string")
    HAS_UPDATES=true
fi

# Update properties if any
if [ "$HAS_UPDATES" = true ]; then
    RESULT=$(update_ticket "$DOC_PATH" "${UPDATE_ARGS[@]}")

    if echo "$RESULT" | jq -e '.fields' > /dev/null 2>&1; then
        [ -n "$NEW_STATUS" ] && echo -e "${GREEN}Status updated to '$NEW_STATUS'${NC}"
        [ -n "$THEME_ID" ] && echo -e "${GREEN}Theme ID updated to $THEME_ID${NC}"
        [ -n "$NEW_PAGE_URL" ] && echo -e "${GREEN}Page URL updated to $NEW_PAGE_URL${NC}"
    else
        echo -e "${RED}Error updating properties${NC}"
        echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
    fi
fi

# Write summary to dedicated summary field
if [ -n "$SUMMARY_TEXT" ]; then
    echo ""
    echo "Writing summary..."
    update_ticket "$DOC_PATH" "summary" "$SUMMARY_TEXT" "string" > /dev/null
    echo -e "${GREEN}Summary saved${NC}"
fi

# Handle QA Before
if [ "$QA_BEFORE" = true ]; then
    echo ""
    echo "Processing QA Before screenshot..."
    if "$RECORD_QA_SCRIPT" "$TICKET_ID" --before; then
        echo -e "${GREEN}QA Before uploaded${NC}"
    else
        echo -e "${YELLOW}QA Before failed${NC}"
    fi
fi

# Handle QA After
if [ "$QA_AFTER" = true ]; then
    echo ""
    echo "Processing QA After screenshot..."
    if [ -f "$METADATA_FILE" ]; then
        CACHED_VIEWPORT=$(jq -r '.viewport // empty' "$METADATA_FILE")
        [ -n "$CACHED_VIEWPORT" ] && echo -e "${GREEN}Using cached viewport: $CACHED_VIEWPORT${NC}"
    fi
    if "$RECORD_QA_SCRIPT" "$TICKET_ID" --capture-after; then
        echo -e "${GREEN}QA After captured and uploaded${NC}"
    else
        echo -e "${YELLOW}QA After capture failed${NC}"
    fi
fi

# Handle QA After from file
if [ -n "$QA_AFTER_FILE" ]; then
    echo ""
    echo "Processing QA After from file..."
    if [ ! -f "$QA_AFTER_FILE" ]; then
        echo -e "${RED}File not found: $QA_AFTER_FILE${NC}"
    else
        if [ -f "$METADATA_FILE" ]; then
            CACHED_VIEWPORT=$(jq -r '.viewport // empty' "$METADATA_FILE")
            if [ -n "$CACHED_VIEWPORT" ]; then
                echo -e "${YELLOW}NOTE: Feedbucket viewport is $CACHED_VIEWPORT${NC}"
                echo -e "${YELLOW}Consider using --qa-after instead for automatic capture.${NC}"
            fi
        fi
        if "$RECORD_QA_SCRIPT" "$TICKET_ID" --after "$QA_AFTER_FILE"; then
            echo -e "${GREEN}QA After uploaded from $QA_AFTER_FILE${NC}"
        else
            echo -e "${YELLOW}QA After upload failed${NC}"
        fi
    fi
fi

# Handle job-report submission (after QA so a combined
# "--qa-before --qa-after --job-report" call captures screenshots first)
if [ "$JOB_REPORT" = true ]; then
    echo ""
    echo -e "${BLUE}Submitting job report...${NC}"
    submit_job_report
fi

# Final summary
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}Ticket $TICKET_ID updated successfully!${NC}"
echo -e "${CYAN}========================================${NC}"
echo "View: https://bucky.sunbowl.ca (Databases > Tickets)"
