#!/bin/bash 

source /root/.env


until [ -f /opt/instruqt/bootstrap/host-bootstrap-completed ]
do
    sleep 1
done

# Wait for the Kubernetes API server to become available
while ! curl --silent --fail --output /dev/null http://localhost:8001/api 
do
    sleep 1 
done

# Enable bash completion for kubectl
echo "source /usr/share/bash-completion/bash_completion" >> /root/.bashrc
echo "complete -F __start_kubectl k" >> /root/.bashrc

# Update package lists and install git and python
apt-get update
apt-get install -y git python3 python3-pip

# Verify Python installation
python3 --version
pip3 --version

DEMO_TYPE=${1:-nginx_demo}  # Default to nginx if no argument provided
echo "Setting up demo type: $DEMO_TYPE" >> log.txt

{ apt-get update; apt-get install nginx -y; } &

kubectl create -f https://download.elastic.co/downloads/eck/2.13.0/crds.yaml
kubectl apply -f https://download.elastic.co/downloads/eck/2.13.0/operator.yaml


#echo $GCSKEY_EDEN_WORKSHOP >> /tmp/gcs.client.eden-workshop.credentials_file

kubectl create secret generic gcs-credentials-eden-workshop --from-file=/tmp/gcs.client.eden-workshop.credentials_file
rm /tmp/gcs.client.eden-workshop.credentials_file

# Combine all three YAML files (namespace.yaml, deployment.yaml, services.yaml) into a single "apply" command:
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: my-namespace
  labels:
    name: my-namespace
  annotations:
    instrumentation.opentelemetry.io/inject-java: "opentelemetry-operator-system/elastic-instrumentation"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-a
  namespace: my-namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: service-a
  template:
    metadata:
      labels:
        app: service-a
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
      containers:
      - name: service-a
        image: djhope99/service-a:latest
        ports:
        - containerPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-b
  namespace: my-namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: service-b
  template:
    metadata:
      labels:
        app: service-b
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
      containers:
      - name: service-b
        image: djhope99/service-b:latest
        ports:
        - containerPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-c
  namespace: my-namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: service-c
  template:
    metadata:
      labels:
        app: service-c
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
      containers:
      - name: service-c
        image: djhope99/service-c:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "512Mi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: load-generator
  namespace: my-namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: load-generator
  template:
    metadata:
      labels:
        app: load-generator
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
      containers:
      - name: load-generator
        image: djhope99/load-generator:latest
        env:
        - name: REQUEST_RATE_MS
          value: "1000"
---
apiVersion: v1
kind: Service
metadata:
  name: service-a
  namespace: my-namespace
spec:
  selector:
    app: service-a
  ports:
    - port: 8080
      targetPort: 8080
  type: LoadBalancer
---
apiVersion: v1
kind: Service
metadata:
  name: service-b
  namespace: my-namespace
spec:
  selector:
    app: service-b
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: service-c
  namespace: my-namespace
spec:
  selector:
    app: service-c
  ports:
    - port: 8080
      targetPort: 8080
EOF

cat <<EOF | kubectl apply -f -
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: kibana
  namespace: default
spec:
  version: 8.16.1
  count: 1
  elasticsearchRef:
    name: elasticsearch
  http:
    tls:
      selfSignedCertificate:
        disabled: true
  config:
    server.publicBaseUrl: http://localhost:30002
    #elastic:
    #  apm:
    #    active: true
    #    serverUrl: "http://apm-service.default.svc:8200"
    #    secretToken: pkcQROVMCzYypqXs0b
    xpack.integration_assistant.enabled: true
    telemetry.optIn: false
    telemetry.allowChangingOptInStatus: false
    xpack.fleet.agents.elasticsearch.hosts: ["http://elasticsearch-es-http.default.svc:9200"]
    xpack.fleet.agents.fleet_server.hosts: ["https://fleet-server-agent-http.default.svc:8220"]
    xpack.fleet.packages:
    - name: system
      version: latest
    - name: elastic_agent
      version: latest
    - name: fleet_server
      version: latest
    - name: apm
      version: latest
    xpack.fleet.agentPolicies:
    - name: Fleet Server on ECK policy
      id: eck-fleet-server
      namespace: default
      #monitoring_enabled:
      #- logs
      #- metrics
      unenroll_timeout: 900
      package_policies:
      - name: fleet_server-1
        id: fleet_server-1
        package:
          name: fleet_server
    - name: Elastic Agent on ECK policy
      id: policy-elastic-agent-on-cloud
      namespace: default
      #monitoring_enabled:
      #- logs
      #- metrics
      unenroll_timeout: 900
      package_policies:
      - name: system-1
        id: system-1
        package:
          name: system
      - package:
          name: apm
        name: apm-1
        inputs:
        - type: apm
          enabled: true
          vars:
          - name: host
            value: 0.0.0.0:8200 
          - name: url
            value: "http://apm-service.default.svc:8200" 
          - name: secret_token
            value: pkcQROVMCzYypqXs0b    
