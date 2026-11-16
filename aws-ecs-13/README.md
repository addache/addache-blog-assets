# aws-ecs-13：ECS Fargate構築 CLI版

[マネコン版 ECS Fargate構築編](https://addache.net/aws-ecs-03/)の構成をCloudShellから作成します。
AWS上の実構築・実削除は未検証です。ローカルの構文確認と模擬コマンドのテストは、実環境での検証とは区別してください。

## ファイル

| ファイル | 用途 |
|---|---|
| setup.sh | ネットワーク取得からECS起動・S3接続先更新までの一括実装 |
| cleanup.sh | 専用リソースの削除、S3とAPI_URLの復元、生成物の退避 |
| settings.example.sh | 本記事の追加設定のみ |
| save-settings.sh | 非秘密の設定・取得結果を安全に保存 |
| task-definition.template.json | Fargateタスク定義 |
| dynamodb-item.json | GUIの項目追加で使用するサンプル。setup.shでは投入しない |

## 前提・設定ファイルの分担

AWS CloudShellのBash、東京リージョン、未変更のデフォルトVPCを使用します。
異なるAZのデフォルトサブネットが2つ以上必要で、インターネットゲートウェイへのデフォルトルートが必要です。独自VPCへの対応やNATの追加は行いません。

環境準備編 → Image Push編 → 本記事の順にsettings.local.shを読み込みます。

- ~/aws-ecs-11/settings.local.sh：アカウント・リージョン、IAMロールARN、DynamoDB/ECR/S3、API_URL
- ~/aws-ecs-12/settings.local.sh：IMAGE_TAGなど
- ~/aws-ecs-13/settings.local.sh：ECS/ALBの追加名と取得ID、PREVIOUS_API_URL

共通値の再入力は不要です。CloudShellでaws、jq、sed、grep、curlが必要です。
IMAGE_TAGのビルド・ECRへのPush完了後に構築します。実行中のActionsの成功を待たずにECRを参照するとImageNotFoundExceptionになることがあります。

## 実行範囲

設定サンプルをsettings.local.shへコピーし、追加リソース名を確認してからbash setup.shを実行します。
既存のsettings.local.shは上書きしません。GUI環境と同名になる場合は追加リソース名を変更してください。

構築順序：VPC/サブネット取得 → SEG → ターゲットグループ/ALB/リスナー → クラスター → ロググループ/タスク定義 → サービス → 起動待機/API応答 → S3 app.js更新。

ALBに最初から専用SEGを指定します。ターゲットの登録はECSサービスに任せます。
タスクはLinux x86_64、256 CPU units、512 MiB、webapi:8080、1タスク、パブリックIP有効、猶予60秒、AZリバランス有効。
ALBはinternet-facing HTTP80、ターゲットはIP/HTTP8080、ヘルスチェック/health。
変更不要な項目は元記事と同じデフォルトを使用します。タスク定義はイメージタグから取得したダイジェストを参照します。

API_URLはALBのDNS名から作成し、環境準備編の設定へ保存します。変更前の値は本記事のPREVIOUS_API_URLへ保存します。
S3ではapp.jsのconst API_URL行だけを書き換えます。公開設定やHTMLを作り直しません。
構築前のapp.jsは.generated/app.original.jsに保存し、以後のURL再変更でもこの原本は上書きしません。

## GUI版を残す範囲

Route 53のAlias登録、ブラウザーでの動作確認、DynamoDBサンプル項目の追加は手動です。
setup.shはDynamoDBへ項目を投入しません。GUI本文の「ココまで来たら、一度動作チェックを行います。」以降へ接続できます。
既存のサンプル項目がある場合、最初からDynamoDBの応答になることがあります。

独自ドメインは任意です。Route 53を省略する場合はALBのDNS名を使って確認します。
独自ドメインを登録しただけではS3の接続先は変わりません。API_URLを独自ドメインの/apiへ変更し、save_settings_toで環境準備編へ保存してapp.jsを更新してください。
HTTPのS3ウェブサイトとHTTPのALBを前提とし、HTTPS化はこの資材に含めません。

## 再開とエラー

同名リソースや前回実行の生成マーカーがあれば一括SHは停止します。自動で既存リソースを上書き・削除しません。
途中失敗でも作成済みリソースは残ります。設定を読み直し、個別手順の未完了箇所から再開します。
.generatedとsettings.local.shは削除しないでください。

```bash
cd ~/aws-ecs-13
source ~/aws-ecs-11/settings.local.sh
source ~/aws-ecs-12/settings.local.sh
source ./settings.local.sh
source ./save-settings.sh
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER='' AWS_CLI_AUTO_PROMPT=off
```

起動しない場合：

```bash
aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" \
  --query 'services[0].{Desired:desiredCount,Running:runningCount,Events:events[0:5]}' --output json
aws logs tail "$LOG_GROUP" --since 10m
```

イメージ、タスク実行ロール、ネットワーク経路、SGの8080番、/healthを確認してください。
HTTP200だけではDB連携成功を意味しません。GUIの項目追加後にsourceとカウント更新を確認します。

## 一括削除

bash cleanup.shを実行し、表示対象を確認してDELETEと入力します。ALB/Fargate/ログには料金が発生します。
本記事の専用環境で、構築完了後に使うスクリプトです。設定ファイルと構築前のapp.js原本が必要です。
サービスに使っているCloudShellの認証情報で削除を実行します。AWSアカウントと保存済みARNを照合します。

削除の順番：

1. 専用サービスのタスク数を0にし、停止・サービス削除を待つ
2. ALBとリスナー、ターゲットグループを削除
3. 保存したタスク定義リビジョンを登録解除、クラスターを削除
4. ENI解放を待ちながらECS用・ALB用SEGを削除
5. ロググループを削除
6. S3 app.jsと環境準備編のAPI_URLを構築前へ復元
7. .generatedをcleanup-backup.XXXXXX/へ退避し、設定内の取得済みIDを整理

タスク定義は登録解除のみで、AWSの履歴からの完全削除は行いません。
別サービスのあるクラスターでは停止します。スタンドアロンタスクは勝手に停止せず、残っていれば削除途中で停止します。
SEGの依存関係エラーは最大約5分再試行し、解消しなければ停止します。
存在しないロググループ/SEGは明示的なNotFoundだけを許容します。権限・通信エラーは無視しません。
途中失敗後に全体を再実行できる保証はありません。last-error.txt、残ったリソースと設定を確認し、未完了箇所を個別に片付けてください。
構築途中で原本やIDがない場合も停止します。名前から別リソースを推測して削除しません。

残すもの：

- 共用IAMロール、ECRリポジトリとイメージ、DynamoDBテーブル、S3バケット/HTML
- DynamoDBのサンプル項目：GUIから不要なサンプル項目だけ削除する
- Route 53のAlias：GUIから今回登録したレコードを削除する
- 設定した追加リソース名、Image Push編のGitHub設定・IAMユーザー

後続環境を作成済みなら、先に後続環境を片付けます。別環境でも使う共用資材へこの削除を流用しないでください。
再構築前は設定を読み直し、GUIからDynamoDBのサンプル項目を削除しておくと、初回と同じ順で検証できます。
backupには設定・作業ファイルが含まれるため、GitHubへ配置しません。

## AWS資料

- [サービスの削除](https://docs.aws.amazon.com/cli/latest/reference/ecs/delete-service.html)
- [サービス削除の待機](https://docs.aws.amazon.com/cli/latest/reference/ecs/wait/services-inactive.html)
- [ALB削除](https://docs.aws.amazon.com/cli/latest/reference/elbv2/delete-load-balancer.html)
