-- =============================================================================
-- 03_raw_tables_ddl.sql
-- 熊本市オープンデータ デモ環境 - RAWテーブル DDL（7テーブル）
--
-- データソース: くまもとデータ連携基盤 (https://datacatalogportal.dlp-kumamoto.jp/)
-- ライセンス: クリエイティブ・コモンズ 表示 (CC BY) - 熊本市
--
-- 実行ロール: SYSADMIN（または ACCOUNTADMIN）
-- 実行場所: Snowsight ワークシート
--
-- 注意:
--   Snowflake では非ASCII文字（日本語）の列名はダブルクォートで囲む必要がある
--   例: "名称" VARCHAR(200)  -- OK
--       名称  VARCHAR(200)  -- NG（構文エラー）
-- =============================================================================

USE DATABASE KUMAMOTO_OPENDATA_DB;
USE SCHEMA RAW_DATA;
USE WAREHOUSE COMPUTE_WH;

-- =============================================================================
-- テーブル 1: 指定緊急避難場所一覧
--   出典CSV: 01__431001_evacuation_space.csv（39列）
--   内容: 熊本市内の指定緊急避難場所（洪水・地震等の災害種別対応情報含む）
--   行数目安: 約 600 件
-- =============================================================================
CREATE OR REPLACE TABLE EVACUATION_PLACES (
  -- 基本識別情報
  "自治体コード"           VARCHAR(10),   -- 全国地方公共団体コード（熊本市: 431001）
  "ID"                    VARCHAR(50),   -- 施設ID
  "名称"                  VARCHAR(200),  -- 避難場所名称
  "名称_カナ"              VARCHAR(200),  -- 名称のフリガナ
  "名称_英字"              VARCHAR(200),  -- 名称の英語表記

  -- 所在地情報
  "所在地_自治体コード"     VARCHAR(10),
  "町字ID"                VARCHAR(20),
  "所在地_連結標記"         VARCHAR(500),  -- 都道府県〜番地の連結表記
  "所在地_都道府県"         VARCHAR(50),
  "所在地_市区町村"         VARCHAR(100),
  "所在地_町字"             VARCHAR(200),
  "所在地_番地以下"         VARCHAR(200),
  "建物名等"               VARCHAR(200),

  -- 位置情報（WGS84 座標系）
  "緯度"                  FLOAT,
  "経度"                  FLOAT,
  "標高"                  FLOAT,

  -- 連絡先
  "電話番号"               VARCHAR(50),
  "内線番号"               VARCHAR(50),
  "メールアドレス"          VARCHAR(200),
  "連絡先FormURL"         VARCHAR(500),
  "連絡先備考"             VARCHAR(500),
  "郵便番号"               VARCHAR(10),
  "市区町村コード"          VARCHAR(10),
  "地方公共団体名"          VARCHAR(100),

  -- 災害種別フラグ（'1' = 対応、空白 = 非対応）
  "洪水対応"               VARCHAR(5),
  "崖崩れ土石流地滑り対応"  VARCHAR(5),
  "高潮対応"               VARCHAR(5),
  "地震対応"               VARCHAR(5),
  "津波対応"               VARCHAR(5),
  "大規模火事対応"          VARCHAR(5),
  "内水氾濫対応"            VARCHAR(5),
  "火山現象対応"            VARCHAR(5),

  -- 施設情報
  "指定避難所との重複"       VARCHAR(5),
  "想定収容人数"            VARCHAR(20),   -- 文字列で保持（NULL や記述が混在）
  "対象町会自治会"          VARCHAR(500),
  "URL"                   VARCHAR(500),
  "画像"                  VARCHAR(500),
  "画像ライセンス"          VARCHAR(100),
  "備考"                  VARCHAR(1000),

  -- ロードメタデータ（自動設定）
  "_LOADED_AT"            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = '指定緊急避難場所一覧（熊本市） - くまもとデータ連携基盤より取得';

-- =============================================================================
-- テーブル 2: 公共施設一覧
--   出典CSV: 13__431001_public_facility.csv
--   内容: 役所・図書館・スポーツ施設等の公共施設
--   行数目安: 約 930 件
-- =============================================================================
CREATE OR REPLACE TABLE PUBLIC_FACILITIES (
  "自治体コード"           VARCHAR(10),
  "ID"                    VARCHAR(50),
  "名称"                  VARCHAR(200),
  "名称_カナ"              VARCHAR(200),
  "名称_英字"              VARCHAR(200),
  "所在地_自治体コード"     VARCHAR(10),
  "町字ID"                VARCHAR(20),
  "所在地_連結標記"         VARCHAR(500),
  "所在地_都道府県"         VARCHAR(50),
  "所在地_市区町村"         VARCHAR(100),
  "所在地_町字"             VARCHAR(200),
  "所在地_番地以下"         VARCHAR(200),
  "建物名等"               VARCHAR(200),
  "緯度"                  FLOAT,
  "経度"                  FLOAT,
  "種別"                  VARCHAR(200),  -- 施設のカテゴリ
  "電話番号"               VARCHAR(50),
  "内線番号"               VARCHAR(50),
  "メールアドレス"          VARCHAR(200),
  "連絡先FormURL"         VARCHAR(500),
  "連絡先備考"             VARCHAR(500),
  "郵便番号"               VARCHAR(10),
  "利用可能曜日"            VARCHAR(100),
  "開始時間"               VARCHAR(10),
  "終了時間"               VARCHAR(10),
  "利用可能日時特記"        VARCHAR(500),
  "URL"                   VARCHAR(500),
  "画像"                  VARCHAR(500),
  "備考"                  VARCHAR(1000),
  "_LOADED_AT"            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = '公共施設一覧（熊本市） - くまもとデータ連携基盤より取得';

-- =============================================================================
-- テーブル 3: 公衆無線LANアクセスポイント一覧
--   出典CSV: 15_lan_431001_public_wireless_lan.csv（28列）
--   内容: 熊本市内の公衆Wi-Fi（くまもとフリーWi-Fi）設置場所
--   行数目安: 約 54 件
--   注意: 一部施設（市電・エリア設置）は緯度経度が NULL
-- =============================================================================
CREATE OR REPLACE TABLE WIFI_ACCESS_POINTS (
  "自治体コード"           VARCHAR(10),
  "法人番号"               VARCHAR(20),
  "ID"                    VARCHAR(50),
  "地方公共団体名"          VARCHAR(100),
  "名称"                  VARCHAR(200),
  "名称_カナ"              VARCHAR(200),
  "名称_英語"              VARCHAR(200),
  "所在地_自治体コード"     VARCHAR(10),
  "町字ID"                VARCHAR(20),
  "所在地_連結標記"         VARCHAR(500),
  "所在地_都道府県"         VARCHAR(50),
  "所在地_市区町村"         VARCHAR(100),
  "所在地_町字"             VARCHAR(200),
  "所在地_番地以下"         VARCHAR(200),
  "建物名等"               VARCHAR(200),
  "緯度"                  FLOAT,    -- 面エリア設置の場合は NULL
  "経度"                  FLOAT,    -- 面エリア設置の場合は NULL
  "設置者"                VARCHAR(200),
  "電話番号"               VARCHAR(50),
  "内線番号"               VARCHAR(50),
  "メールアドレス"          VARCHAR(200),
  "連絡先FormURL"         VARCHAR(500),
  "連絡先備考"             VARCHAR(500),
  "郵便番号"               VARCHAR(10),
  "SSID"                  VARCHAR(200),
  "提供エリア"             VARCHAR(500),
  "URL"                   VARCHAR(500),
  "備考"                  VARCHAR(1000),  -- 例: くまもとフリーWi-Fi
  "_LOADED_AT"            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = '公衆無線LANアクセスポイント一覧（熊本市） - くまもとデータ連携基盤より取得';

-- =============================================================================
-- テーブル 4: 子育て施設一覧
--   出典CSV: 21__431001_preschool.csv（53列）
--   内容: 保育所・児童館・子育て支援センター等
--   行数目安: 約 39 件（熊本市分のみ）
-- =============================================================================
CREATE OR REPLACE TABLE CHILDCARE_FACILITIES (
  "自治体コード"           VARCHAR(10),
  "ID"                    VARCHAR(50),
  "地方公共団体名"          VARCHAR(100),
  "名称"                  VARCHAR(200),
  "名称_カナ"              VARCHAR(200),
  "名称_英字"              VARCHAR(200),
  "種別"                  VARCHAR(200),  -- 保育所・児童館・地域子育て支援拠点 等
  "所在地_自治体コード"     VARCHAR(10),
  "町字ID"                VARCHAR(20),
  "所在地_連結標記"         VARCHAR(500),
  "所在地_都道府県"         VARCHAR(50),
  "所在地_市区町村"         VARCHAR(100),
  "所在地_町字"             VARCHAR(200),
  "所在地_番地以下"         VARCHAR(200),
  "建物名等"               VARCHAR(200),
  "緯度"                  FLOAT,
  "経度"                  FLOAT,
  "高度の種別"             VARCHAR(50),
  "高度の値"               FLOAT,
  "アクセス方法"            VARCHAR(500),
  "駐車場情報"             VARCHAR(200),
  "電話番号"               VARCHAR(50),
  "内線番号"               VARCHAR(50),
  "FAX番号"               VARCHAR(50),
  "メールアドレス"          VARCHAR(200),
  "連絡先FormURL"         VARCHAR(500),
  "連絡先備考"             VARCHAR(500),
  "郵便番号"               VARCHAR(10),
  "法人番号"               VARCHAR(20),
  "団体名"                VARCHAR(200),
  "許可等年月日"            VARCHAR(50),
  "収容定員"               VARCHAR(50),   -- 文字列（数値・記述混在）
  "受入年齢"               VARCHAR(200),
  "利用可能曜日"            VARCHAR(100),
  "開始時間"               VARCHAR(10),
  "終了時間"               VARCHAR(10),
  "利用可能日時特記"        VARCHAR(500),
  "一時預かりの有無"        VARCHAR(10),  -- '有' / '無'
  "子供預かり料金種別"      VARCHAR(100),
  "子供預かり料金"          VARCHAR(100),
  "子供預かり料金備考"      VARCHAR(200),
  "子供預かり開所時間"      VARCHAR(10),
  "子供預かり閉所時間"      VARCHAR(10),
  "病児保育の有無"          VARCHAR(10),  -- '有' / '無'
  "授乳室"                VARCHAR(10),
  "おむつ替えコーナー"      VARCHAR(10),
  "飲食可否"               VARCHAR(50),
  "ベビーカー貸出"          VARCHAR(10),
  "ベビーカー利用"          VARCHAR(10),
  "URL"                   VARCHAR(500),
  "画像"                  VARCHAR(500),
  "画像ライセンス"          VARCHAR(100),
  "備考"                  VARCHAR(1000),
  "_LOADED_AT"            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = '子育て施設一覧（熊本市） - くまもとデータ連携基盤より取得';

-- =============================================================================
-- テーブル 5: 地域・年齢別人口一覧
--   出典CSV: 19_r6.1.1_431001_population_202411-cleaned.csv（47列）
--   内容: 令和6年1月1日時点の校区別・年齢（5歳刻み17区分）・性別人口
--   行数目安: 約 92 件（校区単位）
--   注意: 世帯数にカンマ区切り文字列が混在 → VARCHAR で保持
-- =============================================================================
CREATE OR REPLACE TABLE DEMOGRAPHICS (
  -- 地域情報
  "自治体コード"           VARCHAR(10),
  "地域コード"             VARCHAR(20),
  "地方公共団体名"          VARCHAR(100),
  "調査年月日"             DATE,          -- 2024-01-01
  "地域名"                VARCHAR(200),  -- 校区名（例: 中央区城東校区）

  -- 総人口・性別合計
  "総人口"                INTEGER,
  "男性"                  INTEGER,
  "女性"                  INTEGER,

  -- 年齢別人口（5歳刻み） - 男性
  "_0_4歳男性"            INTEGER,
  "_5_9歳男性"            INTEGER,
  "_10_14歳男性"          INTEGER,
  "_15_19歳男性"          INTEGER,
  "_20_24歳男性"          INTEGER,
  "_25_29歳男性"          INTEGER,
  "_30_34歳男性"          INTEGER,
  "_35_39歳男性"          INTEGER,
  "_40_44歳男性"          INTEGER,
  "_45_49歳男性"          INTEGER,
  "_50_54歳男性"          INTEGER,
  "_55_59歳男性"          INTEGER,
  "_60_64歳男性"          INTEGER,
  "_65_69歳男性"          INTEGER,
  "_70_74歳男性"          INTEGER,
  "_75_79歳男性"          INTEGER,
  "_80_84歳男性"          INTEGER,
  "_85歳以上男性"          INTEGER,

  -- 年齢別人口（5歳刻み） - 女性
  "_0_4歳女性"            INTEGER,
  "_5_9歳女性"            INTEGER,
  "_10_14歳女性"          INTEGER,
  "_15_19歳女性"          INTEGER,
  "_20_24歳女性"          INTEGER,
  "_25_29歳女性"          INTEGER,
  "_30_34歳女性"          INTEGER,
  "_35_39歳女性"          INTEGER,
  "_40_44歳女性"          INTEGER,
  "_45_49歳女性"          INTEGER,
  "_50_54歳女性"          INTEGER,
  "_55_59歳女性"          INTEGER,
  "_60_64歳女性"          INTEGER,
  "_65_69歳女性"          INTEGER,
  "_70_74歳女性"          INTEGER,
  "_75_79歳女性"          INTEGER,
  "_80_84歳女性"          INTEGER,
  "_85歳以上女性"          INTEGER,

  -- 世帯数（"4,315 " のようにカンマ・スペース混在 → VARCHAR で保持）
  "世帯数"                VARCHAR(20),
  "備考"                  VARCHAR(1000),

  "_LOADED_AT"            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = '地域・年齢別人口一覧（熊本市 R6.1.1時点） - くまもとデータ連携基盤より取得';

-- =============================================================================
-- テーブル 6: 駐輪場一覧
--   出典CSV: 16__431001_bicycleparkingarea.csv（27列）
--   内容: 熊本市内の駐輪場（自転車・原付・二輪の駐輪台数、有料無料区分）
--   行数目安: 約 46 件
--   注意:
--     - 12列目のヘッダーが空 → "予備列" として保持
--     - 駐輪台数（原付）に数値と '可' が混在 → VARCHAR で保持
-- =============================================================================
CREATE OR REPLACE TABLE BICYCLE_PARKING (
  "自治体コード"           VARCHAR(10),
  "ID"                    VARCHAR(50),
  "施設名称"               VARCHAR(200),
  "施設名称_カナ"           VARCHAR(200),
  "所在地_自治体コード"     VARCHAR(10),
  "町字ID"                VARCHAR(20),
  "所在地_連結標記"         VARCHAR(500),
  "所在地_都道府県"         VARCHAR(50),
  "所在地_市区町村"         VARCHAR(100),
  "所在地_町字"             VARCHAR(200),
  "所在地_番地以下"         VARCHAR(200),
  "予備列"                VARCHAR(200),  -- 12列目（ヘッダーが空）
  "緯度"                  FLOAT,
  "経度"                  FLOAT,
  "管理者名"               VARCHAR(200),
  "電話番号"               VARCHAR(50),
  "メールアドレス"          VARCHAR(200),
  "連絡先FormURL"         VARCHAR(500),
  "連絡先備考"             VARCHAR(500),
  "駐輪台数_自転車"         VARCHAR(20),  -- 数値
  "駐輪台数_原付"           VARCHAR(20),  -- 数値 または '可' が混在
  "駐輪台数_二輪"           VARCHAR(20),  -- 数値
  "屋根の有無"             VARCHAR(20),  -- '有' / '無' / '一部有'
  "供用時間"               VARCHAR(50),  -- 例: '00:00/24:00'
  "有料無料区分"            VARCHAR(20),  -- '有料' / '無料'
  "二時間無料の有無"        VARCHAR(10),
  "備考"                  VARCHAR(1000),
  "_LOADED_AT"            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = '駐輪場一覧（熊本市） - くまもとデータ連携基盤より取得';

-- =============================================================================
-- テーブル 7: 道路照明灯一覧
--   出典CSV: 18__431001_roadwaylightning.csv（55列）
--   内容: 熊本市内の街路灯・公園灯（管理情報・点検状態）
--   行数目安: 約 30,754 件（最大データセット）
-- =============================================================================
CREATE OR REPLACE TABLE ROAD_LIGHTS (
  "自治体コード"           VARCHAR(10),
  "ID"                    INTEGER,       -- 照明灯ID（管理番号）
  "街路灯区分"             VARCHAR(20),  -- '街路灯' / '公園灯'
  "管理番号1"              VARCHAR(50),  -- 例: '東-01613'
  "管理番号2"              VARCHAR(50),
  "管理番号3"              VARCHAR(50),
  "路線種別"               VARCHAR(50),
  "路線名"                VARCHAR(200),
  "所在地_自治体コード"     VARCHAR(10),
  "町字ID"                VARCHAR(20),
  "所在地_連結標記"         VARCHAR(500),
  "所在地_都道府県"         VARCHAR(50),
  "所在地_市区町村"         VARCHAR(100),
  "所在地_町字"             VARCHAR(200),
  "所在地_番地以下"         VARCHAR(200),
  "照明種別"               VARCHAR(50),  -- '交差点' / '局所' / '連続' / '橋梁'
  "緯度"                  FLOAT,         -- 精度: 小数15桁
  "経度"                  FLOAT,
  "管理者"                VARCHAR(100),  -- 区名（東区・中央区等）
  "電話番号"               VARCHAR(50),
  "メールアドレス"          VARCHAR(200),
  "連絡先FormURL"         VARCHAR(500),
  "連絡先備考"             VARCHAR(500),
  "支柱形式"               VARCHAR(100),
  "電柱種類"               VARCHAR(50),
  "電柱番号"               VARCHAR(100),
  "NTT柱番号"             VARCHAR(100),
  "基礎形式"               VARCHAR(50),
  "灯柱高"                VARCHAR(50),
  "表面処理形式"            VARCHAR(100),
  "取付ポール径"            VARCHAR(50),
  "灯具外形色"             VARCHAR(50),
  "設置年月日"             DATE,
  "灯具亀裂"               VARCHAR(50),
  "灯具腐食"               VARCHAR(50),
  "灯具破断"               VARCHAR(50),
  "柱状態_結論"            VARCHAR(50),  -- '良' / '要検討'
  "電源方式"               VARCHAR(50),
  "電力会社及び営業所"      VARCHAR(200),
  "電力契約種別"            VARCHAR(100),
  "お客さま番号"            VARCHAR(50),
  "灯具形式"               VARCHAR(100),
  "光源"                  VARCHAR(50),   -- 'LED灯' / '水銀灯'
  "灯具型番"               VARCHAR(100),
  "灯具明るさ"             VARCHAR(50),
  "色温度"                VARCHAR(50),
  "安定器"                VARCHAR(100),
  "点滅器"                VARCHAR(50),
  "調光装置"               VARCHAR(50),
  "交換対象"               VARCHAR(50),
  "景観配慮地区名"          VARCHAR(200),
  "設置工事業者名"          VARCHAR(200),
  "分電盤"                VARCHAR(200),
  "備考"                  VARCHAR(1000),
  "更新年月日"             DATE,
  "_LOADED_AT"            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = '道路照明灯一覧（熊本市） - くまもとデータ連携基盤より取得（約30,754件）';

-- 作成確認
SHOW TABLES IN SCHEMA KUMAMOTO_OPENDATA_DB.RAW_DATA;
