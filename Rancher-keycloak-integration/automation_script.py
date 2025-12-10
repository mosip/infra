#!/usr/bin/env python3
"""
Complete automation script for Keycloak-Rancher SAML integration
All configurations passed via environment variables
"""

import requests
import json
import subprocess
import sys
import os
from urllib.parse import urljoin
from dotenv import load_dotenv
load_dotenv()
class Config:
    """Configuration manager that reads from environment variables"""
    
    @staticmethod
    def get_keycloak_config():
        """Get Keycloak configuration from environment variables"""
        required_vars = [
            'KEYCLOAK_HOST',
            'KEYCLOAK_REALM',
            'KEYCLOAK_ADMIN_USER',
            'KEYCLOAK_ADMIN_PASSWORD'
        ]
        
        config = {
            "host": os.getenv('KEYCLOAK_HOST'),
            "realm": os.getenv('KEYCLOAK_REALM', 'master'),
            "admin_user": os.getenv('KEYCLOAK_ADMIN_USER'),
            "admin_password": os.getenv('KEYCLOAK_ADMIN_PASSWORD'),
            "admin_email": os.getenv('KEYCLOAK_ADMIN_EMAIL', 'admin@example.com'),
            "admin_firstname": os.getenv('KEYCLOAK_ADMIN_FIRSTNAME', 'Admin')
        }
        
        # Validate required variables
        missing = [var for var in required_vars if not os.getenv(var)]
        if missing:
            raise ValueError(f"Missing required environment variables: {', '.join(missing)}")
        
        return config
    
    @staticmethod
    def get_rancher_config():
        """Get Rancher configuration from environment variables"""
        required_vars = [
            'RANCHER_HOST',
            'RANCHER_TOKEN'
        ]
        
        config = {
            "host": os.getenv('RANCHER_HOST'),
            "token": os.getenv('RANCHER_TOKEN')
        }
        
        # Validate required variables
        missing = [var for var in required_vars if not os.getenv(var)]
        if missing:
            raise ValueError(f"Missing required environment variables: {', '.join(missing)}")
        
        return config
    
    @staticmethod
    def get_ssl_config():
        """Get SSL configuration from environment variables"""
        return {
            "cert_subject": os.getenv('SSL_CERT_SUBJECT', '/C=US/ST=State/L=City/O=Organization/CN=rancher'),
            "cert_days": os.getenv('SSL_CERT_DAYS', '365'),
            "key_size": os.getenv('SSL_KEY_SIZE', '2048'),
            "key_file": os.getenv('SSL_KEY_FILE', 'myservice.key'),
            "cert_file": os.getenv('SSL_CERT_FILE', 'myservice.cert')
        }
    
    @staticmethod
    def get_saml_config():
        """Get SAML configuration from environment variables"""
        return {
            "descriptor_file": os.getenv('SAML_DESCRIPTOR_FILE', 'keycloak-saml-descriptor.xml'),
            "display_name_field": os.getenv('SAML_DISPLAY_NAME_FIELD', 'givenName'),
            "username_field": os.getenv('SAML_USERNAME_FIELD', 'email'),
            "uid_field": os.getenv('SAML_UID_FIELD', 'username'),
            "groups_field": os.getenv('SAML_GROUPS_FIELD', 'member'),
            "access_mode": os.getenv('SAML_ACCESS_MODE', 'unrestricted')
        }
    
    @staticmethod
    def get_force_recreate():
        """Get force recreate flag from environment variables"""
        return os.getenv('FORCE_RECREATE', 'false').lower() in ('true', '1', 'yes')

