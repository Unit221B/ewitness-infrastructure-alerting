# Elasticsearch Monitoring on Google Cloud Run

Serverless monitoring system for eWitness Elasticsearch cluster that runs health checks and sends email alerts.

## Features

- **Hourly health checks** - Monitor cluster status, heap usage, shards
- **Daily summaries** - Email reports of cluster health
- **Monthly rolling restarts** - Automated maintenance (first Sunday at 2 AM)
- **Email alerts** - Critical/warning notifications to email and Slack
- **Cost-effective** - ~$1-3/month using Cloud Run + Cloud Scheduler

## Architecture

```
Cloud Scheduler → Cloud Run → SSH to DigitalOcean Elasticsearch → Email alerts
```

## Deployment

### Prerequisites

1. **Google Cloud SDK** installed and authenticated
2. **Docker** installed
3. **SSH access** to Elasticsearch nodes configured

### Deploy

```bash
cd /media/generic/8f6026e4-4fcd-4f37-8815-807fdcb8a4043/DEV/ewitness-stack/monitoring
./deploy-cloud-run.sh
```

### Manual Steps

1. **Enable required APIs**:
   ```bash
   gcloud services enable run.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   gcloud services enable cloudscheduler.googleapis.com
   gcloud services enable secretmanager.googleapis.com
   ```

2. **Configure Docker for GCR**:
   ```bash
   gcloud auth configure-docker
   ```

3. **Test deployment**:
   ```bash
   # Get service URL from deployment output
   curl "https://SERVICE_URL/?mode=cluster"
   ```

## Monitoring Modes

| Mode | Description | Schedule |
|------|-------------|----------|
| `all` | Full health check | Hourly |
| `daily-summary` | Daily status email | 8 AM daily |
| `cluster` | Cluster status only | On-demand |
| `heap` | Memory usage check | On-demand |
| `shards` | Shard allocation | On-demand |
| `search` | Search performance | On-demand |
| `monthly-restart` | Rolling restart | First Sunday 2 AM |

## Alert Thresholds

- **Heap >80%** → WARNING email
- **Heap >90%** → CRITICAL email
- **Cluster RED** → P1 CRITICAL email
- **Unassigned shards >100** → WARNING email

## Email Recipients

- **Personal**: your-email@yourcompany.com
- **Slack**: your-slack-channel@yourcompany.slack.com

## Secrets Configuration

The deployment automatically creates these secrets in Secret Manager:

- `elasticsearch-creds` - ES cluster credentials
- `email-app-password` - Gmail app-specific password
- `ssh-private-key` - SSH key for DigitalOcean access

## Cost Breakdown

- **Cloud Run**: ~2000 invocations/month × 30 seconds = ~$1
- **Cloud Scheduler**: 3 jobs × $0.10/month = $0.30
- **Secret Manager**: Free tier covers usage
- **Total**: ~$1.30/month

## Troubleshooting

### Check Cloud Run logs
```bash
gcloud logs tail --format=json --project=ewitness --resource-type=gae_app
```

### Test manually
```bash
# Test health check
curl "https://SERVICE_URL/?mode=all"

# Test specific check
curl "https://SERVICE_URL/?mode=heap"
```

### Update secrets
```bash
echo -n "new-password" | gcloud secrets versions add email-app-password --data-file=-
```

## Migration from Desktop

This replaces the cron jobs that were running on the desktop:

```bash
# Remove old cron jobs
crontab -e
# Remove these lines:
# 0 8 * * * /path/to/elasticsearch-health-check.sh --daily-summary
# 0 * * * * /path/to/elasticsearch-health-check.sh all
# 0 2 * * 0 [ $(date +%d) -le 7 ] && /path/to/elasticsearch-rolling-restart.sh
```

The monitoring is now fully serverless and independent of desktop uptime.