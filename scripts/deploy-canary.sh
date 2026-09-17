#!/bin/bash

set -e

# ============================================================
# Rivermark Canary Deployment Script
# ============================================================

IMAGE="$1"

if [ -z "$IMAGE" ]; then
    echo "ERROR: Docker image was not provided."
    exit 1
fi

echo "============================================"
echo "Rivermark Canary Deployment"
echo "============================================"
echo "New image: $IMAGE"


# ============================================================
# Configuration
# ============================================================

BLUE_CONTAINER="rivermark-blue"
CANARY_CONTAINER="rivermark-canary"

BLUE_PORT="5000"
CANARY_PORT="5001"

NGINX_CONFIG="/etc/nginx/conf.d/rivermark.conf"

HEALTH_RETRIES=10
HEALTH_WAIT=3


# ============================================================
# Find current Blue container
# ============================================================

echo ""
echo "Checking current Blue container..."

if docker ps --format '{{.Names}}' | grep -q "^${BLUE_CONTAINER}$"; then
    echo "Blue container is running."
else
    echo "ERROR: Blue container is not running."
    exit 1
fi


# ============================================================
# Pull new image
# ============================================================

echo ""
echo "Pulling new Docker image..."

docker pull "$IMAGE"


# ============================================================
# Remove old Canary if it exists
# ============================================================

echo ""
echo "Removing old Canary container if present..."

docker rm -f "$CANARY_CONTAINER" 2>/dev/null || true


# ============================================================
# Start new Canary
# ============================================================

echo ""
echo "Starting new Canary container..."

docker run -d \
    --name "$CANARY_CONTAINER" \
    -p 127.0.0.1:${CANARY_PORT}:5000 \
    -e APP_VERSION="${IMAGE##*:}" \
    "$IMAGE"

echo "Canary container started."


# ============================================================
# Canary Health Check
# ============================================================

echo ""
echo "Checking Canary health..."

CANARY_HEALTHY=false

for i in $(seq 1 "$HEALTH_RETRIES"); do

    echo "Health check attempt $i/$HEALTH_RETRIES..."

    if curl -fsS "http://127.0.0.1:${CANARY_PORT}/health" > /dev/null; then
        echo "Canary is healthy."
        CANARY_HEALTHY=true
        break
    fi

    sleep "$HEALTH_WAIT"
done


# ============================================================
# Rollback Function
# ============================================================

rollback() {

    echo ""
    echo "============================================"
    echo "CANARY FAILED - ROLLING BACK"
    echo "============================================"

    cat > "$NGINX_CONFIG" <<EOF
upstream rivermark_backend {
    server 127.0.0.1:${BLUE_PORT} weight=100;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://rivermark_backend;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    nginx -t
    systemctl reload nginx

    echo "Traffic restored to Blue."

    docker rm -f "$CANARY_CONTAINER" 2>/dev/null || true

    echo "Failed Canary removed."

    exit 1
}


# ============================================================
# Initial Canary Health Failure
# ============================================================

if [ "$CANARY_HEALTHY" != "true" ]; then
    rollback
fi


# ============================================================
# Function to update Nginx traffic
# ============================================================

update_nginx() {

    BLUE_WEIGHT="$1"
    CANARY_WEIGHT="$2"

    echo ""
    echo "Updating traffic:"
    echo "Blue   = ${BLUE_WEIGHT}%"
    echo "Canary = ${CANARY_WEIGHT}%"

    cat > "$NGINX_CONFIG" <<EOF
upstream rivermark_backend {
    server 127.0.0.1:${BLUE_PORT} weight=${BLUE_WEIGHT};
    server 127.0.0.1:${CANARY_PORT} weight=${CANARY_WEIGHT};
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://rivermark_backend;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    nginx -t

    systemctl reload nginx

    echo "Nginx traffic updated successfully."
}


# ============================================================
# Canary Health Check Function
# ============================================================

check_canary() {

    echo ""
    echo "Checking Canary health..."

    for i in $(seq 1 "$HEALTH_RETRIES"); do

        echo "Health check attempt $i/$HEALTH_RETRIES..."

        if curl -fsS "http://127.0.0.1:${CANARY_PORT}/health" > /dev/null; then
            echo "Canary is healthy."
            return 0
        fi

        sleep "$HEALTH_WAIT"
    done

    return 1
}


# ============================================================
# Stage 1 - 90/10
# ============================================================

echo ""
echo "============================================"
echo "STAGE 1: 90% BLUE / 10% CANARY"
echo "============================================"

update_nginx 90 10

if ! check_canary; then
    rollback
fi


# ============================================================
# Stage 2 - 70/30
# ============================================================

echo ""
echo "============================================"
echo "STAGE 2: 70% BLUE / 30% CANARY"
echo "============================================"

update_nginx 70 30

if ! check_canary; then
    rollback
fi


# ============================================================
# Stage 3 - 50/50
# ============================================================

echo ""
echo "============================================"
echo "STAGE 3: 50% BLUE / 50% CANARY"
echo "============================================"

update_nginx 50 50

if ! check_canary; then
    rollback
fi


# ============================================================
# Stage 4 - 100% Canary
# ============================================================

echo ""
echo "============================================"
echo "STAGE 4: 100% CANARY"
echo "============================================"

update_nginx 0 100


# ============================================================
# Promote Canary to Blue
# ============================================================

echo ""
echo "============================================"
echo "PROMOTING CANARY TO BLUE"
echo "============================================"

docker stop "$BLUE_CONTAINER"
docker rm "$BLUE_CONTAINER"

docker rename "$CANARY_CONTAINER" "$BLUE_CONTAINER"


# ============================================================
# Recreate Nginx configuration with Blue
# ============================================================

cat > "$NGINX_CONFIG" <<EOF
upstream rivermark_backend {
    server 127.0.0.1:${BLUE_PORT} weight=100;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://rivermark_backend;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF


# ============================================================
# Reload Nginx
# ============================================================

nginx -t

systemctl reload nginx


# ============================================================
# Final Health Check
# ============================================================

echo ""
echo "Final Blue health check..."

if ! curl -fsS "http://127.0.0.1:${BLUE_PORT}/health" > /dev/null; then

    echo "ERROR: Promoted Blue failed health check."

    exit 1
fi


echo ""
echo "============================================"
echo "CANARY DEPLOYMENT SUCCESSFUL"
echo "============================================"

echo "New Blue image: $IMAGE"
echo "Traffic: 100% Blue"