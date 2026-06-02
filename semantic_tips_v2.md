# Cortex Analyst向け Semantic View 設計ガイドライン

## 前提メッセージ
- Cortex Analyst の精度は、プロンプトよりもまず Semantic View の品質に大きく依存します。特に、自然言語の質問を正しい business meaning を持つ SQL に落とせるかどうかが重要です。
- Cortex Analyst はまず Semantic SQL を試し、Semantic View で表現しきれない場合に standard / logical / physical SQL 側へフォールバックします。したがって、Semantic SQL に乗せたい質問を意識して Semantic View を設計することが重要です。

## 基本方針
- まず考えるべきことは、「SQL を出すこと」ではなく、「ユーザーの自然言語質問を、正しい業務意味を持つ SQL に変換できる Semantic View を作ること」です。
- Semantic View は、データベース構造そのものではなく、エンドユーザーの見たい世界に合わせて設計します。物理スキーマ起点ではなく、業務用語起点で考えるのが基本です。
- まずは狭いユースケースから始め、必要に応じて段階的に広げます。大きすぎるモデルは精度・保守性の両面で不利です。

## 推奨するデータモデルの考え方
- 基本は、複数テーブルを無理に 1 本の横長テーブルにせず、素直な star schema に近い形で logical table と relationship を明示するのが第一選択です。
- fact と dimension が素直な many-to-one でつながるなら、Semantic View 内で relationship を定義する設計が適しています。
- 一方で、1つの業務概念を表現するのに複数テーブルの条件合成が必要な場合は、前段のデータマートや中間 view で business logic を整理してから Semantic View に載せる方が安定します。

## Dimension / Metric / Filter の設計
- Dimension は分析の軸です。主に「何で切るか」を表すもので、通常の SQL でいう SELECT / GROUP BY 側の切り口に相当します。
- Filter は絞り込み条件です。ユーザーが頻繁に使う業務条件を名前付きで再利用できるように定義します。
- Dimension は基本的に 1 つの logical table に属する前提で考えます。複数テーブルをまたぐ 1 つの dimension を直接定義する発想は避けた方がよいです。
- 複数テーブルをまたぐ集計ロジックは、必要に応じて derived metric や前段のマートで吸収します。

## Semantic SQL に乗せやすくする設計ポイント
- ユーザーが実際に聞く質問を先に洗い出し、その質問を Semantic SQL で自然に表現できるように dimension / metric / relationship を定義します。
- Semantic SQL では JOIN を直接書きません。必要な join は Semantic View の relationship から推論されます。つまり、join が必要な問いでも relationship が適切なら Semantic SQL に乗ります。
- Semantic View で表現できない複雑な business logic が残っていると、Logical SQL / Physical SQL へのフォールバックが増えやすくなります。

## Description / Synonym / 業務用語の整備
- テーブル・カラムには、技術名ではなく業務で使われる意味が伝わる description を付与します。description は精度改善に効く重要要素です。
- raw table comment に頼るのではなく、最終的に Semantic View に反映された description を整えることが重要です。
- synonym は便利ですが、同じ synonym を複数の列や dimension に重複して付けると競合の原因になります。業務用語はできるだけ一意に保ちます。

## モデルのサイズとスコープ
- 1 つの Semantic View に何でも詰め込まず、ユースケース単位・ドメイン単位で分けます。
- dimension は増やしすぎない方がよく、実務上は 1 モデルあたり 50–100 程度が目安です。不要な列や曖昧な軸は削る方が精度向上につながります。

## 前段でデータ整形を検討すべきケース
- 1 つの業務軸を作るために複数テーブルの CASE / JOIN / 条件合成が必要な場合。
- many-to-many や time-aware join / SCD2 など、Semantic View だけで自然に表現しにくい関係がある場合。
- モデルが広がりすぎ、同じ名前や ID 系の列が複数テーブルに散らばって競合しやすい場合。

## Verified Queries と評価
- POC レベルで終わらせず、本番品質にするには Verified Queries が重要です。特定の質問で確実に正しい SQL を返したい場合に有効です。
- よくある質問、重要 KPI の質問、誤答しやすい質問を優先して Verified Queries を整備します。
- 評価は継続的に実施し、どの質問が Semantic SQL に乗るか、どこで fallback するかを見ながら反復改善します。

## 同名の ID / Name / Status などが複数テーブルにある場合の設計指針
- 同じ business concept を表す ID / name は、複数テーブルでそのまま公開せず、**1つの canonical な Dimension に寄せる**のが基本です。たとえば `orders.customer_id` と `customers.customer_id` が同じ意味なら、公開するのは `customers.customer_id` 側だけにし、`orders.customer_id` は relationship 用の join key として使います。
- 逆に、物理名は同じでも意味が違う場合は、semantic 名を明確に分けます。たとえば `id` をそのまま複数公開せず、`customer_id`、`order_id`、`store_id` のように business meaning が分かる名前にします。
- 複数テーブルにまたがる同一カラムが Dimension 上に存在するとコンフリクトの可能性があります。内部メモでも、こうした場合は **fact テーブル側だけを残し、他のテーブル側の同種 dimension は削除する**、または **custom instructions で使い分けを指定する**のが対策として挙げられています。
- query 結果では unqualified name が使われるため、同名 Dimension / Metric を複数出すと衝突しやすくなります。必要なら qualified name や alias で明示しますが、そもそも Semantic View 側で曖昧さを減らす方が重要です。
- synonym も同様で、同じ synonym を異なるカラム / dimension に設定するとコンフリクトの可能性があります。synonym は一意性を担保し、広すぎる汎用語をむやみに重複付与しないようにします。
- 複数 fact テーブルで共通の business 軸を使いたい場合は、重複定義するのではなく、共通の dimension table に寄せる設計が安定します。

