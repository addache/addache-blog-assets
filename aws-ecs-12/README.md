# aws-ecs-12：Image Push CLI版

元記事：https://addache.net/aws-ecs-02/

AWS CloudShellのBashで、IAM設定とGitHubへの4ファイル配置・タグ送信を進めるサンプルです。①の共通設定を先に読み込み、②には追加設定だけを記入します。

## 前提

- ①のCLI版でロール2つとECRを作成し、~/aws-ecs-11/settings.local.shへ設定・取得結果を保存済み。
- GitHubで今回の検証用に、新しい空の非公開リポジトリを作成済み。README・.gitignore・Licenseは追加しない。
- GitHubの準備と認証をIAMの前に済ませる。ブランチの作成・切り替えは行わない。

## ファイル

| ファイル | 用途 |
|---|---|
| settings.example.sh | IAMユーザー名・GitHubリポジトリ・イメージタグの追加設定 |
| save-settings.sh | 取得値を各回の設定ファイルへ保存 |
| install-gh.sh | 必要な場合だけ公式GitHub CLIをホームへ配置 |
| setup-iam.sh | IAMユーザーと管理ポリシー2つ、PassRoleの登録 |
| prepare-files.sh | GUI版②と同じ4ファイルをfiles/へ取得 |
| publish-files.sh | 空の非公開リポジトリへ最初のコミットを送信 |
| release.sh | Secrets名を確認し、タグ送信とRelease作成 |

## 実行の流れ

1. 空の非公開リポジトリを新規作成。
2. 設定を編集し、①→②の順にsettings.local.shを読み込む。
3. bash install-gh.shの後、export PATH="$HOME/.local/bin:$PATH"を設定。
4. gh auth login --hostname github.com --git-protocol https --web --scopes workflowで認証し、gh auth setup-git --hostname github.comを実行。
5. bash setup-iam.shでIAMを設定。
6. アクセスキーをマネコンで発行し、GitHub Actions Secretsへ手動登録。
7. bash prepare-files.shで4ファイルを取得・確認。
8. bash publish-files.shで最初のコミットを送信。
9. bash release.shでタグを送信。この時点でImage Pushが始まる。

既存のコミットがあるリポジトリは自動配置しません。clone先のrepository/が既にある場合も上書きせず停止するため、途中失敗時は状態を確認して未完了のGit操作から再開します。

送信対象はYAML・app.py・requirements.txt・Dockerfileの4ファイルだけです。GitHubのログイン名とIDに基づくnoreplyアドレスを作者・コミッターに明示します。設定ファイル・AWSキー・GitHubトークンはコミットしません。

アクセスキー発行・Secrets登録・GitHubの認証承認は手動です。認証情報をsettings.local.shへ記入しません。ghの認証設定ディレクトリもコピーしないでください。

一括SHも①→②の順に読み込みます。共通設定やロールARN・ECR URIは①を参照し、②の取得結果は②へ保存します。既存のsettings.local.shにWORK_BRANCHが残っていても使用しないので、削除して構いません。

AWS上の構築と実GitHub認証からECR Pushまでの通し検証は未実施です。構築SHは終了時にリソースを削除しません。片付けには末尾の削除手順を使用します。

## 検証後の削除

cleanup-iam.shを同じフォルダーへ取得し、bash cleanup-iam.shで②の専用IAMユーザー・アクセスキー・付与ポリシーを削除できます。①→②の設定を読み込み、アカウント・保存済みARN・対象ユーザーを照合してDELETE入力後に進みます。GitHubやECR、①の共用リソースは変更しません。再Pushや別用途に使用中のユーザーでは実行しないでください。

## まとめて片付ける場合

cleanup.shはGitHub Actionsが終了していること、AWSアカウントと保存済みのIAMユーザーARNを確認し、対象を表示してDELETE入力を待ちます。Secrets2項目→IAMユーザーの全アクセスキー・既定の付与ポリシー・ユーザー→今回のECRバージョンタグの順に削除します。latestは同じイメージを指している場合だけ削除します。

GitHubリポジトリ、GitHubログイン、①の共通リソースとローカル設定は残します。③でイメージを利用中なら先に③を片付けてください。途中失敗時は削除済みのものもあるため、残った状態を確認します。
