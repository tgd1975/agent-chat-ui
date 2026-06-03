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
# Fresh OpenAI account name each run: an Azure OpenAI subdomain stays reserved
# for ~48h after a soft-delete, so reusing a fixed name triggers
# "CustomDomainInUse". A new name per run sidesteps that; old ones are purged
# best-effort during cleanup. (Endpoint + key are read dynamically, so the
# changing name doesn't matter to the app.)
AOAI=aoai-agentchat-$(openssl rand -hex 4)

# Purge soft-deleted Azure OpenAI accounts (best effort, all of ours).
purge_soft_deleted() {
  az cognitiveservices account list-deleted -o tsv \
    --query "[?starts_with(name,'aoai-agentchat')].[name,location,resourceGroup]" 2>/dev/null \
  | while IFS=$'\t' read -r n l rg; do
      [ -n "$n" ] || continue
      echo "    purging soft-deleted $n ($l) ..."
      az cognitiveservices account purge -n "$n" -l "$l" -g "${rg:-${RG:-agent-chat-rg}}" -o none \
        || echo "    (could not purge $n — harmless leftover unless you hit a region quota)"
  done
}

# Is OUR exact account ($AOAI) still soft-deleted? That is the only thing that
# blocks (re)creating it. Orphans with other suffixes do NOT block this deploy.
mine_still_deleted() {
  [ -n "$(az cognitiveservices account list-deleted -o tsv --query "[?name=='$AOAI'].name" 2>/dev/null)" ]
}

# Full teardown: delete the resource group (blocking) + purge, waiting only for
# OUR account to clear (not unrelated orphans).
do_clean() {
  say "Cleanup: deleting resource group '$RG' (waits until gone) ..."
  az group delete -n "$RG" --yes 2>/dev/null || true
  say "Cleanup: purging soft-deleted Azure OpenAI accounts ..."
  local i
  for i in 1 2 3 4 5; do
    purge_soft_deleted
    mine_still_deleted || { echo "    cleanup done."; return 0; }
    echo "    waiting for '$AOAI' soft-delete to settle ($i/5) ..."; sleep 10
  done
  echo "    continuing anyway — '$AOAI' will be (re)created next."
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
  # creation. Purge any of ours first, then create.
  purge_soft_deleted
  if ! az cognitiveservices account create -n "$AOAI" -g "$RG" -l "$LOC" \
        --kind OpenAI --sku S0 --custom-domain "$AOAI" --yes -o none 2>/tmp/aoai.err; then
    echo; echo "!! Could not create the Azure OpenAI resource:"; sed 's/^/   /' /tmp/aoai.err
    if grep -qi 'quota' /tmp/aoai.err; then
      echo
      echo "   Region '$LOC' is out of Azure OpenAI quota for your subscription —"
      echo "   usually leftover soft-deleted accounts from earlier attempts that"
      echo "   still hold the slot (they self-purge after ~48h)."
      echo "   >> Easiest fix: re-run 'bash deploy.sh' and pick a DIFFERENT region:"
      echo "        swedencentral   (EU, recommended)"
      echo "        westeurope | eastus2 | eastus"
      LEFT=$(az cognitiveservices account list-deleted -o tsv --query "[?location=='$LOC'].name" 2>/dev/null || true)
      [ -n "$LEFT" ] && { echo "   Soft-deleted accounts still in '$LOC':"; printf '%s\n' "$LEFT" | sed 's/^/        /'; }
    fi
    exit 1
  fi
fi

say "Listing available chat models in $LOC ..."
MODELS_JSON=$(az cognitiveservices account list-models -n "$AOAI" -g "$RG" -o json)
TODAY=$(date -u +%Y-%m-%d)
# Candidate list: one (latest) version per model, cheapest first. We then try
# each in turn until one actually deploys — for a feasibility test we just want
# *any* working LLM, so this maximizes the chance something lands.
CANDIDATES=$(echo "$MODELS_JSON" | jq -r --arg today "$TODAY" '
  def rank($n): (["gpt-4o-mini","gpt-4.1-mini","gpt-35-turbo","gpt-4o","gpt-4.1"]|index($n)) // 999;
  [ .[]
    | select(.format=="OpenAI")
    | select((.capabilities.chatCompletion // "false")=="true")
    | select(((.lifecycleStatus // "")|test("Deprecat"))|not)
    | select(((.deprecation.inference // "9999-12-31")[0:10]) > $today) ]
  | group_by(.name) | map(max_by(.version))
  | sort_by(rank(.name), .name)
  | .[] | "\(.name)\t\(.version)\t\(.skus|map(.name)|join(","))"')
[ -n "$CANDIDATES" ] || {
  echo "!! No chat model available in $LOC. Re-run and pick another Location"
  echo "   (try: swedencentral, westus, eastus2)."; exit 1; }

DEPLOYED=0
while IFS=$'\t' read -r MODEL MODEL_VERSION SKUS; do
  [ -n "$MODEL" ] || continue
  SKU=GlobalStandard
  for s in GlobalStandard Standard DataZoneStandard GlobalProvisionedManaged; do
    case ",$SKUS," in *",$s,"*) SKU=$s; break;; esac
  done
  say "Trying $MODEL ($MODEL_VERSION, $SKU) as deployment '$DEPLOY_NAME' ..."
  for CAP in ${DEPLOY_CAP:-10 5 2 1}; do
    if az cognitiveservices account deployment create -n "$AOAI" -g "$RG" \
        --deployment-name "$DEPLOY_NAME" --model-name "$MODEL" \
        --model-version "$MODEL_VERSION" --model-format OpenAI \
        --sku-name "$SKU" --sku-capacity "$CAP" -o none 2>/tmp/dep.err; then
      say "Deployed $MODEL at ${CAP}k TPM."; DEPLOYED=1; break
    fi
    grep -qiE 'quota|capacity|exceed' /tmp/dep.err \
      && { echo "    ${CAP}k TPM too high here, trying smaller ..."; continue; }
    echo "    $MODEL failed (non-quota); next model ..."; break
  done
  [ "$DEPLOYED" = 1 ] && break
  echo "    no quota for $MODEL here; trying next cheapest model ..."
done <<< "$CANDIDATES"

if [ "$DEPLOYED" != 1 ]; then
  echo; echo "!! Could not deploy ANY model in $LOC:"; sed 's/^/   /' /tmp/dep.err
  echo "   Your subscription has ~0 model quota in this region. Either request an"
  echo "   increase (Azure Portal > Quotas > Cognitive Services), or try another"
  echo "   Location (e.g. eastus2, westus, swedencentral)."
  exit 1
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
