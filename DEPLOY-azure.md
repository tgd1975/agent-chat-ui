# Deploy agent-chat-ui to Azure

This runs the whole stack as a single container on **Azure Container Apps**, with
**Azure OpenAI** as the LLM behind the LiteLLM proxy. You get a public HTTPS URL
for the Chainlit chat UI.

```
Browser ──HTTPS──▶ Container App (ingress :8000)
                     ├─ Chainlit UI ─▶ Pydantic AI agent (Skills + MCP)
                     │                         │ LLM_BASE_URL=http://localhost:4000/v1
                     └─ LiteLLM proxy :4000 ──▶ Azure OpenAI (gpt-4o deployment)
```

> Note: Agent **Skills** (`SKILL.md`) are an open, model-agnostic standard, so
> they work over Azure OpenAI too. How reliably a skill/tool is triggered depends
> on the model's tool-calling quality — gpt-4o(-mini) handles it well.

## Prerequisites

- Azure CLI (`az`) logged in: `az login`
- An Azure OpenAI resource with a chat model **deployment** (e.g. `gpt-4o`)
- The Container Apps extension: `az extension add --name containerapp --upgrade`

## 1. Gather your Azure OpenAI values

```bash
export AZURE_API_BASE="https://<your-resource>.openai.azure.com"
export AZURE_API_KEY="<azure-openai-key>"
export AZURE_API_VERSION="2024-08-01-preview"
export AZURE_DEPLOYMENT="gpt-4o"                 # your deployment name

# Master key clients use to authenticate to the LiteLLM proxy (you choose this).
export MASTER_KEY="sk-$(openssl rand -hex 16)"
```

## 2. Provision resources

```bash
export RG=agent-chat-rg
export LOC=eastus
export ACR=agentchat$RANDOM            # must be globally unique, lowercase
export APP=agent-chat-ui
export ENVNAME=agent-chat-env

az group create -n $RG -l $LOC
az acr create -n $ACR -g $RG --sku Basic --admin-enabled true
az containerapp env create -n $ENVNAME -g $RG -l $LOC
```

## 3. Build the image in Azure (no local Docker needed)

```bash
az acr build -r $ACR -t $APP:latest .
```

## 4. Create the Container App

```bash
az containerapp create \
  -n $APP -g $RG --environment $ENVNAME \
  --image $ACR.azurecr.io/$APP:latest \
  --registry-server $ACR.azurecr.io \
  --target-port 8000 --ingress external \
  --min-replicas 1 --max-replicas 1 \
  --secrets azure-key="$AZURE_API_KEY" master-key="$MASTER_KEY" \
  --env-vars \
    LLM_BASE_URL=http://localhost:4000/v1 \
    LLM_API_KEY=secretref:master-key \
    ANTHROPIC_AUTH_TOKEN=secretref:master-key \
    AGENT_MODEL=copilot \
    AZURE_API_BASE="$AZURE_API_BASE" \
    AZURE_API_VERSION="$AZURE_API_VERSION" \
    AZURE_DEPLOYMENT="$AZURE_DEPLOYMENT" \
    AZURE_API_KEY=secretref:azure-key
```

Chainlit uses websockets, so pin to one replica (above) and enable sticky sessions:

```bash
az containerapp ingress sticky-sessions set -n $APP -g $RG --affinity sticky
```

## 5. Open it

```bash
az containerapp show -n $APP -g $RG --query properties.configuration.ingress.fqdn -o tsv
# -> https://<that-fqdn>
```

## Updating after code changes

```bash
az acr build -r $ACR -t $APP:latest .
az containerapp update -n $APP -g $RG --image $ACR.azurecr.io/$APP:latest
```

## Try it locally first (optional)

```bash
docker build -t agent-chat-ui .
docker run --rm -p 8000:8000 --env-file .env agent-chat-ui
# -> http://localhost:8000
```

## Teardown

```bash
az group delete -n $RG --yes --no-wait
```
