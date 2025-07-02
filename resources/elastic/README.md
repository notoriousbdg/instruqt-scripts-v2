# Elastic Agent Integration for Log Generator

This directory contains the necessary files to integrate Elastic agent with the Log Generator application in Kubernetes.

## Overview

The integration installs Elastic agent on each client container, with dedicated agent policies for:
- MySQL client
- Nginx frontend client
- Nginx backend client

Each client has its own agent policy and integration configuration, allowing for more targeted monitoring.

## Files Structure

```
elastic/
├── agent_policies/                     # Contains agent policy definitions
│   ├── mysql-agent-policy.json         # MySQL-specific agent policy
│   ├── nginx-frontend-agent-policy.json # Nginx frontend-specific agent policy
│   └── nginx-backend-agent-policy.json # Nginx backend-specific agent policy
├── integrations/                       # Contains integration configurations
│   ├── mysql.json                      # MySQL integration config
│   ├── nginx-backend.json              # Nginx backend integration config
│   └── nginx-frontend.json             # Nginx frontend integration config
├── install-elastic-agent.py            # Python script to install elastic agent via API
├── install.sh                          # Shell script to run the Python installer and generate logs
└── README.md                           # This file
```

## Kubernetes Resources

The implementation adds the following Kubernetes resources:

1. `elasticsearch-secret.yaml` - Secret containing Elasticsearch credentials
2. `elastic-agent-configmap.yaml` - ConfigMap containing agent policies and integration configurations
3. `elastic-agents.yaml` - Deployment files that include containers with Elastic agent installation

## How It Works

In this implementation:

1. Each client container (MySQL, Nginx frontend, Nginx backend) runs the `install.sh` script as its main process
2. The script:
   - Installs dependencies
   - Runs the Python installation script specific to the client type
   - Starts generating appropriate log files for the client type
   - Keeps the container running to maintain log generation

3. The Python script:
   - Creates the appropriate agent policy for the client type
   - Installs the integration specific to the client type
   - Installs and enrolls the Elastic agent with the correct policy

4. Each client generates appropriate log entries that the Elastic agent monitors and sends to Elasticsearch

## How to Use

### Prerequisites

1. Elasticsearch and Kibana must be accessible from your Kubernetes cluster
2. The user must have permissions to create agent policies and package policies in Kibana

### Setup Instructions

1. Update the Elasticsearch credentials in `kubernetes/elasticsearch-secret.yaml`
   ```yaml
   stringData:
     ELASTICSEARCH_USER: "your_username"
     ELASTICSEARCH_PASSWORD: "your_password"
     KIBANA_URL: "https://your-kibana-url"
   ```

2. Apply the Kubernetes resources:
   ```bash
   kubectl apply -f kubernetes/elasticsearch-secret.yaml
   kubectl apply -f kubernetes/elastic-agent-configmap.yaml
   kubectl apply -f kubernetes/elastic-agents.yaml
   ```

3. Verify that the pods are running:
   ```bash
   kubectl get pods
   ```

## Customization

- To modify the log paths or other integration settings, update the JSON files in the `integrations` directory
- To add more clients or integrations, create additional agent policies and integration configuration files
- To change the agent policy settings, update the appropriate policy JSON file
- To customize log generation, modify the log generation section in `install.sh`

## Troubleshooting

Check the container logs for issues with the installation:
```bash
kubectl logs <pod-name>
```

Check the Elastic agent logs (if the agent was installed):
```bash
kubectl exec -it <pod-name> -- cat /var/log/elastic-agent/elastic-agent.log
```

To check the status of the installed agent:
```bash
kubectl exec -it <pod-name> -- elastic-agent status
```

## Security Considerations

- Store the Elasticsearch credentials securely in Kubernetes secrets
- Use HTTPS for the Kibana URL
- Consider using more restrictive RBAC permissions for the Elastic agent
- For production, ensure your agent enrollment tokens have appropriate restrictions 