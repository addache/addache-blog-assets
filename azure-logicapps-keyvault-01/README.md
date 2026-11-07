# azure-logicapps-keyvault-01：Windows BAT サンプル

対応記事：https://addache.net/azure-logicapps-keyvault-01/

Azure Logic Apps **Consumption** の HTTP GET エンドポイント経由で、Azure Key Vault のシークレットを取得する独立したサンプル3本です。

| ファイル | 動作 |
|---|---|
| [01-rdp.bat](01-rdp.bat) | 接続先・ユーザー・パスワードを取得してRDP接続 |
| [02-app-enabled.bat](02-app-enabled.bat) | ONのときだけ `hostname` を実行 |
| [03-file-copy.bat](03-file-copy.bat) | 実際のデスクトップ上でフォルダ間コピー |

## ダウンロードと設定

GitHubで各BATを開き、**Download raw file** で保存してください（HTMLページを名前を変えて保存しないでください）。拡張子は `.bat` のままです。3本それぞれ単体で使え、別のPS1ファイルや共通BATは不要です。Windowsの `curl.exe` と Windows PowerShell 5.1以降が必要です。メッセージは文字化けを避けるため英語、BATはASCII・CRLFです。

実行前に、**リポジトリの外へ保存した私用コピー**の冒頭だけ編集します。

```bat
set "URI=REPLACE_WITH_LOGIC_APPS_SIGNED_URL"
```

`REPLACE_WITH_LOGIC_APPS_SIGNED_URL` を、Azureポータルで取得した実際の署名付きURL全体に置き換えてください。**BATソースに埋め込むときは、URL中のすべての `%` を `%%` に変更**します。たとえばURL内の `%2F` はBAT内では `%%2F` です。`&` はそのままにし、行全体の二重引用符は維持します。未設定のままでは取得に失敗します。

シークレット名もBAT冒頭に集約しています。取得した値を設定欄へ直接書く必要はありません。設定済みBATをダブルクリックするか、コマンドプロンプトから実行してください。最後は `PAUSE` で結果を確認できます。

## Logic Apps側の前提

記事のワークフローを次の契約で構成してください。

- Requestトリガーのメソッドは **GET**。クエリ `secret_name` を受け取り、指定されたKey Vaultシークレットを取得します。
- 成功時はHTTP 200、本文は**シークレット値だけの1行のプレーンテキスト**（`Content-Type: text/plain; charset=utf-8`）。JSON、引用符付き文字列、Key Vaultオブジェクト全体は返しません。
- 未許可のシークレット名、取得失敗、アクセス拒否は非2xxを返します。空の200応答で成功扱いにしないでください。
- Logic AppsのマネージドIDに必要なKey Vault読み取り権限を設定し、取得を許可する名前を下表の6個に限定してください。記事のIP制限も設定し、読者の送信元IPから呼べる状態にします。

各BATの `GetSecret` は同じ実装です。PowerShell内から `curl.exe --get --data-urlencode` を呼び、`secret_name` をURLエンコードします。接続10秒・全体30秒でタイムアウトし、HTTP 200以外（リダイレクトを含む）、空値、複数行、制御文字、1024文字超、二重引用符を含む値は失敗扱いです。値は一時ファイルに保存しません。`!`、`%`、`&` などを含む値は遅延展開の切替で扱います。Windowsコマンドへの引数として安全に渡せない二重引用符および末尾のバックスラッシュは、この教材では非対応です。

## Key Vaultへ登録する6個の値

| シークレット名 | 登録値 |
|---|---|
| `RDP-HOST` | `localhost` |
| `RDP-USER` | 接続先Windowsのユーザー名（実値は公開しない） |
| `RDP-PASS` | そのユーザーのパスワード（実値は公開しない） |
| `APP-ENABLED` | `ON` または `OFF` |
| `COPY-FROM` | `FromFolder` |
| `COPY-TO` | `ToFolder` |

### ① RDP接続

HOST・USERを表示し、PASSは取得時に `********` とだけ表示します。`cmdkey` で `TERMSRV/<HOST>` の資格情報を登録し、`mstsc` を起動、10秒待って登録した資格情報を削除します。10秒は接続完了の保証ではありません。削除後に入力を求められた場合は、RDPの画面で手動入力してください。

