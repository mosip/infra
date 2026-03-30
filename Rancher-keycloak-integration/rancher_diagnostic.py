#!/usr/bin/env python3
"""
Rancher API Diagnostic Tool
Helps identify the correct endpoints for SAML configuration
"""

import requests
import json
import os
import sys
from dotenv import load_dotenv
load_dotenv()

# HTTP request timeout in seconds
REQUEST_TIMEOUT = 30

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

def get_headers(token):
    """Get authorization headers"""
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

def explore_api(host, token):
    """Explore Rancher API endpoints"""
    headers = get_headers(token)
    
    print("=== Rancher API Diagnostic Tool ===\n")
    print(f"Rancher Host: {host}\n")
    
    # Test basic connectivity
    print("1. Testing API connectivity...")
    try:
        response = requests.get(f"{host}/v3", headers=headers, timeout=REQUEST_TIMEOUT)
        if response.status_code == 200:
            print("   ✓ API is accessible\n")
        else:
            print(f"   ✗ API returned status code: {response.status_code}\n")
            return
    except Exception as e:
        print(f"   ✗ Cannot connect to API: {e}\n")
        return
    
    # List all auth configs
    print("2. Listing authentication configurations...")
    try:
        response = requests.get(f"{host}/v3/authConfigs", headers=headers, timeout=REQUEST_TIMEOUT)
        if response.status_code == 200:
            data = response.json()
            if 'data' in data and len(data['data']) > 0:
                print("   Available auth providers:")
                for config in data['data']:
                    enabled = "✓" if config.get('enabled', False) else "○"
                    print(f"   {enabled} ID: {config.get('id')}")
                    print(f"      Type: {config.get('type')}")
                    print(f"      Name: {config.get('name', 'N/A')}")
                    print(f"      Enabled: {config.get('enabled', False)}")
                    print()
            else:
                print("   No auth providers configured yet\n")
        else:
            print(f"   ✗ Failed to list auth configs: {response.status_code}\n")
    except Exception as e:
        print(f"   ✗ Error: {e}\n")
    
    # Check for SAML-related endpoints
    print("3. Testing SAML-related endpoints...")
    saml_endpoints = [
        "/v3/samlConfig",
        "/v3/keycloaksamlConfig",
        "/v3/keycloakSamlConfig",
        "/v3/authConfigs/keycloaksaml",
        "/v3/authConfigs/saml",
    ]
    
    for endpoint in saml_endpoints:
        url = f"{host}{endpoint}"
        try:
            response = requests.get(url, headers=headers, timeout=REQUEST_TIMEOUT)
            if response.status_code == 200:
                print(f"   ✓ {endpoint} - Available")
                data = response.json()
                if 'type' in data:
                    print(f"      Type: {data['type']}")
                if 'enabled' in data:
                    print(f"      Enabled: {data['enabled']}")
            elif response.status_code == 404:
                print(f"   ○ {endpoint} - Not found")
            else:
                print(f"   ? {endpoint} - Status: {response.status_code}")
        except Exception as e:
            print(f"   ✗ {endpoint} - Error: {e}")
    
    print()
    
    # List available schemas
    print("4. Checking available authentication schemas...")
    try:
        response = requests.get(f"{host}/v3/schemas", headers=headers, timeout=REQUEST_TIMEOUT)
        if response.status_code == 200:
            schemas = response.json()
            if 'data' in schemas:
                saml_schemas = [s for s in schemas['data'] if 'saml' in s.get('id', '').lower()]
                if saml_schemas:
                    print("   SAML-related schemas found:")
                    for schema in saml_schemas:
                        print(f"   - {schema.get('id')} ({schema.get('type')})")
                else:
                    print("   No SAML schemas found")
                
                # Also check for keycloak schemas
                keycloak_schemas = [s for s in schemas['data'] if 'keycloak' in s.get('id', '').lower()]
                if keycloak_schemas:
                    print("\n   Keycloak-related schemas found:")
                    for schema in keycloak_schemas:
                        print(f"   - {schema.get('id')} ({schema.get('type')})")
    except Exception as e:
        print(f"   ✗ Error: {e}")
    
    print("\n")
    
    # Get Rancher version
    print("5. Rancher version information...")
    try:
        response = requests.get(f"{host}/v3/settings/server-version", headers=headers, timeout=REQUEST_TIMEOUT)
        if response.status_code == 200:
            version_data = response.json()
            print(f"   Server Version: {version_data.get('value', 'Unknown')}")
        
        response = requests.get(f"{host}/v3/settings/server-url", headers=headers, timeout=REQUEST_TIMEOUT)
        if response.status_code == 200:
            url_data = response.json()
            print(f"   Server URL: {url_data.get('value', 'Unknown')}")
    except Exception as e:
        print(f"   ✗ Error: {e}")
    
    print("\n")
    
    # Provide recommendations
    print("=== Recommendations ===")
    print("\nBased on the Rancher API exploration, try one of these approaches:\n")
    print("1. If you see 'keycloaksamlConfig' in available schemas:")
    print("   Use: POST/PUT to /v3/keycloaksamlConfig")
    print()
    print("2. If you see 'samlConfig' in available schemas:")
    print("   Use: POST/PUT to /v3/samlConfig")
    print()
    print("3. For Rancher 2.6+, the typical endpoint is:")
    print("   POST to /v3/keycloaksamlConfig (for initial setup)")
    print("   PUT to /v3/keycloaksamlConfig/keycloaksaml (for updates)")
    print()
    print("4. Check Rancher UI at: Authentication -> Configure Keycloak (SAML)")
    print("   and inspect network requests to see the actual endpoint used")
    print()

def export_full_api_info(host, token, output_file="rancher_api_info.json"):
    """Export full API information for debugging"""
    headers = get_headers(token)
    
    api_info = {
        "host": host,
        "endpoints": {}
    }
    
    endpoints = [
        "/v3",
        "/v3/authConfigs",
        "/v3/schemas"
    ]
    
    for endpoint in endpoints:
        try:
            response = requests.get(f"{host}{endpoint}", headers=headers, timeout=REQUEST_TIMEOUT)
            if response.status_code == 200:
                api_info["endpoints"][endpoint] = response.json()
        except requests.exceptions.RequestException as e:
            print(f"  Warning: Failed to fetch {endpoint}: {e}")
        except (json.JSONDecodeError, ValueError) as e:
            print(f"  Warning: Failed to parse JSON from {endpoint}: {e}")
    
    with open(output_file, 'w') as f:
        json.dump(api_info, f, indent=2)
    
    print(f"Full API information exported to: {output_file}")

def main():
    try:
        config = get_rancher_config()
        
        explore_api(config["host"], config["token"])
        
        # Auto-export in non-interactive mode (CI/CD), prompt in interactive mode
        import sys
        if sys.stdin.isatty():
            print("\nWould you like to export full API info for debugging? (y/n): ", end="")
            response = input().strip().lower()
        else:
            response = 'y'  # Auto-export in non-interactive mode
        if response == 'y':
            export_full_api_info(config["host"], config["token"])
        
    except ValueError as e:
        print(f"Error: {e}")
        print("\nUsage:")
        print("  export RANCHER_HOST=https://rancher.example.com")
        print("  export RANCHER_TOKEN=token-xxxxx:xxxxxxxx")
        print("  python3 rancher_diagnostic.py")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\nDiagnostic cancelled by user")
        sys.exit(0)
    except Exception as e:
        print(f"\nUnexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
