-- =============================================================================
-- 07_create_semantic_views.sql
-- 熊本市オープンデータ - セマンティックビュー DDL
--
-- 実行ロール: SYSADMIN（CREATE SEMANTIC VIEW 権限が必要）
-- 実行場所: Snowsight ワークシート
--
-- ★★★ セマンティックビューの設計ポイント ★★★
--
-- 1. ディメンション・メトリック名は ASCII のみ（Cortex Analyst 必須要件）
--    × facilities."施設名称" AS "施設名称"   → エラー（日本語は使えない）
--    ○ facilities.shisetsu_name AS shisetsu_name → OK（ASCIIのみ）
--
-- 2. 日本語はSYNONYMS と COMMENT で補完
--    WITH SYNONYMS = ('施設名称', '施設名', '名称', 'facility name')
--    → 日本語での自然言語クエリに対応できる
--
-- 3. AI_VERIFIED_QUERIES（VQR）で頻出質問の SQL を事前登録
--    → Cortex Analyst がまず VQR にマッチするか確認し、マッチすれば即時実行
--    → 回答精度と応答速度が向上する
--
-- 4. AI_SQL_GENERATION でドメイン特有のルールを指定
--    → カラムの値ドメインや NULL の扱い等を記述
--    → LLM が SQL を生成する際のガイドラインとして使用される
--
-- 5. execution_environment でウェアハウスを明示（Cortex Agent 経由時に必須）
--    → CREATE AGENT の tool_resources に指定
-- =============================================================================

USE DATABASE KUMAMOTO_OPENDATA_DB;
USE SCHEMA ANALYTICS;
USE WAREHOUSE COMPUTE_WH;

