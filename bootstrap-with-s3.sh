#!/bin/bash 

# Wait for the Instruqt host bootstrap to finish
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

curl https://david-hope-elastic-snapshots.s3.us-east-2.amazonaws.com/archive.tar.gz | tar -xz

# Add the variables with proper escaping
echo "LLM_PROXY_STAGING='$LLM_PROXY_STAGING'" >> /root/.env
echo "LLM_PROXY_PROD='$LLM_PROXY_PROD'" >> /root/.env
echo $GCSKEY_EDEN_WORKSHOP >> /tmp/gcs.client.eden-workshop.credentials_file

cd instruqt-scripts
chmod +x setup-elastic-in-instruqt.sh
source ./setup-elastic-in-instruqt.sh
