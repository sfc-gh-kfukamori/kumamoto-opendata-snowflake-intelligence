-- =============================================================================
-- 08_create_agent.sql
-- 熊本市オープンデータ - Cortex Agent（Snowflake Intelligence）作成
--
-- 実行ロール: SYSADMIN（CREATE AGENT 権限が必要）
-- 実行場所: Snowsight ワークシート
--
-- ★★★ Cortex Agent 作成の重要ポイント ★★★
--
-- 1. 構文: CREATE OR REPLACE AGENT（"CORTEX AGENT" ではない）
--
-- 2. ツール定義は FROM SPECIFICATION $$ YAML $$ 内に記述
--    （TOOLS = ({...}) のような形式は使えない）
--
-- 3. Cortex Analyst ツールには execution_environment でウェアハウスを明示的に指定
--    × warehouse: "COMPUTE_WH"       → ドキュメント非掲載のキー（無視される）
--    ○ execution_environment:
--        type: warehouse
--        warehouse: COMPUTE_WH       → 正しい形式
--    ※ これを指定しないと "missing an execution environment" エラーになる
--
-- 4. semantic_view には完全修飾名（DB.SCHEMA.VIEW）を指定
--
-- 5. 権限付与: GRANT USAGE ON AGENT（"CORTEX AGENT" ではない）
-- =============================================================================

USE DATABASE KUMAMOTO_OPENDATA_DB;
USE SCHEMA ANALYTICS;
USE WAREHOUSE COMPUTE_WH;

-- =============================================================================
-- Cortex Agent 作成
-- =============================================================================
CREATE OR REPLACE AGENT KUMAMOTO_OPENDATA_DB.ANALYTICS.KUMAMOTO_CITY_AGENT
  -- Snowflake Intelligence の Agent 一覧・説明欄に表示
  COMMENT = '熊本市オープンデータ（施設・人口・インフラ）への自然言語問い合わせエージェント'

  -- Snowflake Intelligence UI の表示設定
  PROFILE = '{
    "display_name": "くまもとデータアシスタント",
    "color": "blue"
  }'

  -- エージェント仕様（YAML 形式）
  FROM SPECIFICATION
  $$
  # モデル設定: auto = Snowflake が最適モデルを自動選択（推奨）
  models:
    orchestration: auto

  # オーケストレーション設定（タイムアウト・トークン上限）
  orchestration:
    budget:
      seconds: 60
      tokens: 16000

  # エージェントへの指示
  instructions:
    # ユーザーへの回答スタイルの指示
    response: |
      あなたは「くまもとデータアシスタント」です。熊本市のオープンデータを活用して、
      熊本市職員の皆様の業務をサポートするAIアシスタントです。

      回答のルール:
      - 日本語で回答してください
      - 数値はカンマ区切り（例: 1,234人）で表示してください
      - 割合・比率は小数点1桁の%（例: 25.3%）で表示してください
      - 表形式が適切な場合はMarkdownテーブルを使用してください
      - データの出典は「くまもとデータ連携基盤（令和6年公開）」です
      - データに存在しない情報を推測・創作しないでください

      データについて:
      - 人口データの基準日は令和6年（2024年）1月1日です
      - 施設データは最新情報と異なる場合があります（データ公開時点の情報）

    # ツール選択の指示（どの質問にどのツールを使うか）
    orchestration: |
      - 避難場所・公共施設・子育て施設・Wi-Fiに関する質問は facility_search ツールを使う
      - 人口統計・高齢化率・年齢別人口に関する質問は population_and_infra ツールを使う
      - 道路照明灯・駐輪場に関する質問は population_and_infra ツールを使う

    # Snowflake Intelligence UI のサンプル質問ボタン（クリックで自動入力）
    sample_questions:
      - question: "地震に対応している避難場所は何か所ありますか？"
      - question: "65歳以上の高齢者が最も多い校区はどこですか？"
      - question: "一時預かりができる子育て施設を教えてください"
      - question: "水銀灯（LED未換）の道路照明灯は何本残っていますか？"
      - question: "熊本市の区ごとの総人口と高齢化率を教えてください"

  # ツール定義
  # tool_spec の name はシンプルな ASCII 文字列（tool_resources のキーと一致）
  tools:
    # ツール 1: 施設系セマンティックビュー（避難場所・公共施設・子育て施設）
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "facility_search"
        description: |
          熊本市の施設情報（指定緊急避難場所・公共施設・子育て施設）に関する
          問い合わせに使用するツール。
          使用する場面:
          - 避難場所の件数・収容人数・災害種別対応（地震/洪水/津波等）を調べる
          - 公共施設の場所・種別を調べる
          - 子育て施設（一時預かり・病児保育の有無）を調べる
          使用しない場面:
          - 人口統計・高齢化率の分析（population_and_infra を使う）
          - 道路照明灯・駐輪場の情報（population_and_infra を使う）

    # ツール 2: 人口統計・インフラ系セマンティックビュー
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "population_and_infra"
        description: |
          熊本市の人口統計（地域・年齢別）および都市インフラ（道路照明灯・駐輪場）に
          関する問い合わせに使用するツール。
          使用する場面:
          - 校区・区ごとの人口・世帯数を調べる
          - 高齢化率・年少化率・生産年齢人口を分析する
          - 道路照明灯のLED化状況・要対応本数を調べる
          - 駐輪場の台数・有料無料区分を調べる
          使用しない場面:
          - 施設の場所・サービス内容（facility_search を使う）

  # ツールリソース定義
  # ★ execution_environment でウェアハウスを明示指定（必須）
  # ★ warehouse: "WH_NAME" のみでは "missing an execution environment" エラーになる
  tool_resources:
    # 施設系セマンティックビュー
    facility_search:
      semantic_view: "KUMAMOTO_OPENDATA_DB.ANALYTICS.KUMAMOTO_FACILITIES_SV"
      execution_environment:
        type: warehouse
        warehouse: COMPUTE_WH

    # 人口・インフラ系セマンティックビュー
    population_and_infra:
      semantic_view: "KUMAMOTO_OPENDATA_DB.ANALYTICS.KUMAMOTO_DEMOGRAPHICS_SV"
      execution_environment:
        type: warehouse
        warehouse: COMPUTE_WH
  $$;