class KeycloakAPI:
    REQUEST_TIMEOUT = 30  # seconds

    def __init__(self, config):
        self.host = config["host"]
        self.realm = config["realm"]
        self.admin_user = config["admin_user"]
        self.admin_password = config["admin_password"]
        self.token = None
        
    def get_token(self):
        """Get admin access token"""
        url = f"{self.host}/auth/realms/master/protocol/openid-connect/token"
        data = {
            "username": self.admin_user,
            "password": self.admin_password,
            "grant_type": "password",
            "client_id": "admin-cli"
        }
        
        response = requests.post(url, data=data, timeout=self.REQUEST_TIMEOUT)
        response.raise_for_status()
        self.token = response.json()["access_token"]
        print("✓ Keycloak token obtained")
        
    def get_headers(self):
        """Get authorization headers"""
        return {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }
    
    def update_admin_user(self, email, firstname):
        """Update admin user with email and firstName"""
        # Get admin user ID
        url = f"{self.host}/auth/admin/realms/{self.realm}/users"
        params = {"username": self.admin_user}
        response = requests.get(url, headers=self.get_headers(), params=params, timeout=self.REQUEST_TIMEOUT)
        response.raise_for_status()
        
        users = response.json()
        if not users:
            raise ValueError(f"Admin user '{self.admin_user}' not found")
        
        user_id = users[0]["id"]
        
        # Update user
        url = f"{self.host}/auth/admin/realms/{self.realm}/users/{user_id}"
        data = {
            "email": email,
            "firstName": firstname,
            "emailVerified": True
        }
        
        response = requests.put(url, headers=self.get_headers(), json=data, timeout=self.REQUEST_TIMEOUT)
        response.raise_for_status()
        print(f"✓ Admin user updated with email: {email}")
        
    def create_saml_client(self, rancher_host):
        """Create SAML client for Rancher"""
        client_id = f"{rancher_host}/v1-saml/keycloak/saml/metadata"
        
        # First, check if client already exists
        url = f"{self.host}/auth/admin/realms/{self.realm}/clients"
        params = {"clientId": client_id}
        response = requests.get(url, headers=self.get_headers(), params=params, timeout=self.REQUEST_TIMEOUT)
        response.raise_for_status()
        
        existing_clients = response.json()
        
        if existing_clients and len(existing_clients) > 0:
            # Client already exists, return its internal ID
            internal_id = existing_clients[0]["id"]
            print(f"✓ SAML client already exists: {client_id}")
            print(f"  Using existing client ID: {internal_id}")
            return internal_id
        
        # Client doesn't exist, create it
        url = f"{self.host}/auth/admin/realms/{self.realm}/clients"
        data = {
            "clientId": client_id,
            "name": "rancher",
            "protocol": "saml",
            "enabled": True,
            "attributes": {
                "saml.authnstatement": "true",
                "saml.server.signature": "true",
                "saml.assertion.signature": "true",
                "saml.client.signature": "false",
                "saml.encrypt": "false",
                "saml.force.post.binding": "false",
                "saml_force_name_id_format": "false",
                "saml_name_id_format": "username",
                "saml_signature_canonicalization_method": "http://www.w3.org/2001/10/xml-exc-c14n#"
            },
            "redirectUris": [f"{rancher_host}/v1-saml/keycloak/saml/acs"],
            "frontchannelLogout": False
        }
        
        response = requests.post(url, headers=self.get_headers(), json=data, timeout=self.REQUEST_TIMEOUT)
        response.raise_for_status()
        print(f"✓ SAML client created: {client_id}")
        
        # Get internal client ID
        url = f"{self.host}/auth/admin/realms/{self.realm}/clients"
        params = {"clientId": client_id}
        response = requests.get(url, headers=self.get_headers(), params=params, timeout=self.REQUEST_TIMEOUT)
        response.raise_for_status()
        
        clients = response.json()
        if not clients:
            raise ValueError(f"Failed to retrieve created client")
        
        return clients[0]["id"]
    
    def create_protocol_mappers(self, internal_client_id):
        """Create protocol mappers for the client"""
        # First, get existing mappers
        get_url = f"{self.host}/auth/admin/realms/{self.realm}/clients/{internal_client_id}/protocol-mappers/models"
        response = requests.get(get_url, headers=self.get_headers(), timeout=self.REQUEST_TIMEOUT)
        response.raise_for_status()
        existing_mappers = response.json()
        existing_mapper_names = {mapper["name"] for mapper in existing_mappers}
        
        post_url = f"{self.host}/auth/admin/realms/{self.realm}/clients/{internal_client_id}/protocol-mappers/models"
        
        mappers = [
            {
                "name": "username",
                "protocol": "saml",
                "protocolMapper": "saml-user-property-mapper",
                "config": {
                    "user.attribute": "username",
                    "friendly.name": "username",
                    "attribute.name": "username",
                    "attribute.nameformat": "Basic"
                }
            },
            {
                "name": "groups",
                "protocol": "saml",
                "protocolMapper": "saml-group-membership-mapper",
                "config": {
                    "attribute.name": "member",
                    "attribute.nameformat": "Basic",
                    "single": "true",
                    "full.path": "false"
                }
            },
            {
                "name": "email",
                "protocol": "saml",
                "protocolMapper": "saml-user-property-mapper",
                "config": {
                    "user.attribute": "email",
                    "friendly.name": "email",
                    "attribute.name": "email",
                    "attribute.nameformat": "Basic"
                }
            },
            {
                "name": "givenName",
                "protocol": "saml",
                "protocolMapper": "saml-user-property-mapper",
                "config": {
                    "user.attribute": "firstName",
                    "friendly.name": "givenName",
                    "attribute.name": "givenName",
                    "attribute.nameformat": "Basic"
                }
            }
        ]
        
        for mapper in mappers:
            if mapper["name"] in existing_mapper_names:
                print(f"✓ Mapper already exists: {mapper['name']}")
            else:
                response = requests.post(post_url, headers=self.get_headers(), json=mapper, timeout=self.REQUEST_TIMEOUT)
                response.raise_for_status()
                print(f"✓ Created mapper: {mapper['name']}")
    
    def download_saml_descriptor(self, filename):
        """Download SAML descriptor XML"""
        url = f"{self.host}/auth/realms/{self.realm}/protocol/saml/descriptor"
        response = requests.get(url, timeout=self.REQUEST_TIMEOUT)
        response.raise_for_status()
        
        with open(filename, 'w') as f:
            f.write(response.text)
        
        print(f"✓ SAML descriptor downloaded: {filename}")
        return response.text

