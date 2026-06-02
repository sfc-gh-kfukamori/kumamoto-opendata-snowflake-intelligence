# 熊本市オープンデータ × Snowflake Intelligence デモ

熊本県オープンデータカタログ（くまもとデータ連携基盤）から熊本市のオープンデータを
Snowflake に取り込み、**Cortex Analyst + Snowflake Intelligence** で
自然言語による AI データ問い合わせを実現するデモ環境の構築手順とコードです。

---

## デモ概要

熊本市職員の方々が「指定緊急避難場所は何か所？」「高齢化率が最も高い校区は？」
といった日本語の質問を入力するだけで、データベースを直接クエリせずに回答を得られます。

**デモの流れ:**

```
くまもとデータ連携基盤 (CKAN API)
        ↓ HTTPS (External Network Access)
 Snowflake RAW_DATA スキーマ（7テーブル）
        ↓ SQL ビュー変換 + ASCII 列名正規化
 ANALYTICS スキーマ（4分析ビュー）
        ↓ Semantic View (Cortex Analyst)
 Snowflake Intelligence（自然言語 → SQL → 回答）
```

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│  くまもとデータ連携基盤                                        │
│  https://datacatalogportal.dlp-kumamoto.jp/                 │
│  ・7件の CSV ファイル（CC BY ライセンス）                      │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTPS (External Network Access)
                       │ CKAN API → CSV ダウンロード
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  KUMAMOTO_OPENDATA_DB / RAW_DATA スキーマ                     │
│                                                             │
│  EVACUATION_PLACES   指定緊急避難場所 (605件)                │
│  PUBLIC_FACILITIES   公共施設 (933件)                        │
│  WIFI_ACCESS_POINTS  公衆Wi-Fi (54件)                        │
│  CHILDCARE_FACILITIES 子育て施設 (39件)                      │
│  DEMOGRAPHICS        地域・年齢別人口 (92校区)               │
│  BICYCLE_PARKING     駐輪場 (46件)                           │
│  ROAD_LIGHTS         道路照明灯 (30,754件)                   │
└──────────────────────┬──────────────────────────────────────┘
                       │ SQL VIEW (ASCII 列名に正規化)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  KUMAMOTO_OPENDATA_DB / ANALYTICS スキーマ                   │
│                                                             │
│  FACILITIES_COMBINED_V     避難場所+公共施設+子育て統合       │
│  DEMOGRAPHICS_SUMMARY_V    人口・高齢化率サマリー             │
│  ROAD_LIGHTS_STATUS_V      照明灯 LED化状態付き              │
│  BICYCLE_PARKING_SUMMARY_V 駐輪場 台数整形済み               │
└──────────────────────┬──────────────────────────────────────┘
                       │ CREATE SEMANTIC VIEW
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Semantic View (Cortex Analyst)                             │
│                                                             │
│  KUMAMOTO_FACILITIES_SV     施設系 (VQR 5本)                │
│  KUMAMOTO_DEMOGRAPHICS_SV   人口・インフラ系 (VQR 7本)       │
└──────────────────────┬──────────────────────────────────────┘
                       │ CREATE AGENT / tool_resources
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Cortex Agent: KUMAMOTO_CITY_AGENT                          │
│  表示名: くまもとデータアシスタント                            │
│  ツール: facility_search / population_and_infra             │
└──────────────────────┬──────────────────────────────────────┘
                       │ Snowflake Intelligence UI
                       ▼
             熊本市職員が自然言語で問い合わせ
