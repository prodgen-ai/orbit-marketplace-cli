#!/bin/bash
# prepare.sh - Setup Google Cloud environment for Orbit Framework K8s App

# Get current project as default
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)

echo "=========================================================="
echo "🚀 Orbit Agentic AI Framework - Pre-Deployment Setup"
echo "=========================================================="
echo "Please provide your Google Cloud environment details:"

# 1. Interactive Prompts for the Customer
read -p "Enter your GCP Project ID [$CURRENT_PROJECT]: " INPUT_PROJECT
PROJECT_ID=${INPUT_PROJECT:-$CURRENT_PROJECT}

read -p "Enter your GCP Region (e.g., us-central1) [us-central1]: " INPUT_REGION
REGION=${INPUT_REGION:-us-central1}

read -p "Enter your existing GKE Cluster Name: " CLUSTER_NAME
while [[ -z "$CLUSTER_NAME" ]]; do
    read -p "Cluster Name is required. Enter your GKE Cluster Name: " CLUSTER_NAME
done

read -p "Enter your VPC Network Name [default]: " INPUT_VPC
VPC_NAME=${INPUT_VPC:-default}

read -p "Enter the K8s Namespace to deploy into [orbit-ai]: " INPUT_NAMESPACE
NAMESPACE=${INPUT_NAMESPACE:-orbit-ai}

read -p "Enter your Cloud SQL Instance Name (for pgvector): " DB_NAME
while [[ -z "$DB_NAME" ]]; do
    read -p "Cloud SQL Instance Name is required: " DB_NAME
done

# Static App Variables (Must match your schema.yaml defaults)
GSA_NAME="orbit-agent-identity"
GSA_EMAIL="$GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
KSA_NAME="orbit-sa"
PSC_ENDPOINT_NAME="orbit-db-psc-ip"
DB_SECRET_NAME="orbit-db-password"

echo "----------------------------------------------------------"
echo "🚀 Starting Orbit Environment Setup for Project: $PROJECT_ID"

# Get project number for the Reasoning Engine Service Agent email
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# 1. Enable Required APIs
echo "Enabling APIs..."
gcloud services enable \
    cloudbuild.googleapis.com \
    aiplatform.googleapis.com \
    container.googleapis.com \
    artifactregistry.googleapis.com \
    sqladmin.googleapis.com \
    servicenetworking.googleapis.com  \
    secretmanager.googleapis.com \
    cloudkms.googleapis.com \
    pubsub.googleapis.com \
    eventarc.googleapis.com \
    eventarcpublishing.googleapis.com \
    cloudresourcemanager.googleapis.com \
    discoveryengine.googleapis.com \
    iamcredentials.googleapis.com \
    sts.googleapis.com --project=$PROJECT_ID --quiet

# 1.1 Initialize Reasoning Engine Service Identity
echo "Initializing Reasoning Engine Service Identity..."
gcloud beta services identity create --service=aiplatform.googleapis.com --project=$PROJECT_ID

# 2. Create Google Service Account
if ! gcloud iam service-accounts describe "$GSA_EMAIL" >/dev/null 2>&1; then
    echo "Creating Google Service Account..."
    gcloud iam service-accounts create $GSA_NAME --display-name="Orbit Agent Identity"
else
    echo "✅ Service Account already exists."
fi

# 3. Grant IAM Roles to the Custom GSA
echo "Granting IAM Roles to $GSA_EMAIL..."
ROLES=(
    "roles/container.admin" 
    "roles/iam.serviceAccountAdmin" 
    "roles/iam.serviceAccountUser"
    "roles/aiplatform.user"
    "roles/aiplatform.serviceAgent"
    "roles/discoveryengine.editor"
    "roles/serviceusage.serviceUsageConsumer"
    "roles/secretmanager.secretAccessor"
    "roles/iam.serviceAccountViewer"
    "roles/compute.networkAdmin"
    "roles/cloudsql.client"
    "roles/viewer"
)

for ROLE in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$GSA_EMAIL" \
        --role="$ROLE" --quiet >/dev/null
done

# 3.1 Grant Reasoning Engine Role
RE_SERVICE_AGENT="service-$PROJECT_NUMBER@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$RE_SERVICE_AGENT" \
    --role="roles/aiplatform.reasoningEngineServiceAgent" --quiet >/dev/null

# 3.2 Grant IAM Roles to the Cloud Build Service Account
CLOUDBUILD_SA="$PROJECT_NUMBER@cloudbuild.gserviceaccount.com"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CLOUDBUILD_SA" \
    --role="roles/resourcemanager.projectIamAdmin" --quiet >/dev/null

