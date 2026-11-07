# azure-logicapps-keyvault-02：Cloud Shell / Azure CLI版

対応記事の公開予定URL：https://addache.net/azure-logicapps-keyvault-02/

**下書き用サンプルです。Bash構文とJSONの静的検証を行っています。Azure / Cloud Shellでの実構築は未検証です。**

[01のGUI版](../azure-logicapps-keyvault-01/)に対応する構築手順です。Logic Apps Consumption、Key Vault（Standard / Azure RBAC）、読者本人とLogic Appsへの権限設定、6個のシークレット、HTTPトリガーの送信元IP制限、実行履歴7日を設定します。

## ファイル

| ファイル | 用途 |
|---|---|
| [settings.example.sh](settings.example.sh) | 設定値のサンプル。私用の `settings.local.sh` へコピーして編集 |
| [logic-app-resource.template.json](logic-app-resource.template.json) | Azure CLIの `az rest` からPUTするリソース作成リクエストのテンプレート |
| [setup.sh](setup.sh) | 任意の一括実行版。実行した場合は後続の構築作業は不要 |
| [step-by-step.md](step-by-step.md) | 変数を読み込み、コマンドを順に実行する手順 |

このJSONは02の `setup.sh` から使います。01のコードビュー用JSONとは外側の形式が異なります。

## 実行

対象サブスクリプションで「所有者」相当の権限を持つユーザーが、Azure Cloud ShellのBashで操作します。リソース名はGUI版と同じものを使用できます。同じサブスクリプション・リソースグループに同名のリソースがあれば、そのリソースを更新します。Logic Appsのワークフロー定義・IP制限・履歴設定も更新対象です。

```bash
umask 077
if [[ ! -f settings.local.sh ]]; then
  cp settings.example.sh settings.local.sh
fi
chmod 600 settings.local.sh
code settings.local.sh
# REPLACE_WITH... をすべて置換して保存し、エディターを閉じてから:
source ./settings.local.sh
```

通常は [step-by-step.md](step-by-step.md) のコマンドを上から順に実行してください。`source ./settings.local.sh` は現在のBashに変数を読み込むだけで、Azureリソースは変更しません。`KV_ID`・`USER_ID`・`WORKFLOW_ID`・`WORKFLOW_API`・`PRINCIPAL_ID` は、それぞれの手順で取得します。

まとめて実行する場合は `bash setup.sh` を使用できます。その場合、後続の構築作業は不要です。`bash setup.sh` 内の変数は、終了後のコマンド入力には残りません。

`az`・`jq`・`sed` を使用します。Azureリソースを作成・更新し、料金が発生し得ます。検証はご自身のAzure環境で行ってください。

## GUIのロール名とCLIの対応

| 対象 | GUI上のロール | 英語名 | ロールID |
|---|---|---|---|
| 読者本人 | キー コンテナー管理者 | Key Vault Administrator | `00482a5a-887f-4fb3-b363-3b7fe8e74483` |
| Logic AppsのマネージドID | キー コンテナー シークレット ユーザー | Key Vault Secrets User | `4633458b-17de-408a-b874-0445c86b69e6` |

元記事に合わせたロールです。どちらも今回のKey Vaultをスコープにして割り当てます。権限反映には時間がかかることがあります。

## 設定と注意点

- `ALLOWED_IP_CIDR` はBATを実行するWindows PC側のグローバルIPv4と `/32`。Cloud Shellの送信元IPを自動採用しません。
- Key Vaultはパブリックネットワークを許可し、認可はRBACで制御します。閉域網は構成しません。
- Logic Appsは `Microsoft.Logic/workflows` として作成します。Standard用のApp Serviceプランは作成しません。Key Vaultの `--sku standard` はKey Vaultの価格レベルです。
- `sed` で設定値を置換し、`jq` で履歴日数を数値へ変換します。シークレット値をJSONに埋め込みません。
- シークレット登録は `--output none`。ただし値は私用設定ファイルや実行時の引数に平文で存在します。`--debug` や `bash -x` を使用せず、設定済みファイルを公開しないでください。
- 取得した署名付きURLは `.generated/callback-url.txt` に保存し、`sed` で `%` を `%%` へ変換します。`cat .generated/callback-url.txt` の内容をそのままBATの `URI` へ貼り付けてください。追加の手動変換は不要です。TXTはBATソース用で、ブラウザーやcurlへ直接渡すURLではありません。URLを含む画面も公開しないでください。再変換を避けるため、やり直しはURLの取得・保存から実行します。
- `settings.local.sh` と `.generated/` は `.gitignore` で除外します。実際の署名・シークレットをサンプルへ書き込まないでください。
- 再実行すると同名リソースを更新し、シークレットは新しいバージョンとして登録します。削除処理は含めていません。
- 読者のデータアクセスを最大約5分待ちます。Logic Appsの権限付与後は、反映を待ってから許可したWindows PCでテストしてください。
- BAT部分の02記事への載せ方は未検討です。このフォルダにBATは追加していません。

参考：[ロールの定義](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/security)、[Key VaultのRBAC](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)、[Consumptionワークフロー作成API](https://learn.microsoft.com/en-us/rest/api/logic/workflows/create-or-update?view=rest-logic-2019-05-01)、[履歴保存期間](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-limits-and-config)、[送信元IP制限](https://learn.microsoft.com/en-us/azure/logic-apps/set-up-security-permissions)、[HTTP URL取得API](https://learn.microsoft.com/en-us/rest/api/logic/workflow-triggers/list-callback-url?view=rest-logic-2016-06-01)。


### サブスクリプションIDの確認

`SUBSCRIPTION_ID` には「サブスクリプション TEST」などの表示名ではなく、ハイフンを含む36文字のIDを指定します。

```bash
az account list --query '[].{subscriptionName:name,subscriptionId:id}' --output table
```

`SubscriptionId` 列の値を `settings.local.sh` に設定してください。表形式では `id` という列名が省略されるため、`subscriptionId` へ名前を変えています。


