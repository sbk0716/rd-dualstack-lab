#!/usr/bin/env python3
# =============================================================================
# Dual Stack クライアント - IPv6→IPv4 フォールバック観察スクリプト
# =============================================================================
# 目的: IPv6 優先で接続を試み、失敗した場合に IPv4 にフォールバックする動作を
#       詳細に観察するためのスクリプト
#
# 使用方法:
#   python3 ds_client.py <host> [port]
#
# 例:
#   python3 ds_client.py dual-ok.local 80      # 正常系（IPv6 で接続成功）
#   python3 ds_client.py dual-badv6.local 80   # IPv6 失敗 → IPv4 フォールバック
#
# 動作:
#   1. DNS で名前解決（A レコードと AAAA レコードを取得）
#   2. IPv6 アドレスを優先してソート
#   3. 順番に接続を試行（IPv6 → IPv4）
#   4. 最初に成功したアドレスで HTTP リクエストを送信
#
# 補足:
#   curl の Happy Eyeballs は高速だが、フォールバックの様子がわかりにくい
#   このスクリプトは明示的に順番に試行するため、動作が観察しやすい
# =============================================================================

import socket
import sys
import time


def try_connect(family: int, sockaddr: tuple) -> tuple:
    """
    指定されたアドレスファミリ（IPv4/IPv6）で TCP 接続を試行する

    引数:
        family: アドレスファミリ
            - socket.AF_INET: IPv4
            - socket.AF_INET6: IPv6
        sockaddr: 接続先アドレス
            - IPv4: (host, port) のタプル
            - IPv6: (host, port, flowinfo, scope_id) のタプル

    戻り値:
        (socket, elapsed_ms, error) のタプル
            - 成功時: (接続済みソケット, 接続時間(ms), None)
            - 失敗時: (None, None, 例外オブジェクト)
    """
    # TCP ソケットを作成
    # socket.SOCK_STREAM: TCP（コネクション指向）
    # socket.SOCK_DGRAM を指定すると UDP になる
    s = socket.socket(family, socket.SOCK_STREAM)

    # タイムアウトを 2 秒に設定
    # IPv6 が到達不能な場合、このタイムアウトで失敗を検出
    # 本番環境では Happy Eyeballs により並列接続するが、
    # このスクリプトでは順次接続で動作をわかりやすくしている
    s.settimeout(2.0)

    # 接続開始時刻を記録
    t0 = time.time()

    try:
        # TCP 接続を試行
        # 成功すると 3-way ハンドシェイク（SYN → SYN-ACK → ACK）が完了
        s.connect(sockaddr)

        # 接続時間を計算（ミリ秒）
        elapsed_ms = (time.time() - t0) * 1000

        return s, elapsed_ms, None

    except Exception as e:
        # 接続失敗時はソケットを閉じて例外を返す
        # よくある例外:
        #   - socket.timeout: タイムアウト（到達不能）
        #   - ConnectionRefusedError: 接続拒否（ポートが閉じている）
        #   - OSError: ネットワーク到達不能
        s.close()
        return None, None, e


def main():
    """
    メイン関数: 名前解決 → 接続試行 → HTTP リクエスト送信
    """
    # コマンドライン引数からホスト名とポート番号を取得
    # デフォルト: dual-ok.local:80
    host = sys.argv[1] if len(sys.argv) > 1 else "dual-ok.local"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 80

    # =========================================================================
    # 1. 名前解決（DNS クエリ）
    # =========================================================================
    # socket.getaddrinfo(): ホスト名から接続可能なアドレス一覧を取得
    #
    # 引数:
    #   host: ホスト名（例: "dual-ok.local"）
    #   port: ポート番号（例: 80）
    #   0: アドレスファミリ（0 = IPv4/IPv6 両方）
    #   socket.SOCK_STREAM: ソケットタイプ（TCP）
    #
    # 戻り値: (family, type, proto, canonname, sockaddr) のリスト
    #   family: AF_INET (IPv4) または AF_INET6 (IPv6)
    #   sockaddr: (host, port) または (host, port, flowinfo, scope_id)
    infos = socket.getaddrinfo(host, port, 0, socket.SOCK_STREAM)

    # =========================================================================
    # 2. IPv6 優先でソート
    # =========================================================================
    # 多くの OS/アプリケーションは IPv6 を優先する（RFC 6724）
    # このスクリプトでも同様に IPv6 を先に試行する
    #
    # ソートキー:
    #   - IPv6 (AF_INET6): 0
    #   - IPv4 (AF_INET): 1
    # これにより IPv6 が先頭に来る
    infos = sorted(infos, key=lambda x: 0 if x[0] == socket.AF_INET6 else 1)

    # 解決結果を表示
    print(f"resolved: {host}:{port}")
    for fam, _, _, _, sockaddr in infos:
        label = "IPv6" if fam == socket.AF_INET6 else "IPv4"
        print(f"  - {label:4} {sockaddr}")

    # =========================================================================
    # 3. 順番に接続を試行
    # =========================================================================
    # IPv6 → IPv4 の順に接続を試行
    # 最初に成功したアドレスで HTTP リクエストを送信
    last_err = None

    for fam, _, _, _, sockaddr in infos:
        label = "IPv6" if fam == socket.AF_INET6 else "IPv4"
        print(f"try {label}: {sockaddr} ...")

        # 接続試行
        s, dt, err = try_connect(fam, sockaddr)

        if s:
            # 接続成功
            print(f"connected via {label} in {dt:.1f} ms")

            # =================================================================
            # 4. HTTP リクエスト送信
            # =================================================================
            # 簡易的な HTTP/1.1 GET リクエストを送信
            # 本番アプリケーションでは requests ライブラリなどを使用すべき
            req = f"GET / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n"
            s.sendall(req.encode("ascii"))

            # レスポンスの最初の 200 バイトを受信し、1行目（ステータスライン）を表示
            # 例: "HTTP/1.1 200 OK"
            first = s.recv(200).decode("latin1", errors="replace").splitlines()[0]
            print("recv:", first)

            # ソケットを閉じて正常終了
            s.close()
            sys.exit(0)
        else:
            # 接続失敗: 次のアドレスを試行
            # よくある失敗理由:
            #   - IPv6 が到達不能（タイムアウト）
            #   - ポートが閉じている（Connection refused）
            print(f"failed via {label}: {err}")
            last_err = err

    # すべてのアドレスで接続失敗
    print("all failed:", last_err)
    sys.exit(1)


# =============================================================================
# スクリプトのエントリーポイント
# =============================================================================
# python3 ds_client.py ... で実行された場合のみ main() を呼び出す
# import された場合は呼び出さない（テスト用）
if __name__ == "__main__":
    main()
