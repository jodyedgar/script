#!/bin/bash
# common.sh - Shared functions and utilities for Necro
# Part of the Necro project archaeology and cleanup system

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Version
NECRO_VERSION="1.0.0"

# Necro home directory
NECRO_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

#######################################
# Print info message
# Arguments:
#   Message to print
#######################################
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

#######################################
# Print success message
# Arguments:
#   Message to print
#######################################
log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

#######################################
# Print error message
# Arguments:
#   Message to print
#######################################
log_error() {
    echo -e "${RED}✗ Error:${NC} $*" >&2
}

#######################################
# Print warning message
# Arguments:
#   Message to print
#######################################
log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

#######################################
# Print section header
# Arguments:
#   Header text
#######################################
print_header() {
    echo -e "${PURPLE}$*${NC}"
}

#######################################
# Print banner
# Arguments:
#   Banner text
#######################################
print_banner() {
    local text="$1"
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                                                           ║${NC}"
    printf "${PURPLE}║   %-53s  ║${NC}\n" "$text"
    echo -e "${PURPLE}║                                                           ║${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#######################################
# Confirm yes/no prompt
# Arguments:
#   Prompt message
# Returns:
#   0 if yes, 1 if no
#######################################
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    echo -ne "${YELLOW}${prompt}${NC}"
    read -r response

    # Convert to lowercase
    response="${response,,}"

    # Check response
    if [[ -z "$response" ]]; then
        [[ "$default" == "y" ]] && return 0 || return 1
    elif [[ "$response" =~ ^(y|yes)$ ]]; then
        return 0
    else
        return 1
    fi
}

#######################################
# Get project root directory
# Looks for .git, package.json, .necro, or uses current dir
# Returns:
#   Path to project root
#######################################
get_project_root() {
    local current_dir="$PWD"

    # Check for .necro directory first
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.necro" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done

    # Reset and check for .git
    current_dir="$PWD"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done

    # Reset and check for package.json
    current_dir="$PWD"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/package.json" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done

    # Default to current directory
    echo "$PWD"
}

#######################################
# Check if command exists
# Arguments:
#   Command name
# Returns:
#   0 if exists, 1 if not
#######################################
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

#######################################
# Get current date in YYYY-MM-DD format
# Returns:
#   Date string
#######################################
get_date() {
    date '+%Y-%m-%d'
}

#######################################
# Get current timestamp in YYYYMMDD_HHMMSS format
# Returns:
#   Timestamp string
#######################################
get_timestamp() {
    date '+%Y%m%d_%H%M%S'
}

#######################################
# Get date N days ago in YYYY-MM-DD format
# Arguments:
#   Number of days ago
# Returns:
#   Date string
#######################################
get_date_ago() {
    local days="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        date -v-"${days}d" '+%Y-%m-%d'
    else
        # Linux
        date -d "$days days ago" '+%Y-%m-%d'
    fi
}

#######################################
# Get date N days from now in YYYY-MM-DD format
# Arguments:
#   Number of days from now
# Returns:
#   Date string
#######################################
get_date_future() {
    local days="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        date -v+"${days}d" '+%Y-%m-%d'
    else
        # Linux
        date -d "$days days" '+%Y-%m-%d'
    fi
}

#######################################
# Get file modification date
# Arguments:
#   File path
# Returns:
#   Date string in YYYY-MM-DD format
#######################################
get_file_date() {
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null
    else
        # Linux
        stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1
    fi
}

#######################################
# Get file size in human readable format
# Arguments:
#   File path
# Returns:
#   Size string
#######################################
get_file_size() {
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        stat -f "%z" "$file" 2>/dev/null | awk '{
            if ($1 < 1024) print $1 " B"
            else if ($1 < 1048576) printf "%.1f KB\n", $1/1024
            else if ($1 < 1073741824) printf "%.1f MB\n", $1/1048576
            else printf "%.1f GB\n", $1/1073741824
        }'
    else
        # Linux
        stat -c "%s" "$file" 2>/dev/null | awk '{
            if ($1 < 1024) print $1 " B"
            else if ($1 < 1048576) printf "%.1f KB\n", $1/1024
            else if ($1 < 1073741824) printf "%.1f MB\n", $1/1048576
            else printf "%.1f GB\n", $1/1073741824
        }'
    fi
}

#######################################
# Ensure directory exists
# Arguments:
#   Directory path
#######################################
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}

#######################################
# Get relative path from base to target
# Arguments:
#   Base path
#   Target path
# Returns:
#   Relative path
#######################################
get_relative_path() {
    local base="$1"
    local target="$2"

    # Use Python if available for accurate relative path
    if command_exists python3; then
        python3 -c "import os; print(os.path.relpath('$target', '$base'))"
    elif command_exists python; then
        python -c "import os; print(os.path.relpath('$target', '$base'))"
    else
        # Simple fallback - just remove base from target if it's a prefix
        echo "${target#$base/}"
    fi
}

#######################################
# Check if running in git repository
# Returns:
#   0 if in git repo, 1 if not
#######################################
is_git_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

#######################################
# Get git branch name
# Returns:
#   Branch name or empty string
#######################################
get_git_branch() {
    if is_git_repo; then
        git rev-parse --abbrev-ref HEAD 2>/dev/null
    fi
}

#######################################
# Show help for a script
# Arguments:
#   Script name
#   Description
#   Usage string
#   Options array (optional)
#######################################
show_help() {
    local script_name="$1"
    local description="$2"
    local usage="$3"
    shift 3
    local options=("$@")

    echo -e "${PURPLE}${script_name}${NC} - ${description}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $usage"
    echo ""

    if [[ ${#options[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Options:${NC}"
        for option in "${options[@]}"; do
            echo "  $option"
        done
        echo ""
    fi
}

#######################################
# Validate file exists
# Arguments:
#   File path
# Returns:
#   0 if exists, 1 if not (with error message)
#######################################
validate_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    return 0
}

#######################################
# Validate directory exists
# Arguments:
#   Directory path
# Returns:
#   0 if exists, 1 if not (with error message)
#######################################
validate_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_error "Directory not found: $dir"
        return 1
    fi
    return 0
}
