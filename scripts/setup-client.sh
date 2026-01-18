#!/bin/sh
# =============================================================================
# クライアントセットアップスクリプト
# =============================================================================
# 目的: テストクライアントコンテナに必要なツールをインストールする
#
# 実行方法:
#   # コンテナ内で直接実行する場合
#   docker exec -it rd-ds-client sh
#   /scripts/setup-client.sh
#
#   # または、ホストからコピーして実行
#   docker cp scripts/setup-client.sh rd-ds-client:/tmp/
#   docker exec rd-ds-client /tmp/setup-client.sh
#
# インストールされるツール:
#   - curl: HTTP クライアント（Dual Stack テスト用）
#   - bind-tools: DNS ツール（dig, nslookup）
#   - iputils: ネットワークツール（ping, ping6）
#   - python3: Python インタプリタ（フォールバックテスト用）
# =============================================================================

# -----------------------------------------------------------------------------
# シェルオプション設定
# -----------------------------------------------------------------------------
# set -e: コマンドがエラーで終了した場合、スクリプトを即座に終了
set -e

# -----------------------------------------------------------------------------
# パッケージインストール
# -----------------------------------------------------------------------------
# apk: Alpine Linux のパッケージマネージャ
# --no-cache: ダウンロードしたパッケージをキャッシュしない（コンテナサイズ削減）
echo "=========================================="
echo "Installing tools in client container..."
echo "=========================================="
echo ""

# 各パッケージの説明:
#   curl       : HTTP/HTTPS クライアント
#                -4 オプションで IPv4、-6 オプションで IPv6 を指定可能
#   bind-tools : BIND DNS ツール群
#                dig: DNS クエリを実行（A, AAAA レコードの確認）
#                nslookup: 名前解決テスト
#   iputils    : ネットワーク診断ツール
#                ping: ICMP Echo Request を送信して疎通確認
#                tracepath: 経路追跡
#   python3    : Python 3 インタプリタ
#                ds_client.py フォールバックテストスクリプト用
apk add --no-cache curl bind-tools iputils python3

# -----------------------------------------------------------------------------
# インストール完了メッセージ
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "Tools installed successfully!"
echo "=========================================="
echo ""
echo "利用可能なコマンド:"
echo ""
echo "  curl      - HTTP クライアント"
echo "              例: curl -4 http://172.30.0.10/"
echo "              例: curl -6 -g http://[fd00:dead:beef::10]/"
echo ""
echo "  dig       - DNS 名前解決"
echo "              例: dig dual-ok.local A +short"
echo "              例: dig dual-ok.local AAAA +short"
echo ""
echo "  ping      - ICMP 疎通確認"
echo "              例: ping -c 2 172.30.0.10"
echo "              例: ping -c 2 fd00:dead:beef::10"
echo ""
echo "  python3   - Python インタプリタ"
echo "              例: python3 /tmp/ds_client.py dual-ok.local 80"
echo ""
