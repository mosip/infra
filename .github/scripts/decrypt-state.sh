#!/bin/bash

# GPG Decryption Script for Terraform State Files
# This script decrypts existing encrypted state files before Terraform operations

set -e

SCRIPT_NAME="decrypt-state.sh"

echo "🔓 [$SCRIPT_NAME] Decrypting Terraform state files..."

# Function to display usage
usage() {
    echo "Usage: $0 --backend-type <local|remote> --passphrase <passphrase>"
    echo ""
    echo "Options:"
    echo "  --backend-type    Backend type (local or remote)"
    echo "  --passphrase      GPG passphrase for decryption"
    echo "  --help           Show this help message"
    exit 1
}

# Parse command line arguments
BACKEND_TYPE=""
GPG_PASSPHRASE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --backend-type)
            BACKEND_TYPE="$2"
            shift 2
            ;;
        --passphrase)
            GPG_PASSPHRASE="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$BACKEND_TYPE" ]; then
    echo "❌ ERROR: --backend-type is required"
    usage
fi

# Skip decryption for remote backend
if [ "$BACKEND_TYPE" != "local" ]; then
    echo "📡 Remote backend - no state file decryption needed"
    echo "✅ Decryption skipped (not needed for remote backend)"
    exit 0
fi

echo "💾 Local backend detected - checking for encrypted state files..."

# Validate passphrase for local backend
if [ -z "$GPG_PASSPHRASE" ]; then
    echo "❌ ERROR: GPG passphrase is required for local backend decryption"
    exit 1
fi

# Files to decrypt
ENCRYPTED_FILES=("terraform.tfstate.gpg" "terraform.tfstate.backup.gpg" "tf-plan.gpg")
DECRYPTED_COUNT=0

echo "🔍 Looking for encrypted state files to decrypt..."

# Look for encrypted state files
for encrypted_file in "${ENCRYPTED_FILES[@]}"; do
    if [ -f "$encrypted_file" ]; then
        decrypted_file="${encrypted_file%.gpg}"
        echo "🔓 Decrypting $encrypted_file to $decrypted_file..."
        
        # Decrypt the file
        if echo "$GPG_PASSPHRASE" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt "$encrypted_file" > "$decrypted_file"; then
            echo "✅ Successfully decrypted $encrypted_file"
            
            # Verify the decrypted file is valid
            if [ "$decrypted_file" = "terraform.tfstate" ] && [ -s "$decrypted_file" ]; then
                echo "   📋 Terraform state file decrypted and ready for operations"
                
                # Verify JSON structure for state files
                if [[ "$decrypted_file" == *.tfstate ]]; then
                    if python3 -c "import json; json.load(open('$decrypted_file'))" 2>/dev/null; then
                        echo "   ✅ JSON structure is valid"
                    else
                        echo "   ⚠️  Warning: JSON structure may be invalid"
                    fi
                fi
            fi
            
            DECRYPTED_COUNT=$((DECRYPTED_COUNT + 1))
        else
            echo "❌ Failed to decrypt $encrypted_file"
            echo "Please check that the correct GPG_PASSPHRASE is being used"
            exit 1
        fi
    fi
done

if [ $DECRYPTED_COUNT -eq 0 ]; then
    echo "📂 No encrypted state files found - this may be the first run"
    echo "✅ No decryption needed"
else
    echo "✅ [$SCRIPT_NAME] Successfully decrypted $DECRYPTED_COUNT state file(s)"
fi
