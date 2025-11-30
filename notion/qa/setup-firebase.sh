#!/bin/bash

# Firebase Setup Helper for QA Screenshot System
# This script helps configure Firebase authentication

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_ACCOUNT_FILE="$SCRIPT_DIR/service-account.json"

echo -e "${BLUE}Firebase QA Screenshot System Setup${NC}"
echo ""

# Check if service account exists
if [ -f "$SERVICE_ACCOUNT_FILE" ]; then
    echo -e "${GREEN}✓ Service account file found${NC}"
    PROJECT_ID=$(jq -r '.project_id' "$SERVICE_ACCOUNT_FILE")
    echo "  Project: $PROJECT_ID"
else
    echo -e "${YELLOW}⚠ Service account file not found${NC}"
    echo ""
    echo "To set up Firebase authentication:"
    echo ""
    echo "1. Go to Firebase Console:"
    echo "   https://console.firebase.google.com/project/bucky-app-355a3/settings/serviceaccounts/adminsdk"
    echo ""
    echo "2. Click 'Generate new private key'"
    echo ""
    echo "3. Save the downloaded JSON file as:"
    echo "   $SERVICE_ACCOUNT_FILE"
    echo ""
    echo "4. Run this script again to verify setup"
    exit 1
fi

# Check Node.js dependencies
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
    echo -e "${BLUE}Installing Node.js dependencies...${NC}"
    (cd "$SCRIPT_DIR" && npm install)
else
    echo -e "${GREEN}✓ Node.js dependencies installed${NC}"
fi

# Test Firebase connection
echo ""
echo -e "${BLUE}Testing Firebase connection...${NC}"

TEST_RESULT=$(cd "$SCRIPT_DIR" && node -e "
const { initializeApp, cert } = require('firebase-admin/app');
const { getStorage } = require('firebase-admin/storage');
const fs = require('fs');

const serviceAccount = JSON.parse(fs.readFileSync('./service-account.json', 'utf8'));

try {
    initializeApp({
        credential: cert(serviceAccount),
        storageBucket: 'bucky-app-355a3.firebasestorage.app'
    });
    const bucket = getStorage().bucket();
    console.log(JSON.stringify({ success: true, bucket: bucket.name }));
} catch (error) {
    console.log(JSON.stringify({ success: false, error: error.message }));
}
" 2>&1)

if echo "$TEST_RESULT" | jq -e '.success == true' > /dev/null 2>&1; then
    BUCKET=$(echo "$TEST_RESULT" | jq -r '.bucket')
    echo -e "${GREEN}✓ Firebase connection successful${NC}"
    echo "  Storage bucket: $BUCKET"
    echo ""
    echo -e "${GREEN}Setup complete! You can now use:${NC}"
    echo "  ./record-qa.sh TICK-### --before"
    echo "  ./record-qa.sh TICK-### --after ./screenshot.png"
else
    ERROR=$(echo "$TEST_RESULT" | jq -r '.error // .')
    echo -e "${RED}✗ Firebase connection failed: $ERROR${NC}"
    exit 1
fi
