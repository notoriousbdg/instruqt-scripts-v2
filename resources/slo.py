import requests
import os
import json

TIMEOUT = 10
SLO_RESOURCES_PATH = 'slo'

def load():
    new_slo_ids = []
    slo_files = [file for file in os.listdir(SLO_RESOURCES_PATH) if file.endswith(".json")]

    for file in slo_files:
        with open(os.path.join(SLO_RESOURCES_PATH, file), "r", encoding='utf8') as f:
            body = f.read()
            resp = requests.post(
                f"{os.environ['KIBANA_URL']}/api/observability/slos",
                data=body,
                timeout=TIMEOUT,
                auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']),
                headers={"kbn-xsrf": "reporting", "Content-Type": "application/json"}
            )
            resp_json = resp.json()
            print(resp_json)
            new_slo_id = resp_json['id']
            new_slo_ids.append(new_slo_id)

    # Update the dashboard file with new SLO IDs
    update_dashboard_slo_ids(new_slo_ids)

    # Update the alert files with new SLO IDs
    update_alert_files(new_slo_ids)

def update_dashboard_slo_ids(new_slo_ids):
    dashboard_path = 'kibana/dashboards.ndjson'
    with open(dashboard_path, 'r', encoding='utf8') as f:
        dashboard_lines = f.readlines()

    updated_lines = []
    slo_id_index = 0

    for line in dashboard_lines:
        data = json.loads(line)
        if data.get('attributes') and data['attributes'].get('panelsJSON'):
            panels = json.loads(data['attributes']['panelsJSON'])
            for panel in panels:
                embeddableConfig = panel.get('embeddableConfig', {})
                if 'sloId' in embeddableConfig:
                    if slo_id_index < len(new_slo_ids):
                        old_slo_id = embeddableConfig['sloId']
                        new_slo_id = new_slo_ids[slo_id_index]
                        embeddableConfig['sloId'] = new_slo_id
                        slo_id_index += 1
                        print(f"Replaced SLO ID {old_slo_id} with {new_slo_id} in dashboard")
                    else:
                        print("Warning: Not enough new SLO IDs to replace all existing ones")
            # Update the panelsJSON with the modified panels
            data['attributes']['panelsJSON'] = json.dumps(panels)

        updated_line = json.dumps(data)
        updated_lines.append(updated_line)

    # Write back the updated dashboard
    with open(dashboard_path, 'w', encoding='utf8') as f:
        f.writelines(line + '\n' for line in updated_lines)

def update_alert_files(new_slo_ids):
    ALERTS_RESOURCES_PATH = 'alerts'

    # Map alert filenames to indices in new_slo_ids
    alert_files = [
        ('backend_slo_alert.json', 0),
        ('frontend_slo_alert.json', 1),
        ('mysql_slo_alert.json', 2),
    ]

    for alert_file, index in alert_files:
        if index < len(new_slo_ids):
            alert_file_path = os.path.join(ALERTS_RESOURCES_PATH, alert_file)
            if os.path.exists(alert_file_path):
                with open(alert_file_path, 'r', encoding='utf8') as f:
                    alert_data = json.load(f)
                # Replace SLO ID in alert data
                old_slo_id = alert_data.get('params', {}).get('sloId')
                new_slo_id = new_slo_ids[index]
                alert_data['params']['sloId'] = new_slo_id
                # Write updated alert data back to file
                with open(alert_file_path, 'w', encoding='utf8') as f:
                    json.dump(alert_data, f, indent=2)
                print(f"Replaced SLO ID {old_slo_id} with {new_slo_id} in {alert_file}")
            else:
                print(f"Alert file {alert_file} does not exist.")
        else:
            print(f"No new SLO ID available for {alert_file}")

if __name__ == "__main__":
    load()
