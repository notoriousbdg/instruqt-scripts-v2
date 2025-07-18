import requests
import os
import time
from datetime import datetime

TIMEOUT = 360
ASSISTANT_RESOURCES_PATH = "assistant"


def log_message(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}")


def load_kb():
    max_retries = 3
    wait_seconds = 30

    # Try up to 3 times if we get a 500 when setting up KB
    for attempt in range(1, max_retries + 1):
        kb_resp = requests.post(
            f"{os.environ['KIBANA_URL']}/internal/observability_ai_assistant/kb/setup?inference_id=.elser-2-elasticsearch",
            timeout=TIMEOUT,
            auth=(
                os.environ["ELASTICSEARCH_USER"],
                os.environ["ELASTICSEARCH_PASSWORD"],
            ),
            headers={
                "kbn-xsrf": "true",
                "X-Elastic-Internal-Origin": "Kibana",
                "Content-Type": "application/json",
            },
        )

        log_message(f"KB setup response status: {kb_resp.status_code}")
        if kb_resp.status_code != 200:
            log_message(f"KB setup response content: {kb_resp.text}")

        # If there's a server error (500), retry up to max_retries
        if kb_resp.status_code == 500:
            if attempt < max_retries:
                log_message(
                    f"Attempt {attempt}/{max_retries} returned 500, waiting {wait_seconds}s before retry..."
                )
                time.sleep(wait_seconds)
            else:
                log_message("All attempts exhausted, still receiving 500 for KB setup.")
        else:
            # Exit the retry loop if not a 500
            break

    # Once KB setup is done (or we've reached our max retries), call sync
    sync_resp = requests.get(
        f"{os.environ['KIBANA_URL']}/api/ml/saved_objects/sync",
        timeout=TIMEOUT,
        auth=(os.environ["ELASTICSEARCH_USER"], os.environ["ELASTICSEARCH_PASSWORD"]),
        headers={"kbn-xsrf": "reporting"},
    )
    print(sync_resp.json())


def load():
    log_message("Starting assistant load process")

    if "LLM_PROXY_PROD" in os.environ:
        log_message("LLM_PROXY_PROD found in environment variables")
        # Get API key from LLM proxy
        headers = {
            "Authorization": f'Bearer {os.environ["LLM_PROXY_PROD"]}',
            "Content-Type": "application/json",
        }

        try:
            proxy_response = requests.post(
                "https://llm-proxy.prod-3.eden.elastic.dev/key/generate",
                headers=headers,
                json={
                    "models": ["gpt-4o"],
                    "duration": "7d",
                    "metadata": {
                        "user": f'instruqt-observe-ml-{os.environ.get("_SANDBOX_ID", "")}'
                    },
                },
                timeout=TIMEOUT,
            )
            log_message(f"Proxy response status: {proxy_response.status_code}")
            api_key = proxy_response.json()["key"]
            log_message("Successfully obtained API key")

            # Create connector (retry up to 10 times if 403 occurs)
            connector_data = {
                "name": "openai-connector",
                "config": {
                    "apiProvider": "Azure OpenAI",
                    "apiUrl": "https://llm-proxy.prod-3.eden.elastic.dev/v1/chat/completions?model=gpt-4",
                },
                "secrets": {"apiKey": api_key},
                "connector_type_id": ".gen-ai",
            }

            max_retries = 10
            for attempt in range(1, max_retries + 1):
                resp = requests.post(
                    f"{os.environ['KIBANA_URL']}/api/actions/connector",
                    json=connector_data,
                    timeout=TIMEOUT,
                    auth=(
                        os.environ["ELASTICSEARCH_USER"],
                        os.environ["ELASTICSEARCH_PASSWORD"],
                    ),
                    headers={"kbn-xsrf": "true", "Content-Type": "application/json"},
                )
                log_message(f"Connector creation response status: {resp.status_code}")

                if resp.status_code == 403:
                    log_message(
                        f"Attempt {attempt} of {max_retries} returned 403 - retrying..."
                    )
                    if attempt < max_retries:
                        continue
                    else:
                        log_message(
                            "All retry attempts exhausted, still receiving 403."
                        )
                # If not 403, break from the loop
                break

            load_kb()

        except Exception as e:
            log_message(f"Error occurred: {str(e)}")
            raise
    else:
        log_message("LLM_PROXY_PROD not found in environment variables")


if __name__ == "__main__":
    load()
