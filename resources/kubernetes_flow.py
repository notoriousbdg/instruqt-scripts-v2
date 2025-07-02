import requests
import os
from datetime import datetime
import subprocess
import yaml
import time

TIMEOUT = 360

def log_message(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open('log.txt', 'a') as f:
        f.write(f"[{timestamp}] {message}\n")

def run_command(command, shell=False):
    log_message(f"Running command: {command}")
    try:
        result = subprocess.run(
            command if shell else command.split(),
            capture_output=True,
            text=True,
            shell=shell
        )
        log_message(f"Command output: {result.stdout}")
        if result.stderr:
            log_message(f"Command error: {result.stderr}")
        return result
    except Exception as e:
        log_message(f"Command failed: {str(e)}")
        raise

def get_kubernetes_flow():
    log_message("Starting Kubernetes flow request")
    
    try:
        headers = {
            'accept': '*/*',
            'content-type': 'application/json',
            'kbn-xsrf': 'true',
            'X-Elastic-Internal-Origin': 'Kibana'
        }

        data = {
            "pkgName": "kubernetes_otel"
        }

        response = requests.post(
            f"{os.environ['KIBANA_URL']}/internal/observability_onboarding/kubernetes/flow",
            json=data,
            timeout=TIMEOUT,
            auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']),
            headers=headers
        )
        
        log_message(f"Kubernetes flow response status: {response.status_code}")
        return response.json()

    except Exception as e:
        log_message(f"Error occurred: {str(e)}")
        raise

def setup_kubernetes(flow_response):
    # Add helm repository
    run_command("helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update")
    
    # Create namespace
    run_command("kubectl create namespace opentelemetry-operator-system")
    
    # Create secret
    secret_cmd = f"""kubectl create secret generic elastic-secret-otel \
        --namespace opentelemetry-operator-system \
        --from-literal=elastic_endpoint='{flow_response["elasticsearchUrl"]}' \
        --from-literal=elastic_api_key='{flow_response["apiKeyEncoded"]}'"""
    run_command(secret_cmd, shell=True)
    
    # Install helm chart
    helm_cmd = """helm install opentelemetry-kube-stack open-telemetry/opentelemetry-kube-stack \
        --namespace opentelemetry-operator-system \
        --values 'https://raw.githubusercontent.com/elastic/opentelemetry/refs/heads/8.16/resources/kubernetes/operator/helm/values.yaml' \
        --version '0.3.3'"""
    run_command(helm_cmd, shell=True)



def annotate_namespace():
    cmd = """kubectl annotate namespace default \
        instrumentation.opentelemetry.io/inject-nodejs="opentelemetry-operator-system/elastic-instrumentation\""""
    run_command(cmd, shell=True)

def main():
    # Get flow response
    flow_response = get_kubernetes_flow()
    log_message(f"Received flow response: {flow_response}")
    
    # Setup Kubernetes
    setup_kubernetes(flow_response)
    
    # Wait for resources to be ready
    time.sleep(30)

    # Annotate default namespace
    annotate_namespace()
    
    log_message("Setup complete!")
    
    print("""
Next steps:
1. Review and modify deployment.yaml as needed
2. Apply the deployment: kubectl apply -f deployment.yaml
3. After applying, you can:
   - Check pod status: kubectl get pods
   - Describe pod: kubectl describe pod <pod-name>
   - View logs: kubectl logs <pod-name>
""")

if __name__ == "__main__":
    main() 
