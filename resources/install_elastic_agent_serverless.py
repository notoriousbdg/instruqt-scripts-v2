#!/usr/bin/env python3

import os
import sys
import requests
import json
import glob
import time
import logging
import argparse
import subprocess
import base64
import yaml
from pathlib import Path
from urllib3.exceptions import InsecureRequestWarning

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Suppress only the insecure request warning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

# ANSI color codes for better output
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color

# Parse command-line arguments
def parse_arguments():
    parser = argparse.ArgumentParser(description='Install Elastic Agent policies and integrations in Kubernetes')
    
    # Elasticsearch/Kibana connection settings
    parser.add_argument('--kibana-url', dest='kibana_url', help='Kibana URL')
    parser.add_argument('--elasticsearch-url', dest='elasticsearch_url', help='Elasticsearch URL')
    parser.add_argument('--fleet-url', dest='fleet_url', help='Fleet URL')
    parser.add_argument('--username', dest='username', help='Elasticsearch username')
    parser.add_argument('--password', dest='password', help='Elasticsearch password')
    parser.add_argument('--api-key', dest='api_key', help='Elasticsearch API key (alternative to username/password)')
    
    # Kubernetes settings
    parser.add_argument('--namespace', dest='namespace', default='default', help='Kubernetes namespace')
    parser.add_argument('--image-tag', dest='image_tag', default='latest', help='Docker image tag')
    
    # Operation modes
    parser.add_argument('--client-type', dest='client_type', help='Client type: mysql, nginx-frontend, or nginx-backend')
    parser.add_argument('--verify-ssl', dest='verify_ssl', action='store_true', help='Verify SSL certificates')
    parser.add_argument('--output-token', dest='output_token', action='store_true', help='Only output the enrollment token')
    parser.add_argument('--skip-token-generation', dest='skip_token_generation', action='store_true', help='Skip Elastic enrollment token generation')
    parser.add_argument('--force-skip-token', dest='force_skip_token', action='store_true', help='Force skip token generation on any error')
    parser.add_argument('--debug', dest='debug', action='store_true', help='Enable debug output')
    
    # Paths
    parser.add_argument('--base-dir', dest='base_dir', help='Base directory for config files')
    
    return parser.parse_args()

# Read configuration from environment or command-line arguments
def get_config():
    args = parse_arguments()
    
    config = {
        'kibana_url': args.kibana_url or os.environ.get('KIBANA_URL'),
        'elasticsearch_url': args.elasticsearch_url or os.environ.get('ELASTICSEARCH_URL'),
        'elasticsearch_user': args.username or os.environ.get('ELASTICSEARCH_USER'),
        'elasticsearch_password': args.password or os.environ.get('ELASTICSEARCH_PASSWORD'),
        'elasticsearch_api_key': args.api_key or os.environ.get('ELASTICSEARCH_API_KEY'),
        'fleet_url': args.fleet_url or os.environ.get('FLEET_URL') or args.kibana_url or os.environ.get('KIBANA_URL'),
        'verify_ssl': args.verify_ssl or (os.environ.get('VERIFY_SSL', 'false').lower() == 'true'),
        'max_retries': int(os.environ.get('MAX_RETRIES', '5')),
        'retry_delay': int(os.environ.get('RETRY_DELAY', '10')),
        'client_type': args.client_type or os.environ.get('CLIENT_TYPE', 'all'),
        'namespace': args.namespace or os.environ.get('NAMESPACE', 'default'),
        'output_token': args.output_token,
        'base_dir': args.base_dir or os.path.dirname(os.path.abspath(__file__)),
        'skip_token_generation': args.skip_token_generation,
        'force_skip_token': args.force_skip_token,
        'debug': args.debug,
        'image_tag': args.image_tag or 'latest'
    }
    
    # Check if required configuration is set when generating tokens
    if not config['skip_token_generation']:
        if not config['kibana_url']:
            logger.error("Kibana URL is not set")
            sys.exit(1)
        # Check for either username/password or API key
        if not config['elasticsearch_api_key'] and (not config['elasticsearch_user'] or not config['elasticsearch_password']):
            logger.error("Either Elasticsearch API key or username and password must be set")
            sys.exit(1)
    
    return config

# Global configuration
config = get_config()

HEADERS = {
    'Content-Type': 'application/json',
    'kbn-xsrf': 'true'
}