## お客様への推奨メッセージ
- まずは、対象業務を 1 つに絞り、必要な fact / dimension を整理した小さな Semantic View から始めることを推奨します。
- 次に、業務用語、description、relationship、主要 metrics を定義し、代表質問で動作確認します。
- 複雑な business logic は無理に Semantic View へ押し込まず、必要に応じて前段のデータマートで整理します。
- 同じ ID / name / status を複数テーブルでそのまま公開せず、canonical source を決めて business meaning が一意になるよう整理します。
- 最後に Verified Queries で重要質問を固定化し、評価を回しながら精度を上げていく進め方が現実的です。

## 一言でまとめると
- Semantic View 設計の基本は、「物理テーブルをそのまま見せる」のではなく、「ユーザーの質問を、正しい業務意味を持つ Semantic SQL に落とせる形にする」ことです。
- 原則は relationship を活用し、例外的に複雑な business logic だけを前段で整理する、という考え方が最もバランスの良い進め方です。
- 特に同名カラムの扱いでは、**重複列を全部見せない**ことが重要です。semantic view は物理列の写経ではなく、business concept の整理レイヤーとして設計するのが基本です。


---

## Sources

- [Snowflake Cortex Features: Best Practices Guide](https://snowflakecomputing.atlassian.net/wiki/spaces/SKE/pages/4711481919)
- [Cortex Analyst best practices guide](https://docs.google.com/document/d/1sO_0SsVoq1LUdKtZXDxYkx283XyMP_jr-hQQB_nnqcc)
- [Routing Mode for Cortex Analyst | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst/cortex-analyst-routing-mode)
- [Routing Mode for Cortex Analyst | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst/cortex-analyst-routing-mode)
- [Cortex Analyst best practices guide](https://docs.google.com/document/d/1sO_0SsVoq1LUdKtZXDxYkx283XyMP_jr-hQQB_nnqcc)
- [Best practices for semantic views | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/views-semantic/best-practices-dev)
- [FAQ for Semantic Views as Native Schema Objects](https://docs.google.com/document/d/1QRaTIPsDtlyP-RKMbKFxFE8C9EEgbaYxHHKe-hzLvZw)
- [Cortex Analyst best practices guide](https://docs.google.com/document/d/1sO_0SsVoq1LUdKtZXDxYkx283XyMP_jr-hQQB_nnqcc)
- [YAML specification for semantic views | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/views-semantic/semantic-view-yaml-spec)
- [image.png](https://snowflake-be.glean.com/api/v1/downloadchatfile/34899174e06345a584cce9ec2ad4e158)
- [熊本市様_Snowflake Intelligence Overview](https://docs.google.com/presentation/d/1CaxgXXnE3o5UQ5CPFbw2__2gGY_XFUUGhPOesAplqcA)
- [Overview of semantic views | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [YAML specification for semantic views | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/views-semantic/semantic-view-yaml-spec)
- [May 05, 2026: Support for entity-level filters in semantic views (*General availability*) | Snowflake Documentation](https://docs.snowflake.com/en/release-notes/2026/other/2026-05-05-semantic-views-entity-filters)
- [Using SQL commands to create and manage semantic views | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/views-semantic/sql)
- [Querying semantic views | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/views-semantic/querying)
- [Cortex Analyst - GA Customer Facing Deck](https://docs.google.com/presentation/d/1-hgwTcJUPAJZLBbmG6Th_3cLAdx_Dp9vzRAQcpjH1Zk)
- [YAML specification for semantic views | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/views-semantic/semantic-view-yaml-spec)
- [Cortex Analyst best practices guide](https://docs.google.com/document/d/1sO_0SsVoq1LUdKtZXDxYkx283XyMP_jr-hQQB_nnqcc)
- [Overview of semantic views | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [Using Snowsight to create and manage semantic views | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/views-semantic/ui)
- [SEMANTIC_VIEW | Snowflake Documentation](https://docs.snowflake.com/en/sql-reference/constructs/semantic_view)
- [Workshop 2: Refinement and Best Practices](https://docs.google.com/presentation/d/1dM28BBeJei3AG7uKHrhhPkJqcZXtHpSCPGaMioLrIW4)
- [Querying semantic views | Snowflake Documentation](https://docs.snowflake.com/en/user-guide/views-semantic/querying)
- [Cortex Analyst best practices guide](https://docs.google.com/document/d/1sO_0SsVoq1LUdKtZXDxYkx283XyMP_jr-hQQB_nnqcc)
