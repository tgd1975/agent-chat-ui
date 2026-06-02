#!/usr/bin/env bash
# Boot both processes inside the container:
#   1) LiteLLM proxy on :4000  (Anthropic-compatible /v1/messages)
#   2) Chainlit UI on :8000    (the Agent SDK talks to LiteLLM via ANTHROPIC_BASE_URL)
set -euo pipefail

LITELLM_PORT="${LITELLM_PORT:-4000}"
CHAINLIT_PORT="${CHAINLIT_PORT:-8000}"

echo "[start] launching LiteLLM proxy on :${LITELLM_PORT} ..."
litellm --config litellm.config.yaml --port "${LITELLM_PORT}" &
LITELLM_PID=$!

# Make sure the proxy dies with the container.
trap 'kill "${LITELLM_PID}" 2>/dev/null || true' EXIT

echo "[start] waiting for LiteLLM to become ready ..."
for _ in $(seq 1 60); do
  if curl -sf "http://localhost:${LITELLM_PORT}/health/liveliness" >/dev/null 2>&1; then
    echo "[start] LiteLLM is up."
    break
  fi
  if ! kill -0 "${LITELLM_PID}" 2>/dev/null; then
    echo "[start] LiteLLM exited early; aborting." >&2
    exit 1
  fi
  sleep 1
done

echo "[start] launching Chainlit on :${CHAINLIT_PORT} ..."
exec chainlit run app.py --host 0.0.0.0 --port "${CHAINLIT_PORT}" --headless
