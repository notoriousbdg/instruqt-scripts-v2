from flask import Flask
import time
import ml
import kibana
import slo
import context
import assistant
import subprocess
import ingest_pipelines
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import index_template
from install_elastic_agent_serverless import main as install_kubernetes_agents

app = Flask(__name__)

def init():
    # Create the index template
    print("Creating index template...")
    #index_template.load()
    
    print("Installing Kubernetes Elastic Agents...")
    install_kubernetes_agents()
    ingest_pipelines.load()
    time.sleep(60)
    slo.load()
    ml.load_integration_jobs()
    kibana.load() #dashboards
    kibana.create_alerts()
    time.sleep(10)
    assistant.load()
    context.load()
    
init() 