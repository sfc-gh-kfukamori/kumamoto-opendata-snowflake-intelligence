-- =============================================================================
-- 02_external_network_access.sql
-- 熊本市オープンデータ デモ環境 - External Network Access 設定
--
-- 目的: Snowflake 内部（ストアドプロシージャ等）から
--       くまもとデータ連携基盤のCSVファイルを直接取得できるようにする
--
-- 実行ロール: ACCOUNTADMIN（Network Rule と EAI の作成に必要）
-- 実行場所: Snowsight ワークシート
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE KUMAMOTO_OPENDATA_DB;
USE SCHEMA RAW_DATA;
USE WAREHOUSE COMPUTE_WH;

-- -------------------------------------
-- 1. Network Rule 作成
--    くまもとデータ連携基盤のCSVホストへのHTTPS通信を許可するルール
-- -------------------------------------
CREATE NETWORK RULE IF NOT EXISTS KUMAMOTO_OPENDATA_NR
  TYPE              = HOST_PORT
  MODE              = EGRESS  -- Snowflake から外部への通信（アウトバウンド）
  VALUE_LIST        = ('datacatalogportal.dlp-kumamoto.jp:443')
  COMMENT           = 'くまもとデータ連携基盤 CSVダウンロード用 Network Rule';

-- -------------------------------------
-- 2. External Access Integration 作成
--    上記 Network Rule を利用する EAI を作成
--    ENABLED = TRUE で即時有効化
-- -------------------------------------
CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS KUMAMOTO_EAI
  ALLOWED_NETWORK_RULES  = (KUMAMOTO_OPENDATA_NR)
  ENABLED                = TRUE
  COMMENT                = 'くまもとデータ連携基盤 CSV取得用 External Access Integration';

-- -------------------------------------
-- 3. SYSADMIN に EAI の使用権限を付与
--    ストアドプロシージャから EAI を参照するために必要
-- -------------------------------------
GRANT USAGE ON INTEGRATION KUMAMOTO_EAI TO ROLE SYSADMIN;

-- 作成確認
SHOW NETWORK RULES LIKE 'KUMAMOTO_OPENDATA_NR';
SHOW EXTERNAL ACCESS INTEGRATIONS LIKE 'KUMAMOTO_EAI';
