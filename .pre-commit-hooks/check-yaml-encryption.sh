#!/bin/bash
# .pre-commit-hooks/check-yaml-encryption.sh
# Pre-commit hook to check YAML encryption based on .gitattributes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize counters
ENCRYPTED_COUNT=0
UNENCRYPTED_COUNT=0
TOTAL_FILES=0
UNENCRYPTED_FILES=()

echo -e "${BLUE}🔍 Checking YAML encryption based on .gitattributes...${NC}"

# Function to check if a file should be encrypted based on .gitattributes
should_be_encrypted() {
    local file="$1"
    local gitattributes_file=".gitattributes"
    
    # Check if .gitattributes exists
    if [ ! -f "$gitattributes_file" ]; then
        echo -e "${YELLOW}⚠️  .gitattributes file not found${NC}"
        return 1
    fi
    
    # Parse .gitattributes to find encryption rules
    # Look for patterns like: *.yaml filter=encryption, secret/** filter=git-crypt, etc.
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Extract pattern and attributes
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
            pattern="${BASH_REMATCH[1]}"
            attributes="${BASH_REMATCH[2]}"
            
            # Check if this line indicates encryption
            if [[ "$attributes" =~ (filter=|git-crypt|sops|ansible-vault|encrypt) ]]; then
                # Convert gitattributes pattern to shell pattern
                shell_pattern=$(echo "$pattern" | sed 's/\*\*/\*/g')
                
                # Check if the file matches this pattern
                if [[ "$file" == $shell_pattern ]]; then
                    echo "   📋 Matched .gitattributes pattern: $pattern -> $attributes"
                    return 0
                fi
                
                # Handle directory patterns
                if [[ "$pattern" =~ /\*\*$ ]]; then
                    dir_pattern="${pattern%/**}"
                    if [[ "$file" == "$dir_pattern"/* ]]; then
                        echo "   📋 Matched .gitattributes directory pattern: $pattern -> $attributes"
                        return 0
                    fi
                fi
            fi
        fi
    done < "$gitattributes_file"
    
    return 1
}

# Function to check if file is encrypted
check_encryption() {
    local file="$1"
    
    # Get file type using file command
    FILE_TYPE=$(file -b "$file" 2>/dev/null || echo "unknown")
    echo "   File type: $FILE_TYPE"
    
    # Check if file is encrypted using multiple methods
    IS_ENCRYPTED=false
    
    # Method 1: Check file type for binary/encrypted indicators
    if echo "$FILE_TYPE" | grep -qi "data\|encrypted\|binary\|gzip\|compressed"; then
        echo -e "   ${GREEN}✅ Detected as encrypted by file type: $FILE_TYPE${NC}"
        IS_ENCRYPTED=true
    fi
    
    # Method 2: Check for specific encryption markers
    if [ "$IS_ENCRYPTED" = false ]; then
        if grep -q "^\$ANSIBLE_VAULT" "$file" 2>/dev/null; then
            echo -e "   ${GREEN}✅ Ansible Vault encryption detected${NC}"
            IS_ENCRYPTED=true
        elif grep -q "^ansible-vault" "$file" 2>/dev/null; then
            echo -e "   ${GREEN}✅ Ansible Vault encryption detected (alternative format)${NC}"
            IS_ENCRYPTED=true
        elif grep -q "sops:" "$file" 2>/dev/null; then
            echo -e "   ${GREEN}✅ SOPS encryption detected${NC}"
            IS_ENCRYPTED=true
        elif grep -q "age:" "$file" 2>/dev/null; then
            echo -e "   ${GREEN}✅ AGE encryption detected${NC}"
            IS_ENCRYPTED=true
        elif grep -q "pgp:" "$file" 2>/dev/null; then
            echo -e "   ${GREEN}✅ PGP encryption detected${NC}"
            IS_ENCRYPTED=true
        elif grep -q "BEGIN PGP MESSAGE\|BEGIN ENCRYPTED MESSAGE" "$file" 2>/dev/null; then
            echo -e "   ${GREEN}✅ PGP/Encrypted message format detected${NC}"
            IS_ENCRYPTED=true
        elif grep -q "-----BEGIN PGP MESSAGE-----" "$file" 2>/dev/null; then
            echo -e "   ${GREEN}✅ PGP message block detected${NC}"
            IS_ENCRYPTED=true
        elif grep -q "ENC\[" "$file" 2>/dev/null; then
            echo -e "   ${GREEN}✅ ENC[] encryption marker detected${NC}"
            IS_ENCRYPTED=true
        elif head -c 10 "$file" 2>/dev/null | grep -q "^.GITCRYPT" 2>/dev/null; then
            echo -e "   ${GREEN}✅ Git-crypt encryption detected${NC}"
            IS_ENCRYPTED=true
        fi
    fi
    
    # Method 3: Check if file contains mostly non-printable characters (likely encrypted)
    if [ "$IS_ENCRYPTED" = false ]; then
        # Sample first 1000 characters and check if they're mostly printable
        SAMPLE=$(head -c 1000 "$file" 2>/dev/null || true)
        if [ -n "$SAMPLE" ]; then
            # Count printable vs non-printable characters
            PRINTABLE_COUNT=$(echo -n "$SAMPLE" | tr -cd '[:print:][:space:]' | wc -c)
            TOTAL_COUNT=$(echo -n "$SAMPLE" | wc -c)
            
            if [ "$TOTAL_COUNT" -gt 0 ]; then
                PRINTABLE_RATIO=$((PRINTABLE_COUNT * 100 / TOTAL_COUNT))
                echo "   Printable character ratio: ${PRINTABLE_RATIO}%"
                
                # If less than 80% of characters are printable, likely encrypted
                if [ "$PRINTABLE_RATIO" -lt 80 ]; then
                    echo -e "   ${GREEN}✅ Detected as encrypted (low printable character ratio)${NC}"
                    IS_ENCRYPTED=true
                fi
            fi
        fi
    fi
    
    echo "$IS_ENCRYPTED"
}

# Process each file passed by pre-commit
for file in "$@"; do
    # Only process YAML files
    if [[ ! "$file" =~ \.(yaml|yml)$ ]]; then
        continue
    fi
    
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        echo -e "${YELLOW}⚠️  Skipping unreadable file: $file${NC}"
        continue
    fi
    
    echo -e "\n${BLUE}📄 Checking: $file${NC}"
    
    # Check if this file should be encrypted according to .gitattributes
    if should_be_encrypted "$file"; then
        TOTAL_FILES=$((TOTAL_FILES + 1))
        
        # Check if file is actually encrypted
        IS_ENCRYPTED=$(check_encryption "$file")
        
        # Final determination
        if [ "$IS_ENCRYPTED" = true ]; then
            echo -e "${GREEN}✅ RESULT: $file is ENCRYPTED${NC}"
            ENCRYPTED_COUNT=$((ENCRYPTED_COUNT + 1))
        else
            echo -e "${RED}❌ RESULT: $file is NOT ENCRYPTED${NC}"
            UNENCRYPTED_COUNT=$((UNENCRYPTED_COUNT + 1))
            UNENCRYPTED_FILES+=("$file")
        fi
    else
        echo -e "${YELLOW}ℹ️  File not marked for encryption in .gitattributes${NC}"
    fi
done

# Print summary
echo -e "\n${BLUE}=== YAML Encryption Check Results ===${NC}"
echo "Files processed: $TOTAL_FILES"
echo -e "Encrypted: ${GREEN}$ENCRYPTED_COUNT${NC}"
echo -e "Unencrypted: ${RED}$UNENCRYPTED_COUNT${NC}"

# Exit with error if unencrypted files found
if [ $UNENCRYPTED_COUNT -gt 0 ]; then
    echo -e "\n${RED}❌ COMMIT BLOCKED: Found unencrypted files that should be encrypted${NC}"
    echo -e "${YELLOW}The following files need to be encrypted according to .gitattributes:${NC}"
    for file in "${UNENCRYPTED_FILES[@]}"; do
        echo -e "  - ${RED}$file${NC}"
    done
    echo -e "\n${YELLOW}How to fix:${NC}"
    echo "1. Encrypt the files using your preferred method:"
    echo "   - Ansible Vault: ansible-vault encrypt <file>"
    echo "   - SOPS: sops -e <file>"
    echo "   - Git-crypt: git-crypt add <file>"
    echo "   - GPG: gpg -c <file>"
    echo "2. Commit the encrypted files"
    echo "3. Or use --no-verify to skip this check (NOT RECOMMENDED)"
    echo "4. Or update .gitattributes if the file shouldn't be encrypted"
    exit 1
elif [ $TOTAL_FILES -eq 0 ]; then
    echo -e "${YELLOW}ℹ️  No YAML files marked for encryption in .gitattributes${NC}"
    exit 0
else
    echo -e "\n${GREEN}✅ All files marked for encryption are properly encrypted!${NC}"
    exit 0
fi