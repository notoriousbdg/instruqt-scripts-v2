# Delete Elastic resources
kubectl delete agents --all
kubectl delete kibana --all
kubectl delete elasticsearch --all

# Delete the operator
kubectl delete -f https://download.elastic.co/downloads/eck/2.13.0/operator.yaml

# Delete Custom Resource Definitions (CRDs)
kubectl delete -f https://download.elastic.co/downloads/eck/2.13.0/crds.yaml

# Delete other resources
kubectl delete secret gcs-credentials-eden-workshop
kubectl delete service apm apm-nodeport apm-service kibana elasticsearch fleet-nodeport
kubectl delete clusterrole fleet-server
kubectl delete serviceaccount fleet-server
kubectl delete clusterrolebinding fleet-server

# Delete the namespace (if you want to remove everything)
kubectl delete namespace elastic-system
sudo /opt/Elastic/Agent/elastic-agent uninstall
