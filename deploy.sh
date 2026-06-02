#!/usr/bin/env bash
# One-shot Azure deploy for agent-chat-ui.
#
# Run inside Azure Cloud Shell (Bash), from the repo root:
#     bash deploy.sh            # cleans up first, then deploys fresh
#     bash deploy.sh clean       # only tear down + purge soft-deleted OpenAI
#     SKIP_CLEAN=1 bash deploy.sh  # deploy without the upfront cleanup
#
# Cloud Shell is already logged in, so this script reads your Azure OpenAI key
# itself — you never type or paste a secret. Press Enter to accept defaults.
set -euo pipefail

say() { printf '\n==> %s\n' "$*"; }

MODE=${1:-deploy}

# --- 0. login check -------------------------------------------------------
az account show -o none 2>/dev/null || { echo "Not logged in. Run: az login"; exit 1; }
say "Subscription: $(az account show --query name -o tsv)"

SUFFIX=$(az account show --query id -o tsv | tr -d '-' | cut -c1-10)
AOAI=aoai-agentchat-$SUFFIX    # globally unique Azure OpenAI resource

# Purge any soft-deleted Azure OpenAI accounts left from earlier runs (the
# thing that makes re-runs hang with "already exists"). Safe no-op otherwise.
purge_soft_deleted() {
  az cognitiveservices account list-deleted -o tsv \
    --query "[?name=='$AOAI'].[name,location]" 2>/dev/null | while read -r n l; do
      [ -n "$n" ] || continue
      echo "    purging soft-deleted $n ($l) ..."
      az cognitiveservices account purge -n "$n" -g "${RG:-agent-chat-rg}" -l "$l" -o none 2>/dev/null || true
  done
}

# Full teardown: delete the resource group (blocking) + purge soft-deleted.
do_clean() {
  say "Cleanup: deleting resource group '$RG' (waits until gone) ..."
  az group delete -n "$RG" --yes 2>/dev/null || true
  say "Cleanup: purging soft-deleted Azure OpenAI accounts ..."
  purge_soft_deleted
}

# --- clean mode: tear everything down, then exit --------------------------
if [ "$MODE" = "clean" ] || [ "$MODE" = "--clean" ]; then
  RG=agent-chat-rg
  do_clean
  say "Clean. Now run:  bash deploy.sh"
  exit 0
fi

# --- 1. settings (press Enter for [default]) ------------------------------
read -rp "Resource group [agent-chat-rg]: " RG;  RG=${RG:-agent-chat-rg}
read -rp "Location       [eastus]: "        LOC; LOC=${LOC:-eastus}

APP=agent-chat-ui
ENVNAME=agent-chat-env
DEPLOY_NAME=chat               # must match azure/chat in litellm.config.yaml
API_VERSION=2024-10-21
ACR=acragentchat$SUFFIX        # globally unique, lowercase, no hyphens
MASTER_KEY="sk-$(openssl rand -hex 16)"

cat <<EOF

Plan:
  Resource group : $RG ($LOC)
  Azure OpenAI   : $AOAI  ->  deployment '$DEPLOY_NAME' (model auto-selected)
  Registry       : $ACR
  Container App  : $APP
EOF
read -rp "Proceed? [Y/n]: " GO; case "${GO:-Y}" in [nN]*) echo "aborted"; exit 0;; esac

# --- always start clean (set SKIP_CLEAN=1 to keep existing resources) -----
if [ "${SKIP_CLEAN:-0}" = "1" ]; then
  say "SKIP_CLEAN=1 set — keeping existing resources."
else
  do_clean
fi

# --- 2. providers + extension --------------------------------------------
say "Registering resource providers (idempotent) ..."
for P in Microsoft.CognitiveServices Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry; do
  az provider register -n "$P" -o none 2>/dev/null || true
done
az extension add -n containerapp --upgrade -y -o none 2>/dev/null || true

wait_provider() {
  for _ in $(seq 1 30); do
    [ "$(az provider show -n "$1" --query registrationState -o tsv 2>/dev/null)" = "Registered" ] && return 0
    sleep 6
  done
  echo "    (warning: $1 still registering; continuing)"
}
wait_provider Microsoft.CognitiveServices
wait_provider Microsoft.App

# --- 3. resource group ----------------------------------------------------
say "Resource group ..."
az group create -n "$RG" -l "$LOC" -o none

# --- 4. Azure OpenAI resource + model deployment --------------------------
say "Azure OpenAI resource ..."
if ! az cognitiveservices account show -n "$AOAI" -g "$RG" -o none 2>/dev/null; then
  # Self-heal: a same-named account soft-deleted by an earlier teardown blocks
  # creation with "already exists". Purge it first, then create.
  purge_soft_deleted
  az cognitiveservices account create -n "$AOAI" -g "$RG" -l "$LOC" \
    --kind OpenAI --sku S0 --custom-domain "$AOAI" --yes -o none
fi