-- =============================================================================
-- セマンティックビュー 1: KUMAMOTO_FACILITIES_SV
-- 対象: 指定緊急避難場所・公共施設・子育て施設の統合ビュー
-- =============================================================================
CREATE OR REPLACE SEMANTIC VIEW KUMAMOTO_FACILITIES_SV

  TABLES (
    -- FACILITIES_COMBINED_V は3テーブル（避難場所・公共施設・子育て施設）の UNION ALL
    facilities AS KUMAMOTO_OPENDATA_DB.ANALYTICS.FACILITIES_COMBINED_V
      PRIMARY KEY (shisetsu_name, shisetsu_type)
      COMMENT = '熊本市の避難場所・公共施設・子育て施設の統合ビュー'
  )

  -- -----------------------------------------------------------------------
  -- ディメンション定義（絞り込み・グループ化に使う列）
  -- 注意: ディメンション名（AS の左辺）は ASCII のみ使用可能
  --       日本語は SYNONYMS / COMMENT で補完する
  -- -----------------------------------------------------------------------
  DIMENSIONS (
    -- 施設の大分類（指定緊急避難場所 / 公共施設 / 子育て施設）
    facilities.shisetsu_type AS shisetsu_type
      WITH SYNONYMS = ('施設種別大分類', '施設タイプ', '施設分類', '種別', 'facility type')
      COMMENT = '施設の大分類（指定緊急避難場所 / 公共施設 / 子育て施設）',

    -- 施設の詳細種別
    facilities.shisetsu_subtype AS shisetsu_subtype
      WITH SYNONYMS = ('施設種別小分類', '施設詳細種別', '細分類')
      COMMENT = '施設の詳細種別（保育所・児童館・地域子育て支援拠点 等）',

    -- 施設名称
    facilities.shisetsu_name AS shisetsu_name
      WITH SYNONYMS = ('施設名称', '施設名', '名称', 'facility name')
      COMMENT = '施設の正式名称',

    -- 所在地
    facilities.address AS address
      WITH SYNONYMS = ('所在地', '住所', '場所')
      COMMENT = '施設の所在地（都道府県〜番地の連結表記）',

    -- 区名（熊本市の5行政区）
    facilities.ward_name AS ward_name
      WITH SYNONYMS = ('区名', '区', '行政区')
      COMMENT = '熊本市の行政区名（中央区・東区・西区・南区・北区等）',

    -- 位置情報（地図表示用）
    facilities.latitude AS latitude
      COMMENT = '施設の緯度（WGS84）',
    facilities.longitude AS longitude
      COMMENT = '施設の経度（WGS84）',

    -- ---- 避難場所の災害種別フラグ（BOOLEAN） ----
    -- 各災害に対応しているかどうか（TRUE = 対応）
    facilities.jishin_flag AS jishin_flag
      WITH SYNONYMS = ('地震対応フラグ', '地震対応', '地震避難', '地震')
      COMMENT = '地震に対応した指定緊急避難場所かどうか（TRUE=対応）',

    facilities.kozui_flag AS kozui_flag
      WITH SYNONYMS = ('洪水対応フラグ', '洪水対応', '洪水')
      COMMENT = '洪水に対応した指定緊急避難場所かどうか',

    facilities.tsunami_flag AS tsunami_flag
      WITH SYNONYMS = ('津波対応フラグ', '津波対応', '津波')
      COMMENT = '津波に対応した指定緊急避難場所かどうか',

    facilities.kuzure_flag AS kuzure_flag
      WITH SYNONYMS = ('崖崩れ対応フラグ', '崖崩れ', '土石流')
      COMMENT = '崖崩れ・土石流・地滑りに対応した避難場所かどうか',

    facilities.takashio_flag AS takashio_flag
      WITH SYNONYMS = ('高潮対応フラグ', '高潮')
      COMMENT = '高潮に対応した指定緊急避難場所かどうか',

    -- ---- 子育て施設のサービスフラグ ----
    facilities.ichiji_azukari_flag AS ichiji_azukari_flag
      WITH SYNONYMS = ('一時預かり可否', '一時預かり', '一時保育')
      COMMENT = '子育て施設で一時預かりが利用可能かどうか（避難場所は NULL）',

    facilities.byoji_hoiku_flag AS byoji_hoiku_flag
      WITH SYNONYMS = ('病児保育あり', '病児保育', '病中保育')
      COMMENT = '病児保育を実施している子育て施設かどうか（避難場所は NULL）',

    -- 電話番号
    facilities.phone AS phone
      WITH SYNONYMS = ('電話番号', '電話')
      COMMENT = '施設の電話番号'
  )

  -- -----------------------------------------------------------------------
  -- メトリック定義（集計・計算に使う数値）
  -- -----------------------------------------------------------------------
  METRICS (
    -- 施設件数（最も基本的な集計）
    facilities.shisetsu_count AS COUNT(*)
      WITH SYNONYMS = ('施設件数', '施設数', '件数', '箇所数')
      COMMENT = '施設の件数（絞り込み条件に応じてカウント）',

    -- 収容人数（避難場所のみ有効）
    facilities.total_capacity AS SUM(capacity)
      WITH SYNONYMS = ('合計収容人数', '収容人数', '避難収容人数', '定員合計')
      COMMENT = '避難場所の想定収容人数の合計（公共施設・子育て施設は NULL のため除外される）',

    facilities.avg_capacity AS AVG(capacity)
      WITH SYNONYMS = ('平均収容人数')
      COMMENT = '避難場所の想定収容人数の平均',

    facilities.max_capacity AS MAX(capacity)
      WITH SYNONYMS = ('最大収容人数')
      COMMENT = '最も収容人数が大きい避難場所の収容人数'
  )

  COMMENT = '熊本市の施設情報（避難場所・公共施設・子育て施設）のセマンティックビュー。災害種別フラグや子育てサービス有無での絞り込みが可能。'

  -- -----------------------------------------------------------------------
  -- SQL 生成ガイドライン
  -- LLM が SQL を生成する際のドメインルールを記述
  -- -----------------------------------------------------------------------
  AI_SQL_GENERATION '
    shisetsu_type カラムの値は以下の3種類のみ:
      指定緊急避難場所、公共施設、子育て施設
    避難場所を検索する際は shisetsu_type = 指定緊急避難場所 でフィルタする。
    子育て施設を検索する際は shisetsu_type = 子育て施設 でフィルタする。
    公共施設を検索する際は shisetsu_type = 公共施設 でフィルタする。
    capacity（収容定員）は避難場所のみ有効で、公共施設・子育て施設は NULL。
    ward_name は 中央区・東区・西区・南区・北区 の5区が主要な行政区。
    災害フラグ（jishin_flag 等）は避難場所のみ有効で、他の施設種別は NULL または FALSE。
  '

  -- -----------------------------------------------------------------------
  -- Verified Query Recommendations（VQR）
  -- よく聞かれる質問の正解 SQL をあらかじめ登録
  -- Cortex Analyst はまず VQR にマッチするか確認し、マッチすれば即時実行
  -- -----------------------------------------------------------------------
  AI_VERIFIED_QUERIES (
    -- VQR1: 地震対応避難場所の件数（最頻出質問）
    vqr1 AS (
      QUESTION '地震に対応している避難場所は何か所ありますか？'
      SQL 'SELECT COUNT(*) AS cnt FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.FACILITIES_COMBINED_V WHERE shisetsu_type = ''指定緊急避難場所'' AND jishin_flag = TRUE'
    ),
    -- VQR2: 区ごとの避難場所数と収容人数
    vqr2 AS (
      QUESTION '区ごとの指定緊急避難場所の数と合計収容人数を教えてください'
      SQL 'SELECT ward_name, COUNT(*) AS cnt, SUM(capacity) AS total_cap FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.FACILITIES_COMBINED_V WHERE shisetsu_type = ''指定緊急避難場所'' GROUP BY ward_name ORDER BY cnt DESC'
    ),
    -- VQR3: 一時預かり可能な子育て施設
    vqr3 AS (
      QUESTION '一時預かりができる子育て施設を教えてください'
      SQL 'SELECT shisetsu_name, shisetsu_subtype, address, phone FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.FACILITIES_COMBINED_V WHERE shisetsu_type = ''子育て施設'' AND ichiji_azukari_flag = TRUE ORDER BY shisetsu_name'
    ),
    -- VQR4: 収容人数トップ10
    vqr4 AS (
      QUESTION '収容人数が最も多い避難場所のトップ10を教えてください'
      SQL 'SELECT shisetsu_name, address, capacity FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.FACILITIES_COMBINED_V WHERE shisetsu_type = ''指定緊急避難場所'' AND capacity IS NOT NULL ORDER BY capacity DESC LIMIT 10'
    ),
    -- VQR5: 病児保育施設
    vqr5 AS (
      QUESTION '病児保育を実施している施設はどこですか？'
      SQL 'SELECT shisetsu_name, shisetsu_subtype, address, phone FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.FACILITIES_COMBINED_V WHERE byoji_hoiku_flag = TRUE ORDER BY shisetsu_name'
    )
  );


