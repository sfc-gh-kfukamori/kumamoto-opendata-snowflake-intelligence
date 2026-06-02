-- =============================================================================
-- 05_load_procedure.sql
-- 熊本市オープンデータ - Snowflake 内 Python SP による CSV ロード
-- （External Network Access を利用した Snowflake 完結ロード）
--
-- 概要:
--   External Network Access Integration（KUMAMOTO_EAI）を使い、
--   Snowflake 内の Python Stored Procedure から直接 CSV をダウンロードして
--   テーブルへロードします。ローカル Python 実行環境が不要です。
--
-- 前提条件:
--   - 02_external_network_access.sql が実行済みであること
--   - KUMAMOTO_EAI が ENABLED = TRUE であること
--
-- 実行ロール: SYSADMIN
-- 実行場所: Snowsight ワークシート
-- =============================================================================

USE ROLE SYSADMIN;
USE DATABASE KUMAMOTO_OPENDATA_DB;
USE SCHEMA RAW_DATA;
USE WAREHOUSE COMPUTE_WH;

-- =============================================================================
-- ヘルパープロシージャ: 単一 CSV URL をテーブルにロード
-- 引数:
--   p_url        : ダウンロードする CSV の URL
--   p_table      : ロード先テーブル名（スキーマ名なし）
--   p_truncate   : TRUE の場合、既存データを TRUNCATE してからロード
-- =============================================================================
CREATE OR REPLACE PROCEDURE LOAD_CSV_FROM_URL(
    P_URL      STRING,
    P_TABLE    STRING,
    P_TRUNCATE BOOLEAN DEFAULT TRUE
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
-- External Access Integration を指定することで外部 HTTP 通信が許可される
EXTERNAL_ACCESS_INTEGRATIONS = (KUMAMOTO_EAI)
PACKAGES = ('requests', 'chardet', 'snowflake-snowpark-python')
HANDLER = 'main'
COMMENT = 'くまもとデータ連携基盤の CSV URL を指定して Snowflake テーブルへロードする SP'
AS $$
import csv
import io
import chardet
import requests
from snowflake.snowpark import Session

def detect_and_decode(raw_bytes: bytes) -> str:
    """バイト列をエンコーディング自動検出してデコードする"""
    # BOM付き UTF-8 を優先チェック
    if raw_bytes.startswith(b'\xef\xbb\xbf'):
        return raw_bytes.decode('utf-8-sig')
    # chardet でサンプリング検出
    detected = chardet.detect(raw_bytes[:10000])
    enc = detected.get('encoding') or 'utf-8'
    for encoding in [enc, 'utf-8', 'cp932']:
        try:
            return raw_bytes.decode(encoding)
        except (UnicodeDecodeError, LookupError):
            continue
    return raw_bytes.decode('utf-8', errors='replace')

def clean_value(val: str):
    """空文字を None（NULL）に変換する"""
    v = val.strip()
    return v if v else None

def main(session: Session, p_url: str, p_table: str, p_truncate: bool) -> str:
    """
    メインハンドラ:
    1. HTTP GET で CSV をダウンロード
    2. エンコード自動検出してデコード
    3. CSV パース
    4. バッチ INSERT
    """
    BATCH_SIZE = 500

    # --- Step 1: CSV ダウンロード ---
    resp = requests.get(p_url, timeout=60, allow_redirects=True)
    resp.raise_for_status()
    raw_bytes = resp.content

    # --- Step 2: デコード ---
    text = detect_and_decode(raw_bytes)

    # --- Step 3: CSV パース ---
    reader = csv.reader(io.StringIO(text))
    rows_all = list(reader)
    if not rows_all:
        return f"ERROR: {p_table} - CSV が空です"

    headers = rows_all[0]
    # 空ヘッダーを補完
    headers = [h if h.strip() else f"COL_{i+1}" for i, h in enumerate(headers)]
    data_rows = [r for r in rows_all[1:] if any(v.strip() for v in r)]

    # --- Step 4: TRUNCATE（オプション）---
    if p_truncate:
        session.sql(f"TRUNCATE TABLE IF EXISTS {p_table}").collect()

    # --- Step 5: テーブルのカラム情報を取得 ---
    col_info = session.sql(f"SHOW COLUMNS IN TABLE {p_table}").collect()
    table_cols = [row[2] for row in col_info if row[2] != "_LOADED_AT"]
    n_cols = min(len(headers), len(table_cols))

    # --- Step 6: バッチ INSERT ---
    col_names = ", ".join(table_cols[:n_cols])
    placeholders = ", ".join(["?"] * n_cols)
    insert_sql = f"INSERT INTO {p_table} ({col_names}) VALUES ({placeholders})"

    total = 0
    for i in range(0, len(data_rows), BATCH_SIZE):
        batch = data_rows[i : i + BATCH_SIZE]
        params = [
            [clean_value(v) for v in row[:n_cols]]
            for row in batch
        ]
        session.sql(insert_sql, params=params).collect()
        total += len(batch)

    return f"SUCCESS: {p_table} に {total} 行をロードしました"
$$;

-- =============================================================================
-- 全データセットをまとめてロードするプロシージャ
-- =============================================================================
CREATE OR REPLACE PROCEDURE LOAD_ALL_KUMAMOTO_CSV()
RETURNS TABLE (テーブル名 STRING, 結果 STRING)
LANGUAGE SQL
COMMENT = '熊本市オープンデータ全7テーブルを一括ロードする SP'
AS
$$
DECLARE
    results ARRAY := ARRAY_CONSTRUCT();
    msg STRING;
BEGIN
    -- 1. 指定緊急避難場所
    CALL LOAD_CSV_FROM_URL(
        'https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/b83d7fa7-71d3-4a4d-8bfc-b2baad9df5d9/resource/97584727-c1e8-44f8-987f-4a0c5bcb7c15/download/01__431001_evacuation_space.csv',
        'EVACUATION_PLACES', TRUE
    ) INTO :msg;
    results := ARRAY_APPEND(:results, OBJECT_CONSTRUCT('table', 'EVACUATION_PLACES', 'result', :msg));

    -- 2. 公共施設
    CALL LOAD_CSV_FROM_URL(
        'https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/7821d392-e191-4a49-8621-a02f215e9dec/resource/ac243e75-974a-4c24-8184-8ce18afadb2e/download/13__431001_public_facility.csv',
        'PUBLIC_FACILITIES', TRUE
    ) INTO :msg;
    results := ARRAY_APPEND(:results, OBJECT_CONSTRUCT('table', 'PUBLIC_FACILITIES', 'result', :msg));

    -- 3. 公衆無線LAN
    CALL LOAD_CSV_FROM_URL(
        'https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/7ae263f6-601c-4a10-89d9-d11105fb0343/resource/45e48bb2-707b-4743-9d3f-7cb4a0636f7d/download/15_lan_431001_public_wireless_lan.csv',
        'WIFI_ACCESS_POINTS', TRUE
    ) INTO :msg;
    results := ARRAY_APPEND(:results, OBJECT_CONSTRUCT('table', 'WIFI_ACCESS_POINTS', 'result', :msg));

    -- 4. 子育て施設
    CALL LOAD_CSV_FROM_URL(
        'https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/73f49e30-1552-45e1-ae3e-2f4e540d5eeb/resource/5a6dd186-cf34-44e5-852a-e2787e48a050/download/21__431001_preschool.csv',
        'CHILDCARE_FACILITIES', TRUE
    ) INTO :msg;
    results := ARRAY_APPEND(:results, OBJECT_CONSTRUCT('table', 'CHILDCARE_FACILITIES', 'result', :msg));

    -- 5. 地域・年齢別人口
    CALL LOAD_CSV_FROM_URL(
        'https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/cbc9156d-50f6-4dcb-bd38-a2144008e7d9/resource/78ffb49b-211a-4db4-b350-47370562809f/download/19_r6.1.1_431001_population_202411-cleaned.csv',
        'DEMOGRAPHICS', TRUE
    ) INTO :msg;
    results := ARRAY_APPEND(:results, OBJECT_CONSTRUCT('table', 'DEMOGRAPHICS', 'result', :msg));

    -- 6. 駐輪場
    CALL LOAD_CSV_FROM_URL(
        'https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/6782c18a-1a9b-4edf-bdac-a262699af702/resource/8d83d627-2502-400b-be4c-1b255109a231/download/16__431001_bicycleparkingarea.csv',
        'BICYCLE_PARKING', TRUE
    ) INTO :msg;
    results := ARRAY_APPEND(:results, OBJECT_CONSTRUCT('table', 'BICYCLE_PARKING', 'result', :msg));

    -- 7. 道路照明灯
    CALL LOAD_CSV_FROM_URL(
        'https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/8b232cf5-76ab-469d-a282-181992847f51/resource/a05daa97-f154-4da9-9fec-bb64fcbdbad6/download/18__431001_roadwaylightning.csv',
        'ROAD_LIGHTS', TRUE
    ) INTO :msg;
    results := ARRAY_APPEND(:results, OBJECT_CONSTRUCT('table', 'ROAD_LIGHTS', 'result', :msg));

    RETURN TABLE(
        SELECT
            value:table::STRING AS テーブル名,
            value:result::STRING AS 結果
        FROM TABLE(FLATTEN(input => :results))
    );
END;
$$;

-- =============================================================================
-- 実行方法（コメントを外して実行）
-- =============================================================================

-- 個別テーブルをロードする場合:
-- CALL LOAD_CSV_FROM_URL(
--     'https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset/.../download/XXX.csv',
--     'TABLE_NAME',
--     TRUE
-- );

-- 全テーブルを一括ロードする場合:
-- CALL LOAD_ALL_KUMAMOTO_CSV();
