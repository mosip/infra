#!/usr/bin/env bash
#
# Production-Ready PostgreSQL Secrets Generator for MOSIP (Shell Version)
# Usage:
#   DB_PASSWORD=... POSTGRES_PASSWORD=... ./generate-pg-secrets.sh <output_dir> <environment> [--apply]
#
# Example:
#   DB_PASSWORD='StrongDBPass123!' POSTGRES_PASSWORD='SuperPostgresPass456!' \
#   ./generate-pg-secrets.sh /tmp/mosip-secrets production --apply
#

set -euo pipefail

# --- Input Args ---
OUTPUT_DIR="${1:-/tmp/mosip-secrets}"
ENVIRONMENT="${2:-development}"
APPLY="${3:-}"

# --- Configuration ---
NAMESPACE="postgres"
DB_SECRET_NAME="db-common-secrets"
PG_SECRET_NAME="postgres-postgresql"

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}MOSIP PostgreSQL Secrets Generator (Shell Version)${NC}"
echo -e "Environment: ${ENVIRONMENT}"
echo -e "Output Directory: ${OUTPUT_DIR}"

# --- Read secrets from environment variables ---
DB_PASSWORD="${DB_PASSWORD:-}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

# Debug: Check if environment variables are set
if [ -z "$DB_PASSWORD" ]; then
  echo "DEBUG: DB_PASSWORD is not set or empty."
else
  echo "DEBUG: DB_PASSWORD is set."
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "DEBUG: POSTGRES_PASSWORD is not set or empty."
else
  echo "DEBUG: POSTGRES_PASSWORD is set."
fi

# --- Early Kubernetes cluster validation (only if --apply is requested) ---
if [[ "$APPLY" == "--apply" ]]; then
  if command -v kubectl >/dev/null 2>&1; then
    echo -e "${BLUE}Validating Kubernetes cluster access...${NC}"
    if kubectl cluster-info; then
      echo -e "${GREEN}Kubernetes cluster is accessible${NC}"
      
      # Show current context for confirmation
      current_context=$(kubectl config current-context 2>/dev/null || echo "unknown")
      echo -e "${BLUE}Current kubectl context: ${current_context}${NC}"
    else
      echo -e "${RED}ERROR: Unable to access Kubernetes cluster. Check your kubeconfig.${NC}"
      exit 1
    fi
  else
    echo -e "${RED}ERROR: kubectl not found but --apply requested. Please install kubectl.${NC}"
    exit 1
  fi
fi

# --- Validate secrets ---
if [[ -z "$DB_PASSWORD" || -z "$POSTGRES_PASSWORD" ]]; then
  echo -e "${RED}ERROR: Environment variables DB_PASSWORD and POSTGRES_PASSWORD must be set.${NC}"
  echo "Usage example:"
  echo "  DB_PASSWORD='mypassword' POSTGRES_PASSWORD='mypassword' $0 ./secrets production [--apply]"
  echo ""
  echo "For production deployment, set:"
  echo "  export DB_PASSWORD='your-secure-password'"
  echo "  export POSTGRES_PASSWORD='your-postgres-password'" 
  echo "  export ENVIRONMENT='production'"
  exit 1
fi

# --- Password validation ---
validate_password() {
  local password=$1
  local var_name=$2

  if [[ ${#password} -lt 16 ]]; then
    echo -e "${RED}ERROR: $var_name must be at least 16 characters${NC}"
    exit 1
  fi

  echo -e "${GREEN}$var_name meets requirements${NC}"
}

echo -e "${BLUE}Using passwords from environment variables${NC}"

# --- Validate password strength ---
echo -e "${BLUE}Validating passwords for ${ENVIRONMENT} environment...${NC}"
validate_password "$DB_PASSWORD" "DB_PASSWORD"
validate_password "$POSTGRES_PASSWORD" "POSTGRES_PASSWORD"

# --- Ensure output directory exists ---
mkdir -p "$OUTPUT_DIR"

# --- Create Kubernetes Secret YAML ---
create_secret_yaml() {
  local secret_name=$1
  local namespace=$2
  local key=$3
  local value=$4
  local output_file=$5

  local encoded_value
  encoded_value=$(echo -n "$value" | base64 -w 0)

  cat > "$output_file" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $secret_name
  namespace: $namespace
type: Opaque
data:
  $key: $encoded_value
EOF

  chmod 600 "$output_file"
  echo -e "${GREEN}Created $output_file${NC}"
}

# --- Create secrets ---
DB_SECRET_FILE="$OUTPUT_DIR/db-common-secrets.yaml"
PG_SECRET_FILE="$OUTPUT_DIR/postgres-postgresql.yaml"

echo -e "${BLUE}Generating secret YAML files...${NC}"

create_secret_yaml "$DB_SECRET_NAME" "$NAMESPACE" "db-dbuser-password" "$DB_PASSWORD" "$DB_SECRET_FILE"
create_secret_yaml "$PG_SECRET_NAME" "$NAMESPACE" "postgres-password" "$POSTGRES_PASSWORD" "$PG_SECRET_FILE"

echo -e "${GREEN}All PostgreSQL secrets generated successfully!${NC}"
echo -e "${BLUE}Secrets saved to: ${OUTPUT_DIR}${NC}"

# --- Apply secrets if requested ---
if [[ "$APPLY" == "--apply" ]]; then
  echo -e "${BLUE}Applying secrets to Kubernetes...${NC}"
  
  # Create namespace if it doesn't exist
  echo -e "${BLUE}Creating namespace ${NAMESPACE} if it doesn't exist...${NC}"
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  echo -e "${GREEN}Namespace ${NAMESPACE} ready${NC}"
  
  # Apply secrets
  kubectl apply -f "$DB_SECRET_FILE"
  kubectl apply -f "$PG_SECRET_FILE"
  
  echo -e "${GREEN}Secrets applied successfully to cluster${NC}"
  
  # Verify secrets
  echo -e "${BLUE}Verifying secrets...${NC}"
  kubectl get secrets -n "$NAMESPACE" "$DB_SECRET_NAME" "$PG_SECRET_NAME"
  echo -e "${GREEN}Secret verification complete${NC}"
fi

# --- Cleanup sensitive files if applied ---
if [[ "$APPLY" == "--apply" ]]; then
  echo -e "${YELLOW}Cleaning up secret files for security...${NC}"
  rm -f "$DB_SECRET_FILE" "$PG_SECRET_FILE"
  echo -e "${GREEN}Cleanup complete${NC}"
fi
