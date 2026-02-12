# Partner Data Cleanup Guide

This guide provides instructions for running the partner data cleanup workflow to remove partner-related data from the MOSIP database.

## Overview

The **Cleanup Partner Data** workflow is designed to safely remove all partner-related data from your MOSIP database. This is useful when you need to reset partner registrations or clean up test data.

> **⚠️ CRITICAL WARNING**: This operation is **IRREVERSIBLE**. All partner data will be permanently deleted from the database. Always create a backup before running this cleanup.

## What Gets Deleted

The cleanup script removes the following partner-related data:

- Partner management service (PMS) data
- Partner policies
- Partner certificates
- Partner API keys
- Authentication policies
- MISP license keys
- Device provider details
- FTM (Foundational Trust Module) chip details
- Secure biometric interface details

## When to Run This Cleanup

### Recommended Use Cases

✅ **Safe to run when:**
- Resetting a development/testing environment
- Starting fresh partner onboarding after testing
- Cleaning up test partner data before production deployment
- Fixing corrupted partner data that cannot be resolved otherwise

❌ **DO NOT run when:**
- In production environments with active partners
- Without taking a database backup first
- Without understanding the impact on your system
- When partners are actively using the system

## Prerequisites

### 1. Database Access

Ensure you have:
- Database hostname/IP (e.g., `postgres.your-domain.net`)
- Database port (default: `5432` or `5433`)
- Database username (usually `postgres`)
- Database password (configured as GitHub secret `DB_PASSWORD`)

### 2. GitHub Secrets Configuration

Configure the following secrets in your GitHub repository:

**Environment Secret** (Settings → Environments → `<branch-name>` → Add secret):

| Secret Name | Description | Example |
|------------|-------------|---------|
| `DB_PASSWORD` | PostgreSQL database password | `your-secure-password` |

### 3. WireGuard VPN Access (Optional)

If your database is on a private network, configure:

| Secret Name | Description |
|------------|-------------|
| `TF_WG_CONFIG` | WireGuard VPN configuration for database access |

## How to Run the Cleanup

### Step 1: Backup Your Database

**CRITICAL**: Always backup before running cleanup!

```bash
# SSH to your database server
ssh user@postgres-server

# Create backups for both PMS and eSignet databases
pg_dump -h localhost -p 5433 -U postgres -d mosip_pms > pms_backup_$(date +%Y%m%d_%H%M%S).sql
pg_dump -h localhost -p 5433 -U postgres -d mosip_esignet > esignet_backup_$(date +%Y%m%d_%H%M%S).sql

# Verify backups were created
ls -lh pms_backup_*.sql esignet_backup_*.sql
```

### Step 2: Run in Dry-Run Mode First

1. **Navigate to GitHub Actions:**
   - Go to your repository
   - Click **Actions** tab
   - Select **Cleanup Partner Data** workflow (left sidebar)

2. **Click "Run workflow"** (green button on the right)

3. **Configure workflow inputs:**

   ![Cleanup Partner Data Workflow](../_images/cleanup-partner-data.png)

   | Input | Value | Description |
   |-------|-------|-------------|
   | **Database host** | `postgres.your-domain.net` | Your PostgreSQL hostname |
   | **Database port** | `5433` | PostgreSQL port (default: 5432) |
   | **Database user** | `postgres` | Database username |
   | **Dry run** | `true` ✅ | **IMPORTANT**: Start with dry-run! |
   | **Enable Wireguard VPN** | `false` / `true` | Enable if database is on private network |
   | **Type DELETE to confirm** | *leave empty* | Not needed for dry-run |

4. **Click "Run workflow"**

5. **Review the dry-run output:**
   - Check the workflow logs
   - Verify which records would be deleted
   - Confirm the count matches your expectations

### Step 3: Execute the Actual Cleanup

> **⚠️ WARNING**: This step will PERMANENTLY delete data!

