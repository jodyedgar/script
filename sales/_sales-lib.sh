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
