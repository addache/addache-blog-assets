# AWS ↔ Azure Site-to-Site VPN (LibreSwan)

本リポジトリは、ブログ記事  
https://addache.net/aws_azure_vpn01/  
で紹介している **AWS Site-to-Site VPN と Azure 側 Linux VM（LibreSwan）を用いた IPsec VPN 構成** の補助資産です。

## 対象読者

- AWS / Azure の基本的なネットワーク構成を理解している方
- LibreSwan / IPsec の設定ファイルを自分で読んで調整できる方
- 「そのまま動くテンプレ」を期待していない方

※ 初学者向けの手順書ではありません。

---

## リポジトリの方針

- **秘密情報は含みません**
  - `/etc/ipsec.d/vpn.secrets`（PSK）は本リポジトリには置いていません
  - example / template のみを配置しています
- 本リポジトリのファイルは **参考実装** です
  - 環境差（OS / カーネル / 暗号ポリシー）によりそのまま動かない可能性があります

---

## 構成ファイルについて

### vpn.conf.template

LibreSwan 用の IPsec 設定テンプレートです。

- IP アドレス、ID、暗号スイートは環境に合わせて調整してください
- `ike=` や `phase2alg=` の値は **あくまで例** です
- 環境によっては古い DH グループ（例: modp1024）が拒否されることがあります

### sample-vpn.conf

- フォーマット確認用のダミーファイルです
- 実際の PSK は Parameter Store / Key Vault 等の安全な場所で管理してください

### sample-rc-local-latest.service

- vti インターフェース作成後のルーティング設定例です
- route コマンドを使用していますが、iproute2 への置き換えも可能です

### sample-sysctl.conf

- sysctl の追加設定例です
- 環境／ディストリビューションによって追加が必要なケースもあるかと思います

---

## 注意点（重要）

- 本構成は **検証時点での動作確認結果** を元にしています
- セキュリティポリシーや暗号要件は時間と共に変化します
- 本リポジトリの内容をそのまま本番環境へ適用することは推奨しません

「なぜこの設定になっているか」を理解した上で、  
自分の環境に合わせて調整してください。

---

## License / Disclaimer

- 本リポジトリの内容は無保証です
- 利用によって生じた問題について、作者は責任を負いません

