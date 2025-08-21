#!/bin/bash
# Deploy Elasticsearch monitoring to Cloud Run
# Created: 2025-08-21

PROJECT_ID="ewitness"
SERVICE_NAME="elasticsearch-monitoring"
REGION="us-central1"
IMAGE_NAME="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

echo "🚀 Deploying Elasticsearch monitoring to Cloud Run..."

# Authenticate with gcloud
gcloud auth login
gcloud config set project $PROJECT_ID

# Build and push Docker image
echo "📦 Building Docker image..."
docker build -t $IMAGE_NAME .
docker push $IMAGE_NAME

# Create secrets in Secret Manager
echo "🔐 Creating secrets..."
echo -n "elastic:YOUR_ES_PASSWORD" | gcloud secrets create elasticsearch-creds --data-file=- --replication-policy="automatic" || true
echo -n "your_gmail_app_password" | gcloud secrets create email-app-password --data-file=- --replication-policy="automatic" || true

# Get SSH private key and create secret
echo "🔑 Setting up SSH key..."
cat ~/.ssh/id_rsa | gcloud secrets create ssh-private-key --data-file=- --replication-policy="automatic" || true

# Deploy to Cloud Run
echo "☁️  Deploying to Cloud Run..."
gcloud run deploy $SERVICE_NAME \
    --image $IMAGE_NAME \
    --platform managed \
    --region $REGION \
    --allow-unauthenticated \
    --set-env-vars="ELASTICSEARCH_CREDS=/secrets/elasticsearch-creds,EMAIL_APP_PASSWORD=/secrets/email-app-password" \
    --set-secrets="/secrets/elasticsearch-creds=elasticsearch-creds:latest,/secrets/email-app-password=email-app-password:latest,/root/.ssh/id_rsa=ssh-private-key:latest" \
    --memory 512Mi \
    --cpu 1 \
    --timeout 300 \
    --concurrency 1 \
    --max-instances 1

# Get the service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")
echo "✅ Service deployed at: $SERVICE_URL"

# Create Cloud Scheduler jobs
echo "⏰ Setting up Cloud Scheduler jobs..."

# Hourly health check
gcloud scheduler jobs create http elasticsearch-hourly-check \
    --location=$REGION \
    --schedule="0 * * * *" \
    --uri="${SERVICE_URL}/?mode=all" \
    --http-method=GET \
    --description="Hourly Elasticsearch health check" || true

# Daily summary
gcloud scheduler jobs create http elasticsearch-daily-summary \
    --location=$REGION \
    --schedule="0 8 * * *" \
    --uri="${SERVICE_URL}/?mode=daily-summary" \
    --http-method=GET \
    --description="Daily Elasticsearch health summary" || true

# Monthly rolling restart (first Sunday at 2 AM)
gcloud scheduler jobs create http elasticsearch-monthly-restart \
    --location=$REGION \
    --schedule="0 2 * * 0" \
    --uri="${SERVICE_URL}/?mode=monthly-restart" \
    --http-method=GET \
    --description="Monthly Elasticsearch rolling restart" || true

echo "🎉 Deployment complete!"
echo "Monitor at: https://console.cloud.google.com/run/detail/${REGION}/${SERVICE_NAME}"