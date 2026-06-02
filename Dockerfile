# Container image for agent-chat-ui.
# Bundles BOTH runtime layers in one image:
#   * Python  -> Chainlit UI + LiteLLM proxy + Claude Agent SDK
#   * Node    -> the Claude Code CLI that the Agent SDK drives under the hood
#
# start.sh launches the LiteLLM proxy (:4000) and then Chainlit (:8000).
FROM python:3.11-slim

# Node 22 (for @anthropic-ai/claude-code, which the Agent SDK spawns) + curl.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates gnupg \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && npm install -g @anthropic-ai/claude-code \
 && apt-get purge -y gnupg && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chmod +x start.sh

# Chainlit ingress port (LiteLLM stays internal on :4000).
EXPOSE 8000

CMD ["./start.sh"]
