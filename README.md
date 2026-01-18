# Dual Stack Lab

**目的**: Rancher Desktop (macOS / dockerd) を使った IPv4/IPv6 Dual Stack 環境の検証
**対象**: ネットワークエンジニア、バックエンド開発者、インフラエンジニア

---

## 概要

このラボでは以下を検証できます:

- IPv4/IPv6 の疎通確認（HTTP、Ping）
- DNS (A/AAAA レコード) による名前解決
- IPv6 障害時の IPv4 フォールバック動作（Happy Eyeballs）

### 関連リソース

- **Zenn テックブログ**: [Docker で体験する IPv6 Dual Stack 入門](article.md)
- **Zenn 本**: [Azure 閉域ネットワーク設計入門](https://zenn.dev/sbk0716/books/b39367c534044c)

---

## 構成図

```
┌─────────────────────────────────────────────────────────┐
│  dsnet (172.30.0.0/24, fd00:dead:beef::/64)             │
│                                                         │
│  ┌─────────┐    ┌─────────┐    ┌─────────────┐          │
│  │  web    │    │  dns    │    │   client    │          │
│  │ (nginx) │    │(CoreDNS)│    │  (alpine)   │          │
│  │         │    │         │    │             │          │
│  │ .0.10   │    │ .0.53   │    │   .0.20     │          │
│  │ ::10    │    │ ::53    │    │   ::20      │          │
│  └─────────┘    └─────────┘    └─────────────┘          │
└─────────────────────────────────────────────────────────┘
```

### コンテナ一覧

| コンテナ | イメージ | 役割 | IPv4 | IPv6 |
| -------- | -------- | ---- | ---- | ---- |
| web | nginx:alpine | Web サーバ | 172.30.0.10 | fd00:dead:beef::10 |
| dns | coredns/coredns:1.11.1 | DNS サーバ | 172.30.0.53 | fd00:dead:beef::53 |
| client | alpine:3.20 | テストクライアント | 172.30.0.20 | fd00:dead:beef::20 |

---

## 必要環境

- **Rancher Desktop**（推奨）または Docker Desktop
  - Container Engine: **dockerd (moby)** を選択
- Docker Compose が使える環境
- ターミナル（bash/zsh）

> **注意**: Rancher Desktop は無料で商用利用が可能です。

---

## クイックスタート

### 1. リポジトリをクローン

```bash
git clone https://github.com/sbk0716/rd-dualstack-lab.git
cd rd-dualstack-lab
```

### 2. 起動

```bash
./start.sh
```

### 3. クライアントに入る

```bash
docker exec -it rd-ds-client sh
```

### 4. ツールインストール（コンテナ内）

```bash
apk add --no-cache curl bind-tools iputils python3
```

### 5. 基本テスト（コンテナ内）

```bash
# IPv4 で HTTP
curl -4 http://172.30.0.10/

# IPv6 で HTTP
curl -6 -g http://[fd00:dead:beef::10]/

# DNS 確認
dig dual-ok.local A +short
dig dual-ok.local AAAA +short

# 名前で接続（IPv6 優先）
curl http://dual-ok.local/
```

### 6. 停止

```bash
exit  # コンテナから出る
./stop.sh
```

---

## DNS 設定

CoreDNS で以下のホスト名を定義しています:

| ホスト名 | A (IPv4) | AAAA (IPv6) | 用途 |
| -------- | -------- | ----------- | ---- |
| dual-ok.local | 172.30.0.10 | fd00:dead:beef::10 | 正常系テスト |
| dual-badv6.local | 172.30.0.10 | fd00:dead:beef::9999 | IPv6 障害シミュレーション |

---

## テストシナリオ

### シナリオ 1: 正常な Dual Stack 通信

```bash
# 名前解決
dig dual-ok.local A +short      # -> 172.30.0.10
dig dual-ok.local AAAA +short   # -> fd00:dead:beef::10

# 接続（IPv6 優先で接続される）
curl -v http://dual-ok.local/
```

### シナリオ 2: IPv6 フォールバック

```bash
# 壊れた AAAA を確認
dig dual-badv6.local AAAA +short   # -> fd00:dead:beef::9999 (到達不能)

# curl でフォールバック観察
curl -v --connect-timeout 2 http://dual-badv6.local/
```

### シナリオ 3: Python で確実なフォールバック観察

```bash
# スクリプトをコンテナにコピー（ホストで実行）
docker cp scripts/ds_client.py rd-ds-client:/tmp/

# コンテナ内で実行
python3 /tmp/ds_client.py dual-ok.local 80
python3 /tmp/ds_client.py dual-badv6.local 80
```

---

## ファイル構成

```
rd-dualstack-lab/
├── README.md               # このファイル
├── article.md              # Zenn テックブログ記事
├── compose.yaml            # Docker Compose 設定（詳細コメント付き）
├── Corefile                # CoreDNS 設定（詳細コメント付き）
├── start.sh                # 起動スクリプト（詳細コメント付き）
├── stop.sh                 # 停止スクリプト（詳細コメント付き）
├── docs/
│   └── test-report.md      # テストレポート
└── scripts/
    ├── ds_client.py        # Python フォールバックテスト（詳細コメント付き）
    ├── setup-client.sh     # クライアントセットアップ
    ├── test-connectivity.sh # 接続テスト
    └── test-fallback.sh    # フォールバックテスト
```

### 主要ファイルの解説

| ファイル | 説明 |
| -------- | ---- |
| compose.yaml | Docker Compose 設定。Dual Stack ネットワーク（dsnet）と 3 つのコンテナを定義 |
| Corefile | CoreDNS 設定。A/AAAA レコードを定義し、dual-badv6.local で障害シミュレーション |
| start.sh | 起動スクリプト。コンテナ起動後、IPv6 有効確認と IP アドレス表示を実施 |
| stop.sh | 停止スクリプト。コンテナとネットワークをクリーンアップ |
| ds_client.py | Python スクリプト。IPv6→IPv4 フォールバックを詳細に観察可能 |

---

## トラブルシューティング

### IPv6 が動作しない場合

1. **ネットワーク確認**

```bash
docker network inspect rd-dualstack-lab_dsnet | grep EnableIPv6
# "EnableIPv6": true が表示されるか確認
```

2. **コンテナの IPv6 アドレス確認**

```bash
docker inspect rd-ds-web | grep GlobalIPv6Address
# fd00:dead:beef::10 が表示されるか確認
```

3. **コンテナ内から IPv6 ping**

```bash
ping -c 2 fd00:dead:beef::10
```

### Rancher Desktop 固有の問題

- Rancher Desktop は内部的に Linux VM で Docker を実行しています
- macOS ネイティブのネットワークとは分離されています
- ホスト（macOS）からコンテナへの IPv6 通信は制限がある場合があります
- iptables 系の実験は不安定になりやすいです

### コンテナが起動しない場合

```bash
# ログを確認
docker compose logs

# 古いネットワークが残っている場合は削除
docker network rm rd-dualstack-lab_dsnet
```

---

## 技術的な補足

### ULA（Unique Local Address）について

このラボでは `fd00:dead:beef::/64` という ULA を使用しています。

- **fd00::/8**: ULA（プライベート IPv6）の範囲
- IPv4 の `10.0.0.0/8` や `192.168.0.0/16` に相当
- インターネットにはルーティングされない

### Happy Eyeballs (RFC 8305)

curl などのモダンなクライアントは「Happy Eyeballs」アルゴリズムを実装しています。

1. IPv6 と IPv4 を並列で接続試行
2. 先に成功した方を使用
3. IPv6 が数百ミリ秒以内に応答しない場合、IPv4 も試行開始

---

## 関連ドキュメント

### 内部ドキュメント

- [テストレポート](docs/test-report.md) - 動作確認結果の詳細

### 外部リソース

- [Docker IPv6 Networking](https://docs.docker.com/config/daemon/ipv6/)
- [CoreDNS Documentation](https://coredns.io/manual/toc/)
- [Rancher Desktop Documentation](https://docs.rancherdesktop.io/)
- [RFC 8305 - Happy Eyeballs Version 2](https://datatracker.ietf.org/doc/html/rfc8305)

---

## ライセンス

MIT License
