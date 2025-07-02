import os
import requests
import json

# Elasticsearch connection details from environment variables
ELASTICSEARCH_URL = os.environ['ELASTICSEARCH_URL']
HEADERS = {'Content-Type': 'application/json'}

def create_custom_default_mode_template():
    """Create the custom_default_mode index template."""
    
    template_config = {
        "index_patterns": ["*"],
        "priority": 500,
        "template": {
            "settings": {
                "index.mode": "lookup"
            }
        }
    }
    
    template_name = "custom_default_mode"
    template_url = f"{ELASTICSEARCH_URL}/_index_template/{template_name}"
    
    response = requests.put(
        template_url,
        headers=HEADERS,
        auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']),
        json=template_config
    )
    
    if response.status_code not in [200, 201]:
        print(f"Failed to create index template {template_name}: {response.status_code} - {response.text}")
        return False
    
    print(f"Index template {template_name} created successfully.")
    return True

def load():
    """Load the index template."""
    return create_custom_default_mode_template()

if __name__ == "__main__":
    load() 