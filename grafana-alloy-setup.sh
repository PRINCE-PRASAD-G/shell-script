#!/bin/bash
set -e

echo "====================================="
echo " Grafana Alloy + Loki Setup Script"
echo "====================================="

# -------------------------------
# Root check
# -------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (use sudo)"
  exit 1
fi

# -------------------------------
# User inputs
# -------------------------------
read -rp "Container name REGEX (e.g. servana-ai-qa-container): " CONTAINER_REGEX
read -rp "Grafana Loki Push URL: " LOKI_URL
read -rp "Grafana Cloud Username: " LOKI_USERNAME
read -rsp "Grafana Cloud Password / API Key: " LOKI_PASSWORD
echo
read -rp "Environment (dev/qa/stage/prod): " ENVIRONMENT
read -rp "Job name (default: docker-logs): " JOB_NAME
JOB_NAME=${JOB_NAME:-docker-logs}

# -------------------------------
# Install base dependencies
# -------------------------------
echo "🔹 Installing base dependencies..."
apt-get update -y
apt-get install -y gpg wget ca-certificates

# -------------------------------
# Docker check (SAFE)
# -------------------------------
echo "🔹 Checking Docker installation..."
if command -v docker &>/dev/null; then
  echo "✅ Docker already installed. Skipping Docker installation."
else
  echo "⚠️ Docker not found. Installing docker.io..."
  apt-get install -y docker.io
  systemctl enable --now docker
fi

# -------------------------------
# Add Grafana repo
# -------------------------------
echo "🔹 Adding Grafana repository..."
mkdir -p /etc/apt/keyrings

wget -q -O - https://apt.grafana.com/gpg.key \
  | gpg --dearmor \
  | tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  | tee /etc/apt/sources.list.d/grafana.list

apt-get update -y
apt-get install -y alloy

# -------------------------------
# Write Alloy config
# -------------------------------
echo "🔹 Creating Alloy configuration..."
mkdir -p /etc/alloy

cat <<EOF >/etc/alloy/config.alloy
logging {
  level  = "info"
  format = "logfmt"
}

discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
  refresh_interval = "10s"
}

discovery.relabel "docker_containers" {
  targets = discovery.docker.containers.targets

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/?(${CONTAINER_REGEX})"
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

loki.source.docker "docker_logs" {
  host    = "unix:///var/run/docker.sock"
  targets = discovery.relabel.docker_containers.output
  labels = {
    job         = "${JOB_NAME}"
    environment = "${ENVIRONMENT}"
  }
  forward_to = [loki.write.grafana_cloud.receiver]
}

loki.write "grafana_cloud" {
  endpoint {
    url = "${LOKI_URL}"
    basic_auth {
      username = "${LOKI_USERNAME}"
      password = "${LOKI_PASSWORD}"
    }
  }
}
EOF

# -------------------------------
# Create systemd service
# -------------------------------
echo "🔹 Creating systemd service..."
ALLOY_BIN=$(command -v alloy)

cat <<EOF >/etc/systemd/system/alloy.service
[Unit]
Description=Grafana Alloy
After=network.target docker.service
Requires=docker.service

[Service]
ExecStart=${ALLOY_BIN} run /etc/alloy/config.alloy
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# -------------------------------
# Start services
# -------------------------------
echo "🔹 Enabling and starting Alloy..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now alloy
systemctl restart alloy

echo "====================================="
echo "✅ Grafana Alloy setup completed"
echo "📊 View logs: journalctl -u alloy -f"
echo "====================================="
