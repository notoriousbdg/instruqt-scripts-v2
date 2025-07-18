import os
import requests
from pathlib import Path

INDICES_RESOURCES_PATH = "context/indices"
KNOWLEDGE_RESOURCES_PATH = "context/knowledge"

TIMEOUT = 10


def load_knowledge():
    for file in os.listdir(KNOWLEDGE_RESOURCES_PATH):
        if file.endswith(".json"):
            with open(
                os.path.join(KNOWLEDGE_RESOURCES_PATH, file), "rt", encoding="utf8"
            ) as f:
                body = f.read()
                filename = Path(file).stem
                resp = requests.put(
                    f"{os.environ['ELASTICSEARCH_URL']}/kibana-observability-ai-assistant-kb-000001/_doc/${filename}",
                    data=body,
                    timeout=TIMEOUT,
                    auth=(
                        os.environ["ELASTICSEARCH_USER"],
                        os.environ["ELASTICSEARCH_PASSWORD"],
                    ),
                    headers={"Content-Type": "application/json"},
                )
                print(f"loading knowledge {filename}: {resp.json()}")


def load():
    load_knowledge()