```

---

## データセット

| # | データセット名 | テーブル名 | 件数 | ライセンス |
|---|---|---|---|---|
| 1 | 指定緊急避難場所一覧 | `EVACUATION_PLACES` | 605件 | CC BY |
| 2 | 公共施設一覧 | `PUBLIC_FACILITIES` | 933件 | CC BY |
| 3 | 公衆無線LANアクセスポイント | `WIFI_ACCESS_POINTS` | 54件 | CC BY |
| 4 | 子育て施設一覧 | `CHILDCARE_FACILITIES` | 39件 | CC BY |
| 5 | 地域・年齢別人口一覧 | `DEMOGRAPHICS` | 92件 | CC BY |
| 6 | 駐輪場一覧 | `BICYCLE_PARKING` | 46件 | CC BY |
| 7 | 道路照明灯一覧 | `ROAD_LIGHTS` | 30,754件 | CC BY |

**出典:** くまもとデータ連携基盤（熊本市）
**URL:** https://datacatalogportal.dlp-kumamoto.jp/ckan/dataset

---

## ファイル構成

```
kumamoto_demo/
├── README.md                           # このファイル
├── 01_setup/
│   ├── 01_database_setup.sql           # DB・スキーマ・ウェアハウス作成
│   ├── 02_external_network_access.sql  # External Network Access 設定（ACCOUNTADMIN）
│   └── 03_raw_tables_ddl.sql           # RAWテーブル 7本 DDL
├── 02_data_loading/
│   ├── 04_load_all_csv.py              # ローカルPython: CSV取得→Snowflakeロード
│   └── 05_load_procedure.sql           # ENA利用の Snowflake 内 Python SP版
├── 03_modeling/
│   └── 06_analytics_views.sql          # 分析用ビュー（ASCII列名に正規化）
├── 04_semantic_view/
│   └── 07_create_semantic_views.sql    # セマンティックビュー DDL（VQR含む）
└── 05_agent/
    └── 08_create_agent.sql             # Cortex Agent 作成
```

---

## セットアップ手順

### 前提条件

- Snowflake アカウント（ACCOUNTADMIN または同等の権限）
- Python 3.9+（ローカルからデータロードする場合）
- 必要な Python パッケージ:
  ```bash
  pip install snowflake-connector-python requests chardet
  ```
- `~/.snowflake/connections.toml` に接続設定が済んでいること

### Step 1: DB・スキーマ・ウェアハウス作成

Snowsight のワークシートで実行:

```sql
-- SYSADMIN ロールで実行
source: 01_setup/01_database_setup.sql
```

作成されるオブジェクト:
- データベース: `KUMAMOTO_OPENDATA_DB`
- スキーマ: `RAW_DATA`（生データ）、`ANALYTICS`（分析用）
- ウェアハウス: `COMPUTE_WH`（既存の場合はスキップ）

### Step 2: External Network Access 設定

Snowsight で **ACCOUNTADMIN** ロールに切り替えて実行:

```sql
source: 01_setup/02_external_network_access.sql
```

作成されるオブジェクト:
- ネットワークルール: `KUMAMOTO_OPENDATA_NR`（`datacatalogportal.dlp-kumamoto.jp:443` へのEGRESS）
- EAI: `KUMAMOTO_EAI`

### Step 3: RAW テーブル作成

```sql
-- SYSADMIN ロールで実行
source: 01_setup/03_raw_tables_ddl.sql
```

### Step 4: データロード

**方法 A: ローカル Python スクリプト（推奨）**

```bash
cd ~/kumamoto_demo
python 02_data_loading/04_load_all_csv.py
```

**方法 B: Snowflake 内 Python SP（ENA 利用）**

```sql
-- Snowsight で実行（KUMAMOTO_EAI が有効であること）
source: 02_data_loading/05_load_procedure.sql

-- 全テーブルを一括ロード
CALL KUMAMOTO_OPENDATA_DB.RAW_DATA.LOAD_ALL_KUMAMOTO_CSV();
```

### Step 5: 分析ビュー作成

```sql
source: 03_modeling/06_analytics_views.sql
```

### Step 6: セマンティックビュー作成

```sql
source: 04_semantic_view/07_create_semantic_views.sql
```

### Step 7: Cortex Agent 作成

```sql
source: 05_agent/08_create_agent.sql
```

---

## 技術的ポイント

### 1. External Network Access（ENA）でのCSVロード

Snowflake のストアドプロシージャ内から外部 HTTPS エンドポイントにアクセスするには、
`EXTERNAL ACCESS INTEGRATION` が必要です。

```sql
-- Network Rule: 接続先ホストを明示的に許可
CREATE NETWORK RULE KUMAMOTO_OPENDATA_NR
  TYPE      = HOST_PORT
  MODE      = EGRESS
  VALUE_LIST = ('datacatalogportal.dlp-kumamoto.jp:443');

-- External Access Integration: Network Rule を有効化
CREATE EXTERNAL ACCESS INTEGRATION KUMAMOTO_EAI
  ALLOWED_NETWORK_RULES = (KUMAMOTO_OPENDATA_NR)
  ENABLED = TRUE;