-- =============================================================================
-- アクセス権限設定
-- =============================================================================
-- エージェントの利用権限
GRANT USAGE ON AGENT KUMAMOTO_OPENDATA_DB.ANALYTICS.KUMAMOTO_CITY_AGENT TO ROLE PUBLIC;

-- セマンティックビューへの参照権限
GRANT SELECT ON SEMANTIC VIEW KUMAMOTO_OPENDATA_DB.ANALYTICS.KUMAMOTO_FACILITIES_SV   TO ROLE PUBLIC;
GRANT SELECT ON SEMANTIC VIEW KUMAMOTO_OPENDATA_DB.ANALYTICS.KUMAMOTO_DEMOGRAPHICS_SV TO ROLE PUBLIC;

-- 分析ビューへの SELECT 権限（Cortex Analyst が SQL を実行するため）
GRANT SELECT ON VIEW KUMAMOTO_OPENDATA_DB.ANALYTICS.FACILITIES_COMBINED_V     TO ROLE PUBLIC;
GRANT SELECT ON VIEW KUMAMOTO_OPENDATA_DB.ANALYTICS.DEMOGRAPHICS_SUMMARY_V    TO ROLE PUBLIC;
GRANT SELECT ON VIEW KUMAMOTO_OPENDATA_DB.ANALYTICS.ROAD_LIGHTS_STATUS_V      TO ROLE PUBLIC;
GRANT SELECT ON VIEW KUMAMOTO_OPENDATA_DB.ANALYTICS.BICYCLE_PARKING_SUMMARY_V TO ROLE PUBLIC;

-- スキーマとRAWテーブルへのアクセス権限
GRANT USAGE ON SCHEMA KUMAMOTO_OPENDATA_DB.ANALYTICS TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA KUMAMOTO_OPENDATA_DB.RAW_DATA  TO ROLE PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA KUMAMOTO_OPENDATA_DB.RAW_DATA TO ROLE PUBLIC;

-- =============================================================================
-- 動作確認
-- =============================================================================
-- エージェント一覧に表示されるか確認
SHOW AGENTS IN SCHEMA KUMAMOTO_OPENDATA_DB.ANALYTICS;

-- エージェントの詳細設定を確認
DESCRIBE AGENT KUMAMOTO_OPENDATA_DB.ANALYTICS.KUMAMOTO_CITY_AGENT;

-- =============================================================================
-- SQL からのテスト（任意）
-- Snowflake Intelligence UI から直接試す場合は不要
-- =============================================================================
/*
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'KUMAMOTO_OPENDATA_DB.ANALYTICS.KUMAMOTO_CITY_AGENT',
  $${"messages": [{"role": "user", "content": [{"type": "text",
     "text": "地震に対応している避難場所は何か所ありますか？"}]}], "stream": false}$$
);
*/
