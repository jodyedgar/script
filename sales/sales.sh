#!/bin/bash
# sales.sh — Bucky CRM reads for the /Dropbox/Sales workspace.
#
# Runs from any directory. Auth: gcloud auth login.
# Playbook and campaign state live in /Dropbox/Sales; this only reads Firestore.
#
#   sales.sh contact <email|name>     record + enrichment + history + tracking
#   sales.sh company <name>           company, contacts, projects
#   sales.sh history <email>          every touch, both comms collections
#   sales.sh campaign <sequenceId>    live enrollment + tracking state
#   sales.sh verify-mx <file|domain>  deliverability check
#   sales.sh segment <field> <value>  export a contact list
#
# Add --json to any command for raw JSON instead of formatted output.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_sales-lib.sh"

JSON_OUT=false
ARGS=()
for a in "$@"; do
  if [ "$a" = "--json" ]; then JSON_OUT=true; else ARGS+=("$a"); fi
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

CMD="${1:-help}"; shift 2>/dev/null || true

# ------------------------------------------------------------
usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

require() {
  [ -n "${1:-}" ] || { echo -e "${RED}Missing argument.${NC}\n" >&2; usage >&2; exit 1; }
}

# ------------------------------------------------------------
# contact
# ------------------------------------------------------------
cmd_contact() {
  local NEEDLE="$1"; require "$NEEDLE"
  local ROWS; ROWS=$(find_contact "$NEEDLE")
  local N; N=$(echo "$ROWS" | jq 'length')

  if [ "$N" = "0" ]; then
    echo -e "${YELLOW}No contact found for '$NEEDLE'.${NC}"
    if [[ "$NEEDLE" == *"@"* ]]; then
      local D; D=$(domain_of "$NEEDLE")
      echo "  Domain $D is $(mx_status "$D")."
    fi
    return 1
  fi

  if [ "$JSON_OUT" = true ]; then echo "$ROWS"; return 0; fi

  if [ "$N" != "1" ]; then
    echo -e "${YELLOW}$N matches — narrow it down:${NC}"
    echo "$ROWS" | jq -r '.[] | "  \(.firstName // "?") \(.lastName // "") — \(.companyName // "no company") — \(.email // "no email")"'
    return 0
  fi

  local C; C=$(echo "$ROWS" | jq '.[0]')
  local EMAIL; EMAIL=$(echo "$C" | jq -r '.email // empty')
  local CID;   CID=$(echo "$C" | jq -r '._path' | sed 's|contacts/||')

  head1 "$(echo "$C" | jq -r '"\(.firstName // "?") \(.lastName // "")"') — $(echo "$C" | jq -r '.companyName // "no company"')"
  kv "Email"      "$EMAIL"
  kv "Other"      "$(echo "$C" | jq -r '(.additionalEmails // []) | join(", ")')"
  kv "Phone"      "$(echo "$C" | jq -r '.phone // .mobilePhone // empty')"
  kv "Title"      "$(echo "$C" | jq -r '.jobTitle // empty')"
  kv "Website"    "$(echo "$C" | jq -r '.websiteUrl // empty')"
  kv "Categories" "$(echo "$C" | jq -r '(.categories // []) | join(", ")')"
  kv "Seniority"  "$(echo "$C" | jq -r '.seniority // empty')"
  kv "ICP score"  "$(echo "$C" | jq -r '.icpFitScore // empty')"
  kv "LinkedIn"   "$(echo "$C" | jq -r '.linkedinUrl // empty')"
  kv "Owner"      "$(echo "$C" | jq -r '.contactOwner // empty')"
  kv "Clients"    "$(echo "$C" | jq -r '(.clientIds // []) | join(", ")')"
  kv "Doc"        "contacts/$CID"

  # Deliverability — the field lies, so check the domain directly.
  if [ -n "$EMAIL" ]; then
    local D ST; D=$(domain_of "$EMAIL"); ST=$(mx_status "$D")
    if [ "$ST" = "no_mx" ]; then
      printf "  %-18s ${RED}%s${NC}\n" "Deliverable" "NO — $D has no MX record"
    else
      printf "  %-18s ${GREEN}%s${NC}\n" "Deliverable" "yes ($D)"
    fi
  fi
  kv "Last contacted" "$(echo "$C" | jq -r '.lastContactedDate // empty') $(echo "$C" | jq -r 'if .lastContactedDate then "(attempted send — not proof of delivery)" else "" end')"

  # Enrichment
  local ENR; ENR=$(fs_where contactEnrichments contactId EQUAL "$CID" 1 | fs_rows)
  if [ "$(echo "$ENR" | jq 'length')" != "0" ]; then
    head1 "Enrichment"
    echo "$ENR" | jq -r '.[0] | "  Provider: \(.provider // "?")   Enriched: \(.enrichedAt // "?")"'
    echo "$ENR" | jq -r '.[0].company // {} | "  Company: \(.name // "?") | \(.industry // "?") | \(.employeeRange // "?") employees"'
    echo "$ENR" | jq -r '.[0].company // {} | "  Shopify: \(.isShopify // false)   Plan: \(.shopifyPlan // "—")"'
    echo "$ENR" | jq -r '.[0].company.technologies // [] | if length>0 then "  Tech: \(join(", "))" else empty end'
  fi

  # History + tracking — reuse the id we already resolved
  [ -n "$EMAIL" ] && CONTACT_ID="$CID" cmd_history "$EMAIL" --embedded
}

# ------------------------------------------------------------
# history — both comms collections. `communications` is a frozen
# HubSpot import; live mail is in `slackCommunications`.
# ------------------------------------------------------------
cmd_history() {
  local EMAIL="$1"; require "$EMAIL"
  local EMBEDDED="${2:-}"
  local CID="${CONTACT_ID:-}"

  # The frozen import is only queryable by contactId — `participants` is empty
  # and `from`/`to` are nested maps. Resolve the id if we weren't handed one.
  if [ -z "$CID" ]; then
    CID=$(find_contact "$EMAIL" | jq -r '.[0]._path // empty' | sed 's|contacts/||')
  fi

  local IN OUT FROZEN TRACK
  IN=$(fs_where  slackCommunications fromEmail EQUAL          "$EMAIL" 25 | fs_rows)
  OUT=$(fs_where slackCommunications toEmails  ARRAY_CONTAINS "$EMAIL" 25 | fs_rows)
  local LIVE; LIVE=$(jq -n --argjson a "$IN" --argjson b "$OUT" '$a + $b | unique_by(._path)')

  if [ -n "$CID" ]; then
    FROZEN=$(fs_where communications contactIds ARRAY_CONTAINS "$CID" 25 | fs_rows)
  else
    FROZEN='[]'
  fi
  TRACK=$(fs_where emailTrackingEvents recipientEmail EQUAL "$EMAIL" 25 | fs_rows)

  if [ "$JSON_OUT" = true ]; then
    jq -n --argjson live "$LIVE" --argjson frozen "$FROZEN" --argjson tracking "$TRACK" \
      '{live:$live, frozen:$frozen, tracking:$tracking}'
    return 0
  fi

  head1 "Communications — live (slackCommunications)"
  if [ "$(echo "$LIVE" | jq 'length')" = "0" ]; then echo "  none"
  else
    # .timestamp is epoch-seconds as a string on both Slack and email docs
    echo "$LIVE" | jq -r 'sort_by(.timestamp // "0" | tonumber) | reverse | .[] |
      "  \(((.timestamp // "0" | tonumber) | todate)[0:10])  \(.source // "?" | .[0:5])  " +
      "\(.fromEmail // .userName // "?" | .[0:28])  \(.subject // .text // "" | gsub("\n";" ") | .[0:52])"'
  fi

  head1 "Communications — frozen HubSpot import"
  if [ "$(echo "$FROZEN" | jq 'length')" = "0" ]; then echo "  none"
  else echo "$FROZEN" | jq -r 'sort_by(.occurredAt // "") | reverse | .[] |
      "  \((.occurredAt // "?")[0:10])  \(.direction // "?" | .[0:8])  \(.type // "?" | .[0:6])  " +
      "\(.subject // .summary // "" | gsub("\n";" ") | .[0:56])"'
  fi

  head1 "Outbound tracking"
  if [ "$(echo "$TRACK" | jq 'length')" = "0" ]; then echo "  none"
  else echo "$TRACK" | jq -r 'sort_by(.sentAt // "") | reverse | .[] |
      "  \((.sentAt // "?")[0:10])  \(.subject // "" | .[0:44])  " +
      (if .bounced then "BOUNCED" elif .replied then "replied"
       elif .clicked then "clicked" elif .opened then "opened \(.openCount // 0)x"
       else "sent" end)'
  fi
  [ "$EMBEDDED" = "--embedded" ] && echo ""
  return 0
}

# ------------------------------------------------------------
# company
# ------------------------------------------------------------
cmd_company() {
  local NEEDLE="$1"; require "$NEEDLE"
  local ROWS; ROWS=$(find_client "$NEEDLE")
  if [ "$(echo "$ROWS" | jq 'length')" = "0" ]; then
    echo -e "${YELLOW}No client found for '$NEEDLE'.${NC}"; return 1
  fi
  if [ "$JSON_OUT" = true ]; then echo "$ROWS"; return 0; fi

  local CL; CL=$(echo "$ROWS" | jq '.[0]')
  local CLID; CLID=$(echo "$CL" | jq -r '._path' | sed 's|clients/||')

  head1 "$(echo "$CL" | jq -r '.companyName // .name')"
  kv "Doc"      "clients/$CLID"
  kv "Domains"  "$(echo "$CL" | jq -r '(.domains // []) | join(", ")')"
  kv "Slack"    "$(echo "$CL" | jq -r '(.slackChannels // []) | join(", ")')"

  head1 "Contacts"
  fs_where contacts clientIds ARRAY_CONTAINS "$CLID" 50 | fs_rows |
    jq -r 'if length==0 then "  none" else .[] |
      "  \(.firstName // "?") \(.lastName // "")  \(.email // "no email")  \(.jobTitle // "")" end'

  head1 "Projects (rung evidence — department, NOT projectType)"
  fs_where clientProjects clientId EQUAL "$CLID" 50 | fs_rows |
    jq -r 'if length==0 then "  none" else sort_by(.createdAt // "") | reverse | .[] |
      "  \(.displayId // "?")  [\(.department // "no department")]  \(.name // "")" end'
}

# ------------------------------------------------------------
# campaign — live state for a sequence
# ------------------------------------------------------------
cmd_campaign() {
  local SEQ="$1"; require "$SEQ"
  local ENR; ENR=$(fs_where sequenceEnrollments sequenceId EQUAL "$SEQ" 300 | fs_rows)
  if [ "$JSON_OUT" = true ]; then echo "$ENR"; return 0; fi

  local SEQDOC; SEQDOC=$(get_document "outreachSequences/$SEQ" | fs_row)
  head1 "$(echo "$SEQDOC" | jq -r '.name // "unknown sequence"')"
  kv "Status" "$(echo "$SEQDOC" | jq -r '.status // "?"')"
  kv "Sender" "$(echo "$SEQDOC" | jq -r '.senderType // "?"')"

  head1 "Enrollments by status"
  echo "$ENR" | jq -r 'group_by(.status) | .[] | "  \(.[0].status // "?"): \(length)"'

  head1 "Detail"
  echo "$ENR" | jq -r 'sort_by(.contactEmail // "") | .[] |
    "  \(.status // "?" | .[0:14] | . + "              " | .[0:14]) \(.contactEmail // "?")"'
}

# ------------------------------------------------------------
# verify-mx — the check that caught a 22% dead rate
# ------------------------------------------------------------
cmd_verify_mx() {
  local TARGET="$1"; require "$TARGET"
  local DOMAINS
  if [ -f "$TARGET" ]; then
    DOMAINS=$(grep -oiE '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' "$TARGET" |
              sed 's/.*@//' | tr '[:upper:]' '[:lower:]' | sort -u)
    [ -z "$DOMAINS" ] && DOMAINS=$(grep -oiE '\b[a-z0-9-]+\.[a-z]{2,}\b' "$TARGET" | sort -u)
  else
    DOMAINS=$(domain_of "$TARGET")
  fi

  local TOTAL=0 DEAD=0
  echo ""
  while read -r D; do
    [ -z "$D" ] && continue
    TOTAL=$((TOTAL+1))
    if [ "$(mx_status "$D")" = "no_mx" ]; then
      DEAD=$((DEAD+1)); printf "  ${RED}%-40s no MX${NC}\n" "$D"
    else
      printf "  ${GREEN}%-40s live${NC}\n" "$D"
    fi
  done <<< "$DOMAINS"

  hr
  if [ "$TOTAL" -gt 0 ]; then
    printf "  %s domains, ${RED}%s undeliverable${NC} (%s%%)\n" "$TOTAL" "$DEAD" "$((DEAD*100/TOTAL))"
  fi
  echo "  Bounces hurt more than a missed send — they cool the sending domain."
}

# ------------------------------------------------------------
# segment — export a list
# ------------------------------------------------------------
cmd_segment() {
  local FIELD="$1" VALUE="$2"; require "$FIELD"; require "$VALUE"
  local OP="EQUAL"
  case "$FIELD" in
    categories|tags|clientIds|allEmails|additionalEmails) OP="ARRAY_CONTAINS" ;;
  esac

  local ROWS; ROWS=$(fs_where contacts "$FIELD" "$OP" "$VALUE" 500 | fs_rows)
  if [ "$JSON_OUT" = true ]; then echo "$ROWS"; return 0; fi

  echo "$ROWS" | jq -r '["firstName","lastName","email","companyName","jobTitle","phone"],
    (.[] | [.firstName, .lastName, .email, .companyName, .jobTitle, .phone]
           | map(. // "")) | @csv'
  local N; N=$(echo "$ROWS" | jq 'length')
  echo "" >&2
  echo -e "${CYAN}$N contacts.${NC} Redirect to /Dropbox/Sales/exports/ — and MX-check before drafting." >&2
  if [ "$N" -ge 500 ]; then
    echo -e "${RED}TRUNCATED at the 500 limit — this is NOT the full segment.${NC} Narrow the filter before treating it as a list." >&2
  fi
}

# ------------------------------------------------------------
case "$CMD" in
  contact)    cmd_contact "${1:-}" ;;
  company)    cmd_company "${1:-}" ;;
  history)    cmd_history "${1:-}" ;;
  campaign)   cmd_campaign "${1:-}" ;;
  verify-mx)  cmd_verify_mx "${1:-}" ;;
  segment)    cmd_segment "${1:-}" "${2:-}" ;;
  help|-h|--help) usage ;;
  *) echo -e "${RED}Unknown command: $CMD${NC}\n" >&2; usage >&2; exit 1 ;;
esac
