#!/bin/bash

# Add a client theme repo to the Bucky GitHub Apps and record it in Bucky.
# Usage: ./github-apps-add-repo.sh [owner/repo]
#
# Bucky's GitHub Apps (Reader, Builder, Promoter) are installed on SELECTED
# repos only, so a new client's theme repo reaches none of them until an org
# owner adds it. Without it, QA approval can't merge into staging and Cody's
# preflight holds the client's tickets ("On the Bucky GitHub Apps").
#
# GitHub doesn't let an App add itself, so this opens the three settings pages
# for you, checks Builder's install with its key, then stamps
# githubAppsConfirmedAt on the repo's shops/{store}/repos docs (the same thing
# the Client Setup "Theme repo added to the Bucky GitHub Apps" Fix does).
# Called by setup-shopify-store.sh; safe to re-run.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT="bucky-app-355a3"
BUILDER_KEY="$HOME/.config/sunbowl/bucky-builder.pem"
BUILDER_CLIENT_ID="Iv23liNjk3nXvDK39OEg"
APPS=(
    "Sunbowl Bucky Reader|174202382"
    "Sunbowl Bucky Builder|174202433"
    "Sunbowl Bucky Promoter|174202474"
)

REPO="$1"
if [ -z "$REPO" ]; then
    read -r -p "GitHub theme repo (owner/name, e.g. sunbowl/shopify-acme): " REPO
fi
REPO="${REPO#https://github.com/}"
REPO="${REPO%.git}"
if [[ ! "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo -e "${RED}Not an owner/name repo: '$REPO'${NC}"
    exit 1
fi
case "$REPO" in
    sunbowl/bucky-app|sunbowl/sunbowl-shopify-app)
        echo -e "${YELLOW}$REPO is kept off the Bucky GitHub Apps on purpose (the dev team ships it by hand).${NC}"
        exit 0 ;;
esac

if ! gh api "repos/$REPO" --jq .full_name >/dev/null 2>&1; then
    echo -e "${YELLOW}$REPO doesn't exist on GitHub yet (or your gh login can't see it).${NC}"
    echo "Create and push it first, then run: ~/Dropbox/scripts/shopify/github-apps-add-repo.sh $REPO"
    exit 0
fi

# Builder's own view of the repo: installed | missing | unknown (no key / GitHub error).
builder_install() {
    [ -r "$BUILDER_KEY" ] || { echo unknown; return; }
    node - "$REPO" "$BUILDER_KEY" "$BUILDER_CLIENT_ID" <<'NODE'
const crypto = require("crypto"), fs = require("fs");
const [repo, keyPath, clientId] = process.argv.slice(2);
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const now = Math.floor(Date.now() / 1000);
const unsigned = `${b64({ alg: "RS256", typ: "JWT" })}.${b64({ iat: now - 60, exp: now + 540, iss: clientId })}`;
const jwt = `${unsigned}.${crypto.sign("RSA-SHA256", Buffer.from(unsigned), fs.readFileSync(keyPath, "utf8")).toString("base64url")}`;
fetch(`https://api.github.com/repos/${repo}/installation`, {
  headers: { accept: "application/vnd.github+json", authorization: `Bearer ${jwt}`, "x-github-api-version": "2022-11-28" },
}).then((r) => console.log(r.status === 404 ? "missing" : r.ok ? "installed" : "unknown"), () => console.log("unknown"));
NODE
}

echo -e "${GREEN}Bucky GitHub Apps: $REPO${NC}"
if [ "$(builder_install)" = "installed" ]; then
    echo "Builder already has $REPO."
fi

echo ""
echo "Needs a GitHub org owner (Jody). For EACH of the three Apps opening in your browser:"
echo "  1. Under Repository access, keep \"Only select repositories\" (never All repositories)."
echo "  2. Click Select repositories, search for $REPO, tick it."
echo "  3. Click Save."
echo "Signed out? https://github.com/login"
echo ""
for app in "${APPS[@]}"; do
    name="${app%%|*}"; id="${app##*|}"
    url="https://github.com/organizations/sunbowl/settings/installations/$id"
    echo "  $name: $url"
    open "$url" 2>/dev/null || true
done
echo ""

while true; do
    read -r -p "Press Enter once you've saved all three (s = skip for now): " ANSWER
    if [[ "$ANSWER" =~ ^[Ss] ]]; then
        echo -e "${YELLOW}Skipped. Cody's preflight will hold this client's tickets until it's done.${NC}"
        echo "Later: ~/Dropbox/scripts/shopify/github-apps-add-repo.sh $REPO  (or the Client Setup checklist in Bucky)"
        exit 0
    fi
    LIVE="$(builder_install)"
    if [ "$LIVE" = "missing" ]; then
        echo -e "${RED}GitHub says Builder still isn't on $REPO — check you clicked Save, then try again.${NC}"
        continue
    fi
    [ "$LIVE" = "installed" ] && echo -e "${GREEN}Builder verified on $REPO.${NC}"
    [ "$LIVE" = "unknown" ] && echo -e "${YELLOW}Couldn't verify Builder (no key at $BUILDER_KEY or GitHub didn't answer).${NC}"
    read -r -p "Added to Reader AND Promoter too? [y/N] " BOTH
    [[ "$BOTH" =~ ^[Yy] ]] && break
    echo "Finish the other two, then press Enter."
done

# Record it in Bucky: stamp every registered theme doc of this repo.
TOKEN="$(gcloud auth print-access-token 2>/dev/null)"
if [ -z "$TOKEN" ]; then
    echo -e "${YELLOW}gcloud isn't logged in — confirm it in Bucky Client Setup instead (\"Theme repo added to the Bucky GitHub Apps\" → Fix).${NC}"
    exit 0
fi
BASE="https://firestore.googleapis.com/v1/projects/$PROJECT/databases/(default)/documents"
PATHS="$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "${BASE}:runQuery" \
    -d '{"structuredQuery":{"from":[{"collectionId":"repos","allDescendants":true}]}}' \
    | python3 -c '
import json, sys
want = sys.argv[1].lower()
for r in json.load(sys.stdin):
    d = r.get("document")
    if not d: continue
    repo = d.get("fields", {}).get("repo", {}).get("stringValue", "").lower().removeprefix("https://github.com/").removesuffix(".git")
    if d["name"].split("/")[-1].startswith("theme") and repo == want:
        print(d["name"].split("/documents/")[1])
' "$REPO")"

if [ -z "$PATHS" ]; then
    echo -e "${YELLOW}$REPO isn't registered for a store in Bucky yet.${NC}"
    echo "Register its main + staging theme repos in Bucky Client Setup, then tick \"Theme repo added to the Bucky GitHub Apps\" there — or re-run this script after registering."
    exit 0
fi

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COUNT=0
while read -r P; do
    [ -z "$P" ] && continue
    CODE=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
        "${BASE}/${P}?updateMask.fieldPaths=githubAppsConfirmedAt&currentDocument.exists=true" \
        -d "{\"fields\":{\"githubAppsConfirmedAt\":{\"timestampValue\":\"$NOW\"}}}")
    if [ "$CODE" = "200" ]; then COUNT=$((COUNT + 1)); else echo -e "${RED}Couldn't stamp $P ($CODE)${NC}"; fi
done <<< "$PATHS"
echo -e "${GREEN}✓ Recorded in Bucky ($COUNT repo doc(s)). Client Setup and Cody's preflight now show it as done.${NC}"
