#!/bin/bash

# GPG Encryption Script for Terraform State Files
# This script encrypts Terraform state files for secure storage

set -e

SCRIPT_NAME="encrypt-state.sh"

echo "[$SCRIPT_NAME] Encrypting Terraform state files..."

# Function to display usage
usage() {
    echo "Usage: $0 --backend-type <local|remote> --passphrase <passphrase> [--operation <apply|destroy>]"
    echo ""
    echo "Options:"
    echo "  --backend-type    Backend type (local or remote)"
    echo "  --passphrase      GPG passphrase for encryption"
    echo "  --operation       Operation type (apply or destroy) - affects file handling"
    echo "  --destroy-success Whether destroy operation was successful (true/false)"
    echo "  --help           Show this help message"
    exit 1
}

# Parse command line arguments
BACKEND_TYPE=""
GPG_PASSPHRASE=""
OPERATION="apply"
DESTROY_SUCCESS="false"

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
        --operation)
            OPERATION="$2"
            shift 2
            ;;
        --destroy-success)
            DESTROY_SUCCESS="$2"
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
    echo "ERROR: --backend-type is required"
    usage
fi

# Skip encryption for remote backend
if [ "$BACKEND_TYPE" != "local" ]; then
    echo "Remote backend - no state file encryption needed"
    echo "Encryption skipped (not needed for remote backend)"
    exit 0
fi

echo "Local backend detected - checking for state files to encrypt..."

# Validate passphrase for local backend
if [ -z "$GPG_PASSPHRASE" ]; then
    echo "ERROR: GPG passphrase is required for local backend encryption"
    exit 1
fi

# Handle destroy operation logic
if [ "$OPERATION" = "destroy" ]; then
    if [ "$DESTROY_SUCCESS" = "true" ]; then
        echo "Successful destroy operation - removing all state files"
        rm -f terraform.tfstate* *.gpg tf-plan*
        echo "All state files cleaned up after successful destruction"
        exit 0
    else
        echo "Destroy operation not fully successful - encrypting remaining state files"
    fi
fi

# Files to encrypt
STATE_FILES=("terraform.tfstate" "terraform.tfstate.backup")
PLAN_FILES=("tf-plan")
ENCRYPTED_COUNT=0

# Add plan files only for apply operations
if [ "$OPERATION" = "apply" ]; then
    FILES_TO_ENCRYPT=("${STATE_FILES[@]}" "${PLAN_FILES[@]}")
else
    FILES_TO_ENCRYPT=("${STATE_FILES[@]}")
fi

echo "Looking for state files to encrypt..."

# Encrypt each file if it exists
for file in "${FILES_TO_ENCRYPT[@]}"; do
    if [ -f "$file" ]; then
        encrypted_file="${file}.gpg"
        echo "Encrypting $file to $encrypted_file..."
        
        # Encrypt the file using AES256 with compression
        if echo "$GPG_PASSPHRASE" | gpg --batch --yes --quiet --passphrase-fd 0 --cipher-algo AES256 --compress-algo 1 --symmetric --output "$encrypted_file" "$file"; then
            echo "Successfully encrypted $file"
            
            # Verify encrypted file was created and is not empty
            if [ -s "$encrypted_file" ]; then
                echo "   Encrypted file size: $(wc -c < "$encrypted_file") bytes"
                # Remove original unencrypted file for security
                rm -f "$file"
                echo "   Original unencrypted file removed"
                ENCRYPTED_COUNT=$((ENCRYPTED_COUNT + 1))
            else
                echo "ERROR: Encrypted file is empty or was not created"
                exit 1
            fi
        else
            echo "Failed to encrypt $file"
            exit 1
        fi
    fi
done

if [ $ENCRYPTED_COUNT -eq 0 ]; then
    echo "No state files found to encrypt"
    if [ "$OPERATION" = "destroy" ]; then
        echo "No encryption needed (no remaining state files)"
    else
        echo "This may be normal for remote backends or when no state changes occurred"
    fi
else
    echo "[$SCRIPT_NAME] Successfully encrypted $ENCRYPTED_COUNT file(s)"
    echo "Only encrypted .gpg files will be committed to repository"
fi
