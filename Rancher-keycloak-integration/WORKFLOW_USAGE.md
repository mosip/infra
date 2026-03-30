# GitHub Actions Workflow Usage

## Overview
This workflow automates the Keycloak-Rancher SAML integration with all configurations passed as user inputs.

## Workflow File
`.github/workflows/keycloak-rancher-integration.yml`

## How to Use

### 1. Push the Workflow to GitHub
```bash
git add .github/workflows/keycloak-rancher-integration.yml
git commit -m "Add Keycloak-Rancher SAML integration workflow"
git push
```

### 2. Run the Workflow
1. Go to your GitHub repository
2. Click on **Actions** tab
3. Select **Keycloak-Rancher SAML Integration** workflow
4. Click **Run workflow** button
5. Fill in the required inputs (see below)
6. Click **Run workflow**

## Required Inputs

### Keycloak Configuration
- **keycloak_host**: Keycloak host URL (e.g., `https://keycloak.example.com`)
- **keycloak_admin_user**: Admin username
- **keycloak_admin_password**: Admin password

### Rancher Configuration
- **rancher_host**: Rancher host URL (e.g., `https://rancher.example.com`)
- **rancher_token**: Rancher API token

## Optional Inputs (with defaults)

### Keycloak
- **keycloak_realm**: Realm name (default: `master`)
- **keycloak_admin_email**: Admin email (default: `admin@example.com`)
- **keycloak_admin_firstname**: Admin first name (default: `Admin`)

### SSL Configuration
- **ssl_cert_subject**: Certificate subject (default: `/C=US/ST=State/L=City/O=Organization/CN=rancher`)
- **ssl_cert_days**: Certificate validity in days (default: `1825`)
- **ssl_key_size**: Key size in bits (default: `2048`)
- **ssl_key_file**: Key filename (default: `myservice.key`)
- **ssl_cert_file**: Certificate filename (default: `myservice.cert`)

### SAML Configuration
- **saml_descriptor_file**: Descriptor filename (default: `keycloak-saml-descriptor.xml`)
- **saml_display_name_field**: Display name field (default: `givenName`)
- **saml_username_field**: Username field (default: `email`)
- **saml_uid_field**: UID field (default: `username`)
- **saml_groups_field**: Groups field (default: `member`)
- **saml_access_mode**: Access mode (default: `unrestricted`)

### Force Recreate
- **force_recreate**: Force recreate all configurations (default: `false`)
  - When enabled, deletes existing SSL keys, certificates, and SAML descriptor files before running
  - Use this to start fresh or resolve configuration conflicts

## Features

### Force Recreate Option
The `force_recreate` input allows you to:
- Delete existing SSL certificates and keys
- Remove existing SAML descriptor files
- Start with a completely fresh configuration
- Useful for troubleshooting or updating configurations

**When checked:**
1. Removes `myservice.key`, `myservice.cert`, `keycloak-saml-descriptor.xml` (or custom filenames)
2. Generates new SSL certificates
3. Fetches fresh SAML metadata from Keycloak
4. Reconfigures Rancher with new settings

### Security Features
- No sensitive files (keys/certs) are uploaded as artifacts
- All sensitive data is passed as inputs (not stored in repository)
- Generated files are automatically cleaned up after workflow completes

### Diagnostic Fallback
If the main integration fails, the workflow automatically runs the diagnostic tool to help identify issues.

## Alternative: Using GitHub Secrets

For better security, you can modify the workflow to use GitHub Secrets instead of manual inputs:

1. Go to **Settings** → **Secrets and variables** → **Actions**
2. Add secrets for sensitive values:
   - `KEYCLOAK_ADMIN_PASSWORD`
   - `RANCHER_TOKEN`
3. Update the workflow to use: `${{ secrets.SECRET_NAME }}`

Example:
```yaml
KEYCLOAK_ADMIN_PASSWORD: ${{ secrets.KEYCLOAK_ADMIN_PASSWORD }}
RANCHER_TOKEN: ${{ secrets.RANCHER_TOKEN }}
```

## Troubleshooting

### Workflow Fails
- Check the workflow logs in the Actions tab
- Look for the diagnostic tool output (runs automatically on failure)
- Verify all required inputs are correct
- Check network connectivity to Keycloak and Rancher

### Force Recreate Not Working
- Ensure the checkbox is enabled when running the workflow
- Check that file paths in SSL/SAML configuration match existing files
- Review workflow logs for file deletion messages

## Notes
- The workflow runs on `ubuntu-latest` with Python 3.x
- All generated files are temporary and discarded after execution
- No artifacts are uploaded for security reasons
