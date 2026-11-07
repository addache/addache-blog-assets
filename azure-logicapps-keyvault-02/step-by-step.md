### Cloud Shellで構築するための準備

Azure Cloud Shellの **Bash** を使用します。対象サブスクリプションに「所有者」相当の権限があるユーザーで、Azureポータルへログインしてください。

リソース名はGUI版と同じものを使用します。同じ場所に同名リソースがある場合、そのリソースの設定を更新します。削除済みのKey Vaultがソフト削除状態で残っている場合は同名で新規作成できないため、テストでは別の一意なVault名を指定してください。

#### 構築用ファイルを取得する

```bash
mkdir -p ~/azure-logicapps-keyvault-02
cd ~/azure-logicapps-keyvault-02
umask 077

BASE_URL='https://raw.githubusercontent.com/addache/addache-blog-assets/main/azure-logicapps-keyvault-02'

curl -fSLo setup.sh "$BASE_URL/setup.sh"
curl -fSLo settings.example.sh "$BASE_URL/settings.example.sh"
curl -fSLo logic-app-resource.template.json "$BASE_URL/logic-app-resource.template.json"

if [[ ! -f settings.local.sh ]]; then
  cp settings.example.sh settings.local.sh
fi
chmod 600 settings.local.sh
code settings.local.sh
```

#### 設定値を編集する

開いた `settings.local.sh` の設定値を編集します。

```bash
# Azure Cloud Shell / Bash. Edit only settings.local.sh.
# Enter the subscription ID (GUID), not its display name.
SUBSCRIPTION_ID='REPLACE_WITH_SUBSCRIPTION_ID'
LOCATION='japaneast'
RG_NAME='Addache-Test'
KV_NAME='key-testsecrets'
LOGICAPP_NAME='Lap-TestSecrets'
ALLOWED_IP_CIDR='REPLACE_WITH_HOME_PUBLIC_IPV4/32'
RETENTION_DAYS=7

RDP_HOST='localhost'
RDP_USER='REPLACE_WITH_WINDOWS_USER'
RDP_PASS='REPLACE_WITH_WINDOWS_PASSWORD'
APP_ENABLED='ON'
COPY_FROM='FromFolder'
COPY_TO='ToFolder'
```

`REPLACE_WITH...` をご自身の値へ置き換えてください。

##### サブスクリプションID

`SUBSCRIPTION_ID` には表示名ではなく、ハイフンを含む36文字のIDを設定します。以下で `SubscriptionId` 列を確認できます。

```bash
az account list \
  --query '[].{subscriptionName:name,subscriptionId:id}' \
  --output table
```

##### リソース名と送信元IP

`RG_NAME`・`KV_NAME`・`LOGICAPP_NAME` はGUI版と同じ名前で構いません。`KV_NAME` は、ご自身の既存Vault名か、新規作成できる一意な名前にしてください。このサンプルは3～24文字の英小文字・数字・ハイフンを想定し、先頭を英字、末尾を英数字にします。

`ALLOWED_IP_CIDR` には、BATを実行するWindows PC側のグローバルIPv4アドレスへ `/32` を付けて設定します。Cloud Shell側のIPではありません。

##### シークレット値

`RDP_USER`・`RDP_PASS` は接続先Windowsのアカウントです。Azureへログインするユーザーのパスワードではありません。

設定ファイルにパスワードが平文で残るため、このファイルや設定画面は公開しないでください。値自体に単一引用符がある場合は、`'ab'\''cd'` のようにBashの記法でエスケープします。

編集後は、エディター内で **Ctrl＋S** で保存し、**Ctrl＋Q** で閉じてコマンド入力へ戻ります。

#### 一括実行する場合

以下を実行すれば、以降の構築作業をまとめて実行できます。**一括実行した場合、後続のコマンドを重ねて実行する必要はありません。**

```bash
bash setup.sh
```

ただし、処理内容を確認しながら進めるため、本記事では **一括実行せず、以下を順番に実行する方法をおすすめします。**

### 設定値を現在のCloud Shellへ読み込む

`settings.local.sh` を編集しただけでは、コマンド入力で変数を参照できません。次のコマンドで、現在操作しているBashへ設定値を読み込みます。

```bash
cd ~/azure-logicapps-keyvault-02
set +x
set +v
umask 077

source ./settings.local.sh
mkdir -p .generated
```

`source` は、設定ファイルの変数を現在のシェルへ読み込む操作です。ここではAzureリソースを作成しません。

一方、`bash setup.sh` は別のBashで実行されるため、その内部の変数は、終了後のコマンド入力には残りません。