# 3.3 Grant Admin Roles to the Compute Engine Default SA
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$COMPUTE_SA" \
    --role="roles/container.admin" --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$COMPUTE_SA" \
    --role="roles/storage.admin" --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$COMPUTE_SA" \
    --role="roles/eventarc.admin" --quiet >/dev/null

# 4. Bind K8s Service Account to Google Service Account (Workload Identity)
echo "Binding Workload Identity..."
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT_ID.svc.id.goog[$NAMESPACE/$KSA_NAME]" --quiet

# 5. Enable Eventarc Permissions
echo "Configuring Event-Driven permissions..."
STORAGE_AGENT=$(gcloud storage service-agent --project=$PROJECT_ID)
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$STORAGE_AGENT" \
    --role="roles/pubsub.publisher" --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$GSA_EMAIL" \
    --role="roles/eventarc.eventReceiver" --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$GSA_EMAIL" \
    --role="roles/pubsub.subscriber" --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$GSA_EMAIL" \
    --role="roles/monitoring.metricWriter" --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$GSA_EMAIL" \
    --role="roles/eventarc.admin" --quiet >/dev/null
    
# 6. Configure Encryption & Secrets
echo "Setting up KMS and Secret Manager access..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$GSA_EMAIL" \
    --role="roles/secretmanager.secretAccessor" --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$GSA_EMAIL" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$GSA_EMAIL" \
    --role="roles/cloudsql.client" --quiet >/dev/null
             
# ==========================================
# 7. Network Hardening (PSC) - MANUAL BRIDGE
# ==========================================
echo "Configuring Private Service Connect (Manual Bridge)..."
SERVICE_ATTACHMENT=$(gcloud sql instances describe $DB_NAME \
    --project=$PROJECT_ID \
    --format="value(pscServiceAttachmentLink)")

if [ -z "$SERVICE_ATTACHMENT" ]; then
    echo "❌ Error: Could not find PSC Service Attachment for $DB_NAME. Is the instance PSC-enabled?"
    exit 1
fi
echo "Targeting Service Attachment: $SERVICE_ATTACHMENT"

gcloud compute addresses create $PSC_ENDPOINT_NAME \
    --region=$REGION \
    --subnet=$VPC_NAME \
    --project=$PROJECT_ID 2>/dev/null || echo "ℹ️  Address $PSC_ENDPOINT_NAME already exists"

PSC_IP_ADDR=$(gcloud compute addresses describe $PSC_ENDPOINT_NAME \
    --region=$REGION \
    --format="value(address)")

if ! gcloud compute forwarding-rules describe $PSC_ENDPOINT_NAME --region=$REGION --project=$PROJECT_ID >/dev/null 2>&1; then
    echo "Creating Forwarding Rule to bridge VPC -> Cloud SQL..."
    gcloud compute forwarding-rules create $PSC_ENDPOINT_NAME \
        --region=$REGION \
        --network=$VPC_NAME \
        --address=$PSC_ENDPOINT_NAME \
        --target-service-attachment=$SERVICE_ATTACHMENT \
        --project=$PROJECT_ID
else
    echo "✅ Forwarding Rule $PSC_ENDPOINT_NAME already exists."
fi

# 8. Enable GKE Managed Secret Manager Add-on
echo "Enabling Managed Secret Manager add-on for GKE..."
gcloud container clusters update $CLUSTER_NAME \
    --enable-secret-manager \
    --region=$REGION \
    --project=$PROJECT_ID

# 9. Final Infrastructure Hardening
echo "Performing final infrastructure hardening..."
if ! gcloud secrets describe $DB_SECRET_NAME --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Creating $DB_SECRET_NAME secret..."
    gcloud secrets create $DB_SECRET_NAME --replication-policy="automatic" --project="${PROJECT_ID}"
    
    echo -n "Enter the database password to store in Secret Manager: "
    read -s DB_PASS
    echo -n "$DB_PASS" | gcloud secrets versions add $DB_SECRET_NAME --data-file=-
    echo ""
fi

gcloud secrets add-iam-policy-binding $DB_SECRET_NAME \
    --member="serviceAccount:${GSA_EMAIL}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="${PROJECT_ID}" >/dev/null
        
echo -e "\n=========================================================="
echo "🎉 Infrastructure prep complete!"
echo "⚠️  If you saw any red text or errors above, please fix them and run ./prepare.sh again."
echo "🟢 If everything looks good and error-free, you are officially ready to deploy!"
echo "👉 NEXT STEP: Return to the Google Cloud Marketplace UI and click 'Deploy'."
echo "=========================================================="