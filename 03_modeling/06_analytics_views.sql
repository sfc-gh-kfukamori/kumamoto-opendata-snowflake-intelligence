-- =============================================================================
-- 06_analytics_views.sql
-- 熊本市オープンデータ - 分析用ビュー（Cortex Analyst 向けデータモデリング）
--
-- 実行ロール: SYSADMIN
-- 実行場所: Snowsight ワークシート
--
-- ★★★ 重要な設計ポイント ★★★
--
-- Cortex Analyst（Snowflake Intelligence の中核エンジン）は、セマンティックビューの
-- 列名を内部 YAML のカラム識別子として使用する。
-- この識別子には ASCII 文字（英字・数字・アンダースコア）のみが使用可能であり、
-- 日本語文字を含む列名は以下のエラーを引き起こす:
--
--   "invalid column name "施設名称": name must start with an underscore or a letter,
--    and only contain letters, underscores, decimal digits (0-9), and dollar signs ($)."
--
-- このため、RAW_DATA テーブルは日本語列名（CKAN CSV の元列名を保持）としつつ、
-- ANALYTICS スキーマのビューでは全列を英字スネークケースに変換している。
-- 日本語はセマンティックビューの SYNONYMS と COMMENT で補完する。
--
-- 列名対応表:
--   "施設名称" → shisetsu_name
--   "区名"     → ward_name
--   "緯度"     → latitude
--   "経度"     → longitude
--   "地震対応" → jishin_flag   (など)
-- =============================================================================

USE DATABASE KUMAMOTO_OPENDATA_DB;
USE SCHEMA ANALYTICS;
USE WAREHOUSE COMPUTE_WH;

-- =============================================================================
-- ビュー 1: FACILITIES_COMBINED_V
-- 避難場所・公共施設・子育て施設を1つのビューに統合
-- Cortex Analyst から「施設」として統一的に問い合わせられるようにする
-- 全列を ASCII 列名に変換（Cortex Analyst 必須要件）
-- =============================================================================
CREATE OR REPLACE VIEW FACILITIES_COMBINED_V AS
SELECT
  -- 施設種別（大分類・小分類）
  '指定緊急避難場所'                              AS shisetsu_type,
  CASE
    WHEN "洪水対応" = '1' AND "地震対応" = '1'   THEN '複合対応'
    WHEN "地震対応" = '1'                         THEN '地震対応'
    WHEN "洪水対応" = '1'                         THEN '洪水対応'
    ELSE 'その他'
  END                                             AS shisetsu_subtype,
  -- 施設名称・所在地
  "名称"                                          AS shisetsu_name,
  "所在地_連結標記"                                AS address,
  -- 区名を所在地文字列から抽出（例: '...熊本市中央区...' → '中央区'）
  SPLIT_PART(SPLIT_PART("所在地_連結標記", '熊本市', 2), '区', 1) || '区' AS ward_name,
  -- 位置情報
  "緯度"                                          AS latitude,
  "経度"                                          AS longitude,
  -- 収容定員（文字列→整数変換、変換失敗は NULL）
  TRY_CAST("想定収容人数" AS INTEGER)              AS capacity,
  -- 対応災害種別の数（フラグが '1' の数を合計）
  ARRAY_SIZE(ARRAY_COMPACT(ARRAY_CONSTRUCT(
    IFF("洪水対応"          = '1', '洪水', NULL),
    IFF("崖崩れ土石流地滑り対応" = '1', '崖崩れ', NULL),
    IFF("高潮対応"          = '1', '高潮', NULL),
    IFF("地震対応"          = '1', '地震', NULL),
    IFF("津波対応"          = '1', '津波', NULL),
    IFF("大規模火事対応"    = '1', '大規模火事', NULL),
    IFF("内水氾濫対応"      = '1', '内水氾濫', NULL),
    IFF("火山現象対応"      = '1', '火山現象', NULL)
  )))                                             AS disaster_type_count,
  -- 災害種別フラグ（BOOLEAN）
  "地震対応"          = '1'                       AS jishin_flag,
  "洪水対応"          = '1'                       AS kozui_flag,
  "津波対応"          = '1'                       AS tsunami_flag,
  "崖崩れ土石流地滑り対応" = '1'                  AS kuzure_flag,
  "高潮対応"          = '1'                       AS takashio_flag,
  -- 子育てサービスフラグ（避難場所は NULL）
  NULL::BOOLEAN                                   AS ichiji_azukari_flag,
  NULL::BOOLEAN                                   AS byoji_hoiku_flag,
  -- 連絡先
  "電話番号"                                       AS phone,
  "URL"                                           AS url