say "Selecting a current (non-deprecated) chat model in $LOC ..."
MODELS_JSON=$(az cognitiveservices account list-models -n "$AOAI" -g "$RG" -o json)
TODAY=$(date -u +%Y-%m-%d)
SEL=$(echo "$MODELS_JSON" | jq -r --arg today "$TODAY" '
  [ .[]
    | select(.format=="OpenAI")
    | select((.capabilities.chatCompletion // "false")=="true")
    | select(((.lifecycleStatus // "")|test("Deprecat"))|not)
    | select(((.deprecation.inference // "9999-12-31")[0:10]) > $today) ] as $m
  | (["gpt-4o","gpt-4o-mini","gpt-4.1","gpt-4.1-mini","gpt-35-turbo"]) as $pref
  | ( [ $pref[] as $p | $m[] | select(.name==$p) ] + $m )
  | .[0] // empty | "\(.name) \(.version)"')
MODEL=${SEL%% *}; MODEL_VERSION=${SEL##* }
[ -n "$MODEL" ] && [ "$MODEL" != "$MODEL_VERSION" ] || {
  echo "!! No available chat model found in $LOC. Re-run and pick another Location"
  echo "   (try: swedencentral, westus, eastus2)."; exit 1; }
say "Chosen model: $MODEL ($MODEL_VERSION)"

# Pick a deployment SKU the model actually offers, by preference.
AVAIL_SKUS=$(echo "$MODELS_JSON" | jq -r --arg n "$MODEL" --arg v "$MODEL_VERSION" \
  '.[]|select(.name==$n and .version==$v)|.skus[]?.name')
SKU=GlobalStandard
for s in GlobalStandard Standard DataZoneStandard GlobalProvisionedManaged; do
  echo "$AVAIL_SKUS" | grep -qx "$s" && { SKU=$s; break; }
done

say "Model deployment '$DEPLOY_NAME' ($MODEL $MODEL_VERSION, $SKU) ..."
if ! az cognitiveservices account deployment show -n "$AOAI" -g "$RG" --deployment-name "$DEPLOY_NAME" -o none 2>/dev/null; then
  az cognitiveservices account deployment create -n "$AOAI" -g "$RG" \
      --deployment-name "$DEPLOY_NAME" --model-name "$MODEL" \
      --model-version "$MODEL_VERSION" --model-format OpenAI \
      --sku-name "$SKU" --sku-capacity 10 -o none 2>/tmp/dep.err || {
        echo; echo "!! Model deployment failed:"; sed 's/^/   /' /tmp/dep.err
        echo "   This is usually region quota. Re-run bash deploy.sh and choose a"
        echo "   different Location (try: swedencentral, westus, eastus2)."
        exit 1; }
fi

AZURE_API_BASE=$(az cognitiveservices account show -n "$AOAI" -g "$RG" --query properties.endpoint -o tsv)
AZURE_API_KEY=$(az cognitiveservices account keys list -n "$AOAI" -g "$RG" --query key1 -o tsv)
say "OpenAI endpoint: $AZURE_API_BASE"

# --- 5. build image in Azure (no local Docker needed) ---------------------
say "Container registry ..."
az acr show -n "$ACR" -o none 2>/dev/null || \
  az acr create -n "$ACR" -g "$RG" --sku Basic --admin-enabled true -o none
say "Building image (a few minutes) ..."
az acr build -r "$ACR" -t "$APP:latest" . -o none
ACR_USER=$(az acr credential show -n "$ACR" --query username -o tsv)
ACR_PASS=$(az acr credential show -n "$ACR" --query 'passwords[0].value' -o tsv)

# --- 6. Container Apps env + the app --------------------------------------
say "Container Apps environment ..."
az containerapp env show -n "$ENVNAME" -g "$RG" -o none 2>/dev/null || \
  az containerapp env create -n "$ENVNAME" -g "$RG" -l "$LOC" -o none

ENVVARS=(
  ANTHROPIC_BASE_URL=http://localhost:4000
  ANTHROPIC_AUTH_TOKEN=secretref:master-key
  AGENT_MODEL=copilot
  "AZURE_API_BASE=$AZURE_API_BASE"
  "AZURE_API_VERSION=$API_VERSION"
  AZURE_API_KEY=secretref:azure-key
)

say "Deploying the app ..."
if az containerapp show -n "$APP" -g "$RG" -o none 2>/dev/null; then
  az containerapp secret set -n "$APP" -g "$RG" \
    --secrets azure-key="$AZURE_API_KEY" master-key="$MASTER_KEY" -o none
  az containerapp update -n "$APP" -g "$RG" \
    --image "$ACR.azurecr.io/$APP:latest" --set-env-vars "${ENVVARS[@]}" -o none
else
  az containerapp create -n "$APP" -g "$RG" --environment "$ENVNAME" \
    --image "$ACR.azurecr.io/$APP:latest" \
    --registry-server "$ACR.azurecr.io" \
    --registry-username "$ACR_USER" --registry-password "$ACR_PASS" \
    --target-port 8000 --ingress external --min-replicas 1 --max-replicas 1 \
    --secrets azure-key="$AZURE_API_KEY" master-key="$MASTER_KEY" \
    --env-vars "${ENVVARS[@]}" -o none
fi
az containerapp ingress sticky-sessions set -n "$APP" -g "$RG" --affinity sticky -o none || true

FQDN=$(az containerapp show -n "$APP" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv)
cat <<EOF

============================================================
 SUCCESS — open this in your browser (give it ~30s first):

     https://$FQDN

 Tear it all down later (deletes resources AND purges OpenAI) with:
     bash deploy.sh clean
============================================================
EOF