以降は **同じCloud Shellで上から順番に** 実行してください。設定ファイルを編集し直した場合は `source ./settings.local.sh` を再実行します。リソース名を変更した場合は、リソースIDを取得する手順からやり直してください。Cloud Shellを再起動した場合も、変数の読み込みと必要なIDの再取得が必要です。

### Key Vaultを作成する

#### サブスクリプションとリソースを設定する

```bash
az account set --subscription "$SUBSCRIPTION_ID"
az account show --query '{subscription:name,subscriptionId:id}' --output table
az provider register --namespace Microsoft.KeyVault --wait --output none
az provider register --namespace Microsoft.Logic --wait --output none
az group create --name "$RG_NAME" --location "$LOCATION" --output none
az keyvault create \
  --name "$KV_NAME" --resource-group "$RG_NAME" --location "$LOCATION" \
  --sku standard --enable-rbac-authorization true \
  --public-network-access Enabled --default-action Allow --output none
KV_ID="$(az keyvault show --name "$KV_NAME" --resource-group "$RG_NAME" --query id --output tsv)"
```

`az account set` で対象サブスクリプションを選択してから、リソースプロバイダー、リソースグループ、Key Vaultを設定します。

`KV_ID` は今回のKey VaultのリソースIDです。後の権限設定で使うため、作成後に取得して変数へ保存します。

Key Vaultは標準プラン、アクセス許可モデルはAzure RBACです。Key Vaultの `--sku standard` は、Logic AppsのStandardプランを指定するものではありません。

> エラーが表示された場合は、その原因を解消してから次の手順へ進んでください。以降の手順も同様です。

#### 自分へKey Vault Administrator権限を付与する

GUI版の「キー コンテナー管理者」を、現在ログインしている自分自身へ割り当てます。

```bash
USER_ID="$(az ad signed-in-user show --query id --output tsv)"
# Key Vault Administrator / キー コンテナー管理者 (same role as article 01).
az role assignment create \
  --assignee-object-id "$USER_ID" --assignee-principal-type User \
  --role '00482a5a-887f-4fb3-b363-3b7fe8e74483' \
  --scope "$KV_ID" --output none

```

`USER_ID` はログイン中ユーザーのIDです。ロールは日本語表示に依存しないIDで指定しています。

| 対象 | GUI上の表示 | 英語名 |
|---|---|---|
| 読者本人 | キー コンテナー管理者 | Key Vault Administrator |
| Logic Apps | キー コンテナー シークレット ユーザー | Key Vault Secrets User |

所有者であっても、シークレット操作用の権限は別途必要です。[Microsoft Learn：ロールの定義](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/security)

##### 権限が反映されたことを確認する

```bash
az keyvault secret list \
  --vault-name "$KV_NAME" \
  --output none \
  && echo 'Key Vaultへのアクセスを確認できました。'
```

権限付与直後は反映に時間がかかります。権限エラーが出た場合は、少し待ってこの確認コマンドを再実行してください。成功してから次へ進みます。確認ではシークレット値を表示しません。

#### テスト用シークレットを登録する

GUI版と同じ6個を、読み込んだ変数から登録します。

```bash
# --output none prevents secret set from printing secret values.
az keyvault secret set --vault-name "$KV_NAME" --name RDP-HOST --value="$RDP_HOST" --output none
az keyvault secret set --vault-name "$KV_NAME" --name RDP-USER --value="$RDP_USER" --output none
az keyvault secret set --vault-name "$KV_NAME" --name RDP-PASS --value="$RDP_PASS" --output none
az keyvault secret set --vault-name "$KV_NAME" --name APP-ENABLED --value="$APP_ENABLED" --output none
az keyvault secret set --vault-name "$KV_NAME" --name COPY-FROM --value="$COPY_FROM" --output none
az keyvault secret set --vault-name "$KV_NAME" --name COPY-TO --value="$COPY_TO" --output none
unset RDP_PASS
az keyvault secret list --vault-name "$KV_NAME" --query '[].name' --output table
```

`--output none` で登録結果の値を表示しないようにしています。最後は名前だけを一覧表示します。

同じ名前へ再登録すると、シークレットの新しいバージョンが作成されます。`RDP_PASS` は登録後に `unset` しているため、この登録手順を繰り返す場合は、先に `source ./settings.local.sh` で再読み込みしてください。

### Logic Appsを作成する

#### JSONを置換し、Consumptionで作成する

