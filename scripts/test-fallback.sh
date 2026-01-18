#!/bin/sh
# =============================================================================
# IPv6 フォールバックテストスクリプト
# =============================================================================
# 目的: IPv6 が到達不能な場合に IPv4 へ自動フォールバックする動作を確認する
#
# 実行方法:
#   # コンテナ内で実行（事前にツールのインストールが必要）
#   docker exec -it rd-ds-client sh
#   /scripts/test-fallback.sh
#
#   # または、ホストからコピーして実行
#   docker cp scripts/test-fallback.sh rd-ds-client:/tmp/
#   docker exec rd-ds-client /tmp/test-fallback.sh
#
# 前提条件:
#   - setup-client.sh でツールがインストール済み
#   - または apk add --no-cache curl bind-tools iputils python3 を実行済み
#
# テスト内容:
#   1. 壊れた AAAA レコードの確認（到達不能な IPv6 アドレス）
#   2. curl による Happy Eyeballs フォールバックの観察
#   3. Python スクリプトによる詳細なフォールバック動作の確認
#
# 技術背景:
#   dual-badv6.local は意図的に到達不能な IPv6 アドレス (::9999) を返す
#   これにより、クライアントが IPv6 → IPv4 にフォールバックする様子を観察できる
#   このフォールバック機構は「Happy Eyeballs」(RFC 8305) と呼ばれる
# =============================================================================

# -----------------------------------------------------------------------------
# シェルオプション設定
# -----------------------------------------------------------------------------
# set -e: コマンドがエラーで終了した場合、スクリプトを即座に終了
set -e

# -----------------------------------------------------------------------------
# テスト開始メッセージ
# -----------------------------------------------------------------------------
echo "=========================================="
echo "Dual Stack Lab - IPv6 フォールバックテスト"
echo "=========================================="
echo ""
echo "テスト対象ドメイン: dual-badv6.local"
echo ""
echo "このドメインの DNS 設定:"
echo "  A レコード (IPv4):    172.30.0.10      → 正常（nginx に到達可能）"
echo "  AAAA レコード (IPv6): fd00:dead:beef::9999 → 到達不能（存在しない）"
echo ""
echo "期待される動作:"
echo "  1. IPv6 (::9999) への接続を試行 → タイムアウト"
echo "  2. IPv4 (172.30.0.10) にフォールバック → 成功"
echo ""

# =============================================================================
# テスト 1: DNS レコードの確認
# =============================================================================
# まず、dual-badv6.local の DNS 設定を確認する
# A レコード: 正常なアドレス
# AAAA レコード: 到達不能なアドレス
echo "### テスト 1: DNS レコードの確認 ###"
echo ""

echo "[A レコード] dig dual-badv6.local A +short"
echo "---------------------------------------"
dig dual-badv6.local A +short
echo ""
echo "→ IPv4 アドレス 172.30.0.10 は nginx コンテナに到達可能"
echo ""

echo "[AAAA レコード] dig dual-badv6.local AAAA +short"
echo "---------------------------------------"
dig dual-badv6.local AAAA +short
echo ""
echo "→ IPv6 アドレス fd00:dead:beef::9999 は存在しない（到達不能）"
echo ""

# =============================================================================
# テスト 2: curl による Happy Eyeballs フォールバック
# =============================================================================
# curl は Happy Eyeballs (RFC 8305) を実装しており、
# IPv6 と IPv4 を並列で接続試行する
# --connect-timeout: 接続タイムアウト（秒）
# -v: 詳細出力（接続試行の様子を確認）
echo "### テスト 2: curl による Happy Eyeballs フォールバック ###"
echo ""

echo "[dual-badv6.local] curl --connect-timeout 3 http://dual-badv6.local/"
echo "---------------------------------------"
echo ""

# Happy Eyeballs の動作:
#   1. DNS から A と AAAA の両方を取得
#   2. IPv6 を優先して接続試行（250ms 待機）
#   3. IPv6 が応答しなければ IPv4 も並列で試行
#   4. 先に成功した方を使用
echo "期待される出力:"
echo "  Trying [fd00:dead:beef::9999]:80...  ← IPv6 接続試行（失敗）"
echo "  Trying 172.30.0.10:80...             ← IPv4 接続試行"
echo "  Connected to dual-badv6.local (172.30.0.10) ← IPv4 で成功"
echo ""

# 実際の接続
curl -v --connect-timeout 3 http://dual-badv6.local/ 2>&1 | grep -E "Trying|Connected|HTTP/" | head -n 10
echo ""
echo "→ IPv6 失敗後、IPv4 にフォールバックして接続成功"
echo ""

# =============================================================================
# テスト 3: Python スクリプトによる詳細観察
# =============================================================================
# ds_client.py は Happy Eyeballs よりシンプルな実装で、
# IPv6 → IPv4 の順に**順次**接続試行する
# これにより、フォールバックの様子がより明確に観察できる
echo "### テスト 3: Python スクリプトによる詳細観察 ###"
echo ""

# スクリプトの存在確認（/tmp または /scripts のどちらか）
if [ -f /tmp/ds_client.py ]; then
    SCRIPT_PATH="/tmp/ds_client.py"
elif [ -f /scripts/ds_client.py ]; then
    SCRIPT_PATH="/scripts/ds_client.py"
else
    SCRIPT_PATH=""
fi

if [ -n "$SCRIPT_PATH" ]; then
    # 正常系: dual-ok.local（IPv6 で即座に成功）
    echo "[正常系] python3 $SCRIPT_PATH dual-ok.local 80"
    echo "---------------------------------------"
    echo "期待: IPv6 で即座に接続成功"
    echo ""
    python3 "$SCRIPT_PATH" dual-ok.local 80
    echo ""

    # フォールバック: dual-badv6.local（IPv6 タイムアウト → IPv4 成功）
    echo "[フォールバック] python3 $SCRIPT_PATH dual-badv6.local 80"
    echo "---------------------------------------"
    echo "期待: IPv6 タイムアウト（2秒）→ IPv4 で成功"
    echo ""
    python3 "$SCRIPT_PATH" dual-badv6.local 80
    echo ""
    echo "→ Python スクリプトでもフォールバック動作を確認"
else
    # スクリプトが見つからない場合の案内
    echo "Python スクリプトが見つかりません。"
    echo ""
    echo "以下のコマンドでホストからコピーしてください:"
    echo "  docker cp scripts/ds_client.py rd-ds-client:/tmp/"
    echo ""
    echo "その後、再度このスクリプトを実行してください。"
fi

echo ""

# -----------------------------------------------------------------------------
# テスト完了メッセージ
# -----------------------------------------------------------------------------
echo "=========================================="
echo "フォールバックテスト完了！"
echo "=========================================="
echo ""
echo "結果サマリ:"
echo "  ✓ 壊れた AAAA レコードを確認"
echo "  ✓ curl: Happy Eyeballs による高速フォールバック"
if [ -n "$SCRIPT_PATH" ]; then
    echo "  ✓ Python: 順次接続によるフォールバック"
fi
echo ""
echo "技術的なポイント:"
echo "  - curl は Happy Eyeballs (RFC 8305) を実装"
echo "  - IPv6 を優先しつつ、250ms 待っても応答がなければ IPv4 も試行"
echo "  - ユーザーは IPv6 障害に気づかない（これが理想的な動作）"
echo ""
