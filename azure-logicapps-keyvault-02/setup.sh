#!/usr/bin/env bash
# Azure Cloud Shell (Bash): bash setup.sh
# Creates resources and assigns roles in the selected subscription.
set +x
set +v
set -euo pipefail
umask 077

# STEP: prepare
ASSET_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ASSET_DIR"
if [[ ! -f settings.local.sh ]]; then
  echo 'Copy settings.example.sh to settings.local.sh and edit it first.' >&2
  exit 1
fi
source ./settings.local.sh
for name in SUBSCRIPTION_ID LOCATION RG_NAME KV_NAME LOGICAPP_NAME ALLOWED_IP_CIDR RETENTION_DAYS RDP_HOST RDP_USER RDP_PASS APP_ENABLED COPY_FROM COPY_TO; do
  value="${!name:-}"
  if [[ -z "$value" || "$value" == *REPLACE_WITH* ]]; then
    printf 'Set %s in settings.local.sh first.\n' "$name" >&2
    exit 1
  fi
done
[[ "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { echo 'Invalid subscription ID.' >&2; exit 1; }
[[ "$KV_NAME" =~ ^[a-z][a-z0-9-]{1,22}[a-z0-9]$ && "$KV_NAME" != *--* ]] || { echo 'Use a 3-24 character lowercase vault name.' >&2; exit 1; }
[[ "$RG_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Use a simple resource group name.' >&2; exit 1; }
[[ "$LOCATION" =~ ^[a-z0-9]+$ ]] || { echo 'Use a region such as japaneast.' >&2; exit 1; }
[[ "$LOGICAPP_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Use a simple Logic App name.' >&2; exit 1; }
[[ "$ALLOWED_IP_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/32$ ]] || { echo 'Set the Windows PC public IPv4 address followed by /32.' >&2; exit 1; }
IFS=. read -r a b c d <<< "${ALLOWED_IP_CIDR%/32}"
for octet in "$a" "$b" "$c" "$d"; do
  [[ "$octet" =~ ^(0|[1-9][0-9]{0,2})$ ]] && (( octet <= 255 )) || { echo 'Invalid IPv4 octet.' >&2; exit 1; }
done
[[ "$RETENTION_DAYS" =~ ^[1-9][0-9]{0,2}$ ]] && (( RETENTION_DAYS >= 7 && RETENTION_DAYS <= 365 )) || { echo 'Retention must be 7-365 days.' >&2; exit 1; }
for tool in az jq sed; do command -v "$tool" >/dev/null || { echo "Required command missing: $tool" >&2; exit 1; }; done
mkdir -p .generated

# STEP: resources
az account set --subscription "$SUBSCRIPTION_ID"
az account show --query '{subscription:name,id:id}' --output table
az provider register --namespace Microsoft.KeyVault --wait --output none
az provider register --namespace Microsoft.Logic --wait --output none
az group create --name "$RG_NAME" --location "$LOCATION" --output none
az keyvault create \
  --name "$KV_NAME" --resource-group "$RG_NAME" --location "$LOCATION" \
  --sku standard --enable-rbac-authorization true \
  --public-network-access Enabled --default-action Allow --output none
KV_ID="$(az keyvault show --name "$KV_NAME" --resource-group "$RG_NAME" --query id --output tsv)"

# STEP: reader-role
USER_ID="$(az ad signed-in-user show --query id --output tsv)"
[[ -n "$USER_ID" ]] || { echo 'Could not find the signed-in user.' >&2; exit 1; }
# Key Vault Administrator / キー コンテナー管理者 (same role as article 01).
az role assignment create \
  --assignee-object-id "$USER_ID" --assignee-principal-type User \
  --role '00482a5a-887f-4fb3-b363-3b7fe8e74483' \
  --scope "$KV_ID" --output none

# Values are never requested by this access probe.
ready=false
for attempt in {1..30}; do
  if az keyvault secret list --vault-name "$KV_NAME" --output none \
      2>.generated/role-check-error.txt; then
    ready=true
    break
  fi
  printf 'Waiting for Key Vault access (%s/30)...\n' "$attempt"
  sleep 10
done
if [[ "$ready" != true ]]; then
  echo 'Key Vault access is not ready. Check RBAC/network settings and rerun later.' >&2
  echo 'The private error file is .generated/role-check-error.txt.' >&2
  exit 1
fi

# STEP: secrets
# --output none prevents secret set from printing secret values.
az keyvault secret set --vault-name "$KV_NAME" --name RDP-HOST --value="$RDP_HOST" --output none
az keyvault secret set --vault-name "$KV_NAME" --name RDP-USER --value="$RDP_USER" --output none
az keyvault secret set --vault-name "$KV_NAME" --name RDP-PASS --value="$RDP_PASS" --output none
az keyvault secret set --vault-name "$KV_NAME" --name APP-ENABLED --value="$APP_ENABLED" --output none
az keyvault secret set --vault-name "$KV_NAME" --name COPY-FROM --value="$COPY_FROM" --output none
az keyvault secret set --vault-name "$KV_NAME" --name COPY-TO --value="$COPY_TO" --output none
unset RDP_PASS
az keyvault secret list --vault-name "$KV_NAME" --query '[].name' --output table

# STEP: workflow
# Validated names only; secret values never enter this JSON.
sed \
  -e "s|__LOCATION__|$LOCATION|g" \
  -e "s|__KEY_VAULT_NAME__|$KV_NAME|g" \
  -e "s|__ALLOWED_IP_CIDR__|$ALLOWED_IP_CIDR|g" \
  -e "s|__RETENTION_DAYS__|$RETENTION_DAYS|g" \
  logic-app-resource.template.json \
  | jq '.properties.runtimeConfiguration.lifetime.count |= tonumber' \
  > .generated/logic-app-resource.json
jq -e . .generated/logic-app-resource.json >/dev/null
WORKFLOW_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.Logic/workflows/$LOGICAPP_NAME"
WORKFLOW_API="https://management.azure.com$WORKFLOW_ID?api-version=2019-05-01"
# Microsoft.Logic/workflows is the Consumption resource type.
# No Microsoft.Web/sites or App Service plan is created.
az rest --method put --url "$WORKFLOW_API" \
  --headers 'Content-Type=application/json' \
  --body @.generated/logic-app-resource.json --output none

# STEP: logicapp-role
PRINCIPAL_ID=''
for attempt in {1..30}; do
  PRINCIPAL_ID="$(az rest --method get --url "$WORKFLOW_API" --query identity.principalId --output tsv)"
  if [[ -n "$PRINCIPAL_ID" && "$PRINCIPAL_ID" != None && "$PRINCIPAL_ID" != null ]]; then break; fi
  sleep 5
done
[[ -n "$PRINCIPAL_ID" && "$PRINCIPAL_ID" != None && "$PRINCIPAL_ID" != null ]] || { echo 'Managed identity is not ready. Rerun later.' >&2; exit 1; }
# Key Vault Secrets User / キー コンテナー シークレット ユーザー.
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role '4633458b-17de-408a-b874-0445c86b69e6' \
  --scope "$KV_ID" --output none

# STEP: callback
TRIGGER_NAME='When_an_HTTP_request_is_received'
CALLBACK_URL="$(az rest --method post \
  --url "https://management.azure.com$WORKFLOW_ID/triggers/$TRIGGER_NAME/listCallbackUrl?api-version=2016-06-01" \
  --query value --output tsv)"
[[ "$CALLBACK_URL" == https://* && "$CALLBACK_URL" == *sig=* ]] || { echo 'Could not retrieve a signed callback URL.' >&2; exit 1; }
printf '%s\n' "$CALLBACK_URL" > .generated/callback-url.txt
unset CALLBACK_URL
chmod 600 .generated/callback-url.txt

# STEP: verify
az rest --method get --url "$WORKFLOW_API" \
  --query '{resourceType:type,state:properties.state,identity:identity.type,allowedIPs:properties.accessControl.triggers.allowedCallerIpAddresses,retention:properties.runtimeConfiguration.lifetime.count}' \
  --output json
echo 'Setup completed. The private callback URL is in .generated/callback-url.txt.'
echo 'Allow several minutes for the Logic App role assignment to take effect.'
echo 'Test from the allowed Windows PC, not from Cloud Shell.'

