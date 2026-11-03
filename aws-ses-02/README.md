# aws-ses-02：記事掲載用コード・JSON

対応記事：https://addache.net/aws-ses-02/

各ファイルを開き、コード欄のコピーボタンでコピーして、記事で指定したCloudShell上のファイルへ貼り付けてください。記事のnano、sed、AWS CLIの実行順は変わりません。

| ファイル | CloudShellで保存する名前 |
|---|---|
| lambda_function.py | lambda_function.py |
| lambda-trust-policy.json | lambda-trust-policy.json |
| lambda-environment.example.json | lambda-environment.json |
| s3-lifecycle.json | s3-lifecycle.json |
| s3-bucket-policy.template.json | s3-bucket-policy.template.json |
| route53-dkim.template.json | route53-dkim.template.json |
| route53-mx.template.json | route53-mx.template.json |
| receipt-rule.template.json | receipt-rule.template.json |

`lambda-environment.example.json`のWebhook URLはサンプルです。実際のURLはCloudShell上のlambda-environment.jsonに記入します。

`.template.json`の置換用文字列は、記事のsedコマンドで変数の値へ変換します。置換前のファイルをそのままAWSへ登録しないでください。
