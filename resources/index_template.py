import os
import requests
import json

# Elasticsearch connection details from environment variables
ELASTICSEARCH_URL = os.environ['ELASTICSEARCH_URL']
HEADERS = {'Content-Type': 'application/json'}

def create_component_templates():
    """Create component templates for different log types."""
    
    # Component templates for different log types
    component_templates = {
        "logs-mysql.error@custom": {
            "template": {
                "settings": {
                    "index": {
                        "mode": "lookup"
                    }
                }
            }
        },
        "logs-mysql.slowlog@custom": {
            "template": {
                "settings": {
                    "index": {
                        "mode": "lookup"
                    }
                }
            }
        },
        "logs-nginx.access@custom": {
            "template": {
                "settings": {
                    "index": {
                        "mode": "lookup"
                    }
                }
            }
        },
        "logs-nginx.error@custom": {
            "template": {
                "settings": {
                    "index": {
                        "mode": "lookup"
                    }
                }
            }
        }
    }
    
    success_count = 0
    
    for template_name, template_config in component_templates.items():
        template_url = f"{ELASTICSEARCH_URL}/_component_template/{template_name}"
        
        response = requests.put(
            template_url,
            headers=HEADERS,
            auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']),
            json=template_config
        )
        
        if response.status_code not in [200, 201]:
            print(f"Failed to create component template {template_name}: {response.status_code} - {response.text}")
        else:
            print(f"Component template {template_name} created successfully.")
            success_count += 1
    
    return success_count == len(component_templates)

def load():
    """Load the component templates."""
    return create_component_templates()

if __name__ == "__main__":
    load() 