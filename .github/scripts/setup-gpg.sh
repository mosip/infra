#!/bin/bash

# GPG Setup and Key Generation Script for Terraform State Encryption
# This script sets up GPG and generates encryption keys for local backend usage

set -e

SCRIPT_NAME="setup-gpg.sh"
GPG_EMAIL="terraform-state@mosip.local"
GPG_NAME="MOSIP Terraform State"

echo "🔑 [$SCRIPT_NAME] Setting up GPG for Terraform state file encryption..."

# Function to display usage
usage() {
    echo "Usage: $0 --backend-type <local|remote> --passphrase <passphrase>"
    echo ""
    echo "Options:"
    echo "  --backend-type    Backend type (local or remote)"
    echo "  --passphrase      GPG passphrase for encryption"
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

# Skip GPG setup for remote backend
if [ "$BACKEND_TYPE" != "local" ]; then
    echo "📡 Remote backend detected - skipping GPG setup"
    echo "✅ GPG setup skipped (not needed for remote backend)"
    exit 0
fi

echo "💾 Local backend detected - setting up GPG encryption"

# Validate passphrase for local backend
if [ -z "$GPG_PASSPHRASE" ]; then
    echo "❌ ERROR: GPG passphrase is required for local backend"
    echo "Please ensure GPG_PASSPHRASE secret is set in your repository"
    echo "Go to: Settings > Secrets and variables > Actions > New repository secret"
    exit 1
fi

# Validate passphrase is not just whitespace
if [[ "$GPG_PASSPHRASE" =~ ^[[:space:]]*$ ]]; then
    echo "❌ ERROR: GPG passphrase cannot be empty or contain only whitespace"
    exit 1
fi

echo "📦 Installing GPG if not present..."
sudo apt-get update -qq
sudo apt-get install -y gnupg2

echo "🔍 Checking for existing GPG key..."
# Generate GPG key if it doesn't exist
if gpg --list-keys "$GPG_EMAIL" >/dev/null 2>&1; then
    echo "✅ GPG key already exists for $GPG_EMAIL"
else
    echo "🔨 Generating new GPG key for Terraform state encryption..."
    
    # Create GPG batch file with proper passphrase handling
    cat > /tmp/gpg-batch << 'EOFBATCH'
%echo Generating GPG key for Terraform state encryption
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: MOSIP Terraform State
Name-Email: terraform-state@mosip.local
Expire-Date: 0
%commit
%echo GPG key generation complete
EOFBATCH
    
    # Add the passphrase to the batch file
    sed -i "/Name-Email:/a Passphrase: $GPG_PASSPHRASE" /tmp/gpg-batch
    
    # Verify the batch file was created correctly
    if [ ! -f /tmp/gpg-batch ]; then
        echo "❌ ERROR: Failed to create GPG batch file"
        exit 1
    fi
    
    # Check if passphrase line exists and is not empty
    if ! grep -q "^Passphrase: ." /tmp/gpg-batch; then
        echo "❌ ERROR: GPG passphrase is empty or invalid in batch file"
        echo "Please ensure GPG_PASSPHRASE contains a valid passphrase"
        rm -f /tmp/gpg-batch
        exit 1
    fi
    
    echo "🎯 Generating GPG key with batch file..."
    if gpg --batch --generate-key /tmp/gpg-batch; then
        echo "✅ GPG key generated successfully"
    else
        echo "❌ ERROR: GPG key generation failed"
        rm -f /tmp/gpg-batch
        exit 1
    fi
    
    # Cleanup
    rm -f /tmp/gpg-batch
fi

echo "✅ [$SCRIPT_NAME] GPG setup complete for state file encryption"
