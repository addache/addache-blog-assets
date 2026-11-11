# aws-ecs-13：ECS Fargate構築 CLI版

元記事：[ECS③ ～ECS Fargate構築～](https://addache.net/aws-ecs-03/)

AWS CloudShellのBash・東京リージョンで、①の既存資材と②のPush済みイメージを使ってECS Fargateを構成するサンプルです。
静的確認済みの初稿です。AWS上の実構築は未検証です。

| ファイル | 用途 |
|---|---|
| settings.example.sh | settings.local.shへコピーする設定値 |
| setup.sh | 一括実行SH |
| task-definition.template.json | 設定値をjqで反映するタスク定義 |
| dynamodb-item.json | GUI版と同じサンプル項目 |

## 前提

- ①のIAMロール2つ、DynamoDB、ECR、S3静的Webサイトを作成済み。
- ②でLinux/x86_64のアプリイメージをECRへPush済み。IMAGE_TAGを実在するタグへ合わせる。
- 変更していないデフォルトVPCと、異なるAZのデフォルトサブネット2つ以上を使用。インターネットゲートウェイ経由の経路が必要。
- aws・jq・sed・grep・curlを使用。

## 設定と実行

このフォルダーの4ファイルを同じ作業フォルダーへ保存します。settings.example.shをsettings.local.shへコピーし、AWS_ACCOUNT_IDをログイン中の12桁IDへ設定、既存資材名とタグを確認してから実行します。IDは aws sts get-caller-identity --query Account --output text で取得できます。

```bash
bash setup.sh
```

SEG → ターゲットグループ・ALB・リスナー → クラスター → ロググループ・タスク定義 → サービス → 動作確認 → 項目追加 → S3のapp.js更新の順に進みます。

同名リソースやサンプル項目がある場合は停止します。途中失敗時は作成済み資材が残ります。.generated内の記録を確認してから再開してください。同じSHを繰り返す前に既存状態を確認する必要があります。

## GUI版との対応

- タスク: Fargate/Linux x86_64、CPU 256、メモリ512 MiB、webapi:8080、環境変数DYNAMODB_TABLEとAWS_REGION。
- サービス: 起動タイプFARGATE、1タスク、猶予60秒、AZリバランス有効、パブリックIP有効。
- SEG: ALBへTCP80を全IPv4から許可。ECSへTCP8080をALB用SEGからだけ許可。送信は作成時のデフォルト。
- ALB: internet-facing、HTTP80 → IPターゲットHTTP8080、/health。
- ログ: /ecs/ecs-sampleを明示作成。保持期間の変更なし。

ALBを先に作り、最初から専用SEGを指定します。イメージは指定タグから取得した同じダイジェストを使用します。

Route 53の変更は行いません。ALBのDNS名でAPIを確認し、そのURLへS3の既存app.jsのAPI_URLだけを更新します。独自ドメインは元記事で手動設定し、利用する場合はapp.jsの接続先も合わせます。

.generated/app.before.jsは更新前のJavaScriptです。設定・生成JSON・認証情報はS3へアップロードしません。バケットの公開設定は変更しません。

ALB・Fargate・ログなどの料金が発生します。後続回に進まない場合はサービスと今回作成した資材を削除してください。自動削除処理は含みません。①の共用資材の削除とは分けて扱います。
