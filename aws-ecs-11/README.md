# aws-ecs-11：ECSシリーズ① 基盤準備 CLI版

元記事：https://addache.net/aws-ecs-01/  
CLI版の公開予定URL：https://addache.net/aws-ecs-11/

**記事を一緒に仕上げるための初稿です。AWS CloudShellでの実構築は未検証です。**

AWS CloudShellのBash、東京リージョン `ap-northeast-1`、AWS CLI v2のアカウントリージョナル名前空間対応版を前提とします。`aws`・`jq`・`grep`・`sed`・`curl` を使用します。IAMロール作成・ポリシー付与、DynamoDB、ECR、S3の作成・参照・設定権限が必要です。ログイン中のアカウントIDと設定値を照合してから開始します。

## ファイル

| ファイル | 用途 |
|---|---|
| `settings.example.sh` | `settings.local.sh` にコピーして編集する変数一覧 |
| `setup.sh` | 任意の一括実行版 |
| `cleanup.sh` | 検証後の削除用。旧CLI版の独自インラインポリシーにも対応 |
| `web/index.html`・`web/app.js` | S3へ配置するサンプルWeb画面 |

## 対象

IAMロール2つ、文字列キー `id` のオンデマンドDynamoDBテーブル、空のECRリポジトリ、S3バケット、Webファイル2つ、静的Webホスティング設定を作成します。最後にHTTP URLを表示し、`.generated/website-url.txt` と `.generated/resources.json` に保存します。

Route 53の権限委譲は元記事の手順を参照。コンテナイメージのPush、ECS、ALB、APIとの接続、DynamoDBのサンプル項目投入は後続回の範囲です。この段階では画面が表示されれば完了で、APIボタンの接続失敗は想定内です。

## 実行方法

取得方法と個別手順は [公開記事](https://addache.net/aws-ecs-11/) を参照してください。

```bash
if [[ ! -f settings.local.sh ]]; then
  cp settings.example.sh settings.local.sh
fi
(
  set -euo pipefail
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --no-cli-pager)"
  [[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || { echo '12桁のAWSアカウントIDを取得できませんでした。' >&2; exit 1; }
  [[ "$(grep -c '^AWS_ACCOUNT_ID=' settings.local.sh)" == 1 ]] || { echo '設定ファイルのAWS_ACCOUNT_ID行を確認してください。' >&2; exit 1; }
  sed -i "s|^AWS_ACCOUNT_ID=.*$|AWS_ACCOUNT_ID='$ACCOUNT_ID'|" settings.local.sh
  printf '設定ファイルへAWS_ACCOUNT_ID=%sを保存しました。\n' "$ACCOUNT_ID"
) && nano settings.local.sh
# 保存後、一括実行する場合のみ:
bash setup.sh
```

一括実行後に個別CLIを重ねて実行する必要はありません。一括実行の子Bash内で取得した変数は親のCloudShellへ残らないので、後続回で必要な値は `.generated/resources.json` または各サービスの参照CLIから取得します。

## GUI版との対応

- 起動用ロールには `AmazonECSTaskExecutionRolePolicy` を付与します。両ロールの信頼ポリシーはECSタスクの `sts:AssumeRole` を許可し、CLI独自のアカウント・リージョン条件は追加しません。
- アプリ用ロールには、GUI版の画像で選択しているAWS管理ポリシー `AmazonDynamoDBFullAccess_v2` を付与します。GUI版本文に記載のポリシー名とは不一致があるため、選択画面に合わせています。
- S3は元記事と同じアカウントのリージョナル名前空間です。CLIでは接尾辞を含む完全名を指定します。
- S3の公開設定はGUI版に合わせ、バケットのパブリックアクセスブロック4項目をすべて無効にし、バケットポリシーで `/*` の読み取りを許可します。バケットの一覧表示や書き込みは許可しません。
- HTMLの構造・CSS・API応答の表示処理はGUI版の掲載コードに合わせています。APIのURLだけは設定ファイルから置換します。設定ファイル・生成JSON・AWS認証情報はアップロードしません。

## 再実行・失敗時

既存リソースを上書きしない初稿です。開始前に同名のロール・テーブル・リポジトリ・バケットがある場合は停止します。元記事の環境が残っている場合は別の未使用名にしてください。アクセス拒否などの取得エラーも「存在しない」とみなさず停止します。

途中で失敗した場合、既に作成したリソースは残ります。自動削除や自動巻き戻しはしません。状態を確認して個別手順の未完了箇所から再開するか、作成済みの検証リソースを確認して後片付けしてから一括実行し直してください。実行前の既存チェックをそのまま繰り返すと、成功済みリソースを検出して停止します。

S3を公開するため、アカウント・組織のBlock Public Access設定がバケットポリシーによる公開を禁止していると失敗します。スクリプトはアカウント・組織の設定を変更しません。画面公開はHTTPで、HTTPS対応の構成は今回の対象外です。使用したサービスに応じた料金が発生し得ます。

後片付けの対象：この手順で作成したバケット（Webファイル2つを含む）、ECRリポジトリ、DynamoDBテーブル、IAMロール2つと付与ポリシー。後続回で継続利用する場合は残してください。

## 参考

- [元記事](https://addache.net/aws-ecs-01/)
- [ECSタスク実行ロールの管理ポリシー](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonECSTaskExecutionRolePolicy.html)
- [ECSタスクIAMロール](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html)
- [S3名前空間](https://docs.aws.amazon.com/AmazonS3/latest/userguide/gpbucketnamespaces.html)
- [create-bucket](https://docs.aws.amazon.com/cli/latest/reference/s3api/create-bucket.html)
- [S3公開アクセス設定](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PublicAccessBlockConfiguration.html)
- [S3ウェブサイトエンドポイント](https://docs.aws.amazon.com/general/latest/gr/s3.html)

## 再検証前の後片付け

以前のCLI版で作成した環境から検証し直す場合は、現在の `settings.local.sh` を残したまま、最新版の [cleanup.sh](cleanup.sh) を取得して実行してください。対象名とアカウントを表示し、`DELETE` の入力後に削除します。元のサンプル名から変更した場合は、作成時に使った設定値が入っていることを確認してください。

```bash
cd ~/aws-ecs-11
curl -fSLo cleanup.sh 'https://raw.githubusercontent.com/addache/addache-blog-assets/main/aws-ecs-11/cleanup.sh'
bash cleanup.sh
```

旧版の `ECS-Sample-DynamoDB` インラインポリシーと、修正版の `AmazonDynamoDBFullAccess_v2` 管理ポリシーを外してからアプリ用ロールを削除します。①の範囲だけを対象とし、後続回で作成したECSやALBなどは削除しません。追加のS3ファイルやECRイメージは強制削除せず、エラー時に停止します。ローカルの設定ファイルは残します。