class RancherAPI:
    def __init__(self, config):
        self.host = config["host"]
        self.token = config["token"]
        
    def get_headers(self):
        """Get authorization headers"""
        return {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }
    
    def configure_keycloak_saml(self, metadata_xml, private_key, certificate, saml_config):
        """Configure Keycloak SAML authentication in Rancher"""
        
        print("  Configuring Keycloak SAML in Rancher...")
        
        # Rancher uses 'keycloak' as the auth config ID for Keycloak SAML
        # Note: The endpoint is keyCloakConfigs (plural)
        url = f"{self.host}/v3/keyCloakConfigs/keycloak"
        
        # Prepare the configuration data
        # rancherApiHost should be the full hostname with protocol for proper SAML entity matching
        config_data = {
            "enabled": True,
            "accessMode": saml_config["access_mode"],
            "displayNameField": saml_config["display_name_field"],
            "groupsField": saml_config["groups_field"],
            "idpMetadataContent": metadata_xml,
            "rancherApiHost": self.host,  # Keep the full URL with https://
            "spCert": certificate,
            "spKey": private_key,
            "uidField": saml_config["uid_field"],
            "userNameField": saml_config["username_field"]
        }
        
        # Try to get existing config first
        response = requests.get(url, headers=self.get_headers())
        
        if response.status_code == 200:
            # Config exists, update it using PUT
            print(f"  Existing config found, updating...")
            existing_config = response.json()
            
            # Update the fields
            existing_config.update(config_data)
            
            response = requests.put(url, headers=self.get_headers(), json=existing_config)
            
            if response.status_code in [200, 201]:
                print("✓ Rancher Keycloak SAML configuration updated successfully")
                return
        else:
            # Config doesn't exist or hasn't been enabled yet
            # Use the testAndEnable action to enable and configure
            print(f"  Enabling and configuring Keycloak SAML...")
            
            action_url = f"{url}?action=testAndEnable"
            
            # For the testAndEnable action, we need to send the full config
            full_config = {
                "type": "keyCloakConfig",
                "enabled": True,
                "accessMode": saml_config["access_mode"],
                "allowedPrincipalIds": [],
                "displayNameField": saml_config["display_name_field"],
                "groupsField": saml_config["groups_field"],
                "idpMetadataContent": metadata_xml,
                "rancherApiHost": self.host,  # Keep the full URL with https://
                "spCert": certificate,
                "spKey": private_key,
                "uidField": saml_config["uid_field"],
                "userNameField": saml_config["username_field"]
            }
            
            response = requests.post(action_url, headers=self.get_headers(), json=full_config)
        
        if response.status_code in [200, 201]:
            print("✓ Rancher Keycloak SAML configuration completed successfully")
            return
        
        # If that fails, raise the error with details
        print(f"  Configuration failed with status {response.status_code}")
        print(f"  Response: {response.text}")
        response.raise_for_status()
    
    def list_auth_configs(self):
        """List available auth configurations in Rancher"""
        url = f"{self.host}/v3/authConfigs"
        response = requests.get(url, headers=self.get_headers())
        
        if response.status_code == 200:
            configs = response.json()
            print("\n  Available auth configs:")
            if 'data' in configs:
                for config in configs['data']:
                    print(f"    - {config.get('id', 'N/A')} ({config.get('type', 'N/A')})")
            return configs
        return None