-- =============================================================================
-- セマンティックビュー 2: KUMAMOTO_DEMOGRAPHICS_SV
-- 対象: 人口統計（校区別）・道路照明灯・駐輪場
-- =============================================================================
CREATE OR REPLACE SEMANTIC VIEW KUMAMOTO_DEMOGRAPHICS_SV

  TABLES (
    -- 人口サマリー（高齢化率等の計算済み指標を含む）
    demo AS KUMAMOTO_OPENDATA_DB.ANALYTICS.DEMOGRAPHICS_SUMMARY_V
      PRIMARY KEY (area_name)
      COMMENT = '校区ごとの人口サマリー（高齢化率・年少化率等）R6.1.1時点',
    -- 道路照明灯（LED化状態・要対応フラグ付き）
    road AS KUMAMOTO_OPENDATA_DB.ANALYTICS.ROAD_LIGHTS_STATUS_V
      PRIMARY KEY (light_id)
      COMMENT = '道路照明灯の管理状態・光源種別（約30,000件）',
    -- 駐輪場（台数・料金区分）
    bicycle AS KUMAMOTO_OPENDATA_DB.ANALYTICS.BICYCLE_PARKING_SUMMARY_V
      PRIMARY KEY (parking_name)
      COMMENT = '熊本市内の駐輪場一覧'
  )

  DIMENSIONS (
    -- ---- 人口データのディメンション ----
    demo.area_name AS area_name
      WITH SYNONYMS = ('地域名', '校区', '地区名', '地域', '校区名')
      COMMENT = '熊本市の校区名（例: 中央区城東校区）',

    demo.ward_name AS ward_name
      WITH SYNONYMS = ('区名', '区', '行政区')
      COMMENT = '熊本市の行政区名（中央区・東区・西区・南区・北区）',

    demo.survey_date AS survey_date
      WITH SYNONYMS = ('調査年月日', '調査日', '基準日')
      COMMENT = '人口データの調査基準日（令和6年1月1日 = 2024-01-01）',

    -- ---- 道路照明灯のディメンション ----
    road.manager AS manager
      WITH SYNONYMS = ('管理者', '管理区', '担当区')
      COMMENT = '道路照明灯の管理者（区名：東区・中央区等）',

    road.light_type AS light_type
      WITH SYNONYMS = ('街路灯区分', '灯種別')
      COMMENT = '街路灯 or 公園灯の区分',

    road.light_source AS light_source
      WITH SYNONYMS = ('光源', '電球の種類', '光源種別')
      COMMENT = '光源の種類（LED灯・水銀灯等）',

    -- LED化状態（LED化済み / 水銀灯（LED未換）/ その他）
    road.led_status AS led_status
      WITH SYNONYMS = ('LED化状態', 'LED化', 'LED交換状況', '省エネ化')
      COMMENT = 'LED化済み / 水銀灯（LED未換）/ その他',

    road.pillar_status AS pillar_status
      WITH SYNONYMS = ('柱状態', '点検結果', '支柱の状態')
      COMMENT = '支柱の総合判定（良・要検討等）',

    -- 要対応フラグ（TRUE = 要対応）
    road.needs_repair AS needs_repair
      WITH SYNONYMS = ('要対応フラグ', '要対応', '要修繕')
      COMMENT = '対応が必要な照明灯かどうか（TRUE=要対応）',

    -- ---- 駐輪場のディメンション ----
    bicycle.parking_name AS parking_name
      WITH SYNONYMS = ('駐輪場名称', '駐輪場名', '施設名称')
      COMMENT = '駐輪場の名称',

    bicycle.fee_type AS fee_type
      WITH SYNONYMS = ('有料無料区分', '料金', '有料', '無料')
      COMMENT = '有料・無料の区分',

    bicycle.has_roof AS has_roof
      WITH SYNONYMS = ('屋根の有無', '屋根', '屋根付き')
      COMMENT = '駐輪場に屋根があるかどうか'
  )

  METRICS (
    -- ---- 人口メトリック ----
    demo.total_population AS SUM(total_population)
      WITH SYNONYMS = ('総人口', '人口', '住民数')
      COMMENT = '地域の総人口',

    demo.elderly_population AS SUM(elderly_population)
      WITH SYNONYMS = ('高齢者人口', '高齢者数', '65歳以上人口')
      COMMENT = '65歳以上の人口合計',

    demo.young_population AS SUM(young_population)
      WITH SYNONYMS = ('年少人口', '子ども人口', '0〜14歳人口', '子供の数')
      COMMENT = '0〜14歳の人口合計',

    demo.working_age_population AS SUM(working_age_population)
      WITH SYNONYMS = ('生産年齢人口', '労働人口', '15〜64歳人口')
      COMMENT = '15〜64歳の人口合計',

    -- 高齢化率（AVGで集計：校区ごとの高齢化率の平均）
    demo.aging_rate AS AVG(aging_rate)
      WITH SYNONYMS = ('高齢化率', '高齢化', '高齢者比率')
      COMMENT = '高齢化率（65歳以上/総人口×100）の平均（%）',

    demo.youth_rate AS AVG(youth_rate)
      WITH SYNONYMS = ('年少化率', '子ども比率')
      COMMENT = '年少化率（0〜14歳/総人口×100）の平均（%）',

    demo.household_count AS SUM(household_count)
      WITH SYNONYMS = ('世帯数', '世帯', '家庭数')
      COMMENT = '世帯数の合計',

    -- ---- 道路照明灯メトリック ----
    road.light_count AS COUNT(*)
      WITH SYNONYMS = ('照明灯件数', '照明灯の数', '街路灯数', '本数')
      COMMENT = '道路照明灯の件数',

    -- ---- 駐輪場メトリック ----
    bicycle.total_parking AS SUM(total_parking)
      WITH SYNONYMS = ('合計駐輪台数', '駐輪台数', '駐輪スペース')
      COMMENT = '自転車・原付・二輪の合計駐輪可能台数',

    bicycle.parking_count AS COUNT(*)
      WITH SYNONYMS = ('駐輪場件数', '駐輪場数', '駐輪場の数')
      COMMENT = '駐輪場の件数'
  )

  COMMENT = '熊本市の地域・年齢別人口統計（R6.1.1時点）および道路照明灯・駐輪場インフラのセマンティックビュー'

  AI_SQL_GENERATION '
    人口データの基準日は令和6年（2024年）1月1日である。
    高齢者 = 65歳以上（elderly_population）、年少者 = 0〜14歳（young_population）、生産年齢 = 15〜64歳（working_age_population）。
    高齢化率（aging_rate）= 65歳以上の人口 / 総人口 × 100（%）。
    区ごとの集計は ward_name カラムでグループ化する。
    water銀灯を問われた場合は led_status = 水銀灯（LED未換） でフィルタする。
    要対応の照明灯を問われた場合は needs_repair = TRUE でフィルタする。
    無料駐輪場を問われた場合は fee_type = 無料 でフィルタする。
  '

  AI_VERIFIED_QUERIES (
    -- VQR1: 高齢者人口が最も多い校区トップ10
    vqr1 AS (
      QUESTION '65歳以上の高齢者が最も多い校区はどこですか？'
      SQL 'SELECT area_name, elderly_population, aging_rate, total_population FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.DEMOGRAPHICS_SUMMARY_V ORDER BY elderly_population DESC LIMIT 10'
    ),
    -- VQR2: 高齢化率ランキング
    vqr2 AS (
      QUESTION '高齢化率が最も高い校区のランキングを教えてください'
      SQL 'SELECT area_name, ward_name, aging_rate, elderly_population, total_population FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.DEMOGRAPHICS_SUMMARY_V WHERE total_population > 0 ORDER BY aging_rate DESC LIMIT 20'
    ),
    -- VQR3: 区ごとの人口・高齢化率
    vqr3 AS (
      QUESTION '熊本市の区ごとの総人口と高齢化率を教えてください'
      SQL 'SELECT ward_name, SUM(total_population) AS total_pop, SUM(elderly_population) AS elderly_pop, ROUND(SUM(elderly_population)*100.0/NULLIF(SUM(total_population),0),1) AS aging_pct FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.DEMOGRAPHICS_SUMMARY_V GROUP BY ward_name ORDER BY total_pop DESC'
    ),
    -- VQR4: 年少人口が多い校区
    vqr4 AS (
      QUESTION '子ども（0〜14歳）の人口が最も多い校区はどこですか？'
      SQL 'SELECT area_name, ward_name, young_population, total_population, youth_rate FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.DEMOGRAPHICS_SUMMARY_V ORDER BY young_population DESC LIMIT 10'
    ),
    -- VQR5: 水銀灯の残存本数（区別）
    vqr5 AS (
      QUESTION '水銀灯（LED未交換）の道路照明灯は区ごとに何本残っていますか？'
      SQL 'SELECT manager, COUNT(*) AS mercury_count FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.ROAD_LIGHTS_STATUS_V WHERE led_status = ''水銀灯（LED未換）'' GROUP BY manager ORDER BY mercury_count DESC'
    ),
    -- VQR6: 要対応照明灯数（区別）
    vqr6 AS (
      QUESTION '要検討状態の道路照明灯は区ごとに何本ありますか？'
      SQL 'SELECT manager, COUNT(*) AS repair_count FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.ROAD_LIGHTS_STATUS_V WHERE needs_repair = TRUE GROUP BY manager ORDER BY repair_count DESC'
    ),
    -- VQR7: 無料駐輪場の台数
    vqr7 AS (
      QUESTION '無料で使える駐輪場の合計台数と件数を教えてください'
      SQL 'SELECT SUM(total_parking) AS total_spots, COUNT(*) AS parking_cnt FROM KUMAMOTO_OPENDATA_DB.ANALYTICS.BICYCLE_PARKING_SUMMARY_V WHERE fee_type = ''無料'''
    )
  );

-- 作成確認
SHOW SEMANTIC VIEWS IN SCHEMA KUMAMOTO_OPENDATA_DB.ANALYTICS;
