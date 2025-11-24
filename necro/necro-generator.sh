#!/bin/bash
# Necro Generator - Creates all Necro files
# Run this in ~/Dropbox/Scripts/Necro/ directory

set -e

NECRO_HOME="$(pwd)"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   NECRO - Generator Script                                ║"
echo "║   This will create all Necro files                        ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Target directory: $NECRO_HOME"
echo ""

# Confirm
read -p "Create all Necro files here? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Creating directory structure..."

# Create directories
mkdir -p bin templates docs lib tests

echo "✓ Directories created"
echo ""
echo "Creating files..."

# lib/common.sh
cat > lib/common.sh << 'EOF'
#!/bin/bash
# Common functions for Necro scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}→${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

# Confirmation prompt
confirm() {
    local prompt="$1"
    local response
    echo -e "${YELLOW}$prompt (y/n):${NC}"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Find project root (looks for package.json, .git, etc)
get_project_root() {
    local dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/package.json" ]] || [[ -d "$dir/.git" ]] || [[ -f "$dir/firebase.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "$(pwd)"
    return 1
}

# Get relative path from base to target
get_relative_path() {
    local base="$1"
    local target="$2"
    echo "${target#$base/}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get file modification date
get_file_date() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$1" 2>/dev/null
    else
        stat -c "%y" "$1" 2>/dev/null | cut -d'.' -f1
    fi
}

# Get file size in human readable format
get_file_size() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f "%z" "$1" 2>/dev/null | awk '{
            if ($1 < 1024) print $1 " B"
            else if ($1 < 1048576) printf "%.1f KB\n", $1/1024
            else printf "%.1f MB\n", $1/1048576
        }'
    else
        ls -lh "$1" 2>/dev/null | awk '{print $5}'
    fi
}
EOF

chmod +x lib/common.sh
echo "✓ Created lib/common.sh"

# Placeholder for actual implementation
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   NEXT: Implement the actual commands                    ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "This generator script creates the structure."
echo "Read NECRO_IMPLEMENTATION_GUIDE.md for full implementation details."
echo ""
echo "Tell Claude Code to implement all the scripts according to"
echo "the implementation guide."
