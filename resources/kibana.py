import os
import requests
import json

KIBANA_RESOURCES_PATH = 'kibana'
ALERTS_RESOURCES_PATH = 'alerts'
TIMEOUT = 10

def load():
    for file in os.listdir(KIBANA_RESOURCES_PATH):
        if file.endswith(".ndjson"):
            with open(os.path.join(KIBANA_RESOURCES_PATH, file), "rt", encoding='utf8') as f:
                dashboards = f.read()
                resp = requests.post(
                    f"{os.environ['KIBANA_URL']}/api/saved_objects/_import",
                    files={"file": ("export.ndjson", dashboards)},
                    timeout=TIMEOUT,
                    auth=(
                        os.environ['ELASTICSEARCH_USER'],
                        os.environ['ELASTICSEARCH_PASSWORD']
                    ),
                    headers={"kbn-xsrf": "reporting"},
                    params={'compatibilityMode': True, 'overwrite': True}
                )
                print(resp.json())

def create_alerts():
    for file in os.listdir(ALERTS_RESOURCES_PATH):
        if file.endswith(".json"):
            with open(os.path.join(ALERTS_RESOURCES_PATH, file), "rt", encoding='utf8') as f:
                alert_data = json.load(f)
                resp = requests.post(
                    f"{os.environ['KIBANA_URL']}/api/alerting/rule",
                    json=alert_data,
                    timeout=TIMEOUT,
                    auth=(
                        os.environ['ELASTICSEARCH_USER'],
                        os.environ['ELASTICSEARCH_PASSWORD']
                    ),
                    headers={
                        "kbn-xsrf": "reporting",
                        "Content-Type": "application/json"
                    }
                )
                print(resp.json())

if __name__ == "__main__":
    load()
    create_alerts()




                