---
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
  namespace: default
spec:
  version: 8.16.1
  secureSettings:
  - secretName: gcs-credentials-eden-workshop
  http:
    tls:
      selfSignedCertificate:
        disabled: true
  nodeSets:
  - name: default
    count: 1
    config:
      node.store.allow_mmap: false
      # default is 30, but we need a bit more capacity for elser
      xpack.ml.max_machine_memory_percent: 35
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          resources:
            requests:
              memory: 6Gi
            limits:
              memory: 6Gi
---
apiVersion: agent.k8s.elastic.co/v1alpha1
kind: Agent
metadata:
  name: fleet-server
  namespace: default
spec:
  version: 8.16.1
  kibanaRef:
    name: kibana
  elasticsearchRefs:
  - name: elasticsearch
  mode: fleet
  fleetServerEnabled: true
  policyID: eck-fleet-server
  deployment:
    replicas: 1
    podTemplate:
      spec:
        serviceAccountName: fleet-server
        automountServiceAccountToken: true
        securityContext:
          runAsUser: 0
        containers:
        - name: agent
          resources:
            requests:
              memory: 300Mi
              cpu: 0.2
            limits:
              memory: 1000Mi
              cpu: 1
---
apiVersion: agent.k8s.elastic.co/v1alpha1
kind: Agent
metadata: 
  name: elastic-agent
  namespace: default
spec:
  version: 8.16.1
  kibanaRef:
    name: kibana
  fleetServerRef: 
    name: fleet-server
  mode: fleet
  policyID: policy-elastic-agent-on-cloud
  image: docker.elastic.co/beats/elastic-agent-complete:8.15.2
  deployment:
    replicas: 1
    podTemplate:
      spec:
        securityContext:
          runAsUser: 1000
        volumes:
        - emptyDir: {}
          name: agent-data
        containers:
        - name: agent
          resources:
            requests:
              memory: 300Mi
              cpu: 0.2
            limits:
              memory: 2000Mi
              cpu: 2
---
apiVersion: v1
kind: Service
metadata:
  name: apm
  namespace: default
spec:
  selector:
    agent.k8s.elastic.co/name: elastic-agent
  ports:
  - protocol: TCP
    port: 30820
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: default
spec:
  selector:
    kibana.k8s.elastic.co/name: kibana
  ports:
  - protocol: TCP
    nodePort: 30002
    port: 5601
  type: NodePort
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: default
spec:
  selector:
    elasticsearch.k8s.elastic.co/cluster-name: elasticsearch
  ports:
  - protocol: TCP
    nodePort: 30920
    port: 9200
  type: NodePort
---
apiVersion: v1
kind: Service
metadata:
  name: apm-nodeport
  namespace: default
spec:
  selector:
    agent.k8s.elastic.co/name: elastic-agent
  ports:
  - protocol: TCP
    nodePort: 30820
    port: 8200
  type: NodePort
---
apiVersion: v1
kind: Service
metadata:
  name: apm-service
  namespace: default
spec:
  selector:
    agent.k8s.elastic.co/name: elastic-agent
  ports:
  - protocol: TCP
    port: 8200
    targetPort: 8200
---
apiVersion: v1
kind: Service
metadata:
  name: fleet-nodeport
  namespace: default
spec:
  selector:
    agent.k8s.elastic.co/name: fleet-server
    common.k8s.elastic.co/type: agent
  ports:
  - protocol: TCP
    nodePort: 30822
    port: 8220
  type: NodePort
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fleet-server
rules:
- apiGroups: [""]
  resources:
  - pods
  - namespaces
  - nodes
  verbs:
  - get
  - watch
  - list
