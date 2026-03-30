# Keycloak-Rancher SAML Integration Automation

Automated setup for Keycloak and Rancher SAML authentication using GitHub Actions workflows.

## 📋 Prerequisites

- GitHub repository with Actions enabled
- Access to configure repository secrets
- WireGuard VPN configuration for cluster access
- Keycloak admin credentials
- Rancher API token

## 🚀 Quick Start (Using GitHub Actions Workflow)

The recommended approach is to use the **Keycloak-Rancher SAML Integration** workflow.

### Step 1: Configure Repository Secrets

Navigate to your repository: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add the following secrets:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password | `your-secure-password` |
| `RANCHER_TOKEN` | Rancher API token | `token-xxxxx:xxxxxxxxxxxxxxxx` |
| `TF_WG_CONFIG` | WireGuard VPN configuration | (see below) |

### Step 2: Run the Workflow

1. Go to **Actions** tab in your repository
2. Select **Keycloak-Rancher SAML Integration** from the left sidebar
3. Click **Run workflow**
4. Fill in the required inputs:

| Input | Required | Description | Example |
|-------|----------|-------------|---------|
| `keycloak_host` | Yes | Keycloak server URL | `https://keycloak.example.com` |
| `keycloak_admin_user` | Yes | Keycloak admin username | `admin` |
| `rancher_host` | Yes | Rancher server URL | `https://rancher.example.com` |
| `keycloak_realm` | No | Keycloak realm (default: `master`) | `master` |
| `keycloak_admin_email` | No | Admin email | `admin@example.com` |
| `ssl_cert_subject` | No | SSL certificate subject | `/C=US/ST=State/L=City/O=Organization/CN=rancher` |
| `saml_access_mode` | No | SAML access mode | `unrestricted` |
| `force_recreate` | No | Force recreate existing config | `false` |

5. Click **Run workflow**

### Step 3: Monitor Execution

1. Click on the running workflow to view progress
2. Watch the job steps:
   - ✅ Checkout repository
   - ✅ Set up Python
   - ✅ Install dependencies
   - ✅ Configure and start WireGuard VPN
   - ✅ Run Keycloak-Rancher SAML Integration
3. If the workflow fails, the **Rancher Diagnostics** step runs automatically

### Step 4: Verify Integration

After successful workflow completion:

1. Login to Rancher UI
2. Go to **Users & Authentication** → **Auth Provider**
3. Verify Keycloak SAML is configured and enabled
4. Test login using Keycloak credentials

## 🔧 How to Get Required Credentials

### Rancher API Token

1. Login to Rancher UI
2. Click on your user profile (top right)
3. Select **API & Keys**
4. Click **Add Key**
5. Provide a description and set expiration
6. Click **Create**
7. Copy the generated token (format: `token-xxxxx:xxxxxxxxxxxxxxxx`)

### WireGuard Configuration

The `TF_WG_CONFIG` secret should contain a valid WireGuard configuration:

```ini
[Interface]
PrivateKey = <your-private-key>
Address = <your-vpn-ip>/32

[Peer]
PublicKey = <server-public-key>
AllowedIPs = <allowed-ip-range>
Endpoint = <vpn-endpoint>:51820
PersistentKeepalive = 25
```

---

## 📦 What the Workflow Does

### Keycloak Configuration
1. ✅ Authenticates as admin user
2. ✅ Updates admin user with email and firstName
3. ✅ Creates SAML client for Rancher
4. ✅ Configures client settings (signatures, encryption, etc.)
5. ✅ Creates protocol mappers (username, groups, email, givenName)
6. ✅ Downloads SAML descriptor XML

### Rancher Configuration
1. ✅ Generates self-signed SSL certificate (5-year validity)
2. ✅ Configures Keycloak SAML authentication
3. ✅ Uploads certificate and metadata
4. ✅ Enables SAML authentication

---

## 📝 Environment Variables Reference

### Keycloak Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KEYCLOAK_HOST` | Yes | - | Keycloak server URL |
| `KEYCLOAK_REALM` | No | `master` | Keycloak realm name |
| `KEYCLOAK_ADMIN_USER` | Yes | - | Admin username |
| `KEYCLOAK_ADMIN_PASSWORD` | Yes | - | Admin password (from secrets) |
| `KEYCLOAK_ADMIN_EMAIL` | No | `admin@example.com` | Admin email |
| `KEYCLOAK_ADMIN_FIRSTNAME` | No | `Admin` | Admin first name |

### Rancher Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RANCHER_HOST` | Yes | - | Rancher server URL |
| `RANCHER_TOKEN` | Yes | - | Rancher API token (from secrets) |

### SSL Certificate Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SSL_CERT_SUBJECT` | No | `/C=US/ST=State/...` | Certificate subject |
| `SSL_CERT_DAYS` | No | `1825` | Certificate validity days (5 years) |
| `SSL_KEY_SIZE` | No | `2048` | RSA key size |
| `SSL_KEY_FILE` | No | `myservice.key` | Private key filename |
| `SSL_CERT_FILE` | No | `myservice.cert` | Certificate filename |

