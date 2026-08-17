#!/usr/bin/env bash
set -u

APP_NAME="kelivo-remote-ssh-mcp"
CONFIG_DIR="${KELIVO_MCP_CONFIG_DIR:-/etc/kelivo-remote-ssh-mcp}"

pm2 status "${APP_NAME}"

if [[ -r "${CONFIG_DIR}/runtime.env" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_DIR}/runtime.env"
  echo
  curl --show-error --fail "http://127.0.0.1:${MCP_PORT:-3000}/healthz"
  echo
else
  echo "Runtime config not found: ${CONFIG_DIR}/runtime.env" >&2
fi

if command -v systemctl >/dev/null 2>&1; then
  echo
  systemctl is-active cloudflared || true
fi
