#!/bin/bash
set -e

echo ""
echo "========= Grafana Alloy Installer ========="
echo ""

read -p "Enter Docker container name (example: servana-ai-qa-container): " CONTAINER_NAME
read -p "Enter environment name (example: development / staging / prod): " ENVIRONMENT
read -p "Enter Grafana Loki URL (example: https://logs-prod-028.grafana.net/loki/api/v1/push): " GRAFANA_URL
read -p "Enter Grafana Username: " GRAFANA_USERNAME
read -s -p "Enter Grafana Password: " GRAFANA_PASSWORD
echo ""

echo ""
echo "Installing dependencies..."
apt update -y
apt install -y wget gpg docker.io

echo ""
echo "Adding Grafana repo + key..."
mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
| tee /etc/apt/sources.list.d/grafana.list > /dev/null

apt update -y
apt install -y alloy

echo ""
echo "Creating Alloy config..."

mkdir -p /etc/alloy

cat > /etc/alloy/config.alloy <<EOF
logging {
  level = "info"
  format = "logfmt"
}

// Docker container discovery
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
  refresh_interval = "10s"
}

// Relabel to add container metadata and filter by name
discovery.relabel "docker_containers" {
  targets = discovery.docker.containers.targets

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/?($CONTAINER_NAME)"
    action        = "keep"
  }

  rule {
    source_labels = ["__meta_docker_container_name"]
    target_label  = "container_name"
    regex         = "/?(.*)"
    replacement   = "\$1"
  }

  rule {
    source_labels = ["__meta_docker_container_image"]
    target_label  = "container_image"
  }

  rule {
    source_labels = ["__meta_docker_container_id"]
    target_label  = "container_id"
    regex         = "(.{12}).*"
    replacement   = "\$1"
  }

  rule {
    source_labels = ["__meta_docker_container_state"]
    target_label  = "container_state"
  }
}

// Docker log source
loki.source.docker "default" {
  host    = "unix:///var/run/docker.sock"
  targets = discovery.relabel.docker_containers.output
  labels  = {
    job = "docker-logs",
    environment = "$ENVIRONMENT",
  }
  forward_to = [loki.write.grafana_cloud.receiver]
}

// Grafana Cloud Loki writer
loki.write "grafana_cloud" {
  endpoint {
    url = "$GRAFANA_URL"
    basic_auth {
      username = "$GRAFANA_USERNAME"
      password = "$GRAFANA_PASSWORD"
    }
  }
}
EOF

echo ""
echo "Finding Alloy path..."
ALLOY_PATH=$(which alloy)

if [ -z "$ALLOY_PATH" ]; then
  echo "❌ Alloy not found. Installation failed."
  exit 1
fi

echo "Alloy path: $ALLOY_PATH"

echo ""
echo "Creating systemd service..."

cat > /etc/systemd/system/alloy.service <<EOF
[Unit]
Description=Grafana Alloy
After=network.target docker.service
Requires=docker.service

[Service]
ExecStart=$ALLOY_PATH run /etc/alloy/config.alloy
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

echo ""
echo "Reloading and starting Alloy..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable alloy
systemctl restart alloy

echo ""
echo "Checking status..."
sleep 2
systemctl status alloy --no-pager

echo ""
echo "✅ INSTALLATION COMPLETE"
echo "------------------------------------------------"
echo "Container: $CONTAINER_NAME"
echo "Environment: $ENVIRONMENT"
echo "Grafana URL: $GRAFANA_URL"
echo "------------------------------------------------"
echo ""
echo "To view logs: journalctl -u alloy -f"