### SAML Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SAML_DESCRIPTOR_FILE` | No | `keycloak-saml-descriptor.xml` | Descriptor filename |
| `SAML_DISPLAY_NAME_FIELD` | No | `givenName` | Display name field |
| `SAML_USERNAME_FIELD` | No | `email` | Username field |
| `SAML_UID_FIELD` | No | `username` | UID field |
| `SAML_GROUPS_FIELD` | No | `member` | Groups field |
| `SAML_ACCESS_MODE` | No | `unrestricted` | Access mode |

---

## 🔍 Troubleshooting

### Workflow Fails at WireGuard Step

**Error**: `Failed to start WireGuard VPN`

**Solution**:
1. Verify `TF_WG_CONFIG` secret is configured correctly
2. Ensure the WireGuard configuration contains valid `[Interface]` and `[Peer]` sections
3. Check VPN endpoint is reachable

### Workflow Fails at Integration Step

**Error**: Authentication or connection issues

**Solution**:
1. Verify `KEYCLOAK_ADMIN_PASSWORD` secret is correct
2. Verify `RANCHER_TOKEN` secret is valid and not expired
3. Check Keycloak and Rancher hosts are accessible via VPN
4. Review the **Rancher Diagnostics** output (runs automatically on failure)

### Invalid Rancher Token

**Error**: `401 Unauthorized` or `Invalid token`

**Solution**:
1. Regenerate Rancher API token
2. Update `RANCHER_TOKEN` secret with new token
3. Verify token format: `token-xxxxx:xxxxxxxxxxxxxxxx`

### Keycloak Client Already Exists

**Solution**: Enable `force_recreate` option when running the workflow to recreate existing configurations.

---

## 🛠️ Alternative: Manual Execution (Optional)

<details>
<summary>Click to expand manual execution options</summary>

If you need to run the integration manually (outside of GitHub Actions), you can use the scripts directly.

### Prerequisites for Manual Execution

- Python 3.7+
- Bash
- OpenSSL
- curl
- jq (for bash scripts)
- Docker & Docker Compose (for containerized approach)

### 1. Clone/Download the Scripts

```bash
# Download all scripts to a directory
mkdir keycloak-rancher-integration
cd keycloak-rancher-integration
```

### 2. Configure Environment Variables

```bash
# Copy the example environment file
cp .env.example .env

# Edit with your configurations
vi .env
```

**Required Variables:**

```bash
KEYCLOAK_HOST=https://keycloak.example.com
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=your-password
RANCHER_HOST=https://rancher.example.com
RANCHER_TOKEN=token-xxxxx:xxxxxxxxxxxxxxxx
```

### 3. Run the Automation

#### Option A: Python Script (Recommended)

```bash
# Install dependencies
pip install requests

# Load environment variables and run
source .env
python3 automation_script.py

# If Keycloak client already exists, it will be reused automatically
# To force recreate everything:
python3 automation_script.py --force

# To only configure Keycloak:
python3 automation_script.py --skip-rancher

# To only configure Rancher (requires existing SAML descriptor):
python3 automation_script.py --skip-keycloak
```

#### Option B: Using Makefile

```bash
# Setup dependencies
make setup

# Run complete automation
make run

# Or run individual steps
make run-keycloak  # Only Keycloak setup
make run-rancher   # Only Rancher setup
```

#### Option C: Docker

```bash
# Build and run in Docker
docker-compose up --build
```

#### Option D: Bash Scripts

```bash
# Make scripts executable
chmod +x keycloak_automation.sh rancher_automation.sh

# Load environment variables
source .env

# Run Keycloak setup
./keycloak_automation.sh

# Run Rancher setup
./rancher_automation.sh
```

### Debug Mode (Manual Execution)

```bash
# Enable verbose output
set -x
./keycloak_automation.sh
```

For Python script:
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

</details>

---

## 🔒 Security Best Practices

1. **Use GitHub Secrets** for all sensitive data (passwords, tokens, VPN configs)
2. **Never commit `.env` file** to version control
3. **Rotate API tokens** regularly
4. **Use strong passwords** for Keycloak admin
5. **Limit token scope** in Rancher
6. **Review workflow logs** - sensitive data is masked automatically

---

## 📚 Additional Resources

- [Keycloak Admin REST API](https://www.keycloak.org/docs-api/latest/rest-api/)
- [Rancher API Documentation](https://rancher.com/docs/rancher/v2.x/en/api/)
- [SAML 2.0 Specification](http://docs.oasis-open.org/security/saml/Post2.0/sstc-saml-tech-overview-2.0.html)
- [GitHub Actions Workflow Guide](../docs/WORKFLOW_GUIDE.md)

---

## 📄 License

MIT License - feel free to use and modify as needed.