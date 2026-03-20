# Orbit Agentic AI Framework - Command Line Deployment Guide

The **Orbit Framework** is a production-grade Agentic AI Landing Zone designed for Google Cloud. It enables organizations to deploy stateful, proactive AI agents that leverage **LangGraph** for reasoning, **Vertex AI** for intelligence, and **GKE** for hyperscale.

This repository contains the configuration files and instructions required to deploy Orbit to a Google Kubernetes Engine (GKE) cluster via the command line, bypassing the Google Cloud Console UI.

## 📋 Prerequisites

Before deploying this framework via CLI, ensure your environment meets the following requirements:

### Google Cloud Resources
1. **Google Cloud Project:** An underlying GCP environment with an active billing account.
2. **GKE Cluster:** A running Kubernetes cluster. This framework is fully optimized for **GKE Autopilot**, which handles Workload Identity and node scaling automatically.
3. **Cloud SQL Database:** A Postgres database instance with `pgvector` enabled and a Private Service Connect (PSC) Service Attachment.
4. **Vertex AI Availability:** The **Vertex AI Model Garden API** must be accessible within the region where the framework is deployed.
5. **Google Cloud Storage Bucket:** A bucket to trigger events, if messaging is enabled.

### Local CLI Tools
* [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) - Authenticated via `gcloud auth login`.
* [Kubernetes CLI (`kubectl`)](https://kubernetes.io/docs/tasks/tools/) - Configured to communicate with your GKE cluster.
* **mpdev**: The Google Cloud Marketplace CLI tool. [Download mpdev here](https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools/tree/master/mpdev).
* **Application CRD**: Ensure the Google Cloud Marketplace Application CRD is installed on your cluster.

---

## 🚀 Deployment Instructions

### 1. Clone this repository
Clone this public deployment repository to your local machine to get the required template files:
```bash
git clone https://github.com/prodgen-ai/orbit-marketplace-cli.git
cd orbit-marketplace-cli
```

### 2. Prepare your namespace
Create the Kubernetes namespace where Orbit will reside:

```bash
export NAMESPACE=orbit-ai
kubectl create namespace $NAMESPACE
```

### 3. Environment Preparation

Before deploying, you must initialize your Google Cloud Project. 

**Note for Event-Driven AI:** If this is your first time deploying to this GCP Project, you must initialize the Eventarc GKE forwarder manually by running this command and pressing 'y' to accept the IAM roles:
```bash
`gcloud eventarc gke-destinations init`
```

Next, run the interactive setup script. This script automatically enables the required APIs, creates necessary Service Accounts, sets up IAM bindings, and provisions the PSC network bridge.

```bash
chmod +x interactive_prepare.sh
./interactive_prepare.sh
```

### 4. Configure Deployment Parameters
Copy the sample parameters file and fill in your specific environment variables:

```bash
cp parameters.yaml.template parameters.yaml
```
Edit parameters.yaml to include your specific cluster details, reporting endpoint, and network configurations.

### 5. Deploy the Application
Use mpdev to trigger the Marketplace deployer image. This will unpack the Orbit Helm charts and configure the agent and validator workloads on your cluster.

```bash
mpdev install \
  --deployer=us-docker.pkg.dev/prodgen-orbit-public/orbit-ai/deployer:1.0 \
  --parameters_file=parameters.yaml
```

### 6. Bind Workload Identity (Required)
Once the deployment initiates, you must link the newly created Kubernetes Service Account to your Google Cloud IAM Service Account:

```bash
kubectl annotate sa orbit-sa -n $NAMESPACE \
  iam.gke.io/gcp-service-account=orbit-agent-identity@YOUR_PROJECT_ID.iam.gserviceaccount.com --overwrite
```

## 📊 Observability & Verification
Verify that the application pods have successfully pulled their images and are running:

```bash
kubectl get pods -n $NAMESPACE
```
**Arize Phoenix Integration:** Every prompt sent to Vertex AI, every tool call, and every LangGraph transition is automatically instrumented and logged. To view your agent's real-time performance, port-forward the internal Phoenix service to your local machine:

```bash
kubectl port-forward svc/orbit-phoenix 6006:6006 -n $NAMESPACE
```

Then, open your browser and navigate to: http://localhost:6006

## 📈 Next Steps
Once deployed, you can extend the framework's capabilities:

* **Customizing Logic:** Edit the StateGraph in main.py to define your own custom agentic workflows.

* **Adding Superpowers (Custom Tools):** Open tools.py to give your agent new capabilities. You can write custom Python functions wrapped in the LangChain @tool decorator to let your agent query external APIs or interact with other business systems.

* **Scaling:** The framework can be scaled dynamically to handle high-concurrency workloads. Use standard Kubernetes commands to increase your replica counts: `kubectl scale deployment orbit-agent --replicas=3 -n $NAMESPACE`
  
* **Event-Driven AI:** Event-driven messaging (via the webhook microservice and Eventarc triggers) is deployed and enabled by default. If you wish to disable this feature to run a lightweight version of the framework, you can scale the webhook down after deployment: `kubectl scale deployment orbit-webhook --replicas=0 -n $NAMESPACE`

## Support
For issues during CLI deployment, please open an issue in this repository.
