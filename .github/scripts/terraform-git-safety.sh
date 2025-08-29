#!/bin/bash

# Terraform Git Safety Script
# Ensures .terraform directory and sensitive files are never committed

set -e

SCRIPT_NAME="terraform-git-safety.sh"

echo "[$SCRIPT_NAME] Ensuring .terraform files are never committed..."

# Function to check and remove .terraform files from git staging area
cleanup_terraform_files() {
    local working_dir="$1"
    
    if [ -n "$working_dir" ]; then
        cd "$working_dir"
    fi
    
    echo "Checking current directory: $(pwd)"
    
    # Remove .terraform directory from git cache if it exists
    if git ls-files --cached | grep -q "\.terraform"; then
        echo "⚠️ WARNING: Found .terraform files in git cache - removing them"
        git rm --cached -r .terraform 2>/dev/null || true
        echo "✅ Removed .terraform directory from git cache"
    fi
    
    # Remove .terraform.lock.hcl from git cache if it exists  
    if git ls-files --cached | grep -q "\.terraform\.lock\.hcl"; then
        echo "⚠️ WARNING: Found .terraform.lock.hcl in git cache - removing it"
        git rm --cached .terraform.lock.hcl 2>/dev/null || true
        echo "✅ Removed .terraform.lock.hcl from git cache"
    fi
    
    # Check for any other potentially sensitive Terraform files
    SENSITIVE_PATTERNS=(
        "terraform\.tfstate$"
        "terraform\.tfstate\.backup$" 
        "\.tfvars\.backup$"
        "crash\.log$"
        "crash\..*\.log$"
    )
    
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        if git ls-files --cached | grep -E "$pattern"; then
            echo "⚠️ WARNING: Found potentially sensitive files matching pattern: $pattern"
            git ls-files --cached | grep -E "$pattern" | while read -r file; do
                echo "  Checking: $file"
                # Only remove if not encrypted (.gpg files are OK)
                if [[ ! "$file" =~ \.gpg$ ]]; then
                    echo "  ⚠️ Removing unencrypted sensitive file: $file"
                    git rm --cached "$file" 2>/dev/null || true
                fi
            done
        fi
    done
    
    # Show final status
    echo ""
    echo "=== Git Status After Cleanup ==="
    git status --porcelain | head -10 || echo "No staged changes"
    
    # Check if any .terraform files are still staged
    if git diff --cached --name-only | grep -E "\\.terraform|terraform\\.lock"; then
        echo "❌ ERROR: .terraform files are still staged!"
        echo "Staged .terraform files:"
        git diff --cached --name-only | grep -E "\\.terraform|terraform\\.lock"
        return 1
    else
        echo "✅ No .terraform files are staged for commit"
    fi
}

# Function to verify .gitignore has proper entries
verify_gitignore() {
    local gitignore_file=".gitignore"
    
    if [ ! -f "$gitignore_file" ]; then
        echo "⚠️ WARNING: No .gitignore file found"
        return 1
    fi
    
    # Check for essential Terraform ignore patterns
    REQUIRED_PATTERNS=(
        "\\.terraform/"
        "\\.terraform\\.lock\\.hcl"
        "\\*\\.tfstate"
        "\\*\\.tfstate\\.\\*"
    )
    
    local missing_patterns=()
    
    for pattern in "${REQUIRED_PATTERNS[@]}"; do
        if ! grep -q "$pattern" "$gitignore_file"; then
            missing_patterns+=("$pattern")
        fi
    done
    
    if [ ${#missing_patterns[@]} -gt 0 ]; then
        echo "⚠️ WARNING: Missing .gitignore patterns:"
        printf '  - %s\n' "${missing_patterns[@]}"
        return 1
    else
        echo "✅ .gitignore has proper Terraform exclusions"
    fi
}

# Function to show current repository state
show_repo_state() {
    echo ""
    echo "=== Repository State Summary ==="
    
    # Show .terraform directories
    echo "Terraform directories found:"
    find . -name ".terraform" -type d 2>/dev/null | head -5 | sed 's/^/  /' || echo "  None found"
    
    # Show .terraform.lock.hcl files
    echo "Terraform lock files found:"
    find . -name ".terraform.lock.hcl" 2>/dev/null | head -5 | sed 's/^/  /' || echo "  None found"
    
    # Show staged files count
    local staged_count=$(git diff --cached --name-only | wc -l)
    echo "Files currently staged for commit: $staged_count"
    
    if [ "$staged_count" -gt 0 ] && [ "$staged_count" -lt 20 ]; then
        echo "Staged files:"
        git diff --cached --name-only | sed 's/^/  /'
    fi
}

# Main execution
main() {
    local working_dir="${1:-}"
    
    echo "[$SCRIPT_NAME] Starting Terraform Git Safety Check"
    echo "Working directory: ${working_dir:-$(pwd)}"
    
    # Step 1: Clean up any .terraform files from git cache
    cleanup_terraform_files "$working_dir"
    
    # Step 2: Verify .gitignore is properly configured  
    verify_gitignore
    
    # Step 3: Show current repository state
    show_repo_state
    
    echo ""
    echo "[$SCRIPT_NAME] Terraform Git Safety Check Complete"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [working_directory]"
        echo ""
        echo "Ensures .terraform directory and sensitive files are never committed to git"
        echo ""
        echo "Options:"
        echo "  working_directory  Optional directory to check (defaults to current directory)"
        echo "  --help, -h        Show this help message"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