```

Python SP での利用:
```python
-- SP の EXTERNAL_ACCESS_INTEGRATIONS 句に指定
CREATE OR REPLACE PROCEDURE LOAD_CSV_FROM_URL(P_URL STRING, P_TABLE STRING)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
EXTERNAL_ACCESS_INTEGRATIONS = (KUMAMOTO_EAI)  -- ← ここで EAI を指定
PACKAGES = ('requests', 'snowflake-snowpark-python')
HANDLER = 'main'
...
```

### 2. Cortex Analyst の列名制約と ASCII 正規化

**Cortex Analyst がセマンティックビューを読み込む際、列名（ディメンション・メトリック名）は
ASCII 文字のみ使用可能です。** 日本語の列名があると以下のエラーが発生します:

```
invalid column name "施設名称": name must start with an underscore or a letter,
and only contain letters, underscores, decimal digits (0-9), and dollar signs ($).
```

このため、ANALYTICS スキーマのビューでは全ての列名を英字スネークケースに変換しています:

| 元の日本語列名（RAW_DATA） | 変換後の ASCII 列名（ANALYTICS） |
|---|---|
| `"施設名称"` | `shisetsu_name` |
| `"区名"` | `ward_name` |
| `"緯度"` | `latitude` |
| `"地震対応"` | `jishin_flag` |
| `"高齢化率"` | `aging_rate` |

セマンティックビューでは SYNONYMS に日本語を登録することで、
日本語での自然言語クエリに対応します:

```sql
facilities.shisetsu_name AS shisetsu_name  -- ASCII 名（Cortex Analyst が使用）
  WITH SYNONYMS = ('施設名称', '施設名', '名称', 'facility name')  -- 日本語対応
  COMMENT = '施設の正式名称'
```

### 3. Cortex Agent の `execution_environment` 指定

Cortex Agent から Cortex Analyst ツールを呼び出す際、
**ウェアハウスの指定は `execution_environment` オブジェクトで行う必要があります。**

```yaml
# ❌ 動作しない（無視される）
tool_resources:
  facility_search:
    semantic_view: "DB.SCHEMA.VIEW"
    warehouse: "COMPUTE_WH"

# ✅ 正しい形式
tool_resources:
  facility_search:
    semantic_view: "DB.SCHEMA.VIEW"
    execution_environment:
      type: warehouse
      warehouse: COMPUTE_WH
```

`execution_environment` がないと `missing an execution environment` エラーになります。

### 4. Verified Query Recommendations（VQR）

セマンティックビューの `AI_VERIFIED_QUERIES` に頻出質問の正解 SQL を登録することで:

- **精度向上**: VQR にマッチした質問は事前検証済み SQL をそのまま実行
- **速度向上**: LLM による SQL 生成をスキップするため応答が速い
- **デモの安定性**: デモで使う質問を VQR に登録しておくと確実に動作

```sql
AI_VERIFIED_QUERIES (
  vqr1 AS (
    QUESTION '地震に対応している避難場所は何か所ありますか？'
    SQL 'SELECT COUNT(*) AS cnt FROM ... WHERE jishin_flag = TRUE'
  ),
  ...
)
```

### 5. データ品質の対応

CSVデータには以下の品質上の問題があり、ロード・変換時に対処しています:

| 問題 | データセット | 対処方法 |
|---|---|---|
| 世帯数に `"4,315 "` のようなカンマ・スペース混在 | 人口 | `REPLACE` でカンマ除去後 `TRY_CAST` |
| 駐輪台数（原付）に数値と `'可'` が混在 | 駐輪場 | `CASE WHEN '可' THEN NULL` |
| 12列目のヘッダーが空 | 駐輪場 | `"予備列"` として保持 |
| 収容人数が記述的な文字列の場合あり | 避難場所 | `TRY_CAST` でNULL変換 |
| 公共施設 CSV がエンコーディング問題 | 公共施設 | `chardet` で自動検出 + cp932フォールバック |

---

## テーブルデータモデル

### RAW_DATA スキーマ（生データ）

```
EVACUATION_PLACES（指定緊急避難場所）
├── "自治体コード"  VARCHAR -- 431001（熊本市）
├── "名称"         VARCHAR -- 施設名
├── "緯度"         FLOAT   -- WGS84
├── "経度"         FLOAT   -- WGS84
├── "地震対応"     VARCHAR -- '1'=対応, ''=非対応
├── "洪水対応"     VARCHAR -- 同上
├── "津波対応"     VARCHAR -- 同上
├── "想定収容人数" VARCHAR -- 数値（文字列で保持）
└── ...（全39列）