- apiGroups: ["coordination.k8s.io"]
  resources:
  - leases
  verbs:
  - get
  - create
  - update
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fleet-server
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: fleet-server
subjects:
- kind: ServiceAccount
  name: fleet-server
  namespace: default
roleRef:
  kind: ClusterRole
  name: fleet-server
  apiGroup: rbac.authorization.k8s.io
EOF

# wait until elasticsearch is created
echo 'waiting for elasticsearch'

until kubectl get pods -n default | grep -q elasticsearch 
do
  sleep 1
done

echo 'waiting for elasticsearch to be ready'

# wait for all pods to be ready, loop 5 times
for i in {1..5}
do
  if kubectl wait pod -n default -l common.k8s.elastic.co/type --for=condition=Ready --timeout=60s; then
    break
  fi  
  sleep 1
done

echo 'waiting for kibana'
until kubectl get pods -n default | grep -q kibana 
do
  sleep 1
done
echo 'waiting for kibana to be ready'

# wait for all pods to be ready, loop 5 times
for i in {1..5}
do
  if kubectl wait pod -n default -l common.k8s.elastic.co/type --for=condition=Ready --timeout=60s; then
    break
  fi  
  sleep 1
done

echo 'waiting for fleet-server'
until kubectl get pods -n default | grep -q fleet-server 
do
  sleep 1
done
echo 'waiting for fleet-server to be ready'

# wait for all pods to be ready, loop 5 times
for i in {1..5}
do
  if kubectl wait pod -n default -l common.k8s.elastic.co/type --for=condition=Ready --timeout=60s; then
    break
  fi  
  sleep 1
done

echo 'waiting for elastic-agent'
until kubectl get pods -n default | grep -q elastic-agent 
do
  sleep 1
done
echo 'waiting for elastic-agent to be ready'

# wait for all pods to be ready, loop 5 times
for i in {1..5}
do
  if kubectl wait pod -n default -l common.k8s.elastic.co/type --for=condition=Ready --timeout=60s; then
    break
  fi  
  sleep 1
done

# shebang
#!/bin/bash



echo 'ELASTICSEARCH_USERNAME=elastic' >> /root/.env
# echo without newline
echo -n 'ELASTICSEARCH_PASSWORD=' >> /root/.env

# read password from kubectl get secret elasticsearch-es-elastic-user -o go-template='{{.data.elastic | base64decode}}', save to file as ELASTICSEARCH_PASSWORD=$value
kubectl get secret elasticsearch-es-elastic-user -n default -o go-template='{{.data.elastic | base64decode}}' >> /root/.env
echo '' >> /root/.env
echo 'ELASTICSEARCH_URL="http://localhost:30920"' >> /root/.env
echo 'KIBANA_URL="http://localhost:30002"' >> /root/.env
echo 'BUILD_NUMBER="10"' >> /root/.env
echo 'ELASTIC_VERSION="8.9.0"' >> /root/.env

echo 'ELASTIC_APM_SERVER_URL=http://apm-service.default.svc:8200' >> /root/.env
echo 'ELASTIC_APM_SECRET_TOKEN=pkcQROVMCzYypqXs0b' >> /root/.env





{ apt-get update; apt-get install nginx -y; } 

export $(cat /root/.env | xargs) 

BASE64=$(echo -n "elastic:${ELASTICSEARCH_PASSWORD}" | base64)

KIBANA_URL_WITHOUT_PROTOCOL=$(echo $KIBANA_URL | sed -e 's#http[s]\?://##g')

ulimit -n 16384

echo '
upstream keepalive-upstream {
  server '${KIBANA_URL_WITHOUT_PROTOCOL}';
  server '${KIBANA_URL_WITHOUT_PROTOCOL}';
  server '${KIBANA_URL_WITHOUT_PROTOCOL}';
  keepalive 64;
}

server { 
  listen 30001 default_server;
  server_name kibana;
  location /nginx_status {
    stub_status on;
    allow 127.0.0.1;
    deny all;
  }
  location / {
    proxy_set_header Host '${KIBANA_URL_WITHOUT_PROTOCOL}';
    proxy_pass http://keepalive-upstream;
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    proxy_set_header Connection "";
    proxy_hide_header Content-Security-Policy;
    proxy_set_header X-Scheme $scheme;
    proxy_set_header Authorization "Basic '${BASE64}'";
    proxy_set_header Accept-Encoding "";
    proxy_redirect off;
    proxy_http_version 1.1;
    client_max_body_size 20M;
    proxy_read_timeout 600;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains;";
    proxy_send_timeout          300;
    send_timeout                300;
    proxy_connect_timeout       300;
 }
}