FROM KUMAMOTO_OPENDATA_DB.RAW_DATA.EVACUATION_PLACES

UNION ALL

SELECT
  '公共施設'                                       AS shisetsu_type,
  COALESCE("種別", 'その他')                        AS shisetsu_subtype,
  "名称"                                           AS shisetsu_name,
  "所在地_連結標記"                                 AS address,
  SPLIT_PART(SPLIT_PART("所在地_連結標記", '熊本市', 2), '区', 1) || '区' AS ward_name,
  "緯度"                                           AS latitude,
  "経度"                                           AS longitude,
  NULL::INTEGER                                    AS capacity,
  NULL::INTEGER                                    AS disaster_type_count,
  NULL::BOOLEAN AS jishin_flag,
  NULL::BOOLEAN AS kozui_flag,
  NULL::BOOLEAN AS tsunami_flag,
  NULL::BOOLEAN AS kuzure_flag,
  NULL::BOOLEAN AS takashio_flag,
  NULL::BOOLEAN AS ichiji_azukari_flag,
  NULL::BOOLEAN AS byoji_hoiku_flag,
  "電話番号"                                        AS phone,
  "URL"                                            AS url
FROM KUMAMOTO_OPENDATA_DB.RAW_DATA.PUBLIC_FACILITIES

UNION ALL

SELECT
  '子育て施設'                                      AS shisetsu_type,
  COALESCE("種別", 'その他子育て施設')               AS shisetsu_subtype,
  "名称"                                            AS shisetsu_name,
  "所在地_連結標記"                                  AS address,
  SPLIT_PART(SPLIT_PART("所在地_連結標記", '熊本市', 2), '区', 1) || '区' AS ward_name,
  "緯度"                                            AS latitude,
  "経度"                                            AS longitude,
  TRY_CAST("収容定員" AS INTEGER)                   AS capacity,
  NULL::INTEGER                                     AS disaster_type_count,
  NULL::BOOLEAN AS jishin_flag,
  NULL::BOOLEAN AS kozui_flag,
  NULL::BOOLEAN AS tsunami_flag,
  NULL::BOOLEAN AS kuzure_flag,
  NULL::BOOLEAN AS takashio_flag,
  "一時預かりの有無" = '有'                          AS ichiji_azukari_flag,
  "病児保育の有無"   = '有'                          AS byoji_hoiku_flag,
  "電話番号"                                         AS phone,
  "URL"                                             AS url
FROM KUMAMOTO_OPENDATA_DB.RAW_DATA.CHILDCARE_FACILITIES;