DEMOGRAPHICS（地域・年齢別人口）
├── "調査年月日"   DATE    -- 2024-01-01
├── "地域名"       VARCHAR -- 校区名
├── "総人口"       INTEGER
├── "_0_4歳男性"   INTEGER -- 年齢5歳刻み17区分×男女＝34列
├── ...（5歳刻みの年齢別×男女）
└── "世帯数"       VARCHAR -- カンマ入り文字列の場合あり

ROAD_LIGHTS（道路照明灯）※最大テーブル（30,754件）
├── "ID"           INTEGER -- 管理番号
├── "管理者"       VARCHAR -- 区名
├── "光源"         VARCHAR -- 'LED灯' / '水銀灯'
├── "柱状態_結論"  VARCHAR -- '良' / '要検討'
└── ...（全55列）
```

### ANALYTICS スキーマ（分析用ビュー）

```
FACILITIES_COMBINED_V（3テーブルのUNION ALL + ASCII列名変換）
├── shisetsu_type        VARCHAR -- '指定緊急避難場所'/'公共施設'/'子育て施設'
├── shisetsu_name        VARCHAR -- 施設名
├── ward_name            VARCHAR -- 区名（所在地から抽出）
├── latitude / longitude FLOAT   -- 位置情報
├── capacity             INTEGER -- 収容定員（避難場所のみ）
├── jishin_flag          BOOLEAN -- 地震対応 (避難場所のみ)
├── kozui_flag           BOOLEAN -- 洪水対応
├── tsunami_flag         BOOLEAN -- 津波対応
├── ichiji_azukari_flag  BOOLEAN -- 一時預かり (子育て施設のみ)
└── byoji_hoiku_flag     BOOLEAN -- 病児保育 (子育て施設のみ)

DEMOGRAPHICS_SUMMARY_V（人口3区分 + 高齢化率を事前計算）
├── area_name              VARCHAR -- 校区名
├── ward_name              VARCHAR -- 区名
├── total_population       INTEGER -- 総人口
├── elderly_population     INTEGER -- 65歳以上人口
├── young_population       INTEGER -- 0〜14歳人口
├── working_age_population INTEGER -- 15〜64歳人口
├── aging_rate             FLOAT   -- 高齢化率 (%)
└── youth_rate             FLOAT   -- 年少化率 (%)

ROAD_LIGHTS_STATUS_V（LED化判定・要対応フラグ付き）
├── light_id        INTEGER -- ID
├── manager         VARCHAR -- 管理者（区名）
├── led_status      VARCHAR -- 'LED化済み'/'水銀灯（LED未換）'/'その他'
└── needs_repair    BOOLEAN -- 要対応フラグ

BICYCLE_PARKING_SUMMARY_V（駐輪台数を数値化・合計計算済み）
├── parking_name   VARCHAR -- 駐輪場名
├── total_parking  INTEGER -- 合計駐輪台数
├── fee_type       VARCHAR -- '有料'/'無料'
└── has_roof       VARCHAR -- '有'/'無'/'一部有'
```

---

## セマンティックビュー詳細説明

### 概要

セマンティックビュー（Semantic View）は、物理テーブル・ビューに対して
「ビジネスの意味・文脈」を付加する Snowflake の機能です。
Cortex Analyst はこのセマンティックビューを参照して自然言語を SQL に変換します。

### KUMAMOTO_FACILITIES_SV の構造

```
セマンティックビュー: KUMAMOTO_FACILITIES_SV
│
├── TABLES
│   └── facilities = FACILITIES_COMBINED_V（施設統合ビュー）
│
├── DIMENSIONS（絞り込み・グループ化に使う列）
│   ├── shisetsu_type   「指定緊急避難場所/公共施設/子育て施設」
│   ├── ward_name       「区名」（中央区/東区/西区/南区/北区）
│   ├── jishin_flag     「地震対応フラグ」（BOOLEAN）
│   ├── kozui_flag      「洪水対応フラグ」（BOOLEAN）
│   ├── tsunami_flag    「津波対応フラグ」（BOOLEAN）
│   ├── ichiji_azukari_flag  「一時預かり可否」（BOOLEAN）
│   └── byoji_hoiku_flag     「病児保育あり」（BOOLEAN）
│
├── METRICS（集計に使う数値）
│   ├── shisetsu_count   COUNT(*)          「施設件数」
│   ├── total_capacity   SUM(capacity)     「合計収容人数」
│   ├── avg_capacity     AVG(capacity)     「平均収容人数」
│   └── max_capacity     MAX(capacity)     「最大収容人数」
│
├── AI_SQL_GENERATION（SQL生成ガイドライン）
│   └── 列の値域・NULLの扱い等をLLMに指示
│
└── AI_VERIFIED_QUERIES（VQR: 事前検証済み質問）
    ├── vqr1: 「地震に対応している避難場所は何か所？」→ COUNT WHERE jishin_flag=TRUE
    ├── vqr2: 「区ごとの避難場所数と収容人数」→ GROUP BY ward_name
    ├── vqr3: 「一時預かりができる子育て施設」→ WHERE ichiji_azukari_flag=TRUE
    ├── vqr4: 「収容人数トップ10」→ ORDER BY capacity DESC LIMIT 10
    └── vqr5: 「病児保育施設」→ WHERE byoji_hoiku_flag=TRUE
