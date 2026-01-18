#!/bin/bash
# =============================================================================
# Dual Stack Lab 起動スクリプト
# =============================================================================
# 目的: Docker Compose で IPv4/IPv6 Dual Stack ラボ環境を起動し、
#       ネットワーク設定と IP アドレスの割り当てを確認する
#
# 実行方法:
#   ./start.sh
#
# 処理内容:
#   1. Docker Compose でコンテナを起動
#   2. コンテナの起動状態を確認
#   3. IPv6 が有効になっているか確認
#   4. 各コンテナに割り当てられた IP アドレスを表示
#   5. 次のステップ（テスト方法）を案内
# =============================================================================

# -----------------------------------------------------------------------------
# シェルオプション設定
# -----------------------------------------------------------------------------
# set -e: コマンドがエラー（終了コード != 0）で終了した場合、スクリプトを即座に終了
# これにより、途中でエラーが発生した場合に後続の処理が実行されるのを防ぐ
set -e

# -----------------------------------------------------------------------------
# スクリプトのディレクトリに移動
# -----------------------------------------------------------------------------
# $0: 実行されたスクリプトのパス（例: ./start.sh, /path/to/start.sh）
# dirname "$0": スクリプトが配置されているディレクトリのパスを取得
# cd "$(...)": そのディレクトリに移動
# pwd: 現在のディレクトリの絶対パスを取得
# この処理により、スクリプトをどこから実行しても正しく動作する
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# -----------------------------------------------------------------------------
# 起動処理の開始メッセージ
# -----------------------------------------------------------------------------
echo "=========================================="
echo "Starting Dual Stack Lab..."
echo "=========================================="
echo ""

# =============================================================================
# 1. コンテナ起動
# =============================================================================
# docker compose up: compose.yaml に定義されたサービスを起動
# -d オプション: デタッチモード（バックグラウンド実行）
#   - コンテナをバックグラウンドで起動し、ターミナルを解放
#   - ログは docker compose logs で確認可能
echo "### Starting containers ###"
docker compose up -d

echo ""
echo "### Container status ###"
# docker ps: 実行中のコンテナを一覧表示
# --filter "name=rd-ds-": コンテナ名が "rd-ds-" で始まるものだけを表示
#   - rd-ds-web
#   - rd-ds-dns
#   - rd-ds-client
docker ps --filter "name=rd-ds-"

echo ""

# =============================================================================
# 2. ネットワーク確認
# =============================================================================
# Docker ネットワークの IPv6 設定を確認
# compose.yaml で enable_ipv6: true を設定している場合、
# "EnableIPv6": true が出力される
echo "### Checking network configuration ###"
echo ""

# docker network inspect: ネットワークの詳細情報を JSON 形式で出力
# 2>/dev/null: エラー出力を抑制（ネットワークが存在しない場合のエラーを隠す）
# grep -o '"EnableIPv6": true': IPv6 が有効な場合にマッチする文字列を抽出
# || echo "not found": grep がマッチしなかった場合（IPv6 無効時）のフォールバック
IPV6_ENABLED=$(docker network inspect rd-dualstack-lab_dsnet 2>/dev/null | grep -o '"EnableIPv6": true' || echo "not found")

# IPv6 の有効/無効を判定して表示
if [ "$IPV6_ENABLED" = '"EnableIPv6": true' ]; then
    echo "IPv6 is ENABLED on dsnet network"
else
    # IPv6 が無効な場合は警告を表示
    # 原因として考えられるのは:
    #   - compose.yaml の enable_ipv6: true が設定されていない
    #   - Docker デーモンの IPv6 設定が無効
    echo "WARNING: IPv6 might not be enabled!"
    echo "Run: docker network inspect rd-dualstack-lab_dsnet"
fi

echo ""

# =============================================================================
# 3. コンテナの IP アドレス確認
# =============================================================================
# docker inspect: コンテナの詳細情報を取得
# --format: Go テンプレートを使用して出力をカスタマイズ
#
# {{range .NetworkSettings.Networks}}...{{end}}:
#   - コンテナが接続しているすべてのネットワークをループ
#   - 今回は dsnet ネットワークのみなので 1 つだけ出力される
#
# {{.IPAddress}}: IPv4 アドレス（例: 172.30.0.10）
# {{.GlobalIPv6Address}}: IPv6 グローバルアドレス（例: fd00:dead:beef::10）
echo "### Container IP addresses ###"
echo ""

# Web サーバ（nginx）の IP アドレス
echo "web container:"
docker inspect rd-ds-web --format '  IPv4: {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker inspect rd-ds-web --format '  IPv6: {{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}'
echo ""

# DNS サーバ（CoreDNS）の IP アドレス
echo "dns container:"
docker inspect rd-ds-dns --format '  IPv4: {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker inspect rd-ds-dns --format '  IPv6: {{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}'
echo ""

# テストクライアント（Alpine Linux）の IP アドレス
echo "client container:"
docker inspect rd-ds-client --format '  IPv4: {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker inspect rd-ds-client --format '  IPv6: {{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}'

echo ""

# =============================================================================
# 4. 次のステップの案内
# =============================================================================
# ユーザーがテストを実施するための手順を表示
echo "=========================================="
echo "Lab started successfully!"
echo ""
echo "Next steps:"
echo "  1. Enter client container:"
echo "     docker exec -it rd-ds-client sh"
echo ""
echo "  2. Install tools (inside container):"
echo "     apk add --no-cache curl bind-tools iputils python3"
echo ""
echo "  3. Run tests (inside container):"
echo "     curl -4 http://172.30.0.10/"
echo "     curl -6 -g http://[fd00:dead:beef::10]/"
echo "     dig dual-ok.local A +short"
echo "     dig dual-ok.local AAAA +short"
echo "=========================================="
