#!/bin/bash 


# Enable bash completion for kubectl
echo "source /usr/share/bash-completion/bash_completion" >> /root/.bashrc
echo "complete -F __start_kubectl k" >> /root/.bashrc

{ apt-get update; apt-get install nginx -y; } &

kubectl create -f https://download.elastic.co/downloads/eck/2.13.0/crds.yaml
kubectl apply -f https://download.elastic.co/downloads/eck/2.13.0/operator.yaml

cat <<EOF | kubectl apply -f -
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: kibana
  namespace: default
spec:
  version: 8.15.2
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
    xpack.fleet.agents.elasticsearch.hosts: ["http://34.123.25.253:30920"]
    xpack.fleet.agents.fleet_server.hosts: ["https://34.123.25.253:30822"]
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
  version: 8.15.2
  secureSettings:
  - secretName: snapshot-settings
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
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 100Gi
        storageClassName: standard
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
  version: 8.15.2
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
  version: 8.15.2
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

export KIBANA_URL=http://34.123.25.253:30002
export PASSWORD=$(kubectl get secret elasticsearch-es-elastic-user -n default -o go-template='{{.data.elastic | base64decode}}')
export ELASTICSEARCH_USER=elastic
export ELASTICSEARCH_PASSWORD=$PASSWORD
export FLEET_URL=https://34.123.25.253:30822
export ELASTICSEARCH_URL=http://34.123.25.253:30920
export BASE64=$(echo -n "elastic:${PASSWORD}" | base64)

curl -s -X POST --header "Authorization: Basic $BASE64" "$ELASTICSEARCH_URL/_license/start_trial?acknowledge=true"
{"acknowledged":true,"trial_was_started":true,"type":"trial"}

cd resources
pip3 install -r requirements.txt
python3 app.py