-- =============================================================================
-- ビュー 2: DEMOGRAPHICS_SUMMARY_V
-- 人口データを校区単位に集計、高齢化率・年少化率を計算
-- 年齢3区分: 年少(0-14歳) / 生産年齢(15-64歳) / 高齢者(65歳以上)
-- =============================================================================
CREATE OR REPLACE VIEW DEMOGRAPHICS_SUMMARY_V AS
SELECT
  "地域コード"                                AS area_code,
  "地域名"                                    AS area_name,
  -- 校区名から区名を抽出（例: '中央区城東校区' → '中央区'）
  SPLIT_PART("地域名", '区', 1) || '区'       AS ward_name,
  "調査年月日"                                AS survey_date,
  "総人口"                                    AS total_population,
  "男性"                                      AS male_population,
  "女性"                                      AS female_population,
  -- 世帯数: "4,315 " のようにカンマ・スペース混在 → 除去してキャスト
  TRY_CAST(REPLACE(REPLACE("世帯数", ',', ''), ' ', '') AS INTEGER) AS household_count,
  -- 年少人口（0〜14歳）
  (COALESCE("_0_4歳男性",0)  + COALESCE("_0_4歳女性",0)  +
   COALESCE("_5_9歳男性",0)  + COALESCE("_5_9歳女性",0)  +
   COALESCE("_10_14歳男性",0) + COALESCE("_10_14歳女性",0)) AS young_population,
  -- 生産年齢人口（15〜64歳）
  (COALESCE("_15_19歳男性",0) + COALESCE("_15_19歳女性",0) +
   COALESCE("_20_24歳男性",0) + COALESCE("_20_24歳女性",0) +
   COALESCE("_25_29歳男性",0) + COALESCE("_25_29歳女性",0) +
   COALESCE("_30_34歳男性",0) + COALESCE("_30_34歳女性",0) +
   COALESCE("_35_39歳男性",0) + COALESCE("_35_39歳女性",0) +
   COALESCE("_40_44歳男性",0) + COALESCE("_40_44歳女性",0) +
   COALESCE("_45_49歳男性",0) + COALESCE("_45_49歳女性",0) +
   COALESCE("_50_54歳男性",0) + COALESCE("_50_54歳女性",0) +
   COALESCE("_55_59歳男性",0) + COALESCE("_55_59歳女性",0) +
   COALESCE("_60_64歳男性",0) + COALESCE("_60_64歳女性",0)) AS working_age_population,
  -- 高齢者人口（65歳以上）
  (COALESCE("_65_69歳男性",0) + COALESCE("_65_69歳女性",0) +
   COALESCE("_70_74歳男性",0) + COALESCE("_70_74歳女性",0) +
   COALESCE("_75_79歳男性",0) + COALESCE("_75_79歳女性",0) +
   COALESCE("_80_84歳男性",0) + COALESCE("_80_84歳女性",0) +
   COALESCE("_85歳以上男性",0) + COALESCE("_85歳以上女性",0)) AS elderly_population,
  -- 高齢化率 = 高齢者人口 / 総人口 × 100（総人口0の場合はNULL）
  ROUND(
    (COALESCE("_65_69歳男性",0)+COALESCE("_65_69歳女性",0)+
     COALESCE("_70_74歳男性",0)+COALESCE("_70_74歳女性",0)+
     COALESCE("_75_79歳男性",0)+COALESCE("_75_79歳女性",0)+
     COALESCE("_80_84歳男性",0)+COALESCE("_80_84歳女性",0)+
     COALESCE("_85歳以上男性",0)+COALESCE("_85歳以上女性",0))*100.0/NULLIF("総人口",0), 1
  ) AS aging_rate,
  -- 年少化率 = 年少人口 / 総人口 × 100
  ROUND(
    (COALESCE("_0_4歳男性",0)+COALESCE("_0_4歳女性",0)+
     COALESCE("_5_9歳男性",0)+COALESCE("_5_9歳女性",0)+
     COALESCE("_10_14歳男性",0)+COALESCE("_10_14歳女性",0))*100.0/NULLIF("総人口",0), 1
  ) AS youth_rate
FROM KUMAMOTO_OPENDATA_DB.RAW_DATA.DEMOGRAPHICS;


