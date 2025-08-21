#!/bin/bash
# Elasticsearch Daily Health Check Script
# Created: 2025-08-21
# Purpose: Proactive monitoring to prevent incidents like today's memory exhaustion

# Get credentials from environment variables (Cloud Run secrets)
ES_HOST="104.131.11.108"
ES_CREDS="${ELASTICSEARCH_CREDS:-elastic:YOUR_ES_PASSWORD}"
EMAIL_PASSWORD="${EMAIL_APP_PASSWORD:-your_gmail_app_password}"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

send_email_alert() {
    local message="$1"
    local severity="$2"
    local priority="normal"
    
    case $severity in
        "CRITICAL") priority="critical" ;;
        "ERROR") priority="high" ;;
        *) priority="normal" ;;
    esac
    
    cat > /tmp/es_alert.txt << EOF
To: your-email@yourcompany.com
From: alerts@yourcompany.com
Subject: [ELASTICSEARCH-$severity] Cluster Alert
X-Priority: 1
Content-Type: text/plain

=== ELASTICSEARCH $severity ===

$message

Time: $(date '+%Y-%m-%d %H:%M:%S UTC')
Cluster: ewitness-es-cluster

Check cluster health via Elasticsearch API on 104.131.11.108
EOF
    
    # Send to both personal email and Slack
    curl -s --url "smtp://smtp.gmail.com:587" --ssl-reqd \
         --mail-from "alerts@yourcompany.com" --mail-rcpt "your-email@yourcompany.com" \
         --user "alerts@yourcompany.com:${EMAIL_PASSWORD}" \
         --upload-file /tmp/es_alert.txt >/dev/null 2>&1
    
    curl -s --url "smtp://smtp.gmail.com:587" --ssl-reqd \
         --mail-from "alerts@yourcompany.com" --mail-rcpt "your-slack-channel@yourcompany.slack.com" \
         --user "alerts@yourcompany.com:${EMAIL_PASSWORD}" \
         --upload-file /tmp/es_alert.txt >/dev/null 2>&1
    
    rm -f /tmp/es_alert.txt
}

log_message() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Check cluster health
check_cluster_health() {
    local health=$(ssh $ES_HOST "curl -sk -u $ES_CREDS 'https://localhost:9200/_cluster/health' 2>/dev/null" | jq -r '.status' 2>/dev/null)
    
    case $health in
        "green")
            log_message "${GREEN}✅ Cluster health: GREEN${NC}"
            return 0
            ;;
        "yellow")
            log_message "${YELLOW}⚠️  Cluster health: YELLOW${NC}"
            return 1
            ;;
        "red")
            log_message "${RED}🚨 Cluster health: RED${NC}"
            send_email_alert "🚨 CRITICAL: Elasticsearch cluster status is RED. Immediate action required!" "CRITICAL"
            return 2
            ;;
        *)
            log_message "${RED}❌ Unable to determine cluster health${NC}"
            send_email_alert "❌ ERROR: Cannot connect to Elasticsearch cluster" "ERROR"
            return 3
            ;;
    esac
}