def debug_log(message):
    """Print debug message if debug mode is enabled."""
    if config['debug']:
        logger.info(f"{YELLOW}[DEBUG] {message}{NC}")

def command_exists(command):
    """Check if a command exists on the system."""
    try:
        subprocess.run(['which', command], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        return True
    except subprocess.CalledProcessError:
        return False

def check_prerequisites():
    """Check if required tools are installed."""
    print(f"\n{BLUE}Checking prerequisites...{NC}")
    
    # Check for kubectl
    if not command_exists('kubectl'):
        print(f"{RED}Error: kubectl is required but not installed. Please install kubectl and try again.{NC}")
        sys.exit(1)
    
    # Check for curl
    if not command_exists('curl'):
        print(f"{RED}Error: curl is required but not installed. Please install curl and try again.{NC}")
        sys.exit(1)
    
    # Check for jq and install if missing
    if not command_exists('jq'):
        print(f"{YELLOW}Warning: jq is not installed. Installing it for JSON processing...{NC}")
        try:
            if command_exists('apt-get'):
                subprocess.run(['sudo', 'apt-get', 'update'], check=True)
                subprocess.run(['sudo', 'apt-get', 'install', '-y', 'jq'], check=True)
            elif command_exists('brew'):
                subprocess.run(['brew', 'install', 'jq'], check=True)
            elif command_exists('yum'):
                subprocess.run(['sudo', 'yum', 'install', '-y', 'jq'], check=True)
            else:
                print(f"{RED}Error: Could not install jq. Please install it manually and try again.{NC}")
                sys.exit(1)
        except subprocess.CalledProcessError as e:
            print(f"{RED}Error installing jq: {str(e)}{NC}")
            sys.exit(1)
    
    # Verify connection to Kubernetes cluster
    print(f"{BLUE}Verifying Kubernetes cluster connection...{NC}")
    try:
        subprocess.run(['kubectl', 'cluster-info'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    except subprocess.CalledProcessError:
        print(f"{RED}Error: Unable to connect to Kubernetes cluster. Please check your kubeconfig.{NC}")
        sys.exit(1)
    
    # Check that deployment file exists
    deployment_file = os.path.join(config['base_dir'], 'kubernetes', 'elastic-agents.yaml')
    if not os.path.exists(deployment_file):
        print(f"{RED}Error: Deployment file not found at {deployment_file}{NC}")
        sys.exit(1)
    
    return True

def create_namespace():
    """Create Kubernetes namespace if it doesn't exist."""
    if config['namespace'] != 'default':
        print(f"\n{BLUE}Creating namespace {config['namespace']} if it doesn't exist...{NC}")
        try:
            result = subprocess.run([
                'kubectl', 'create', 'namespace', config['namespace'],
                '--dry-run=client', '-o', 'yaml'
            ], stdout=subprocess.PIPE, check=True, text=True)
            
            subprocess.run(['kubectl', 'apply', '-f', '-'], input=result.stdout, check=True, text=True)
            print(f"{GREEN}Namespace created or already exists.{NC}")
        except subprocess.CalledProcessError as e:
            print(f"{RED}Error creating namespace: {str(e)}{NC}")
            sys.exit(1)

def deploy_log_generator():
    """Deploy the log-generator from Kubernetes YAML file."""
    print(f"\n{BLUE}Deploying log-generator...{NC}")
    
    # Get log-generator deployment file
    log_generator_file = os.path.join(config['base_dir'], 'kubernetes', 'log-generator.yaml')
    
    if not os.path.exists(log_generator_file):
        print(f"{RED}Error: Log-generator file not found at {log_generator_file}{NC}")
        sys.exit(1)
    
    # Apply the log-generator deployment
    try:
        subprocess.run([
            'kubectl', 'apply', '-f', log_generator_file,
            '--namespace', config['namespace']
        ], check=True)
        print(f"{GREEN}Log-generator deployed successfully.{NC}")
    except subprocess.CalledProcessError as e:
        print(f"{RED}Error deploying log-generator: {str(e)}{NC}")
        sys.exit(1)

def create_elasticsearch_secret():
    """Create or update Elasticsearch credentials secret."""
    print(f"\n{BLUE}Checking for existing Elasticsearch credentials secret...{NC}")
    
    # Check if secret exists and delete it if found
    try:
        result = subprocess.run([
            'kubectl', 'get', 'secret', 'elasticsearch-credentials',
            '-n', config['namespace']
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        if result.returncode == 0:
            print(f"{YELLOW}Found existing secret 'elasticsearch-credentials'. Deleting it...{NC}")
            subprocess.run([
                'kubectl', 'delete', 'secret', 'elasticsearch-credentials',
                '-n', config['namespace']
            ], check=True)
            print(f"{GREEN}Existing secret deleted successfully.{NC}")
        else:
            print(f"{BLUE}No existing secret found. Creating new secret...{NC}")
    except subprocess.CalledProcessError as e:
        print(f"{RED}Error checking for existing secret: {str(e)}{NC}")
    
    # Create new secret
    print(f"\n{BLUE}Creating Elasticsearch credentials secret...{NC}")
    try:
        command = [
            'kubectl', 'create', 'secret', 'generic', 'elasticsearch-credentials',
            '--namespace', config['namespace'],
            '--from-literal=KIBANA_URL=' + config['kibana_url'],
            '--from-literal=ELASTICSEARCH_URL=' + config['elasticsearch_url'],
            '--from-literal=FLEET_URL=' + config['fleet_url'],
        ]
        
        # Add either API key or username/password
        if config['elasticsearch_api_key']:
            command.append('--from-literal=ELASTICSEARCH_API_KEY=' + config['elasticsearch_api_key'])
        else:
            command.append('--from-literal=ELASTICSEARCH_USER=' + config['elasticsearch_user'])
            command.append('--from-literal=ELASTICSEARCH_PASSWORD=' + config['elasticsearch_password'])
            
        command.extend(['--dry-run=client', '-o', 'yaml'])
        
        result = subprocess.run(command, stdout=subprocess.PIPE, check=True, text=True)
        
        subprocess.run(['kubectl', 'apply', '-f', '-'], input=result.stdout, check=True, text=True)
        
        print(f"{GREEN}Secret created successfully.{NC}")
    except subprocess.CalledProcessError as e:
        print(f"{RED}Error creating secret: {str(e)}{NC}")
        sys.exit(1)

def get_auth_headers():
    """Get authentication headers for Elasticsearch API calls."""
    headers = HEADERS.copy()
    
    if config['elasticsearch_api_key']:
        headers['Authorization'] = f"ApiKey {config['elasticsearch_api_key']}"
        return headers, None
    else:
        return headers, (config['elasticsearch_user'], config['elasticsearch_password'])

def wait_for_kibana():
    """No longer needed for serverless deployment, always returns True."""
    print(f"\n{BLUE}Using Elastic serverless deployment - no need to wait for Kibana{NC}")
    return True

def get_agent_policy_id(policy_name):
    """Get the ID of an agent policy by name."""
    print(f"{BLUE}Looking for agent policy '{policy_name}'...{NC}")
    
    headers, auth = get_auth_headers()
    url = f"{config['kibana_url']}/api/fleet/agent_policies"
    
    try:
        if auth:
            response = requests.get(url, headers=headers, auth=auth, verify=config['verify_ssl'])
        else:
            response = requests.get(url, headers=headers, verify=config['verify_ssl'])
            
        if response.status_code != 200:
            print(f"{RED}Error retrieving agent policies: {response.status_code} {response.text}{NC}")
            return None
        
        policies = response.json().get('items', [])
        for policy in policies:
            if policy.get('name') == policy_name:
                print(f"{GREEN}Found agent policy '{policy_name}' with ID: {policy['id']}{NC}")
                return policy['id']
        
        print(f"{YELLOW}Agent policy '{policy_name}' not found{NC}")
        return None
    except Exception as e:
        print(f"{RED}Error retrieving agent policies: {str(e)}{NC}")
        return None

def get_policy_by_client_type(client_type):
    """Get the appropriate policy name based on client type."""
    if client_type == 'mysql':
        return "MySQL Monitoring Policy"
    elif client_type == 'nginx-frontend':
        return "Nginx Frontend Monitoring Policy"
    elif client_type == 'nginx-backend':
        return "Nginx Backend Monitoring Policy"
    else:
        logger.error(f"Unknown client type: {client_type}")
        return None

def create_agent_policies(agent_policies_dir, client_type):
    """Create the agent policies from JSON files."""
    if not os.path.exists(agent_policies_dir):
        print(f"{RED}Agent policies directory not found: {agent_policies_dir}{NC}")
        return None
    
    # Map client type to the correct policy file name
    if client_type == 'mysql':
        policy_file = os.path.join(agent_policies_dir, "mysql-agent-policy.json")
    elif client_type == 'nginx-frontend':
        policy_file = os.path.join(agent_policies_dir, "nginx-frontend-agent-policy.json")
    elif client_type == 'nginx-backend':
        policy_file = os.path.join(agent_policies_dir, "nginx-backend-agent-policy.json")
    else:
        print(f"{RED}Unknown client type: {client_type}{NC}")
        return None
    
    if not os.path.exists(policy_file):
        print(f"{RED}Policy file not found: {policy_file}{NC}")
        return None
    
    print(f"{BLUE}Creating agent policy from {policy_file}...{NC}")
    
    try:
        with open(policy_file, 'r') as f:
            policy_data = json.load(f)
        
        # Check if policy already exists
        policy_id = get_agent_policy_id(policy_data['name'])
        if policy_id:
            print(f"{YELLOW}Agent policy '{policy_data['name']}' already exists with ID: {policy_id}{NC}")
            return policy_id
        
        headers, auth = get_auth_headers()
        url = f"{config['kibana_url']}/api/fleet/agent_policies"
        
        if auth:
            response = requests.post(url, headers=headers, auth=auth, json=policy_data, verify=config['verify_ssl'])
        else:
            response = requests.post(url, headers=headers, json=policy_data, verify=config['verify_ssl'])
            
        if response.status_code != 200:
            print(f"{RED}Error creating agent policy: {response.status_code} {response.text}{NC}")
            return None
        
        policy_id = response.json().get('item', {}).get('id')
        if policy_id:
            print(f"{GREEN}Created agent policy '{policy_data['name']}' with ID: {policy_id}{NC}")
            return policy_id
        else:
            print(f"{RED}Failed to create agent policy: Response did not contain a policy ID{NC}")
            return None
    except Exception as e:
        print(f"{RED}Error creating agent policy: {str(e)}{NC}")
        return None

def install_integration(integrations_dir, client_type):
    """Install the integration for the specified client type."""
    if not os.path.exists(integrations_dir):
        print(f"{RED}Integrations directory not found: {integrations_dir}{NC}")
        return False
    
    # Map client type to integration file name
    if client_type == 'mysql':
        integration_file = os.path.join(integrations_dir, "mysql.json")
    elif client_type == 'nginx-frontend':
        integration_file = os.path.join(integrations_dir, "nginx-frontend.json")
    elif client_type == 'nginx-backend':
        integration_file = os.path.join(integrations_dir, "nginx-backend.json")
    else:
        print(f"{RED}Unknown client type: {client_type}{NC}")
        return False
    
    if not os.path.exists(integration_file):
        print(f"{RED}Integration file not found: {integration_file}{NC}")
        return False
    
    # Get the agent policy ID (get the policy name first, then get its ID)
    policy_name = get_policy_by_client_type(client_type)
    if not policy_name:
        print(f"{RED}Failed to get agent policy name for client type: {client_type}{NC}")
        return False
        
    policy_id = get_agent_policy_id(policy_name)
    if not policy_id:
        print(f"{RED}Failed to get agent policy ID for policy name: {policy_name}{NC}")
        return False
    
    print(f"{BLUE}Installing integration from {integration_file} to policy ID {policy_id}...{NC}")
    
    try:
        # Load the integration configuration from the JSON file
        with open(integration_file, 'r') as f:
            integration_config = json.load(f)
        
        # Get agent policy name from the config
        agent_policy_name = integration_config.get('agent_policy_name')
        if not agent_policy_name:
            print(f"{RED}No 'agent_policy_name' specified in {integration_file}{NC}")
            return False

        # Create package policy
        package_policy = integration_config.get('package_policy')
        if not package_policy:
            print(f"{RED}No 'package_policy' specified in {integration_file}{NC}")
            return False

        # Add the policy ID to the package policy
        package_policy_payload = package_policy.copy()
        package_policy_payload['policy_id'] = policy_id
        
        headers, auth = get_auth_headers()
        url = f"{config['kibana_url']}/api/fleet/package_policies"
        
        if auth:
            response = requests.post(url, headers=headers, auth=auth, json=package_policy_payload, verify=config['verify_ssl'])
        else:
            response = requests.post(url, headers=headers, json=package_policy_payload, verify=config['verify_ssl'])
            
        if response.status_code != 200:
            print(f"{RED}Error installing integration: {response.status_code} {response.text}{NC}")
            return False
        
        print(f"{GREEN}Integration installed successfully!{NC}")
        return True
    except Exception as e:
        print(f"{RED}Error installing integration: {str(e)}{NC}")
        return False

def generate_enrollment_token(client_type):
    """Generate an enrollment token for a specific client type."""
    # Get the agent policy ID (get the policy name first, then get its ID)
    policy_name = get_policy_by_client_type(client_type)
    if not policy_name:
        logger.error(f"Failed to get agent policy name for client type: {client_type}")
        if config['force_skip_token']:
            return None
        sys.exit(1)
    
    policy_id = get_agent_policy_id(policy_name)
    if not policy_id:
        logger.error(f"Failed to get agent policy ID for policy name: {policy_name}")
        if config['force_skip_token']:
            return None
        sys.exit(1)
    
    logger.info(f"Generating enrollment token for policy ID: {policy_id}")
    
    headers, auth = get_auth_headers()
    url = f"{config['kibana_url']}/api/fleet/enrollment_api_keys"
    
    try:
        # 1. First get the list of existing tokens to check if one exists for this policy
        if auth:
            response = requests.get(url, headers=headers, auth=auth, verify=config['verify_ssl'])
        else:
            response = requests.get(url, headers=headers, verify=config['verify_ssl'])
            
        if response.status_code != 200:
            logger.error(f"Error retrieving enrollment tokens: {response.status_code} {response.text}")
            if config['force_skip_token']:
                return None
            sys.exit(1)
        
        # Check for existing token
        existing_tokens = response.json().get('list', [])
        for token in existing_tokens:
            if token.get('policy_id') == policy_id:
                logger.info(f"Found existing enrollment token for policy ID {policy_id}")
                return token.get('api_key')
        
        # 2. Create a new token if one doesn't exist
        create_data = {"policy_id": policy_id}
        if auth:
            response = requests.post(url, headers=headers, auth=auth, json=create_data, verify=config['verify_ssl'])
        else:
            response = requests.post(url, headers=headers, json=create_data, verify=config['verify_ssl'])
            
        if response.status_code != 200:
            logger.error(f"Error creating enrollment token: {response.status_code} {response.text}")
            if config['force_skip_token']:
                return None
            sys.exit(1)
        
        api_key = response.json().get('item', {}).get('api_key')
        if not api_key:
            logger.error("API key not found in response")
            if config['force_skip_token']:
                return None
            sys.exit(1)
        
        logger.info(f"Successfully generated enrollment token for policy ID: {policy_id}")
        return api_key
    except Exception as e:
        logger.error(f"Error generating enrollment token: {str(e)}")
        if config['force_skip_token']:
            return None
        sys.exit(1)

def create_enrollment_tokens_configmap():
    """Generate tokens for each client type and store in a ConfigMap."""
    if config['skip_token_generation']:
        print(f"{YELLOW}Skipping enrollment token generation as requested.{NC}")
        return True
    
    print(f"\n{BLUE}Setting up Elastic Agent policies and generating enrollment tokens...{NC}")
    
    # Initialize token variables with placeholders
    mysql_token = "EXAMPLE_MYSQL_TOKEN_PLACEHOLDER"
    nginx_frontend_token = "EXAMPLE_NGINX_FRONTEND_TOKEN_PLACEHOLDER"
    nginx_backend_token = "EXAMPLE_NGINX_BACKEND_TOKEN_PLACEHOLDER"
    
    # Generate tokens if Kibana is available
    if wait_for_kibana():
        # Set paths
        agent_policies_dir = os.path.join(config['base_dir'], 'elastic', 'agent_policies')
        integrations_dir = os.path.join(config['base_dir'], 'elastic', 'integrations')
        
        # Create MySQL policy and token
        client_type = 'mysql'
        create_agent_policies(agent_policies_dir, client_type)
        install_integration(integrations_dir, client_type)
        token = generate_enrollment_token(client_type)
        if token:
            mysql_token = token
            print(f"{GREEN}Successfully generated MySQL enrollment token{NC}")
        else:
            print(f"{RED}Failed to generate MySQL enrollment token{NC}")
            if config['force_skip_token']:
                print(f"{YELLOW}Force skip token enabled. Using placeholder token.{NC}")
            else:
                return False
        
        # Create Nginx Frontend policy and token
        client_type = 'nginx-frontend'
        create_agent_policies(agent_policies_dir, client_type)
        install_integration(integrations_dir, client_type)
        token = generate_enrollment_token(client_type)
        if token:
            nginx_frontend_token = token
            print(f"{GREEN}Successfully generated Nginx Frontend enrollment token{NC}")
        else:
            print(f"{RED}Failed to generate Nginx Frontend enrollment token{NC}")
            if config['force_skip_token']:
                print(f"{YELLOW}Force skip token enabled. Using placeholder token.{NC}")
            else:
                return False
        
        # Create Nginx Backend policy and token
        client_type = 'nginx-backend'
        create_agent_policies(agent_policies_dir, client_type)
        install_integration(integrations_dir, client_type)
        token = generate_enrollment_token(client_type)
        if token:
            nginx_backend_token = token
            print(f"{GREEN}Successfully generated Nginx Backend enrollment token{NC}")
        else:
            print(f"{RED}Failed to generate Nginx Backend enrollment token{NC}")
            if config['force_skip_token']:
                print(f"{YELLOW}Force skip token enabled. Using placeholder token.{NC}")
            else:
                return False
    else:
        if config['force_skip_token']:
            print(f"{YELLOW}Force skip token enabled. Using placeholder tokens.{NC}")
        else:
            return False
    
    # Check if enrollment tokens ConfigMap exists and delete it
    print(f"\n{BLUE}Checking for existing enrollment tokens ConfigMap...{NC}")
    try:
        result = subprocess.run([
            'kubectl', 'get', 'configmap', 'enrollment-tokens',
            '-n', config['namespace']
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        if result.returncode == 0:
            print(f"{YELLOW}Found existing ConfigMap 'enrollment-tokens'. Deleting it...{NC}")
            subprocess.run([
                'kubectl', 'delete', 'configmap', 'enrollment-tokens',
                '-n', config['namespace']
            ], check=True)
            print(f"{GREEN}Existing ConfigMap deleted successfully.{NC}")
    except subprocess.CalledProcessError as e:
        print(f"{RED}Error checking for existing ConfigMap: {str(e)}{NC}")
    
    # Create ConfigMap with enrollment tokens
    print(f"\n{BLUE}Creating enrollment tokens ConfigMap...{NC}")
    try:
        result = subprocess.run([
            'kubectl', 'create', 'configmap', 'enrollment-tokens',
            '--namespace', config['namespace'],
            '--from-literal=mysql-enrollment-token=' + mysql_token,
            '--from-literal=nginx-frontend-enrollment-token=' + nginx_frontend_token,
            '--from-literal=nginx-backend-enrollment-token=' + nginx_backend_token,
            '--dry-run=client', '-o', 'yaml'
        ], stdout=subprocess.PIPE, check=True, text=True)
        
        subprocess.run(['kubectl', 'apply', '-f', '-'], input=result.stdout, check=True, text=True)
        
        print(f"{GREEN}Enrollment tokens ConfigMap created successfully.{NC}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"{RED}Error creating ConfigMap: {str(e)}{NC}")
        sys.exit(1)

def deploy_log_clients():
    """Deploy log clients from Kubernetes YAML files."""
    print(f"\n{BLUE}Deploying log clients...{NC}")
    
    # Get deployment file
    deployment_file = os.path.join(config['base_dir'], 'kubernetes', 'elastic-agents.yaml')
    
    # Update image tag if needed
    if config['image_tag'] != 'latest':
        print(f"\n{BLUE}Updating image tag to {config['image_tag']} in deployment...{NC}")
        try:
            # Read the deployment file
            with open(deployment_file, 'r') as f:
                deployment_yaml = f.read()
            
            # Replace the image tag
            updated_yaml = deployment_yaml.replace('djhope99/log-generator-v2:latest', f"djhope99/log-generator-v2:{config['image_tag']}")
            
            # Create temporary file for the updated YAML
            temp_file = os.path.join(os.path.dirname(deployment_file), 'temp_deployment.yaml')
            with open(temp_file, 'w') as f:
                f.write(updated_yaml)
            
            deployment_file = temp_file
        except Exception as e:
            print(f"{RED}Error updating image tag: {str(e)}{NC}")
            sys.exit(1)
    
    # Apply the deployment
    try:
        subprocess.run([
            'kubectl', 'apply', '-f', deployment_file,
            '--namespace', config['namespace']
        ], check=True)
        print(f"{GREEN}Log clients deployed successfully.{NC}")
        
        # Clean up temporary file if created
        if config['image_tag'] != 'latest':
            os.remove(deployment_file)
    except subprocess.CalledProcessError as e:
        print(f"{RED}Error deploying log clients: {str(e)}{NC}")
        sys.exit(1)

def verify_deployment():
    """Verify the deployment status."""
    print(f"\n{BLUE}Verifying deployment...{NC}")
    try:
        subprocess.run([
            'kubectl', 'get', 'deployments',
            '--namespace', config['namespace'],
            '-l', 'app in (mysql-log-client,nginx-backend-log-client,nginx-frontend-log-client)'
        ], check=True)
    except subprocess.CalledProcessError as e:
        print(f"{RED}Error verifying deployment: {str(e)}{NC}")
    
    # Wait for pods to be ready
    print(f"\n{BLUE}Waiting for pods to be ready...{NC}")
    try:
        subprocess.run([
            'kubectl', 'wait', '--for=condition=ready', 'pod',
            '--selector=app in (mysql-log-client,nginx-backend-log-client,nginx-frontend-log-client)',
            '--timeout=300s',
            '--namespace', config['namespace']
        ], check=True)
        print(f"{GREEN}All pods are ready!{NC}")
    except subprocess.CalledProcessError:
        print(f"{YELLOW}Warning: Not all pods are ready after 5 minutes.{NC}")
        print(f"{YELLOW}Check the status of your pods with:{NC}")
        print(f"{YELLOW}kubectl get pods -n {config['namespace']}{NC}")

def display_completion_message():
    """Display a completion message with next steps."""
    print(f"\n{GREEN}Installation complete!{NC}")
    print(f"\n{BLUE}To check the logs of your pods, use these commands:{NC}")
    print(f"kubectl logs -n {config['namespace']} -l app=mysql-log-client -c mysql-log-generator")
    print(f"kubectl logs -n {config['namespace']} -l app=nginx-backend-log-client -c nginx-backend-log-generator")
    print(f"kubectl logs -n {config['namespace']} -l app=nginx-frontend-log-client -c nginx-frontend-log-generator")

    print(f"\n{BLUE}To check the Elastic Agent logs:{NC}")
    print(f"kubectl logs -n {config['namespace']} -l app=mysql-log-client -c elastic-agent")
    print(f"kubectl logs -n {config['namespace']} -l app=nginx-backend-log-client -c elastic-agent")
    print(f"kubectl logs -n {config['namespace']} -l app=nginx-frontend-log-client -c elastic-agent")

    print(f"\n{BLUE}To access your Elastic stack:{NC}")
    print(f"Kibana URL: {config['kibana_url']}")
    print(f"Elasticsearch URL: {config['elasticsearch_url']}")
    print(f"Username: {config['elasticsearch_user']}")
    print(f"\n{GREEN}Thank you for using the Log Generator with Elastic Agent Integration!{NC}")

def main():
    """Main function to execute the Kubernetes installation process."""
    # Check for required tools and connections
    check_prerequisites()
    
    # Create namespace if needed
    create_namespace()
    
    # Deploy log-generator
    deploy_log_generator()
    
    # Create Elasticsearch credentials secret
    create_elasticsearch_secret()
    
    # Generate enrollment tokens and create ConfigMap
    create_enrollment_tokens_configmap()
    
    # Deploy log clients
    deploy_log_clients()
    
    # Verify deployment
    verify_deployment()
    
    # Display completion message
    display_completion_message()

if __name__ == "__main__":
    # If only outputting a token, handle that special case
    if config['output_token']:
        if not config['client_type'] or config['client_type'] == 'all':
            print(f"{RED}Error: --client-type must be specified when using --output-token{NC}")
            sys.exit(1)
        
        # Generate enrollment token (no need to wait for Kibana in serverless)
        enrollment_token = generate_enrollment_token(config['client_type'])
        if enrollment_token:
            print(enrollment_token)  # Print only the token for scripting
            sys.exit(0)
    else:
        # Run the full installation
        main() 