upstream fleet-upstream {
  server localhost:30822;
  server localhost:30822;
  server localhost:30822;
}

server {
  listen 8220 ssl;
  
  server_name fleet-server;
  ssl_certificate /etc/ssl/certs/nginx-selfsined.crt;
  ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;

  location / {
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    proxy_pass https://fleet-upstream;
    proxy_connect_timeout       300;
    proxy_send_timeout          300;
    proxy_read_timeout          300;
    send_timeout                300;
  }
}
server {
  listen 9200;
  server_name elasticsearch;
  
  location / {
    proxy_pass http://localhost:30920;
    proxy_connect_timeout       300;
    proxy_send_timeout          300;
    proxy_read_timeout          300;
    send_timeout                300;
  }
}
' > /etc/nginx/conf.d/default.conf

# enable trial
#cat <<EOF | kubectl apply -f -
#apiVersion: v1
#kind: Secret
#metadata:
#  name: eck-trial-license
#  namespace: elastic-system
#  labels:
#    license.k8s.elastic.co/type: enterprise_trial
#  annotations:
#    elastic.co/eula: accepted 
#EOF

echo "Starting trial license"
echo ""
curl -s -X POST --header "Authorization: Basic $BASE64" "$ELASTICSEARCH_URL/_license/start_trial?acknowledge=true"

echo '127.0.0.1 fleet-server-agent-http.default.svc' >> /etc/hosts
echo '127.0.0.1 elasticsearch-es-http.default.svc' >> /etc/hosts

sudo mkdir /etc/ssl/private
sudo chmod 700 /etc/ssl/private

sudo openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=fleet-server-agent-http.default.svc" \
    -keyout /etc/ssl/private/nginx-selfsigned.key  -out /etc/ssl/certs/nginx-selfsined.crt

systemctl restart nginx



echo '
---

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apm-ing
  namespace: default
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: "apm.kubernetes-vm.$_SANDBOX_ID.instruqt.io"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: apm-lb
            port:
              number: 8200
' > /root/ingress-apm.yaml

envsubst < /root/ingress-apm.yaml | kubectl apply -f -

echo '
apiVersion: v1
kind: Service
metadata:
  name: apm-lb
  namespace: default
spec:
  ports:
  - name: apm-lb
    port: 8200
    protocol: TCP
    targetPort: 8200
  selector:
    agent.k8s.elastic.co/name: elastic-agent
  type: LoadBalancer
' > /root/apm-lb.yaml


kubectl apply -f /root/apm-lb.yaml

echo '
apiVersion: v1
kind: Service
metadata:
  name: kibana-lb
  namespace: default
spec:
  ports:
  - name: kibana-lb
    port: 5601
    protocol: TCP
    targetPort: 5601
  selector:
    kibana.k8s.elastic.co/name: kibana
  type: LoadBalancer
' > /root/kibana-lb.yaml

kubectl apply -f /root/kibana-lb.yaml

kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.10/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml

export AUTH=$(echo -n "elastic:$(kubectl get secret elasticsearch-es-elastic-user -n default -o go-template='{{.data.elastic | base64decode}}')" | base64 -w0)

# middleware that sets request and response header to dummy value
echo '
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: set-upstream-basic-auth
spec:
  headers:
    customRequestHeaders:
      X-Request-Id: "123"
      Authorization: "Basic $AUTH"
    customResponseHeaders:
      X-Response-Id: "4567"
' > /root/middleware.yaml

envsubst < /root/middleware.yaml | kubectl apply -f -

# ingress route for kibana

echo '
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: kibana-ing
  namespace: default
