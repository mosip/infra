#!/bin/bash
# Script to cleanup partner onboarder data from mosip_pms and mosip_esignet databases
# This script deletes data for default esignet, demo-oidc, and resident-oidc partners
## Usage: ./cleanup-partner-data.sh [--dry-run] [--host DB_HOST] [--port DB_PORT] [--user DB_USER]

set -e

# Default values
DRY_RUN=false
DB_HOST="${DB_HOST:-postgres}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --host)
      DB_HOST="$2"
      shift 2
      ;;
    --port)
      DB_PORT="$2"
      shift 2
      ;;
    --user)
      DB_USER="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Function to execute SQL
execute_sql() {
  local database=$1
  local sql=$2
  local description=$3
  
  if [ "$DRY_RUN" == "true" ]; then
    echo "[DRY-RUN] $description"
    echo "  SQL: $sql"
    # Show count that would be deleted - convert DELETE to SELECT COUNT(*)
    local count_sql="${sql/DELETE/SELECT COUNT(*)}"
    local count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$database" -t -c "$count_sql" 2>/dev/null | xargs || echo "0")
    echo "  Records to delete: $count"
  else
    echo "Executing: $description"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$database" -c "$sql"
  fi
}

echo "=============================================="
echo "Partner Data Cleanup Script"
echo "=============================================="
echo "Database Host: $DB_HOST"
echo "Database Port: $DB_PORT"
echo "Database User: $DB_USER"
echo "Dry Run: $DRY_RUN"
echo "=============================================="

if [ -z "$DB_PASSWORD" ]; then
  echo "ERROR: DB_PASSWORD environment variable not set"
  echo "Usage: DB_PASSWORD=yourpassword $0 [--dry-run]"
  exit 1
fi

echo ""
echo "Cleaning up mosip_pms database..."
echo "----------------------------------------------"

# auth_policy table
execute_sql "mosip_pms" \
  "DELETE FROM auth_policy WHERE name LIKE '%mpolicy-default-esignet%';" \
  "Delete auth_policy for esignet"

execute_sql "mosip_pms" \
  "DELETE FROM auth_policy WHERE name LIKE '%mpolicy-default-demo-oidc%';" \
  "Delete auth_policy for demo-oidc"

execute_sql "mosip_pms" \
  "DELETE FROM auth_policy WHERE name LIKE '%mpolicy-default-resident-oidc%';" \
  "Delete auth_policy for resident-oidc"

# policy_group table
execute_sql "mosip_pms" \
  "DELETE FROM policy_group WHERE name LIKE '%mpolicygroup-default-esignet%';" \
  "Delete policy_group for esignet"

execute_sql "mosip_pms" \
  "DELETE FROM policy_group WHERE name LIKE '%mpolicygroup-default-resident-oidc%';" \
  "Delete policy_group for resident-oidc"

execute_sql "mosip_pms" \
  "DELETE FROM policy_group WHERE name LIKE '%mpolicygroup-default-demo-oidc%';" \
  "Delete policy_group for demo-oidc"

# partner_policy_request table
execute_sql "mosip_pms" \
  "DELETE FROM partner_policy_request WHERE part_id LIKE '%mpartner-default-esignet%';" \
  "Delete partner_policy_request for esignet"

execute_sql "mosip_pms" \
  "DELETE FROM partner_policy_request WHERE part_id LIKE '%mpartner-default-demo-oidc%';" \
  "Delete partner_policy_request for demo-oidc"

execute_sql "mosip_pms" \
  "DELETE FROM partner_policy_request WHERE part_id LIKE '%mpartner-default-resident-oidc%';" \
  "Delete partner_policy_request for resident-oidc"

# partner table
execute_sql "mosip_pms" \
  "DELETE FROM partner WHERE id LIKE '%mpartner-default-esignet%';" \
  "Delete partner for esignet"

execute_sql "mosip_pms" \
  "DELETE FROM partner WHERE id LIKE '%mpartner-default-demo-oidc%';" \
  "Delete partner for demo-oidc"

execute_sql "mosip_pms" \
  "DELETE FROM partner WHERE id LIKE '%mpartner-default-resident-oidc%';" \
  "Delete partner for resident-oidc"

# misp_license table
execute_sql "mosip_pms" \
  "DELETE FROM misp_license WHERE misp_id LIKE '%mpartner-default-esignet%';" \
  "Delete misp_license for esignet"

# oidc_client table
execute_sql "mosip_pms" \
  "DELETE FROM oidc_client WHERE rp_id LIKE '%mpartner-default-resident-oidc%';" \
  "Delete oidc_client for resident-oidc"

execute_sql "mosip_pms" \
  "DELETE FROM oidc_client WHERE rp_id LIKE '%mpartner-default-demo-oidc%';" \
  "Delete oidc_client for demo-oidc"

echo ""
echo "Cleaning up mosip_esignet database..."
echo "----------------------------------------------"

# client_detail table
execute_sql "mosip_esignet" \
  "DELETE FROM client_detail WHERE rp_id LIKE '%mpartner-default-demo-oidc%';" \
  "Delete client_detail for demo-oidc"

execute_sql "mosip_esignet" \
  "DELETE FROM client_detail WHERE rp_id LIKE '%mpartner-default-resident-oidc%';" \
  "Delete client_detail for resident-oidc"

echo ""
echo "=============================================="
if [ "$DRY_RUN" == "true" ]; then
  echo "DRY-RUN COMPLETE - No data was deleted"
  echo "Run without --dry-run to execute deletions"
else
  echo "CLEANUP COMPLETE"
fi
echo "=============================================="