def generate_ssl_certificate(ssl_config):
    """Generate self-signed SSL certificate"""
    print("Generating SSL certificate...")
    
    cmd = [
        "openssl", "req", "-x509", "-sha256", "-nodes",
        "-days", ssl_config["cert_days"],
        "-newkey", f"rsa:{ssl_config['key_size']}",
        "-keyout", ssl_config["key_file"],
        "-out", ssl_config["cert_file"],
        "-subj", ssl_config["cert_subject"]
    ]
    
    subprocess.run(cmd, check=True, capture_output=True)
    
    with open(ssl_config["key_file"], "r") as f:
        private_key = f.read()
    
    with open(ssl_config["cert_file"], "r") as f:
        certificate = f.read()
    
    print(f"✓ SSL certificate generated: {ssl_config['cert_file']}")
    return private_key, certificate

def print_usage():
    """Print usage information"""
    print("""
=== Keycloak-Rancher SAML Integration Automation ===

Required Environment Variables:
  KEYCLOAK_HOST              Keycloak server URL (e.g., https://keycloak.example.com)
  KEYCLOAK_ADMIN_USER        Keycloak admin username
  KEYCLOAK_ADMIN_PASSWORD    Keycloak admin password
  RANCHER_HOST               Rancher server URL (e.g., https://rancher.example.com)
  RANCHER_TOKEN              Rancher API token

Optional Environment Variables:
  KEYCLOAK_REALM             Keycloak realm (default: master)
  KEYCLOAK_ADMIN_EMAIL       Admin user email (default: admin@example.com)
  KEYCLOAK_ADMIN_FIRSTNAME   Admin user first name (default: Admin)
  
  SSL_CERT_SUBJECT           Certificate subject (default: /C=US/ST=State/L=City/O=Organization/CN=rancher)
  SSL_CERT_DAYS              Certificate validity days (default: 365)
  SSL_KEY_SIZE               RSA key size (default: 2048)
  SSL_KEY_FILE               Private key filename (default: myservice.key)
  SSL_CERT_FILE              Certificate filename (default: myservice.cert)
  
  SAML_DESCRIPTOR_FILE       SAML descriptor filename (default: keycloak-saml-descriptor.xml)
  SAML_DISPLAY_NAME_FIELD    Display name field (default: givenName)
  SAML_USERNAME_FIELD        Username field (default: email)
  SAML_UID_FIELD             UID field (default: username)
  SAML_GROUPS_FIELD          Groups field (default: member)
  SAML_ACCESS_MODE           Access mode (default: unrestricted)

Example Usage:
  export KEYCLOAK_HOST=https://keycloak.example.com
  export KEYCLOAK_ADMIN_USER=admin
  export KEYCLOAK_ADMIN_PASSWORD=password
  export RANCHER_HOST=https://rancher.example.com
  export RANCHER_TOKEN=token-xxxxx:xxxxxxxxxxxxxxxx
  
  python3 automation_script.py
""")