```

### KUMAMOTO_DEMOGRAPHICS_SV の構造

```
セマンティックビュー: KUMAMOTO_DEMOGRAPHICS_SV
│
├── TABLES（3テーブル）
│   ├── demo    = DEMOGRAPHICS_SUMMARY_V（人口サマリー）
│   ├── road    = ROAD_LIGHTS_STATUS_V（道路照明灯）
│   └── bicycle = BICYCLE_PARKING_SUMMARY_V（駐輪場）
│
├── DIMENSIONS
│   ├── demo: area_name, ward_name, survey_date
│   ├── road: manager, led_status, needs_repair, light_source
│   └── bicycle: parking_name, fee_type, has_roof
│
├── METRICS
│   ├── demo: total_population, elderly_population, young_population,
│   │        working_age_population, aging_rate, youth_rate, household_count
│   ├── road: light_count
│   └── bicycle: total_parking, parking_count
│
└── AI_VERIFIED_QUERIES（VQR 7本）
    ├── vqr1: 「高齢者人口が最多の校区」
    ├── vqr2: 「高齢化率ランキング」
    ├── vqr3: 「区ごとの人口・高齢化率」
    ├── vqr4: 「子ども人口が最多の校区」
    ├── vqr5: 「水銀灯残存本数（区別）」
    ├── vqr6: 「要対応照明灯数（区別）」
    └── vqr7: 「無料駐輪場の台数」
```

### セマンティックビューと Cortex Analyst の動作フロー

```
ユーザーの質問: 「地震に対応している避難場所は何か所？」
         ↓
  [1] VQR マッチングチェック
      → "vqr1" に完全一致 → 事前検証済み SQL を即時実行（高速・高精度）
         ↓
  [2] SQL 実行
      SELECT COUNT(*) AS cnt FROM FACILITIES_COMBINED_V
      WHERE shisetsu_type='指定緊急避難場所' AND jishin_flag=TRUE
         ↓
  [3] 結果: 593件
         ↓
  [4] LLM が日本語の回答文を生成
      「地震に対応している指定緊急避難場所は **593か所** あります。」
```

---

## デモ用サンプル質問

Snowflake Intelligence UI の「くまもとデータアシスタント」に入力できる質問例です。

### 防災・避難場所

```
地震に対応している避難場所は何か所ありますか？
洪水と津波の両方に対応している避難場所の一覧を教えてください
収容人数が最も多い避難場所はどこですか？
中央区の指定緊急避難場所を一覧してください
```

### 子育て・施設

```
一時預かりができる子育て施設を教えてください
病児保育のある施設は何か所ありますか？
保育施設の種別ごとの件数を教えてください
```

### 人口統計

```
65歳以上の高齢者が最も多い校区はどこですか？
高齢化率が最も高い校区のランキングを教えてください
熊本市の区ごとの総人口と高齢化率を教えてください
子ども（0〜14歳）の人口が最も多い地域はどこですか？
```

### インフラ

```
水銀灯（LED未換）の道路照明灯は区ごとに何本残っていますか？
要検討状態の照明灯が最も多い区はどこですか？
無料で使える駐輪場の合計台数を教えてください
```

---

## ライセンス

データソース（くまもとデータ連携基盤）:
**クリエイティブ・コモンズ 表示 (CC BY)** - 熊本市

コード: **MIT License**
