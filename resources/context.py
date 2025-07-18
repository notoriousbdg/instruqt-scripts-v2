import os
import requests
from pathlib import Path
import re

INDICES_RESOURCES_PATH = "context/indices"
KNOWLEDGE_RESOURCES_PATH = "context/knowledge"

TIMEOUT = 10


def get_latest_kb_index():
    """
    Query Elasticsearch for all indices matching the assistant KB pattern,
    and return the one with the highest numeric suffix.
    """
    es_url = os.environ["ELASTICSEARCH_URL"]
    auth = (
        os.environ["ELASTICSEARCH_USER"],
        os.environ["ELASTICSEARCH_PASSWORD"],
    )
    # Use _cat/indices API to get all matching indices, sorted descending
    resp = requests.get(
        f"{es_url}/_cat/indices/.kibana-observability-ai-assistant-kb-*?h=index&s=index:desc",
        timeout=TIMEOUT,
        auth=auth,
    )
    resp.raise_for_status()
    indices = [line.strip() for line in resp.text.splitlines() if line.strip()]
    # Extract numeric suffix and find the highest
    pattern = re.compile(r"^\.kibana-observability-ai-assistant-kb-(\d+)$")
    max_index = None
    max_num = -1
    for idx in indices:
        m = pattern.match(idx)
        if m:
            num = int(m.group(1))
            if num > max_num:
                max_num = num
                max_index = idx
    if not max_index:
        raise RuntimeError("No matching KB index found in Elasticsearch.")
    print(f"Using latest KB index: {max_index}")
    return max_index


def load_knowledge():
    latest_index = get_latest_kb_index()
    for file in os.listdir(KNOWLEDGE_RESOURCES_PATH):
        if file.endswith(".json"):
            with open(
                os.path.join(KNOWLEDGE_RESOURCES_PATH, file), "rt", encoding="utf8"
            ) as f:
                body = f.read()
                filename = Path(file).stem
                resp = requests.put(
                    f"{os.environ['ELASTICSEARCH_URL']}/{latest_index}/_doc/${filename}",
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