-- =============================================================================
-- ビュー 3: ROAD_LIGHTS_STATUS_V
-- 道路照明灯の状態・種別を整形（LED化判定・要対応フラグを追加）
-- =============================================================================
CREATE OR REPLACE VIEW ROAD_LIGHTS_STATUS_V AS
SELECT
  "ID"              AS light_id,
  "街路灯区分"       AS light_type,        -- '街路灯' / '公園灯'
  "管理番号1"        AS mgmt_no,
  "管理者"           AS manager,           -- 区名（東区・中央区等）
  "路線種別"         AS road_type,
  "路線名"           AS road_name,
  "照明種別"         AS illumination_type, -- '交差点' / '局所' / '連続' / '橋梁'
  "緯度"             AS latitude,
  "経度"             AS longitude,
  "光源"             AS light_source,      -- 'LED灯' / '水銀灯' 等
  -- LED化状態の分類（光源文字列から判定）
  CASE
    WHEN "光源" LIKE '%LED%'  THEN 'LED化済み'
    WHEN "光源" LIKE '%水銀%' THEN '水銀灯（LED未換）'
    ELSE 'その他'
  END                AS led_status,
  "柱状態_結論"      AS pillar_status,     -- '良' / '要検討'
  -- 要対応フラグ: '要' を含む状態判定を TRUE に変換
  "柱状態_結論" LIKE '%要%' AS needs_repair,
  "設置年月日"       AS install_date,
  DATEDIFF('year', "設置年月日", CURRENT_DATE()) AS years_since_install,
  "更新年月日"       AS update_date
FROM KUMAMOTO_OPENDATA_DB.RAW_DATA.ROAD_LIGHTS;


-- =============================================================================
-- ビュー 4: BICYCLE_PARKING_SUMMARY_V
-- 駐輪場の台数・料金区分を整形
-- 駐輪台数（原付）は数値と '可' が混在 → CASE で処理
-- =============================================================================
CREATE OR REPLACE VIEW BICYCLE_PARKING_SUMMARY_V AS
SELECT
  "施設名称"             AS parking_name,
  "所在地_連結標記"       AS address,
  "緯度"                 AS latitude,
  "経度"                 AS longitude,
  "管理者名"             AS manager,
  -- 自転車台数（数値変換）
  TRY_CAST("駐輪台数_自転車" AS INTEGER)  AS bicycle_count,
  -- 原付台数（'可' は NULL として扱う）
  CASE
    WHEN "駐輪台数_原付" = '可' THEN NULL
    ELSE TRY_CAST("駐輪台数_原付" AS INTEGER)
  END                                      AS moped_count,
  -- 二輪台数
  TRY_CAST("駐輪台数_二輪" AS INTEGER)    AS bike_count,
  -- 合計駐輪台数（自転車 + 原付 + 二輪、NULL は 0 として計算）
  COALESCE(TRY_CAST("駐輪台数_自転車" AS INTEGER), 0)
  + COALESCE(CASE WHEN "駐輪台数_原付" = '可' THEN 0
                  ELSE TRY_CAST("駐輪台数_原付" AS INTEGER) END, 0)
  + COALESCE(TRY_CAST("駐輪台数_二輪" AS INTEGER), 0) AS total_parking,
  "屋根の有無"           AS has_roof,       -- '有' / '無' / '一部有'
  "供用時間"             AS operating_hours, -- 例: '00:00/24:00'
  "有料無料区分"         AS fee_type,        -- '有料' / '無料'
  "二時間無料の有無"     AS free_2hr,
  "備考"                 AS notes
FROM KUMAMOTO_OPENDATA_DB.RAW_DATA.BICYCLE_PARKING;


-- 作成確認
SHOW VIEWS IN SCHEMA KUMAMOTO_OPENDATA_DB.ANALYTICS;

-- 各ビューの件数確認
SELECT '避難・公共・子育て統合' AS view_name, COUNT(*) AS cnt FROM FACILITIES_COMBINED_V
UNION ALL SELECT '人口サマリー',       COUNT(*) FROM DEMOGRAPHICS_SUMMARY_V
UNION ALL SELECT '道路照明灯状態',     COUNT(*) FROM ROAD_LIGHTS_STATUS_V
UNION ALL SELECT '駐輪場サマリー',     COUNT(*) FROM BICYCLE_PARKING_SUMMARY_V;
