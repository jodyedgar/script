#!/bin/bash
# jobreport.sh — smooth job-report walkthrough videos via Browserless cloud recording.
#
# Replaces the jumpy screenshot-GIF capture: records a real 30fps browser session
# showing BOTH the Shopify admin (how to edit the feature) and the storefront
# (the feature itself), then submits it to the Bucky job-report pipeline
# (Gemini transcript -> Jody-voice audio -> video+audio MP4 with captions).
#
# Commands:
#   jobreport.sh auth <store>                    One-time (per session expiry) Shopify
#                                                admin login; saves cookies locally for
#                                                the cloud browser to replay.
#   jobreport.sh record <scenario.json> [outdir] Record the walkthrough. Prints the
#                                                final MP4 + GIF thumbnail paths.
#   jobreport.sh submit TICK-### --video FILE --thumb FILE --qa-notes "..."
#                                                Submit to the job-report pipeline
#                                                (delegates to ticket.sh).
#   jobreport.sh full TICK-### <scenario.json> --qa-notes "..."
#                                                record + submit in one go.
#
# Scenario format: see the header of record.js (segments of goto/pause/
# smoothScroll/click/waitFor/hide/type steps; "auth": true segments replay the
# saved admin session). Example: ~/Dropbox/scripts/jobreport/scenario.example.json
#
# Requirements: node, ffmpeg, gcloud auth (for the Browserless token + Firestore),
# gsutil (upload), and a Browserless plan with session recording (Prototyping+).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JR_DIR="$SCRIPT_DIR/jobreport"
TICKET_SH="$SCRIPT_DIR/tickets/ticket.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

cmd="${1:-}"; shift || true
case "$cmd" in
  auth)
    [ $# -ge 1 ] || usage
    node "$JR_DIR/auth.js" "$1"
    ;;

  record)
    [ $# -ge 1 ] || usage
    SCENARIO="$1"
    OUTDIR="${2:-$(mktemp -d /tmp/jobreport-XXXXXX)}"
    node "$JR_DIR/record.js" "$SCENARIO" "$OUTDIR"
    ;;

  submit)
    [ $# -ge 1 ] || usage
    TICKET="$1"; shift
    VIDEO=""; THUMB=""; NOTES=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --video) VIDEO="$2"; shift 2 ;;
        --thumb) THUMB="$2"; shift 2 ;;
        --qa-notes) NOTES="$2"; shift 2 ;;
        *) echo -e "${RED}unknown option: $1${NC}"; exit 2 ;;
      esac
    done
    [ -n "$VIDEO" ] && [ -n "$NOTES" ] || { echo -e "${RED}submit needs --video and --qa-notes${NC}"; exit 2; }
    ARGS=("$TICKET" --job-report --video "$VIDEO" --qa-notes "$NOTES")
    [ -n "$THUMB" ] && ARGS+=(--gif "$THUMB")
    exec "$TICKET_SH" "${ARGS[@]}"
    ;;

  full)
    [ $# -ge 2 ] || usage
    TICKET="$1"; SCENARIO="$2"; shift 2
    NOTES=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --qa-notes) NOTES="$2"; shift 2 ;;
        *) echo -e "${RED}unknown option: $1${NC}"; exit 2 ;;
      esac
    done
    [ -n "$NOTES" ] || { echo -e "${RED}full needs --qa-notes${NC}"; exit 2; }
    OUTDIR="$(mktemp -d /tmp/jobreport-XXXXXX)"
    echo -e "${BLUE}Recording walkthrough...${NC}"
    RESULT="$(node "$JR_DIR/record.js" "$SCENARIO" "$OUTDIR" | tail -1)"
    VIDEO="$(echo "$RESULT" | jq -r '.video')"
    THUMB="$(echo "$RESULT" | jq -r '.thumbnail')"
    echo -e "${GREEN}Recorded: $VIDEO${NC}"
    exec "$TICKET_SH" "$TICKET" --job-report --video "$VIDEO" --gif "$THUMB" --qa-notes "$NOTES"
    ;;

  *) usage ;;
esac
