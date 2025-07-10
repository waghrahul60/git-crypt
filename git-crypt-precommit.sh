#!/bin/bash

# Git Crypt Pre-commit Hook
# This script validates that files marked for encryption in .gitattributes
# are actually encrypted before commit

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Function to check if a file is encrypted
# Returns 0 if encrypted (file type is 'data'), 1 if not encrypted
is_file_encrypted() {
    local file_path="$1"
    
    # Check if file exists
    if [[ ! -f "$file_path" ]]; then
        return 1
    fi
    
    # Get file type using the 'file' command
    local file_type=$(file -b "$file_path" 2>/dev/null)
    
    # Check if file type contains 'data' (indicating binary/encrypted content)
    if [[ "$file_type" == *"data"* ]]; then
        return 0  # File is encrypted
    else
        return 1  # File is not encrypted (likely ASCII/text)
    fi
}

# Function to get files that should be encrypted according to .gitattributes
get_encrypted_files_pattern() {
    local gitattributes_file=".gitattributes"
    
    if [[ ! -f "$gitattributes_file" ]]; then
        print_warning "No .gitattributes file found"
        return 1
    fi
    
    # Extract file patterns that have filter=git-crypt or crypt attributes
    grep -E "(filter=git-crypt|git-crypt)" "$gitattributes_file" 2>/dev/null | \
    grep -v "^#" | \
    awk '{print $1}' | \
    grep -v "^$"
}

# Function to check if a file matches any of the encrypted patterns
should_be_encrypted() {
    local file_path="$1"
    local patterns="$2"
    
    while IFS= read -r pattern; do
        # Remove leading/trailing whitespace
        pattern=$(echo "$pattern" | xargs)
        
        # Skip empty patterns
        [[ -z "$pattern" ]] && continue
        
        # Convert gitattributes pattern to shell pattern
        # Handle simple glob patterns
        if [[ "$file_path" == $pattern ]]; then
            return 0
        fi
        
        # Handle directory patterns
        if [[ "$pattern" == *"/"* ]]; then
            if [[ "$file_path" == $pattern ]]; then
                return 0
            fi
        fi
        
        # Handle wildcard patterns
        if [[ "$pattern" == *"*"* ]]; then
            if [[ "$file_path" == $pattern ]]; then
                return 0
            fi
        fi
        
    done <<< "$patterns"
    
    return 1
}

# Main validation function
validate_encryption() {
    local exit_code=0
    local checked_files=0
    local encrypted_files=0
    local unencrypted_files=0
    
    # Get patterns from .gitattributes
    local patterns=$(get_encrypted_files_pattern)
    
    if [[ -z "$patterns" ]]; then
        print_warning "No git-crypt patterns found in .gitattributes"
        return 0
    fi
    
    echo "Checking file encryption status..."
    echo "Patterns from .gitattributes:"
    echo "$patterns"
    echo ""
    
    # Get staged files for commit
    local staged_files=$(git diff --cached --name-only --diff-filter=ACM)
    
    if [[ -z "$staged_files" ]]; then
        print_warning "No staged files found"
        return 0
    fi
    
    # Check each staged file
    while IFS= read -r file; do
        # Skip if file doesn't exist (might be deleted)
        [[ ! -f "$file" ]] && continue
        
        # Check if this file should be encrypted
        if should_be_encrypted "$file" "$patterns"; then
            ((checked_files++))
            
            if is_file_encrypted "$file"; then
                print_success "File '$file' is properly encrypted"
                ((encrypted_files++))
            else
                print_error "File '$file' should be encrypted but appears to be plain text"
                echo "  File type: $(file -b "$file")"
                ((unencrypted_files++))
                exit_code=1
            fi
        fi
    done <<< "$staged_files"
    
    echo ""
    echo "Encryption check summary:"
    echo "  Files checked: $checked_files"
    echo "  Properly encrypted: $encrypted_files"
    echo "  Unencrypted (violations): $unencrypted_files"
    
    if [[ $exit_code -eq 0 ]]; then
        if [[ $checked_files -eq 0 ]]; then
            echo "No files requiring encryption found in this commit."
        else
            print_success "All files requiring encryption are properly encrypted!"
        fi
    else
        echo ""
        print_error "Commit blocked: Some files that should be encrypted are not encrypted."
        echo "Please run 'git crypt lock' and 'git crypt unlock' to ensure proper encryption."
        echo "Or check your .gitattributes configuration."
    fi
    
    return $exit_code
}

# Function to install this script as a pre-commit hook
install_hook() {
    local hook_path=".git/hooks/pre-commit"
    local script_path="$(realpath "$0")"
    
    # Create hooks directory if it doesn't exist
    mkdir -p ".git/hooks"
    
    # Create the pre-commit hook
    cat > "$hook_path" << EOF
#!/bin/bash
# Git Crypt Pre-commit Hook
# Auto-generated hook that calls the validation script

# Call the validation script
"$script_path" validate

# Exit with the same code as the validation script
exit \$?
EOF
    
    # Make the hook executable
    chmod +x "$hook_path"
    
    print_success "Pre-commit hook installed successfully at $hook_path"
}

# Main script logic
case "${1:-validate}" in
    "validate")
        validate_encryption
        ;;
    "install")
        install_hook
        ;;
    "help"|"-h"|"--help")
        echo "Git Crypt Pre-commit Hook Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  validate    Validate encryption status of staged files (default)"
        echo "  install     Install this script as a pre-commit hook"
        echo "  help        Show this help message"
        echo ""
        echo "This script checks if files marked for encryption in .gitattributes"
        echo "are actually encrypted before allowing a commit."
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac