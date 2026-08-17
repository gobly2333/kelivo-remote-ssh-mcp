#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${ROOT_DIR}/scripts/install.sh"
bash -n "${ROOT_DIR}/scripts/start.sh"
bash -n "${ROOT_DIR}/scripts/status.sh"

rg -q -- '--outputTransport streamableHttp' "${ROOT_DIR}/scripts/start.sh"
rg -q -- '--streamableHttpPath' "${ROOT_DIR}/scripts/start.sh"
rg -q -- 'Kelivo transport: HTTP \(Streamable HTTP\)' "${ROOT_DIR}/scripts/install.sh"
rg -q -- '/mcp' "${ROOT_DIR}/README.md"

if rg -n --hidden \
  --glob '!.git/**' \
  --glob '!tests/static-checks.sh' \
  '(CF_TUNNEL_TOKEN|BEGIN (RSA|OPENSSH) PRIVATE KEY|SSH_PASSWORD=.{4,}|[0-9a-f]{32}\.cfargotunnel\.com)' \
  "${ROOT_DIR}"; then
  echo "Potential secret found." >&2
  exit 1
fi

echo "Static checks passed."
