#!/bin/bash
# Shared helpers for sales.sh
# Builds on the ticket scripts' Firestore lib (gcloud auth + REST, project bucky-app-355a3).
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/_sales-lib.sh"

_SALES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../tickets/_firestore-lib.sh
source "$_SALES_LIB_DIR/../tickets/_firestore-lib.sh"

# ============================================================
# Firestore value unwrapping
#
# The ticket lib extracts one typed field at a time (fs_string, fs_number...).
# Sales work needs whole records, so this converts Firestore's typed-value JSON
# into plain JSON in one pass. Everything downstream reads normal fields.
# ============================================================

read -r -d '' FS_UNWRAP_JQ <<'JQ' || true
def unwrap:
  if type == "object" then
    if   has("stringValue")    then .stringValue
    elif has("integerValue")   then (.integerValue | tonumber)
    elif has("doubleValue")    then .doubleValue
    elif has("booleanValue")   then .booleanValue
    elif has("timestampValue") then .timestampValue
    elif has("nullValue")      then null
    elif has("bytesValue")     then "<bytes>"
    elif has("referenceValue") then (.referenceValue | sub(".*/documents/"; ""))
    elif has("geoPointValue")  then .geoPointValue
    elif has("arrayValue")     then [ (.arrayValue.values // [])[] | unwrap ]
    elif has("mapValue")       then ((.mapValue.fields // {}) | with_entries(.value |= unwrap))
    else . end
  else . end;

def docflat:
  { _path: ((.name // "") | sub(".*/documents/"; "")) }
  + ((.fields // {}) | with_entries(.value |= unwrap));
JQ

# Flatten a runQuery response (array of {document:...}) → array of plain objects
fs_rows() {
  jq "$FS_UNWRAP_JQ"' [ .[] | select(.document) | .document | docflat ]'
}

# Flatten a single-document GET response → plain object
fs_row() {
  jq "$FS_UNWRAP_JQ"' if .fields then docflat else {} end'
}

# ============================================================
# Generic queries
# ============================================================

# fs_where COLLECTION FIELD OP VALUE [LIMIT] [ORDER_FIELD] [ORDER_DIR]
# OP: EQUAL | ARRAY_CONTAINS | GREATER_THAN | LESS_THAN | NOT_EQUAL
# Values are sent as strings; use fs_where_typed for non-string comparisons.
fs_where() {
  local COLLECTION="$1" FIELD="$2" OP="$3" VALUE="$4"
  local LIMIT="${5:-50}" ORDER_FIELD="${6:-}" ORDER_DIR="${7:-DESCENDING}"
  local TOKEN; TOKEN=$(get_auth_token)

  local BODY
  BODY=$(jq -n \
    --arg col "$COLLECTION" --arg field "$FIELD" --arg op "$OP" \
    --arg val "$VALUE" --argjson limit "$LIMIT" \
    --arg ofield "$ORDER_FIELD" --arg odir "$ORDER_DIR" \
    '{structuredQuery:
       ({ from:  [{collectionId:$col}],
          where: {fieldFilter:{field:{fieldPath:$field},op:$op,value:{stringValue:$val}}},
          limit: $limit }
        + (if $ofield == "" then {}
           else {orderBy:[{field:{fieldPath:$ofield},direction:$odir}]} end))}')

  curl -s -X POST "$FIRESTORE_BASE:runQuery" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BODY"
}

# fs_where_bool COLLECTION FIELD BOOL [LIMIT]
fs_where_bool() {
  local COLLECTION="$1" FIELD="$2" VALUE="$3" LIMIT="${4:-50}"
  local TOKEN; TOKEN=$(get_auth_token)
  curl -s -X POST "$FIRESTORE_BASE:runQuery" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -n --arg col "$COLLECTION" --arg f "$FIELD" \
            --argjson v "$VALUE" --argjson l "$LIMIT" \
            '{structuredQuery:{from:[{collectionId:$col}],
              where:{fieldFilter:{field:{fieldPath:$f},op:"EQUAL",value:{booleanValue:$v}}},
              limit:$l}}')"
}

# ============================================================
# Domain lookups
# ============================================================

# Find a contact by email (uses the denormalized allEmails array) or by name.
find_contact() {
  local NEEDLE="$1" RES
  if [[ "$NEEDLE" == *"@"* ]]; then
    RES=$(fs_where contacts allEmails ARRAY_CONTAINS "$(echo "$NEEDLE" | tr '[:upper:]' '[:lower:]')" 5)
    local COUNT; COUNT=$(echo "$RES" | fs_rows | jq 'length')
    if [ "$COUNT" = "0" ]; then
      # fall back to the primary email field for pre-migration docs
      RES=$(fs_where contacts email EQUAL "$NEEDLE" 5)
    fi
  else
    RES=$(fs_where contacts firstName EQUAL "$NEEDLE" 10)
    if [ "$(echo "$RES" | fs_rows | jq 'length')" = "0" ]; then
      RES=$(fs_where contacts lastName EQUAL "$NEEDLE" 10)
    fi
    if [ "$(echo "$RES" | fs_rows | jq 'length')" = "0" ]; then
      RES=$(fs_where contacts companyName EQUAL "$NEEDLE" 10)
    fi
  fi
  echo "$RES" | fs_rows
}

find_client() {
  local NEEDLE="$1" RES
  RES=$(fs_where clients name EQUAL "$NEEDLE" 5)
  if [ "$(echo "$RES" | fs_rows | jq 'length')" = "0" ]; then
    RES=$(fs_where clients companyName EQUAL "$NEEDLE" 5)
  fi
  echo "$RES" | fs_rows
}

# ============================================================
# Writes
# ============================================================

# Fields no sales command may write. Touching email/additionalEmails without
# recomputing allEmails silently breaks array-contains lookups, and no trigger
# rebuilds it. Identity edits are judgment calls — they belong in salesProposals.
FS_PROTECTED_FIELDS="email additionalEmails allEmails firstName lastName clientIds"

# fs_update DOC_PATH KEY VALUE TYPE [KEY VALUE TYPE ...]
# Wraps the ticket lib's generic PATCH (updateMask, so unlisted fields survive)
# and refuses protected fields.
fs_update() {
  local DOC_PATH="$1"; shift
  local i=1
  for arg in "$@"; do
    if [ $(( (i - 1) % 3 )) -eq 0 ]; then
      for prot in $FS_PROTECTED_FIELDS; do
        if [ "$arg" = "$prot" ]; then
          echo -e "${RED}REFUSED: '$arg' is a protected field.${NC}" >&2
          echo "  Writing it without recomputing allEmails breaks contact lookup." >&2
          echo "  Identity changes are judgment calls — use: sales.sh propose" >&2
          return 1
        fi
      done
    fi
    i=$((i+1))
  done
  update_ticket "$DOC_PATH" "$@"
}

# The sanctioned bypass. A human approving a proposal IS the authorization to
# write an identity field, so `approve` uses this instead of fs_update.
# Never call it directly from a command that isn't gated on human approval.
fs_update_approved() { update_ticket "$@"; }

now_iso() { date -u +"%Y-%m-%dT%H:%M:%S.000000Z"; }

# Resolve an email to its contacts/{id} path. Empty if not found.
contact_doc_path() {
  find_contact "$1" | jq -r '.[0]._path // empty'
}

# Record a judgment call for batch approval rather than writing it directly.
create_proposal() {
  local CONTACT_PATH="$1" FIELD="$2" CURRENT="$3" PROPOSED="$4" REASON="$5"
  local TOKEN; TOKEN=$(get_auth_token)
  local NOW; NOW=$(now_iso)

  curl -s -X POST "$FIRESTORE_BASE/salesProposals" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -n --arg cp "$CONTACT_PATH" --arg f "$FIELD" --arg cur "$CURRENT" \
             --arg prop "$PROPOSED" --arg why "$REASON" --arg now "$NOW" \
      '{fields:{
          contactPath:  {stringValue:$cp},
          contactId:    {stringValue:($cp | sub("contacts/";""))},
          field:        {stringValue:$f},
          currentValue: {stringValue:$cur},
          proposedValue:{stringValue:$prop},
          reason:       {stringValue:$why},
          status:       {stringValue:"pending"},
          proposedBy:   {stringValue:"sales.sh"},
          proposedAt:   {timestampValue:$now},
          createdAt:    {timestampValue:$now}}}')"
}

# ============================================================
# Merchant probe — the ICP gate
#
# "Verified merchant" is the entry requirement for Rung 1, and Bucky has no
# native flag for it. Ranking BC contacts by warmth and seniority put a housing
# authority, a contractor and an insurance broker at the top of an ecommerce
# list; this is the check that fixes that.
#
# Echoes: "<platform>" | "not_merchant" | "unreachable"
#
# `unreachable` is deliberately NOT `not_merchant`. Bot protection and slow
# hosts look identical to a dead site from here, and ~109 domains were dropped
# that way on the Tier D build. Never write isMerchant=false on unreachable.
# ============================================================
# Free/ISP mailbox providers. Probing these tells you nothing about the CONTACT —
# gmail.com has no store, but the founder using it may well run one. Never infer
# merchant status from a personal mailbox; fall back to their website or leave
# them unverified. Writing isMerchant=false here disqualifies a real merchant
# from Rung 1 permanently.
FREE_EMAIL_DOMAINS="gmail.com googlemail.com hotmail.com hotmail.ca outlook.com live.com live.ca msn.com yahoo.com yahoo.ca ymail.com aol.com icloud.com me.com mac.com shaw.ca telus.net rogers.com sympatico.ca bell.net protonmail.com proton.me gmx.com mail.com zoho.com fastmail.com"

is_free_email_domain() {
  local D; D=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  for f in $FREE_EMAIL_DOMAINS; do [ "$D" = "$f" ] && return 0; done
  return 1
}

probe_merchant() {
  local DOMAIN="$1" BODY
  is_free_email_domain "$DOMAIN" && { echo "free_email"; return; }
  BODY=$(curl -sL --max-time 12 --compressed \
    -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36" \
    "https://$DOMAIN/" 2>/dev/null)

  [ -z "$BODY" ] && { echo "unreachable"; return; }

  # Most specific first — several platforms leave WordPress traces.
  if grep -qiE 'cdn\.shopify\.com|/cdn/shop/|Shopify\.theme|myshopify\.com|shopify-features' <<<"$BODY"; then
    echo "shopify"
  elif grep -qiE 'woocommerce|wp-content/plugins/woocommerce|wc-ajax' <<<"$BODY"; then
    echo "woocommerce"
  elif grep -qiE 'cdn[0-9]*\.bigcommerce\.com|bigcommerce\.com/s-' <<<"$BODY"; then
    echo "bigcommerce"
  elif grep -qiE 'static\.wixstatic\.com.*(store|ecom)|wixstores' <<<"$BODY"; then
    echo "wix"
  elif grep -qiE 'Magento|mage/cookies|static/version.*/frontend' <<<"$BODY"; then
    echo "magento"
  elif grep -qiE 'squarespace' <<<"$BODY" && grep -qiE '/cart|commerce-' <<<"$BODY"; then
    echo "squarespace"
  # Generic cart signals — a store on something unrecognised.
  elif grep -qiE 'add[ _-]?to[ _-]?cart|/checkout|shopping[ _-]?cart' <<<"$BODY"; then
    echo "other_cart"
  else
    echo "not_merchant"
  fi
}

# MX check — the deliverability gate. Echoes "live" or "no_mx".
mx_status() {
  local DOMAIN="$1" MX
  MX=$(dig +short MX "$DOMAIN" 2>/dev/null | head -1)
  if [ -n "$MX" ]; then echo "live"; else echo "no_mx"; fi
}

domain_of() { echo "${1##*@}" | tr '[:upper:]' '[:lower:]'; }

# ============================================================
# Output
# ============================================================

hr()   { printf '%s\n' "────────────────────────────────────────────────────────────"; }
head1() { printf "\n${CYAN}%s${NC}\n" "$1"; hr; }
kv()   { printf "  %-18s %s\n" "$1" "${2:-—}"; }
