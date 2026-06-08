# Container image for agent-chat-ui.
# Pure Python now — the engine is Pydantic AI (model-agnostic), so no Node /
# Claude CLI is needed. start.sh launches the LiteLLM proxy (:4000) and Chainlit (:8000).
FROM python:3.11-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chmod +x start.sh

# Chainlit ingress port (LiteLLM stays internal on :4000).
EXPOSE 8000

CMD ["./start.sh"]
