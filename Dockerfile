FROM debian:bookworm-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    openssh-client \
    bc \
    ca-certificates \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy health check script and web server
COPY elasticsearch-health-check.sh .
COPY server.py .
RUN chmod +x elasticsearch-health-check.sh server.py

# Copy SSH configuration
COPY ssh_config /root/.ssh/config
RUN chmod 600 /root/.ssh/config

# Create SSH keys directory
RUN mkdir -p /root/.ssh

# Expose port
EXPOSE 8080

# Set entrypoint to web server
ENTRYPOINT ["python3", "server.py"]