#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR="${KELIVO_MCP_CONFIG_DIR:-/etc/kelivo-remote-ssh-mcp}"
RUNTIME_FILE="${CONFIG_DIR}/runtime.env"
SSH_CONFIG_FILE="${CONFIG_DIR}/ssh-config.json"

if [[ ! -r "${RUNTIME_FILE}" ]]; then
  echo "Missing runtime config: ${RUNTIME_FILE}" >&2
  exit 1
fi

if [[ ! -r "${SSH_CONFIG_FILE}" ]]; then
  echo "Missing SSH config: ${SSH_CONFIG_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${RUNTIME_FILE}"

: "${MCP_DOMAIN:?MCP_DOMAIN is required}"
: "${MCP_PORT:=3000}"
: "${MCP_PATH_TOKEN:?MCP_PATH_TOKEN is required}"
: "${MCP_LOG_LEVEL:=info}"

MCP_PATH="/${MCP_PATH_TOKEN}/mcp"

exec npx -y supergateway \
  --stdio "npx -y @fangjunjie/ssh-mcp-server --config-file ${SSH_CONFIG_FILE}" \
  --outputTransport streamableHttp \
  --port "${MCP_PORT}" \
  --streamableHttpPath "${MCP_PATH}" \
  --healthEndpoint /healthz \
  --logLevel "${MCP_LOG_LEVEL}"
