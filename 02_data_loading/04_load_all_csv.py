#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
04_load_all_csv.py
熊本市オープンデータ CSV → Snowflake ロードスクリプト

概要:
    くまもとデータ連携基盤のCSVファイルをHTTPSで取得し、
    Snowflake の RAW_DATA スキーマにある各テーブルへロードします。

前提条件:
    pip install snowflake-connector-python requests chardet

実行方法:
    cd ~/kumamoto_demo
    python 02_data_loading/04_load_all_csv.py

Snowflake接続:
    ~/.snowflake/connections.toml の [jp_demo_team5] セクションを使用
    ウェアハウス: COMPUTE_WH
    データベース: KUMAMOTO_OPENDATA_DB
    スキーマ:     RAW_DATA
"""

import csv
import io
import logging
import sys
import time
from datetime import datetime

import chardet
import requests
import snowflake.connector

# ===========================================================================
# 設定
# ===========================================================================

# Snowflake 接続設定
SNOWFLAKE_CONNECTION = "jp_demo_team5"   # ~/.snowflake/connections.toml のキー名
SNOWFLAKE_DATABASE   = "KUMAMOTO_OPENDATA_DB"
SNOWFLAKE_SCHEMA     = "RAW_DATA"
SNOWFLAKE_WAREHOUSE  = "COMPUTE_WH"

# バッチ挿入サイズ（1回のINSERTで送る行数）
BATCH_SIZE = 500

# HTTP タイムアウト（秒）
HTTP_TIMEOUT = 60

# ログ設定（INFO レベルでコンソールに出力）
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S"
)
logger = logging.getLogger(__name__)

# ===========================================================================
# データセット定義
# 各データセットの CSV URL と Snowflake テーブル名・列数を定義
# ===========================================================================

DATASETS = [
    {
        "name": "指定緊急避難場所一覧",
        "table": "EVACUATION_PLACES",
        "url": (
            "https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/"
            "b83d7fa7-71d3-4a4d-8bfc-b2baad9df5d9/resource/"
            "97584727-c1e8-44f8-987f-4a0c5bcb7c15/download/"
            "01__431001_evacuation_space.csv"
        ),
        # テーブルのカラム数（_LOADED_AT を除く）
        "expected_cols": 38,
    },
    {
        "name": "公共施設一覧",
        "table": "PUBLIC_FACILITIES",
        "url": (
            "https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/"
            "7821d392-e191-4a49-8621-a02f215e9dec/resource/"
            "ac243e75-974a-4c24-8184-8ce18afadb2e/download/"
            "13__431001_public_facility.csv"
        ),
        # 公共施設CSVはエンコード問題が報告されているため flexible モードで処理
        "expected_cols": None,
        "flexible": True,
    },
    {
        "name": "公衆無線LANアクセスポイント",
        "table": "WIFI_ACCESS_POINTS",
        "url": (
            "https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/"
            "7ae263f6-601c-4a10-89d9-d11105fb0343/resource/"
            "45e48bb2-707b-4743-9d3f-7cb4a0636f7d/download/"
            "15_lan_431001_public_wireless_lan.csv"
        ),
        "expected_cols": 28,
    },
    {
        "name": "子育て施設一覧",
        "table": "CHILDCARE_FACILITIES",
        "url": (
            "https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/"
            "73f49e30-1552-45e1-ae3e-2f4e540d5eeb/resource/"
            "5a6dd186-cf34-44e5-852a-e2787e48a050/download/"
            "21__431001_preschool.csv"
        ),
        "expected_cols": 53,
    },
    {
        "name": "地域・年齢別人口一覧",
        "table": "DEMOGRAPHICS",
        "url": (
            "https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/"
            "cbc9156d-50f6-4dcb-bd38-a2144008e7d9/resource/"
            "78ffb49b-211a-4db4-b350-47370562809f/download/"
            "19_r6.1.1_431001_population_202411-cleaned.csv"
        ),
        "expected_cols": 47,
    },
    {
        "name": "駐輪場一覧",
        "table": "BICYCLE_PARKING",
        "url": (
            "https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/"
            "6782c18a-1a9b-4edf-bdac-a262699af702/resource/"
            "8d83d627-2502-400b-be4c-1b255109a231/download/"
            "16__431001_bicycleparkingarea.csv"
        ),
        "expected_cols": 27,
    },
    {
        "name": "道路照明灯一覧",
        "table": "ROAD_LIGHTS",
        "url": (
            "https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/"
            "8b232cf5-76ab-469d-a282-181992847f51/resource/"
            "a05daa97-f154-4da9-9fec-bb64fcbdbad6/download/"
            "18__431001_roadwaylightning.csv"
        ),
        "expected_cols": 55,
    },
]


# ===========================================================================
# ユーティリティ関数
# ===========================================================================

def fetch_csv_bytes(url: str, timeout: int = HTTP_TIMEOUT) -> bytes:
    """
    指定URLからCSVをバイト列として取得する。
    リダイレクトを自動追跡し、失敗時はエラーを発生させる。
    """
    logger.info(f"  HTTPSダウンロード中: {url[:80]}...")
    resp = requests.get(url, timeout=timeout, allow_redirects=True)
    resp.raise_for_status()
    logger.info(f"  → {len(resp.content):,} bytes 取得")
    return resp.content


def detect_and_decode(raw_bytes: bytes) -> str:
    """
    CSVのバイト列をエンコーディング自動検出してデコードする。
    検出順序: UTF-8-SIG（BOM付き）→ UTF-8 → Shift-JIS (cp932)
    """
    # BOM 付き UTF-8 を優先チェック
    if raw_bytes.startswith(b'\xef\xbb\xbf'):
        return raw_bytes.decode('utf-8-sig')

    # chardet で自動検出
    detected = chardet.detect(raw_bytes[:10000])   # 先頭10KB でサンプリング
    enc = detected.get('encoding') or 'utf-8'
    confidence = detected.get('confidence', 0)
    logger.info(f"  エンコード検出: {enc} (信頼度: {confidence:.0%})")

    # 検出結果を試みる。失敗したら cp932（Shift-JIS）にフォールバック
    for encoding in [enc, 'utf-8', 'cp932']:
        try:
            return raw_bytes.decode(encoding)
        except (UnicodeDecodeError, LookupError):
            continue

    # 最終手段: errors='replace' で強制デコード
    logger.warning("  ⚠ エンコード検出失敗。replace モードで強制デコードします")
    return raw_bytes.decode('utf-8', errors='replace')


def parse_csv(text: str, dataset_name: str) -> tuple[list[str], list[list[str]]]:
    """
    CSV テキストをヘッダーとデータ行のリストに変換する。
    空ヘッダー列は列番号で補完する（駐輪場CSVの12列目空問題に対応）。
    """
    reader = csv.reader(io.StringIO(text))
    rows = list(reader)

    if not rows:
        raise ValueError(f"{dataset_name}: CSVが空です")

    # ヘッダー処理
    headers = rows[0]

    # 空ヘッダーを「COL_N」に置換（重複列名によるエラー防止）
    seen = {}
    cleaned_headers = []
    for i, h in enumerate(headers):
        if h.strip() == "":
            h = f"COL_{i+1}"
        # 重複ヘッダーにサフィックスを追加
        base = h
        if base in seen:
            seen[base] += 1
            h = f"{base}_{seen[base]}"
        else:
            seen[base] = 0
        cleaned_headers.append(h)

    # データ行（空行を除外）
    data_rows = [r for r in rows[1:] if any(v.strip() for v in r)]

    logger.info(f"  ヘッダー: {len(cleaned_headers)} 列 / データ行: {len(data_rows):,} 行")
    return cleaned_headers, data_rows


def clean_value(val: str) -> str | None:
    """
    1セルの値を Snowflake 用にクリーニングする。
    - 空文字・空白のみ → None（NULL）
    - 前後の空白・改行を除去
    """
    v = val.strip()
    return v if v else None


def batch_insert(cursor, table: str, headers: list[str], rows: list[list[str]]) -> int:
    """
    行データを BATCH_SIZE 件ずつ Snowflake テーブルに INSERT する。
    実際のカラム数とCSVのカラム数が異なる場合は自動的に調整する。
    戻り値: 挿入した総行数
    """
    if not rows:
        return 0

    # テーブルの実際のカラム一覧を取得（_LOADED_AT を除く）
    cursor.execute(f"SHOW COLUMNS IN TABLE {table}")
    table_cols = [
        row[2]  # カラム名は3列目
        for row in cursor.fetchall()
        if row[2] != "_LOADED_AT"
    ]
    n_cols = len(table_cols)

    # CSVカラム数とテーブルカラム数が違う場合のログ
    if len(headers) != n_cols:
        logger.warning(
            f"  ⚠ CSV列数({len(headers)}) ≠ テーブル列数({n_cols}) "
            f"→ 先頭 {min(len(headers), n_cols)} 列を使用"
        )

    use_cols = min(len(headers), n_cols)
    col_names = ", ".join(table_cols[:use_cols])
    placeholders = ", ".join(["%s"] * use_cols)
    insert_sql = f"INSERT INTO {table} ({col_names}) VALUES ({placeholders})"

    total_inserted = 0
    for i in range(0, len(rows), BATCH_SIZE):
        batch = rows[i : i + BATCH_SIZE]
        # 各行を (use_cols) 列に整形し、NULL変換を適用
        cleaned_batch = [
            tuple(clean_value(v) for v in row[:use_cols])
            for row in batch
        ]
        cursor.executemany(insert_sql, cleaned_batch)
        total_inserted += len(batch)
        logger.info(f"  → {total_inserted:,} / {len(rows):,} 行 挿入済み")

    return total_inserted


# ===========================================================================
# メイン処理
# ===========================================================================

def connect_snowflake():
    """
    ~/.snowflake/connections.toml の接続設定を使って Snowflake に接続する。
    """
    logger.info(f"Snowflake 接続中 ({SNOWFLAKE_CONNECTION})...")
    conn = snowflake.connector.connect(
        connection_name=SNOWFLAKE_CONNECTION,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_SCHEMA,
        warehouse=SNOWFLAKE_WAREHOUSE,
    )
    logger.info("✓ Snowflake 接続成功")
    return conn


def load_dataset(cursor, dataset: dict) -> dict:
    """
    1つのデータセットを CSVダウンロード → パース → INSERT する。
    戻り値: ステータス辞書 {name, status, rows, error}
    """
    name   = dataset["name"]
    table  = dataset["table"]
    url    = dataset["url"]

    logger.info(f"\n{'='*60}")
    logger.info(f"📂 {name} ({table}) のロード開始")
    logger.info(f"{'='*60}")

    try:
        # Step 1: CSV ダウンロード
        raw_bytes = fetch_csv_bytes(url)

        # Step 2: エンコードデコード
        text = detect_and_decode(raw_bytes)

        # Step 3: CSV パース
        headers, rows = parse_csv(text, name)

        # Step 4: 既存データの削除（べき等性確保）
        cursor.execute(f"TRUNCATE TABLE IF EXISTS {table}")
        logger.info(f"  既存データを TRUNCATE しました")

        # Step 5: バッチ INSERT
        n = batch_insert(cursor, table, headers, rows)

        logger.info(f"✅ {name}: {n:,} 行をロード完了")
        return {"name": name, "status": "success", "rows": n, "error": None}

    except Exception as exc:
        logger.error(f"❌ {name}: ロード失敗 → {exc}")
        return {"name": name, "status": "error", "rows": 0, "error": str(exc)}


def main():
    """
    全データセットを順番にロードし、最後にサマリーを表示する。
    """
    start_time = time.time()
    logger.info("=" * 60)
    logger.info("熊本市オープンデータ CSVロード開始")
    logger.info(f"対象テーブル数: {len(DATASETS)}")
    logger.info("=" * 60)

    # Snowflake 接続
    try:
        conn = connect_snowflake()
    except Exception as e:
        logger.error(f"Snowflake 接続失敗: {e}")
        logger.error("~/.snowflake/connections.toml の設定を確認してください")
        sys.exit(1)

    cursor = conn.cursor()
    results = []

    try:
        for dataset in DATASETS:
            result = load_dataset(cursor, dataset)
            results.append(result)
            # 各データセット後に自動コミット（デフォルトで有効）

    finally:
        cursor.close()
        conn.close()
        logger.info("\nSnowflake 接続をクローズしました")

    # ===========================================================================
    # 結果サマリー
    # ===========================================================================
    elapsed = time.time() - start_time
    logger.info("\n" + "=" * 60)
    logger.info("📊 ロード結果サマリー")
    logger.info("=" * 60)

    success_count = 0
    total_rows = 0
    for r in results:
        status_icon = "✅" if r["status"] == "success" else "❌"
        rows_str = f"{r['rows']:,} 行" if r["status"] == "success" else f"失敗: {r['error']}"
        logger.info(f"{status_icon} {r['name']:20s} → {rows_str}")
        if r["status"] == "success":
            success_count += 1
            total_rows += r["rows"]

    logger.info("-" * 60)
    logger.info(f"成功: {success_count}/{len(DATASETS)} テーブル")
    logger.info(f"合計: {total_rows:,} 行ロード")
    logger.info(f"経過時間: {elapsed:.1f} 秒")
    logger.info("=" * 60)

    # 失敗があれば非0終了
    if success_count < len(DATASETS):
        sys.exit(1)


if __name__ == "__main__":
    main()
