#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="kelivo-remote-ssh-mcp"
CONFIG_DIR="/etc/${APP_NAME}"
INSTALL_DIR="/usr/local/lib/${APP_NAME}"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
  echo "Error: $*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

if [[ "${EUID}" -ne 0 ]]; then
  die "Run this installer as root: sudo bash scripts/install.sh"
fi

if [[ ! -r /etc/os-release ]]; then
  die "Cannot detect operating system. Ubuntu or Debian is required."
fi

# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) die "Unsupported OS: ${ID:-unknown}. Ubuntu or Debian is required." ;;
esac

for dependency in node npm curl openssl; do
  command_exists "${dependency}" || die "Missing ${dependency}. Install Node.js 20+, npm, curl and openssl first."
done

NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
if (( NODE_MAJOR < 20 )); then
  die "Node.js 20 or newer is required. Current: $(node -v)"
fi

if ! command_exists pm2; then
  echo "Installing PM2..."
  npm install -g pm2
fi

echo
echo "Kelivo Remote SSH MCP installer"
echo

read -r -p "Public MCP domain (example: mcp.example.com): " MCP_DOMAIN
MCP_DOMAIN="${MCP_DOMAIN#https://}"
MCP_DOMAIN="${MCP_DOMAIN%%/*}"
[[ -n "${MCP_DOMAIN}" ]] || die "Domain cannot be empty."

read -r -p "SSH host [127.0.0.1]: " SSH_HOST
SSH_HOST="${SSH_HOST:-127.0.0.1}"
read -r -p "SSH port [22]: " SSH_PORT
SSH_PORT="${SSH_PORT:-22}"
[[ "${SSH_PORT}" =~ ^[0-9]+$ ]] || die "SSH port must be numeric."
read -r -p "SSH username [root]: " SSH_USERNAME
SSH_USERNAME="${SSH_USERNAME:-root}"

echo "Authentication:"
echo "  1) Password"
echo "  2) Private key"
read -r -p "Choose [1]: " AUTH_CHOICE
AUTH_CHOICE="${AUTH_CHOICE:-1}"

SSH_PASSWORD=""
SSH_PRIVATE_KEY=""
case "${AUTH_CHOICE}" in
  1)
    read -r -s -p "SSH password: " SSH_PASSWORD
    echo
    [[ -n "${SSH_PASSWORD}" ]] || die "Password cannot be empty."
    ;;
  2)
    read -r -p "Absolute private key path: " SSH_PRIVATE_KEY
    [[ -r "${SSH_PRIVATE_KEY}" ]] || die "Private key is not readable: ${SSH_PRIVATE_KEY}"
    ;;
  *) die "Choose 1 or 2." ;;
esac

read -r -p "Local MCP port [3000]: " MCP_PORT
MCP_PORT="${MCP_PORT:-3000}"
[[ "${MCP_PORT}" =~ ^[0-9]+$ ]] || die "MCP port must be numeric."

MCP_PATH_TOKEN="$(openssl rand -hex 24)"

install -d -m 700 "${CONFIG_DIR}"
install -d -m 755 "${INSTALL_DIR}"
install -m 755 "${SOURCE_DIR}/scripts/start.sh" "${INSTALL_DIR}/start.sh"

export SSH_HOST SSH_PORT SSH_USERNAME SSH_PASSWORD SSH_PRIVATE_KEY AUTH_CHOICE
node - "${CONFIG_DIR}/ssh-config.json" <<'NODE'
const fs = require('fs');
const outputPath = process.argv[2];
const entry = {
  name: 'default',
  host: process.env.SSH_HOST,
  port: Number(process.env.SSH_PORT),
  username: process.env.SSH_USERNAME,
};
if (process.env.AUTH_CHOICE === '1') {
  entry.password = process.env.SSH_PASSWORD;
} else {
  entry.privateKey = process.env.SSH_PRIVATE_KEY;
}
fs.writeFileSync(outputPath, `${JSON.stringify([entry], null, 2)}\n`, { mode: 0o600 });
NODE
unset SSH_PASSWORD SSH_PRIVATE_KEY
chmod 600 "${CONFIG_DIR}/ssh-config.json"

{
  printf 'MCP_DOMAIN=%q\n' "${MCP_DOMAIN}"
  printf 'MCP_PORT=%q\n' "${MCP_PORT}"
  printf 'MCP_PATH_TOKEN=%q\n' "${MCP_PATH_TOKEN}"
  printf 'MCP_LOG_LEVEL=%q\n' "info"
} > "${CONFIG_DIR}/runtime.env"
chmod 600 "${CONFIG_DIR}/runtime.env"

if pm2 describe "${APP_NAME}" >/dev/null 2>&1; then
  echo "Replacing existing PM2 process ${APP_NAME}..."
  pm2 delete "${APP_NAME}"
fi

KELIVO_MCP_CONFIG_DIR="${CONFIG_DIR}" pm2 start "${INSTALL_DIR}/start.sh" \
  --name "${APP_NAME}" \
  --interpreter bash
pm2 save

for _ in {1..20}; do
  if curl --silent --fail "http://127.0.0.1:${MCP_PORT}/healthz" >/dev/null; then
    echo
    echo "MCP is healthy."
    echo "Kelivo transport: SSE"
    echo "Kelivo URL: https://${MCP_DOMAIN}/${MCP_PATH_TOKEN}/sse"
    echo
    echo "Cloudflare Published application Service URL must be: http://localhost:${MCP_PORT}"
    exit 0
  fi
  sleep 1
done

echo
echo "MCP did not become healthy. Check logs:"
echo "  pm2 logs ${APP_NAME} --lines 100 --nostream"
exit 1