spec:
  entryPoints:
    - websecure
  routes:
  - match: Host(`kibana.kubernetes-vm.$_SANDBOX_ID.instruqt.io`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: kibana-lb
      port: 5601
    middlewares:
    - name: set-upstream-basic-auth
' > /root/ingress-kibana.yaml

envsubst < /root/ingress-kibana.yaml | kubectl apply -f -


export $(cat /root/.env | xargs)
BASE64=$(echo -n "elastic:${ELASTICSEARCH_PASSWORD}" | base64)

output=$(curl 'https://llm-proxy.prod-3.eden.elastic.dev/key/generate' \
--header 'Authorization: Bearer '"$LLM_PROXY_PROD"'' \
--header 'Content-Type: application/json' \
--data-raw '{"models": ["gpt-4"],"duration": "7d", "metadata": {"user": "instruqt-observe-ml-'"$_SANDBOX_ID"'"}}')

key=$(echo $output | jq -r '.key')

echo "OPENAI_API_KEY=$key" >> /root/.env

export $(cat /root/.env | xargs)
BASE64=$(echo -n "elastic:${ELASTICSEARCH_PASSWORD}" | base64)
echo "updating settings"

cat > settings.json << EOF
{
   "attributes":{
      "buildNum":70088,
      "defaultIndex":"dccd1810-2016-11eb-8016-cf9f9e5961e9",
      "isDefaultIndexMigrated":true,
      "notifications:banner":null,
      "notifications:lifetime:banner":null,
      "timepicker:quickRanges":"[\n{\n    \"from\": \"2022-06-07T08:20:00+02:00\",\n    \"to\": \"2022-06-07T10:00:00+02:00\",\n    \"display\": \"Database\"\n  },\n    {\n    \"from\": \"now/d\",\n    \"to\": \"now/d\",\n    \"display\": \"Today\"\n  },\n  {\n    \"from\": \"now/w\",\n    \"to\": \"now/w\",\n    \"display\": \"This week\"\n  },\n  {\n    \"from\": \"now-15m\",\n    \"to\": \"now\",\n    \"display\": \"Last 15 minutes\"\n  },\n  {\n    \"from\": \"now-30m\",\n    \"to\": \"now\",\n    \"display\": \"Last 30 minutes\"\n  },\n  {\n    \"from\": \"now-1h\",\n    \"to\": \"now\",\n    \"display\": \"Last 1 hour\"\n  },\n  {\n    \"from\": \"now-24h/h\",\n    \"to\": \"now\",\n    \"display\": \"Last 24 hours\"\n  },\n  {\n    \"from\": \"now-7d/d\",\n    \"to\": \"now\",\n    \"display\": \"Last 7 days\"\n  },\n  {\n    \"from\": \"now-30d/d\",\n    \"to\": \"now\",\n    \"display\": \"Last 30 days\"\n  },\n  {\n    \"from\": \"now-90d/d\",\n    \"to\": \"now\",\n    \"display\": \"Last 90 days\"\n  },\n  {\n    \"from\": \"now-1y/d\",\n    \"to\": \"now\",\n    \"display\": \"Last 1 year\"\n  }\n]"
   },
   "coreMigrationVersion":"8.8.0",
   "created_at":"2024-01-17T15:00:18.968Z",
   "id":"8.12.0",
   "managed":false,
   "references":[
   ],
   "type":"config",
   "typeMigrationVersion":"8.9.0",
   "updated_at":"2024-01-17T15:00:18.968Z",
   "version":"Wzg3NDUyMyw4XQ=="
}
EOF
cat settings.json | jq -c > settings.ndjson

mkdir /home/env/

export $(cat /root/.env | xargs)
# write OPENAI_API_KEY to .env
echo "OPENAI_API_KEY=$OPENAI_API_KEY" >> /home/env/.env

# remove OPENAI_API_KEY from .env
sed -i '/OPENAI_API_KEY/d' /root/.env

curl -s -X POST --header "Authorization: Basic $BASE64"  -H "kbn-xsrf: true" \
"http://localhost:30002/api/saved_objects/_import?overwrite=true" --form file=@settings.ndjson

export ELASTICSEARCH_USER=elastic
export KIBANA_URL=http://localhost:30002
export FLEET_URL=https://localhost:30822
export PASSWORD=$(kubectl get secret elasticsearch-es-elastic-user -n default -o go-template='{{.data.elastic | base64decode}}')


curl -s -X POST --header "Authorization: Basic $BASE64" "$ELASTICSEARCH_URL/_license/start_trial?acknowledge=true"


set -euo pipefail

log_message() {
  local timestamp
  timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
  # Replace echo with any file-logging approach if needed:
  echo "[$timestamp] $1"
}

load_kb() {
  # Send POST request to set up the knowledge base
  local kb_setup_status
  kb_setup_status="$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    --connect-timeout 360 \
    --user "$ELASTICSEARCH_USER:$ELASTICSEARCH_PASSWORD" \
    -H 'kbn-xsrf: true' \
    -H 'X-Elastic-Internal-Origin: Kibana' \
    -H 'Content-Type: application/json' \
    "${KIBANA_URL}/internal/observability_ai_assistant/kb/setup")"

  log_message "KB setup response status: ${kb_setup_status}"

  # Send GET request to sync saved objects
  local sync_resp
  sync_resp="$(curl -s \
    -X GET \
    --connect-timeout 360 \
    --user "$ELASTICSEARCH_USER:$ELASTICSEARCH_PASSWORD" \
    -H 'kbn-xsrf: reporting' \
    "${KIBANA_URL}/api/ml/saved_objects/sync")"

  log_message "Sync response: $sync_resp"
}

function load() {
  log_message "Starting assistant load process"

  if [[ -n "${LLM_PROXY_PROD:-}" ]]; then
    log_message "LLM_PROXY_PROD found in environment variables"

    # 1) Obtain an API key from the LLM proxy
    #    We'll capture both the body and the status code below.
    local tmpfile
    tmpfile="$(mktemp)"
    local proxy_response_status
    proxy_response_status="$(curl -s -o "$tmpfile" -w "%{http_code}" \
      -X POST \
      -H "Authorization: Bearer $LLM_PROXY_PROD" \
      -H 'Content-Type: application/json' \
      --connect-timeout 360 \
      -d "{
        \"models\": [\"gpt-4o\"],
        \"duration\": \"7d\",
        \"metadata\": {
          \"user\": \"instruqt-observe-ml-${_SANDBOX_ID:-}\"
        }
      }" \
      "https://llm-proxy.prod-3.eden.elastic.dev/key/generate")"

    log_message "Proxy response code: $proxy_response_status"

    if [[ "$proxy_response_status" -ne 200 ]]; then
      log_message "Error: LLM proxy request failed (HTTP $proxy_response_status)."
      log_message "Response was:"
      cat "$tmpfile"
      rm -f "$tmpfile"
      exit 1
    fi

    # Extract key from JSON response
    local api_key
    api_key="$(jq -r '.key' < "$tmpfile")"
    rm -f "$tmpfile"

    if [[ -z "$api_key" || "$api_key" == "null" ]]; then
      log_message "Error: Could not find 'key' in proxy response."
      exit 1
    fi
    log_message "Successfully obtained API key."

    # 2) Create the connector in Kibana (retry on 403 or other failed codes)
    local connector_resp_code
    local connector_resp_tmp
    local max_retries=5
    local attempt=1

    while (( attempt <= max_retries )); do
      connector_resp_tmp="$(mktemp)"
      connector_resp_code="$(curl -s -o "$connector_resp_tmp" -w "%{http_code}" \
        -X POST \
        --connect-timeout 360 \
        --user "$ELASTICSEARCH_USER:$ELASTICSEARCH_PASSWORD" \
        -H 'kbn-xsrf: true' \
        -H 'Content-Type: application/json' \
        -d "{
          \"name\": \"openai-connector\",
          \"config\": {
            \"apiProvider\": \"Azure OpenAI\",
            \"apiUrl\": \"https://llm-proxy.prod-3.eden.elastic.dev/v1/chat/completions?model=gpt-4\"
          },
          \"secrets\": {
            \"apiKey\": \"${api_key}\"
          },
          \"connector_type_id\": \".gen-ai\"
        }" \
        "${KIBANA_URL}/api/actions/connector")"

      log_message "Connector creation attempt #$attempt response code: ${connector_resp_code}"

      if [[ "$connector_resp_code" =~ ^2[0-9]{2}$ ]]; then
        # 2xx range => success
        rm -f "$connector_resp_tmp"
        log_message "Connector created successfully."
        break
      else
        log_message "Connector creation failed with code $connector_resp_code (attempt #$attempt)."
        log_message "Response body:"
        cat "$connector_resp_tmp"
        rm -f "$connector_resp_tmp"
        
        if (( attempt == max_retries )); then
          log_message "Reached max retries ($max_retries). Exiting."
          exit 1
        fi

        # Wait briefly before retrying
        sleep 5
      fi
      (( attempt++ ))
    done

    # 3) Load (or re-load) the knowledge base
    load_kb
    load_kb

  else
    log_message "LLM_PROXY_PROD not found in environment variables."
  fi
}