def main():
    """Main execution function"""
    try:
        # Load configurations from environment variables
        keycloak_config = Config.get_keycloak_config()
        rancher_config = Config.get_rancher_config()
        ssl_config = Config.get_ssl_config()
        saml_config = Config.get_saml_config()
        force_recreate = Config.get_force_recreate()
        
    except ValueError as e:
        print(f"✗ Configuration Error: {e}\n", file=sys.stderr)
        print_usage()
        sys.exit(1)
    
    print("=== Keycloak-Rancher SAML Integration Automation ===\n")
    print(f"Keycloak Host: {keycloak_config['host']}")
    print(f"Keycloak Realm: {keycloak_config['realm']}")
    print(f"Rancher Host: {rancher_config['host']}")
    print(f"Force Recreate: {'Yes' if force_recreate else 'No'}\n")
    
    try:
        # Step 0: Clean up existing files if force recreate is enabled
        if force_recreate:
            print("Step 0: Force recreate enabled - cleaning up existing files...")
            files_to_remove = [
                ssl_config['key_file'],
                ssl_config['cert_file'],
                saml_config['descriptor_file']
            ]
            for file in files_to_remove:
                if os.path.exists(file):
                    os.remove(file)
                    print(f"  ✓ Removed {file}")
            print()
        
        # Step 1: Configure Keycloak
        print("Step 1: Configuring Keycloak...")
        keycloak = KeycloakAPI(keycloak_config)
        keycloak.get_token()
        keycloak.update_admin_user(
            keycloak_config["admin_email"],
            keycloak_config["admin_firstname"]
        )
        
        internal_client_id = keycloak.create_saml_client(rancher_config["host"])
        keycloak.create_protocol_mappers(internal_client_id)
        metadata_xml = keycloak.download_saml_descriptor(saml_config["descriptor_file"])
        
        print("\n✓ Keycloak configuration completed!\n")
        
        # Step 2: Generate certificates
        print("Step 2: Generating SSL certificates...")
        private_key, certificate = generate_ssl_certificate(ssl_config)
        print()
        
        # Step 3: Configure Rancher
        print("Step 3: Configuring Rancher...")
        rancher = RancherAPI(rancher_config)
        
        # First, list available auth configs to understand what's available
        rancher.list_auth_configs()
        
        rancher.configure_keycloak_saml(metadata_xml, private_key, certificate, saml_config)
        
        print("\n=== Integration completed successfully! ===")
        print(f"\nYou can now login to Rancher at: {rancher_config['host']}")
        print("Use your Keycloak credentials to authenticate.")
        
    except requests.exceptions.RequestException as e:
        print(f"\n✗ API Error: {e}", file=sys.stderr)
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response Status: {e.response.status_code}", file=sys.stderr)
            print(f"Response Body: {e.response.text}", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"\n✗ SSL Generation Error: {e}", file=sys.stderr)
        print(f"Output: {e.output.decode() if e.output else 'N/A'}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()