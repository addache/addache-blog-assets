# aws-ecs-02：コンテナイメージのPush用サンプル

対応記事：[Azure経験者がAWS ECSで同じ構成を作ってみる② ～Image Push～](https://addache.net/aws-ecs-02/)

記事掲載の5つのコードを格納しています。コードの動作は記事掲載版から変更していません。

| ファイル | 用途・読者側の配置先 |
|---|---|
| [iam-passrole-ecs.template.json](iam-passrole-ecs.template.json) | IAM-PassRole-ECS用ポリシー。IAMのポリシーエディターへ貼り付け |
| [.github/workflows/deploy.yml](.github/workflows/deploy.yml) | 読者のリポジトリの同じパスへ配置 |
| [app.py](app.py) | 読者のリポジトリ直下へ配置 |
| [requirements.txt](requirements.txt) | 読者のリポジトリ直下へ配置 |
| [Dockerfile](Dockerfile) | 読者のリポジトリ直下へ配置 |

## 使い方

各ファイルを開いてコードをコピーし、記事の手順に従って使用してください。
IAMポリシーの `[AWSアカウントID]` は、ご自身の12桁のIDへ置き換えます。ロール名を変更した場合はARN内の名前も合わせてください。

アプリ・Dockerfile・requirements.txtは、読者のリポジトリ直下へ置きます。
このフォルダーの階層ごと配置すると、YAMLの `docker build .` の対象が変わるため、上の表の配置先に合わせてください。

YAMLのリージョン・ECRリポジトリ名は、作成済みリソースに合わせます。
AWSアクセスキーとシークレットアクセスキーは読者のGitHubリポジトリのActions Secretsへ設定し、ファイルには記入しません。

このリポジトリではYAMLを `aws-ecs-02/.github/workflows/` に格納しています。
リポジトリ直下の `.github/workflows/` ではないため、ここでは実行されません。
読者のリポジトリへ配置すると、`v*` タグのPushまたは手動実行でイメージをECRへPushします。

`app.py` は環境変数 `DYNAMODB_TABLE` が未指定の場合、記事掲載値の `ecs-sample-table` を使用します。
実際に接続するテーブル名は、ECS側の環境変数で指定できます。

Python・JSONの構文を確認しています。AWS上の実行やコンテナのビルド・Pushは、この資材移設作業では実施していません。