[GitHubのJSONテンプレート](https://github.com/addache/addache-blog-assets/blob/main/azure-logicapps-keyvault-02/logic-app-resource.template.json)には、ワークフロー、マネージドID、IP制限、実行履歴の設定をまとめています。

```bash
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
```

`sed` で設定値を置換し、`jq` で履歴日数を数値へ整えてから、`az rest` で投入します。シークレット値はJSONへ埋め込みません。

`WORKFLOW_ID` はLogic AppsのリソースID、`WORKFLOW_API` は作成・確認に使う管理APIのURLです。以降の手順でも使います。

作成するリソースの種類はConsumptionの `Microsoft.Logic/workflows` です。Standard用のApp Serviceプランは作成しません。

#### Logic AppsへKey Vault Secrets User権限を付与する

作成したLogic AppsのマネージドIDを取得して、今回のKey Vaultに対する読み取り権限を割り当てます。

```bash
PRINCIPAL_ID="$(az rest --method get \
  --url "$WORKFLOW_API" \
  --query identity.principalId \
  --output tsv)"

if [[ -n "$PRINCIPAL_ID" && "$PRINCIPAL_ID" != None && "$PRINCIPAL_ID" != null ]]; then
  az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role '4633458b-17de-408a-b874-0445c86b69e6' \
    --scope "$KV_ID" \
    --output none
else
  echo 'マネージドIDを取得できませんでした。少し待って、この手順を再実行してください。'
fi
```

GUI版で「キー コンテナー シークレット ユーザー」を選び、Logic Appsをメンバーに追加する操作に対応します。IDを取得できなかった場合は、ここで止めて再実行してください。

こちらの権限も反映に時間がかかる場合があります。後の接続テストで権限エラーが出た場合は、数分待って再度試してください。

#### IP制限と履歴設定

作成時のJSONに、以下を含めています。別途設定するコマンドは不要です。

| 項目 | 設定 |
|---|---|
| HTTPトリガーの送信元IP | `ALLOWED_IP_CIDR` |
| 実行履歴の保存期間 | `RETENTION_DAYS`（初期値7日） |
| HTTPアクションのSecure outputs | ON |
| Response-MyHomeのSecure inputs | ON |

### HTTP URLを取得する

```bash
TRIGGER_NAME='When_an_HTTP_request_is_received'

CALLBACK_URL="$(az rest --method post \
  --url "https://management.azure.com$WORKFLOW_ID/triggers/$TRIGGER_NAME/listCallbackUrl?api-version=2016-06-01" \
  --query value \
  --output tsv)"

if [[ "$CALLBACK_URL" == https://* && "$CALLBACK_URL" == *sig=* ]]; then
  printf '%s\n' "$CALLBACK_URL" > .generated/callback-url.txt
  sed -i 's/%/%%/g' .generated/callback-url.txt
  chmod 600 .generated/callback-url.txt
  echo 'BAT貼り付け用のHTTP URLを .generated/callback-url.txt に保存しました。'
else
  echo 'HTTP URLを取得できませんでした。エラーを確認してください。'
fi
unset CALLBACK_URL
```

取得した署名付きURLを `.generated/callback-url.txt` へ保存したあと、`sed` で `%` を `%%` に置き換えます。たとえば `%2F` は `%%2F` になります。

表示した内容を、そのままBAT冒頭の `URI` へ貼り付けてください。**すでに変換済みなので、手動でさらに `%` を増やす必要はありません。**

```bash
cat .generated/callback-url.txt
```

TXT内はBATソースへの貼り付け用です。ブラウザーやcurlで直接呼ぶURLには、Azureから取得した未変換の値を使います。

`sed` の行だけを繰り返すと `%` がさらに増えるため、やり直す場合はURL取得・TXTへの保存からまとめて再実行してください。

このURLには認証用の署名が含まれています。URLを含む画面や、設定済みBATを公開しないでください。

### 構築結果を確認する

```bash
az rest --method get --url "$WORKFLOW_API" \
  --query '{resourceType:type,state:properties.state,identity:identity.type,allowedIPs:properties.accessControl.triggers.allowedCallerIpAddresses,retention:properties.runtimeConfiguration.lifetime.count}' \
  --output json
```

以下が確認できれば、設定作業は完了です。

| 項目 | 確認内容 |
|---|---|
| `resourceType` | `Microsoft.Logic/workflows` |
| `state` | `Enabled` |
| `identity` | `SystemAssigned` |
| `allowedIPs` | Windows PC側の許可IP |
| `retention` | `7`（初期値の場合） |

接続テストは、許可した送信元IPのWindows PCから行います。Cloud ShellからのHTTPアクセスは、送信元IPが異なるため拒否される場合があります。

