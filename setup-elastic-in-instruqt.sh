#!/bin/bash 

source /root/.env

DEMO_TYPE=${1:-nginx_demo}  # Default to nginx if no argument provided
echo "Setting up demo type: $DEMO_TYPE" >> log.txt

{ apt-get update; apt-get install nginx -y; } &

kubectl create -f https://download.elastic.co/downloads/eck/2.13.0/crds.yaml
kubectl apply -f https://download.elastic.co/downloads/eck/2.13.0/operator.yaml


#echo $GCSKEY_EDEN_WORKSHOP >> /tmp/gcs.client.eden-workshop.credentials_file

kubectl create secret generic gcs-credentials-eden-workshop --from-file=/tmp/gcs.client.eden-workshop.credentials_file
rm /tmp/gcs.client.eden-workshop.credentials_file

cat <<EOF | kubectl apply -f -
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: kibana
  namespace: default
spec:
  version: 8.17.0
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
  version: 8.17.0
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
  version: 8.17.0
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
  version: 8.17.0
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

echo "OPENAI_API_KEY=$key" >> /root/.env

export $(cat /root/.env | xargs)
BASE64=$(echo -n "elastic:${ELASTICSEARCH_PASSWORD}" | base64)

export ELASTICSEARCH_USER=elastic
export KIBANA_URL=http://localhost:30002
export FLEET_URL=https://localhost:30822
export PASSWORD=$(kubectl get secret elasticsearch-es-elastic-user -n default -o go-template='{{.data.elastic | base64decode}}')


curl -s -X POST --header "Authorization: Basic $BASE64" "$ELASTICSEARCH_URL/_license/start_trial?acknowledge=true"

cd resources
pip3 install -r requirements.txt
python3 ${DEMO_TYPE}.py