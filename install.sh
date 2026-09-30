#!/bin/bash
# ==============================================================================
#                      AUTOMATED HYBRID AI INFRASTRUCTURE SETUP
# ==============================================================================

set -e

echo "======================================================================"
echo "Preparing Infrastructure: Generating Local AI Orchestration Stack"
echo "======================================================================"

# --- 0. Clean prior build artifacts AND docker volumes ---
echo "Cleaning up old configuration files and database volumes..."
docker compose down -v --remove-orphans > /dev/null 2>&1 || true
rm -rf .env litellm-config.yaml docker-compose.yml

# --- 1. User Inputs & Variable Definitions ---
read -p "Enter Cloud Fallback Model ID [Default: openrouter/openai/gpt-4o]: " INPUT_CLOUD_MODEL
read -s -p "Paste Cloud Provider API Key (Hidden Input): " INPUT_CLOUD_API_KEY
echo ""
read -p "Enter Target Host Local GENERAL Model [Default: llama3.2]: " INPUT_GENERAL_MODEL
read -p "Enter Target Host Local CODING Model [Default: qwen2.5-coder]: " INPUT_CODING_MODEL
read -p "Enter Target Host Local VISION Model [Default: llama3.2-vision]: " INPUT_VISION_MODEL
read -p "Enter Local Ollama Host Endpoint URL [Default: http://host.docker.internal:11434]: " INPUT_LOCAL_AI
read -p "Enter Local Model Timeout in Seconds [Default: 45]: " INPUT_TIMEOUT
read -p "Enter Ollama RAM Retention Time [Default: 10m]: " INPUT_KEEP_ALIVE

CLOUD_MODEL=${INPUT_CLOUD_MODEL:-"openrouter/openai/gpt-4o"}
CLOUD_API_KEY=${INPUT_CLOUD_API_KEY:-"your_placeholder_secret_cloud_token"}
GENERAL_MODEL=${INPUT_GENERAL_MODEL:-"llama3.2"}
CODING_MODEL=${INPUT_CODING_MODEL:-"qwen2.5-coder"}
VISION_MODEL=${INPUT_VISION_MODEL:-"llama3.2-vision"}
LOCAL_AI=${INPUT_LOCAL_AI:-"http://host.docker.internal:11434"}
LITELLM_TIMEOUT=${INPUT_TIMEOUT:-45}
LITELLM_MAX_RETRIES=0
OLLAMA_KEEP_ALIVE=${INPUT_KEEP_ALIVE:-"10m"}

# --- Generate secure cryptographic Master Key and DB Password ---
echo "Generating secure Master Key and Database Password..."
MASTER_KEY="sk-$(openssl rand -hex 16)"
DB_PASSWORD="$(openssl rand -hex 16)"

# --- 2. Environment Variables (.env) ---
echo "Creating environment state repository (.env)..."
cat <<EOF > .env
# Model Configuration
LOCAL_GENERAL_MODEL=${GENERAL_MODEL}
LOCAL_CODING_MODEL=${CODING_MODEL}
LOCAL_VISION_MODEL=${VISION_MODEL}
LOCAL_OLLAMA_ENDPOINT=${LOCAL_AI}
CLOUD_TARGET_MODEL=${CLOUD_MODEL}
CLOUD_API_KEY=${CLOUD_API_KEY}

# Performance & Routing Parameters
LITELLM_TIMEOUT=${LITELLM_TIMEOUT}
LITELLM_MAX_RETRIES=${LITELLM_MAX_RETRIES}
OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE}
LITELLM_WORKERS=4

# LiteLLM Security & UI Authentication
LITELLM_MASTER_KEY=${MASTER_KEY}

# PostgreSQL Configuration
POSTGRES_USER=litellm
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=litellm
DATABASE_URL=postgresql://litellm:${DB_PASSWORD}@postgres:5432/litellm
EOF

# --- 3. LiteLLM Routing Registry (litellm-config.yaml) ---
echo "Creating service orchestration registry (litellm-config.yaml)..."
cat <<EOF > litellm-config.yaml
model_list:
  # 1. General Text AI
  - model_name: general-ai
    litellm_params:
      model: ollama_chat/${GENERAL_MODEL}
      api_base: ${LOCAL_AI}
      timeout: ${LITELLM_TIMEOUT}
      max_retries: ${LITELLM_MAX_RETRIES}

  # 2. Code Generation AI
  - model_name: coding-ai
    litellm_params:
      model: ollama_chat/${CODING_MODEL}
      api_base: ${LOCAL_AI}
      timeout: ${LITELLM_TIMEOUT}
      max_retries: ${LITELLM_MAX_RETRIES}

  # 3. Multimodal / Vision AI
  - model_name: vision-ai
    litellm_params:
      model: ollama_chat/${VISION_MODEL}
      api_base: ${LOCAL_AI}
      timeout: ${LITELLM_TIMEOUT}
      max_retries: ${LITELLM_MAX_RETRIES}

  # 4. Cloud Fallback (Native Vision & Text Support)
  - model_name: hybrid-fallback
    litellm_params:
      model: ${CLOUD_MODEL}
      api_key: os.environ/CLOUD_API_KEY

