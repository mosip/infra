# Keycloak-Rancher SAML Integration Automation

Automated setup for Keycloak and Rancher SAML authentication using environment variables.

## 📋 Prerequisites

- Python 3.7+ (for Python script)
- Bash (for shell scripts)
- OpenSSL
- curl
- jq (for bash scripts)
- Docker & Docker Compose (for containerized approach)

## 🚀 Quick Start

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

## 📝 Environment Variables Reference

### Keycloak Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KEYCLOAK_HOST` | Yes | - | Keycloak server URL |
| `KEYCLOAK_REALM` | No | `master` | Keycloak realm name |
| `KEYCLOAK_ADMIN_USER` | Yes | - | Admin username |
| `KEYCLOAK_ADMIN_PASSWORD` | Yes | - | Admin password |
| `KEYCLOAK_ADMIN_EMAIL` | No | `admin@example.com` | Admin email |
| `KEYCLOAK_ADMIN_FIRSTNAME` | No | `Admin` | Admin first name |

### Rancher Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RANCHER_HOST` | Yes | - | Rancher server URL |
| `RANCHER_TOKEN` | Yes | - | Rancher API token |

### SSL Certificate Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SSL_CERT_SUBJECT` | No | `/C=US/ST=State/...` | Certificate subject |
| `SSL_CERT_DAYS` | No | `365` | Certificate validity days |
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

## 🔧 How to Get Rancher API Token

1. Login to Rancher UI
2. Click on your user profile (top right)
3. Select **API & Keys**
4. Click **Add Key**
5. Provide a description and set expiration
6. Click **Create**
7. Copy the generated token (format: `token-xxxxx:xxxxxxxxxxxxxxxx`)

## 📦 What the Automation Does

### Keycloak Configuration
1. ✅ Authenticates as admin user
2. ✅ Updates admin user with email and firstName
3. ✅ Creates SAML client for Rancher
4. ✅ Configures client settings (signatures, encryption, etc.)
5. ✅ Creates protocol mappers (username, groups, email, givenName)
6. ✅ Downloads SAML descriptor XML

### Rancher Configuration
1. ✅ Generates self-signed SSL certificate
2. ✅ Configures Keycloak SAML authentication
3. ✅ Uploads certificate and metadata
4. ✅ Enables SAML authentication

## 🛠️ Advanced Usage

### Using with CI/CD

```yaml
# GitLab CI example
deploy:
  script:
    - export KEYCLOAK_HOST=$KEYCLOAK_HOST
    - export KEYCLOAK_ADMIN_USER=$KEYCLOAK_ADMIN_USER
    - export KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD
    - export RANCHER_HOST=$RANCHER_HOST
    - export RANCHER_TOKEN=$RANCHER_TOKEN
    - python3 automation_script.py
```

### Using with Kubernetes Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: keycloak-rancher-integration
spec:
  template:
    spec:
      containers:
      - name: integration
        image: your-registry/keycloak-rancher-integration:latest
        envFrom:
        - secretRef:
            name: integration-secrets
      restartPolicy: OnFailure
```

### Using with Terraform

```hcl
resource "null_resource" "keycloak_rancher_integration" {
  provisioner "local-exec" {
    command = "python3 automation_script.py"
    environment = {
      KEYCLOAK_HOST          = var.keycloak_host
      KEYCLOAK_ADMIN_USER    = var.keycloak_admin_user
      KEYCLOAK_ADMIN_PASSWORD = var.keycloak_admin_password
      RANCHER_HOST           = var.rancher_host
      RANCHER_TOKEN          = var.rancher_token
    }
  }
}
```

## 🔍 Troubleshooting

### Common Issues

**1. Connection Refused**
```bash
# Test connectivity
make test-keycloak
make test-rancher
```

**2. Authentication Failed**
- Verify admin credentials
- Check Keycloak is accessible
- Ensure realm name is correct

**3. Invalid Token**
- Regenerate Rancher API token
- Check token hasn't expired
- Verify token format: `token-xxxxx:xxxxxxxxxxxxxxxx`

**4. SSL Certificate Issues**
- Ensure OpenSSL is installed
- Check write permissions in directory
- Verify certificate subject format

### Debug Mode

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

## 📁 Generated Files

After successful execution:
- `myservice.key` - Private key for SAML
- `myservice.cert` - Certificate for SAML
- `keycloak-saml-descriptor.xml` - SAML metadata from Keycloak

## 🔒 Security Best Practices

1. **Never commit `.env` file** to version control
2. **Use secrets management** (Vault, AWS Secrets Manager, etc.)
3. **Rotate API tokens** regularly
4. **Use strong passwords** for Keycloak admin
5. **Limit token scope** in Rancher
6. **Store certificates securely**
7. **Use HTTPS** for all endpoints

## 📚 Additional Resources

- [Keycloak Admin REST API](https://www.keycloak.org/docs-api/latest/rest-api/)
- [Rancher API Documentation](https://rancher.com/docs/rancher/v2.x/en/api/)
- [SAML 2.0 Specification](http://docs.oasis-open.org/security/saml/Post2.0/sstc-saml-tech-overview-2.0.html)

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

MIT License - feel free to use and modify as needed.