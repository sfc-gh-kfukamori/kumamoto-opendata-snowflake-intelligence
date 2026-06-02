-- =============================================================================
-- 01_database_setup.sql
-- 熊本市オープンデータ デモ環境 - データベース・スキーマ・ウェアハウス作成
--
-- 実行ロール: SYSADMIN（または適切な権限を持つロール）
-- 実行場所: Snowsight ワークシート
-- =============================================================================

-- -------------------------------------
-- 1. データベース作成
--    KUMAMOTO_OPENDATA_DB: 熊本市オープンデータを格納するデータベース
-- -------------------------------------
CREATE DATABASE IF NOT EXISTS KUMAMOTO_OPENDATA_DB
  COMMENT = '熊本市オープンデータ（くまもとデータ連携基盤）デモ用データベース';

-- -------------------------------------
-- 2. スキーマ作成
--    RAW_DATA   : CSVから直接ロードした生データ
--    ANALYTICS  : 分析用ビュー・セマンティックビュー・エージェント
-- -------------------------------------
CREATE SCHEMA IF NOT EXISTS KUMAMOTO_OPENDATA_DB.RAW_DATA
  COMMENT = '熊本市オープンデータ CSV 生データ格納スキーマ';

CREATE SCHEMA IF NOT EXISTS KUMAMOTO_OPENDATA_DB.ANALYTICS
  COMMENT = '分析用ビュー・セマンティックビュー・Cortex Agent 格納スキーマ';

-- -------------------------------------
-- 3. ウェアハウス確認・作成（既存の場合はスキップ）
--    COMPUTE_WH が存在しない場合のみ作成する
-- -------------------------------------
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE
  COMMENT = 'デモ用コンピュートウェアハウス（S サイズ・60秒自動停止）';

-- -------------------------------------
-- 4. 権限付与（必要に応じて調整）
--    SYSADMIN ロールに全権限を付与
-- -------------------------------------
GRANT ALL ON DATABASE KUMAMOTO_OPENDATA_DB TO ROLE SYSADMIN;
GRANT ALL ON SCHEMA KUMAMOTO_OPENDATA_DB.RAW_DATA TO ROLE SYSADMIN;
GRANT ALL ON SCHEMA KUMAMOTO_OPENDATA_DB.ANALYTICS TO ROLE SYSADMIN;

-- 現在のコンテキストをデモ用に設定
USE DATABASE KUMAMOTO_OPENDATA_DB;
USE SCHEMA RAW_DATA;
USE WAREHOUSE COMPUTE_WH;

-- 作成確認
SHOW DATABASES LIKE 'KUMAMOTO_OPENDATA_DB';
SHOW SCHEMAS IN DATABASE KUMAMOTO_OPENDATA_DB;