router_settings:
  fallbacks:
    - general-ai: ["hybrid-fallback"]
    - coding-ai: ["hybrid-fallback"]
    - vision-ai: ["hybrid-fallback"]

litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: "redis" 
    port: 6379

environment_variables:
  HEADROOM_API_BASE: "http://headroom:8787"
EOF

# --- 4. Multi-Container Topology (docker-compose.yml) ---
echo "Creating virtual machine network mapping layout (docker-compose.yml)..."
cat <<'EOF' > docker-compose.yml
version: '3.8'

networks:
  ai_mesh:
    driver: bridge

services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-proxy
    restart: always
    ports:
      - "4000:4000"
    volumes:
      - ./litellm-config.yaml:/app/litellm-config.yaml
    extra_hosts:
      - "host.docker.internal:host-gateway"
    env_file:
      - .env
    networks:
      - ai_mesh
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "3"
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
    depends_on:
      postgres:
        condition: service_healthy
      headroom:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: [
      "--config", "/app/litellm-config.yaml",
      "--host", "0.0.0.0",
      "--port", "4000"
    ]

  postgres:
    image: postgres:15-alpine
    container_name: litellm-db
    restart: always
    env_file:
      - .env
    networks:
      - ai_mesh
    volumes:
      - litellm_pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U litellm -d litellm"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: litellm-cache
    restart: always
    ports:
      - "6379:6379"
    networks:
      - ai_mesh
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "3"
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3
    command: redis-server --save 60 1 --loglevel warning

  headroom:
    image: ghcr.io/headroomlabs-ai/headroom:latest
    container_name: headroom-sidecar
    restart: always
    environment:
      - PORT=8787
    ports:
      - "8787:8787"
    networks:
      - ai_mesh
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "3"
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8787/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant-vector-db
    restart: always
    ports:
      - "6333:6333"
      - "6334:6334"
    volumes:
      - qdrant_storage:/qdrant/storage
    networks:
      - ai_mesh
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "3"
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:6333/readyz || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  qdrant_storage:
  litellm_pg_data:
EOF

# --- 5. Configure Host System Settings ---
echo "======================================================================"
echo "Configuring Host Machine Dependencies..."

if command -v systemctl &> /dev/null && systemctl list-unit-files | grep -q ollama.service; then
  echo "Applying network binding and RAM keep-alive (${OLLAMA_KEEP_ALIVE}) to Ollama service..."
  sudo mkdir -p /etc/systemd/system/ollama.service.d
  echo "[Service]" | sudo tee /etc/systemd/system/ollama.service.d/environment.conf > /dev/null
  echo "Environment=OLLAMA_HOST=0.0.0.0" | sudo tee -a /etc/systemd/system/ollama.service.d/environment.conf > /dev/null
  echo "Environment=OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE}" | sudo tee -a /etc/systemd/system/ollama.service.d/environment.conf > /dev/null
  sudo systemctl daemon-reload
  sudo systemctl restart ollama
fi

if command -v ufw &> /dev/null; then
  echo "Opening firewall port 4000 for external network access..."
  sudo ufw allow 4000/tcp > /dev/null 2>&1 || true
fi

if command -v ollama &> /dev/null; then
  echo "Pulling local general model '${GENERAL_MODEL}' into Ollama..."
  ollama pull "${GENERAL_MODEL}"
  echo "Pulling local coding model '${CODING_MODEL}' into Ollama..."
  ollama pull "${CODING_MODEL}"
  echo "Pulling local vision model '${VISION_MODEL}' into Ollama..."
  ollama pull "${VISION_MODEL}"
fi

# --- 6. Launch Containers ---
echo "Starting Docker Compose stack..."
docker compose up -d

echo "======================================================================"
echo "Installation Complete!"
echo "======================================================================"
echo "LiteLLM Router available at: http://localhost:4000"
echo "Available Model Endpoints:"
echo "  1. general-ai -> local: ${GENERAL_MODEL} (fallback: ${CLOUD_MODEL})"
echo "  2. coding-ai  -> local: ${CODING_MODEL} (fallback: ${CLOUD_MODEL})"
echo "  3. vision-ai  -> local: ${VISION_MODEL} (fallback: ${CLOUD_MODEL})"
echo ""
echo "Admin UI Credentials (http://localhost:4000/ui):"
echo "  Username: admin"
echo "  Password: ${MASTER_KEY}"
echo "======================================================================"