1. **Run the workflow again with these settings:**

   | Input | Value | Description |
   |-------|-------|-------------|
   | **Database host** | `postgres.your-domain.net` | Your PostgreSQL hostname |
   | **Database port** | `5433` | PostgreSQL port |
   | **Database user** | `postgres` | Database username |
   | **Dry run** | `false` ❌ | **Execute actual deletion** |
   | **Enable Wireguard VPN** | `false` / `true` | Based on your setup |
   | **Type DELETE to confirm** | `DELETE` | **MUST type exactly "DELETE"** |

2. **Click "Run workflow"**

3. **Monitor the execution:**
   - Watch the workflow logs
   - Verify successful deletion messages
   - Check for any errors

### Step 4: Verify Cleanup

After cleanup completes, verify the data was removed:

```bash
# Connect to database
psql -h postgres.your-domain.net -p 5433 -U postgres -d mosip_pms

# Check if partner tables are empty
SELECT COUNT(*) FROM pms.partner;
SELECT COUNT(*) FROM pms.partner_policy;
SELECT COUNT(*) FROM pms.auth_policy;

# Exit
\q
```

## Workflow Parameters Explained

### Database Configuration

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `db_host` | PostgreSQL hostname or IP | `postgres` | Yes |
| `db_port` | PostgreSQL service port | `5432` | Yes |
| `db_user` | Database username | `postgres` | Yes |

### Execution Mode

| Parameter | Description | Values |
|-----------|-------------|--------|
| `dry_run` | Preview changes without deleting | `true` (safe) / `false` (execute) |
| `confirm_deletion` | Safety confirmation for actual deletion | Must type `DELETE` exactly |

### Network Access

| Parameter | Description | When to Enable |
|-----------|-------------|----------------|
| `enable_wireguard` | Connect via WireGuard VPN | Database is on private network |

## Troubleshooting

### Error: DB_PASSWORD secret not set

**Problem:** The `DB_PASSWORD` environment secret is not configured.

**Solution:**
1. Go to: Repository → Settings → Environments → `<branch-name>`
2. Add secret: `DB_PASSWORD` with your database password
3. Re-run the workflow

### Error: Cannot connect to database

**Problem:** Database is not reachable or credentials are incorrect.

**Solutions:**
- Verify database hostname/port is correct
- Check if database is on a private network (enable WireGuard VPN)
- Verify database credentials are correct
- Test connection manually:
  ```bash
  psql -h postgres.your-domain.net -p 5433 -U postgres -d mosip_pms
  ```

### Error: You must type 'DELETE' to confirm

**Problem:** Confirmation text was not entered correctly when running in non-dry-run mode.

**Solution:**
- Type exactly `DELETE` (all uppercase) in the confirmation field
- Do not add spaces or extra characters

## Post-Cleanup Steps

After successfully cleaning up partner data:

1. **Re-run Partner Onboarding:**
   - Deploy the partner-onboarder helm chart again
   - Or manually trigger partner onboarding jobs

2. **Verify Partner Registration:**
   - Check MinIO for onboarding reports
   - Verify partners are registered correctly
   - Test partner authentication

3. **Update Dependent Services:**
   - Restart services that cache partner data
   - Clear any application caches
   - Verify API keys are refreshed

## Safety Checklist

Before running cleanup in any environment:

- [ ] Database backup created and verified
- [ ] Dry-run executed and reviewed
- [ ] Impact on dependent services understood
- [ ] Stakeholders notified (if production/staging)
- [ ] Rollback plan prepared
- [ ] Confirmation typed correctly (`DELETE`)
- [ ] Post-cleanup steps planned

## Related Documentation

- [Partner Onboarding Guide](ONBOARDING_GUIDE.md)
- [Database Backup and Recovery](../terraform/README.md#database-management)
- [Secret Generation Guide](SECRET_GENERATION_GUIDE.md)

## Support

If you encounter issues:
1. Check workflow logs for detailed error messages
2. Verify database connectivity and credentials
3. Review the [Troubleshooting](#troubleshooting) section above
4. Check related documentation links
5. Open an issue in the repository with error logs

---

**Remember**: Always run dry-run first, create backups, and understand the impact before executing the cleanup!