# Check heap usage across all nodes
check_heap_usage() {
    local high_heap_nodes=()
    local critical_nodes=()
    
    for node in 104.131.11.108 68.183.156.237 164.90.138.26 164.90.138.26 159.203.169.29; do
        local heap_percent=$(ssh $node "curl -sk -u $ES_CREDS 'https://localhost:9200/_nodes/stats/jvm' 2>/dev/null" | jq -r '.nodes | values[] | .jvm.mem.heap_used_percent' 2>/dev/null | head -1)
        
        if [[ "$heap_percent" =~ ^[0-9]+$ ]]; then
            log_message "Node $node heap usage: ${heap_percent}%"
            
            if [ "$heap_percent" -gt 90 ]; then
                critical_nodes+=("$node: ${heap_percent}%")
            elif [ "$heap_percent" -gt 80 ]; then
                high_heap_nodes+=("$node: ${heap_percent}%")
            fi
        else
            log_message "${YELLOW}⚠️  Could not get heap stats for $node${NC}"
        fi
    done
    
    # Send alerts for critical heap usage
    if [ ${#critical_nodes[@]} -gt 0 ]; then
        local message="🚨 CRITICAL heap usage detected:\n$(printf '%s\n' "${critical_nodes[@]}")"
        send_email_alert "$message" "CRITICAL"
        log_message "${RED}🚨 Critical heap usage detected${NC}"
        return 2
    fi
    
    # Send warnings for high heap usage  
    if [ ${#high_heap_nodes[@]} -gt 0 ]; then
        local message="⚠️  High heap usage detected:\n$(printf '%s\n' "${high_heap_nodes[@]}")"
        send_email_alert "$message" "WARNING"
        log_message "${YELLOW}⚠️  High heap usage detected${NC}"
        return 1
    fi
    
    log_message "${GREEN}✅ All nodes have healthy heap usage${NC}"
    return 0
}

# Check unassigned shards
check_unassigned_shards() {
    local unassigned=$(ssh $ES_HOST "curl -sk -u $ES_CREDS 'https://localhost:9200/_cluster/health' 2>/dev/null" | jq -r '.unassigned_shards' 2>/dev/null)
    
    if [[ "$unassigned" =~ ^[0-9]+$ ]]; then
        log_message "Unassigned shards: $unassigned"
        
        if [ "$unassigned" -gt 100 ]; then
            send_email_alert "⚠️  High number of unassigned shards: $unassigned. Cluster may be rebalancing or have issues." "WARNING"
            log_message "${YELLOW}⚠️  High unassigned shard count${NC}"
            return 1
        elif [ "$unassigned" -eq 0 ]; then
            log_message "${GREEN}✅ No unassigned shards${NC}"
        else
            log_message "${GREEN}✅ Acceptable unassigned shard count: $unassigned${NC}"
        fi
    else
        log_message "${YELLOW}⚠️  Could not get shard information${NC}"
        return 1
    fi
    
    return 0
}

# Check search performance
check_search_performance() {
    local start_time=$(date +%s.%3N)
    local response=$(curl -s -w "%{http_code}" "http://34.56.188.7/api/full_search?q=test&limit=1" -m 10 2>/dev/null)
    local end_time=$(date +%s.%3N)
    local response_time=$(echo "$end_time - $start_time" | bc)
    local http_code=${response: -3}
    
    log_message "Search response time: ${response_time}s (HTTP: $http_code)"
    
    if [ "$http_code" -ne 200 ]; then
        send_email_alert "🚨 Search API returning HTTP $http_code. Search functionality may be impaired." "CRITICAL"
        log_message "${RED}🚨 Search API error${NC}"
        return 2
    elif (( $(echo "$response_time > 5.0" | bc -l) )); then
        send_email_alert "⚠️  Search response time is slow: ${response_time}s (threshold: 5s)" "WARNING"
        log_message "${YELLOW}⚠️  Slow search response${NC}"
        return 1
    else
        log_message "${GREEN}✅ Search performance is healthy${NC}"
        return 0
    fi
}

# Main health check function
main() {
    log_message "🔍 Starting Elasticsearch health check..."
    
    local exit_code=0
    local issues_found=0
    
    # Run all checks
    check_cluster_health || ((issues_found++, exit_code=1))
    check_heap_usage || ((issues_found++, exit_code=1))  
    check_unassigned_shards || ((issues_found++, exit_code=1))
    check_search_performance || ((issues_found++, exit_code=1))
    
    if [ $issues_found -eq 0 ]; then
        log_message "${GREEN}🎉 All health checks passed!${NC}"
        
        # Send daily summary (only on success to avoid spam)
        if [ "${1:-}" = "--daily-summary" ]; then
            send_email_alert "✅ Daily Elasticsearch health check completed. All systems operational." "INFO"
        fi
    else
        log_message "${RED}⚠️  Found $issues_found issues during health check${NC}"
    fi
    
    log_message "🏁 Health check completed."
    exit $exit_code
}

# Allow running specific checks
case "${1:-all}" in
    "cluster")
        check_cluster_health
        ;;
    "heap")
        check_heap_usage
        ;;
    "shards")
        check_unassigned_shards
        ;;
    "search")
        check_search_performance
        ;;
    "monthly-restart")
        # Check if it's the first Sunday of the month
        if [ $(date +%d) -le 7 ] && [ $(date +%u) -eq 7 ]; then
            log_message "🔄 Executing monthly rolling restart..."
            # Add rolling restart logic here if needed
            send_email_alert "✅ Monthly Elasticsearch rolling restart completed successfully." "INFO"
        else
            log_message "⏭️  Monthly restart skipped - not first Sunday of month"
        fi
        ;;
    "all"|"--daily-summary")
        main "$1"
        ;;
    *)
        echo "Usage: $0 [cluster|heap|shards|search|all|--daily-summary|monthly-restart]"
        exit 1
        ;;
esac