自動取得・値検証・登録に失敗した場合は、接続先と資格情報を手動入力できるRDP画面を開きます。既に対象の資格情報が存在する場合も、自動登録と削除を行わず手動画面を開きます。既存の保存済み資格情報がRDPで使用される可能性はあります。

Windows HomeはRDPの**接続先（ホスト）になれません**。対応エディションでもリモートデスクトップの有効化とログイン権限が必要です。`localhost` はBATを実行したPC自身です。通常のWindowsクライアントでは同一PC・同一セッションへの接続が拒否される場合があり、全員が接続成功を確認できるテストではありません。接続を試すなら、利用可能な別PCを用意して `RDP-HOST` を変更してください。ホスト名/IPv4と任意のポートを想定し、URLやIPv6リテラルは対象外です。

`cmdkey /pass` のパスワードは短時間でもプロセス引数に現れ、登録中はWindows資格情報に保存されます。強制終了・PC停止・削除失敗では残ることがあるため、必要に応じて資格情報マネージャーの `TERMSRV/<HOST>` を手動削除してください。サンプル実行中は同じ接続先の資格情報を別プロセスで変更しないでください。

### ② ON/OFF制御

`APP-ENABLED` を表示し、`ON` のときだけ `hostname` と結果表示を行います。`OFF` はスキップ、取得失敗やそれ以外の値は実行せず終了します（ON/OFFの大文字小文字は区別しません）。①③からは一切参照しません。

### ③ ファイルコピー

**実行前に、読者自身がデスクトップへ `FromFolder` を作り、その中にテスト用テキストファイルなどを置いてください。** BATはコピー元やテストファイルを作りません。

PowerShellの `[Environment]::GetFolderPath('Desktop')` で実際のデスクトップを取得するため、OneDrive等へ移動している環境でもそのパスを使用します。`ToFolder` は存在しないときだけ作成し、既存なら再利用します。

`XCOPY /E /I /Y` は空のサブフォルダもコピーし、同名ファイルを**確認なしで上書き**します。削除やミラー同期は行いません。終了コードを表示し、0を成功、1をコピー対象なし、それ以外をエラーとして扱います。コピー途中のエラーは巻き戻しません。

設定取得失敗、コピー元不在、デスクトップ取得失敗、不正な名前ではコピーしません。この教材で許可するフォルダ名は英数字・`_`・`-` のみです。同名の元/先、絶対パス、`..`、デバイス名、元/先および配下のジャンクション・シンボリックリンク等は拒否します。検査中・コピー中に対象フォルダを変更しないでください。

## 公開・秘密情報の扱い

- 実際の署名付きURLは、そのURLを知る人がAPIを呼べる認証情報です。**GitHub、README、コミット、スクリーンショット、問い合わせログへ絶対に含めないでください。** 実際のRDPユーザー名・パスワードも同様です。
- 署名付きURLはBATへ直書きする記事のサンプルです。BATの閲覧者から署名を隠せる仕組みではありません。設定済みBATは私用として管理してください。
- 私用コピーをこのフォルダに置く場合は `01-rdp.local.bat` などに改名してください。同梱の `.gitignore` は `*.local.bat` を除外します。元のBATを直接編集すると除外されないので注意してください。
- `@echo off` を維持し、curlのverbose/traceを有効にしないでください。取得エラーは値やURLを出さない汎用表示です。HOST・USERは要件どおり表示するため、実行画面そのものの公開は避けてください。
- Logic Appsの実行履歴についても、Key Vaultアクションや応答など秘密が通る処理にSecure Inputs/Outputsを設定してください。漏えいした署名は再生成し、BAT側を更新します。
- 公開DNS TXTによるURL配布は、このサンプルには含めません。

参考：[Logic AppsのHTTPエンドポイント](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-http-endpoint)、[Logic Appsのセキュリティと実行履歴](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-securing-a-logic-app)、[RDPの対応エディション](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/remote-desktop-allow-access)。

