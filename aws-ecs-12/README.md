# aws-ecs-12：Image Push CLI版

元記事：https://addache.net/aws-ecs-02/

AWS CloudShellのBashでIAM設定とGitHubへの資材配置・タグPushを進めるサンプルです。AWS上の実構築・GitHub認証からイメージPushまでの通し実行は未検証です。

| ファイル | 用途 |
|---|---|
| settings.example.sh | settings.local.shへコピーする設定値。キーやトークンは入れない |
| save-settings.sh | 取得したARNやコミットSHAなどの途中保存 |
| setup-iam.sh | IAMユーザー、管理ポリシー2つ、PassRoleインラインポリシー |
| install-gh.sh | 公式GitHub CLIをホーム配下へ配置。既に使えればスキップ |
| prepare-files.sh | GUI版②の4ファイルをfiles/へ取得 |
| publish-files.sh | 非公開リポジトリの新しい作業ブランチへ4ファイルを送信 |
| release.sh | Secrets名を確認してタグPush・Release作成 |

①のロール2つとECRが作成済みであることが前提です。AWSアカウント・リージョン・既存資材名とARNは①の設定から読み込みます。②ではIAM_USER_NAME、GITHUB_REPOSITORY（所有者/リポジトリ名）、未使用のWORK_BRANCH・IMAGE_TAGだけを設定します。

アクセスキーの発行・Secrets登録・初回GitHub認証は手動です。これらの操作を無人で完了するSHは用意していません。対象は書き込み権限のある非公開リポジトリで、空の専用リポジトリを想定しています。同名ファイル・既存ワークフロー・既存ブランチは上書きしません。既存構成と衝突する場合はGUI版のファイル配置へ切り替えます。

## 実行の流れ

1. 設定を編集し、bash setup-iam.shでIAMを作成。
2. マネコンでアクセスキー発行、対象GitHubのActions Secretsへ手動登録。
3. bash install-gh.shの後、export PATH="$HOME/.local/bin:$PATH"を設定。
4. gh auth login --hostname github.com --git-protocol https --web --scopes workflowで本人認証。
5. gh auth setup-git --hostname github.comを実行。
6. bash prepare-files.shで資材を取得し、必要ならリージョン・ECR名を編集。
7. bash publish-files.shで作業ブランチへ送信。
8. bash release.shでタグを送る。この時点でAWSへのImage Pushが始まる。

GitHubのコミットにはログイン名とIDに基づくnoreplyアドレスをリポジトリ単位で設定します。mainへの強制Pushは行いません。元記事のdeploy.ymlはタグPushまたは手動実行がトリガーで、作業ブランチのPushだけでは実行しません。

GUI版との主な手順差は、新しい作業ブランチを使用する点と、PassRoleをユーザーのインラインポリシーとして登録する点です。許可するロールとアクションは元記事のJSONと同じです。コード4点はaws-ecs-02の資材を再利用します。

ghは認証情報をホーム側へ保存する場合があります。認証設定ディレクトリをリポジトリへコピーしないでください。リポジトリへ配置するのは明示した4ファイルだけです。

一括SHの取得結果はsettings.local.shへ保存します。別のBashや一括SHの終了後は①のsettings.local.sh、②のsettings.local.sh、②のsave-settings.shの順にsourceして復元します。repository/が既にある場合は自動処理を停止するので、失敗したGit操作を確認して再開します。

自動削除はありません。AWSのユーザー・キー、GitHubのSecrets、ブランチ・タグ・Releaseは用途を確認して片付けてください。

## 設定ファイルの分担

①→②の順にsettings.local.shを読み込みます。一括SHも同じ順序です。①は共通AWS設定と既存資材、②はIAMユーザー・GitHub・イメージタグ、③はECS・ALBの追加設定を持ちます。後のファイルへ同じ共通設定を再記入しません。

既存のsettings.local.shは自動更新しないため、旧版の②③に残る①由来の重複行は新しいテンプレートを見て削除してください。③のIMAGE_TAGは②へ集約します。実リソースの削除・再作成は不要です。