# --------------------------------
# Script execution starts here
# --------------------------------
load > assistant.log

LOG_FILE="log.txt"
TIMEOUT=360

function run_command() {
  local cmd="$1"
  log_message "Running command: ${cmd}"
  # shellcheck disable=SC2086
  eval "${cmd}" 2>> "${LOG_FILE}" 1>> "${LOG_FILE}"
  local status=$?
  if [ $status -ne 0 ]; then
    log_message "Command failed with exit code ${status}"
    exit $status
  fi
}

function get_kubernetes_flow() {

  if [ -z "${KIBANA_URL}" ] || [ -z "${ELASTICSEARCH_USER}" ] || [ -z "${ELASTICSEARCH_PASSWORD}" ]; then
    exit 1
  fi

  # Prepare headers and POST data
  local headers=(
    -H "accept: */*"
    -H "content-type: application/json"
    -H "kbn-xsrf: true"
    -H "X-Elastic-Internal-Origin: Kibana"
  )
  local data='{"pkgName":"kubernetes_otel"}'

  # Use curl to get the flow response
  local response
  response=$(curl -s -X POST \
    "${KIBANA_URL}/internal/observability_onboarding/kubernetes/flow" \
    -u "${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}" \
    "${headers[@]}" \
    -d "${data}" \
    --max-time "${TIMEOUT}" )

  if [ $? -ne 0 ] || [ -z "${response}" ]; then
    exit 1
  fi

  echo "${response}"
}

function setup_kubernetes() {
  local es_url="$1"
  local api_key="$2"

  # Add helm repository
  run_command "helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update"

  # Create namespace
  run_command "kubectl create namespace opentelemetry-operator-system"

  # Create secret
  local secret_cmd="kubectl create secret generic elastic-secret-otel \
    --namespace opentelemetry-operator-system \
    --from-literal=elastic_endpoint='${es_url}' \
    --from-literal=elastic_api_key='${api_key}'"
  run_command "${secret_cmd}"

  # Install helm chart
  local helm_cmd="helm install opentelemetry-kube-stack open-telemetry/opentelemetry-kube-stack \
    --namespace opentelemetry-operator-system \
    --values 'https://raw.githubusercontent.com/elastic/opentelemetry/refs/heads/8.16/resources/kubernetes/operator/helm/values.yaml' \
    --version '0.3.3'"
  run_command "${helm_cmd}"
}

function annotate_namespace() {
  local cmd="kubectl annotate namespace default \
      instrumentation.opentelemetry.io/inject-nodejs=\"opentelemetry-operator-system/elastic-instrumentation\""
  run_command "${cmd}"
}

function main() {
  # Get the flow response JSON
  local flow_response
  flow_response=$(get_kubernetes_flow)

  # Extract necessary fields using jq
  local es_url
  local api_key
  es_url=$(echo "${flow_response}" | jq -r '.elasticsearchUrl // empty')
  api_key=$(echo "${flow_response}" | jq -r '.apiKeyEncoded // empty')

  if [ -z "${es_url}" ] || [ -z "${api_key}" ]; then
    log_message "Error: Could not parse 'elasticsearchUrl' or 'apiKeyEncoded' from the flow response."
    exit 1
  fi

  log_message "Received flow response: ${flow_response}"

  # Setup Kubernetes
  setup_kubernetes "${es_url}" "${api_key}"

  # Wait for resources to be ready (adjust timing as needed)
  log_message "Waiting 30 seconds for resources to become ready..."
  sleep 30

  # Annotate the default namespace
  annotate_namespace

  log_message "Setup complete!"

  # Print next steps
  cat <<EOF

Next steps:
1. Review and modify deployment.yaml as needed
2. Apply the deployment: kubectl apply -f deployment.yaml
3. After applying, you can:
   - Check pod status: kubectl get pods
   - Describe pod: kubectl describe pod <pod-name>
   - View logs: kubectl logs <pod-name>

EOF
}

main > edot-2-workshop.log

kubectl rollout restart deployment service-c -n my-namespace
kubectl rollout restart deployment service-b -n my-namespace
kubectl rollout restart deployment service-a -n my-namespace