# Kanri System — Claude Code 引き継ぎドキュメント

> **新しいClaude Codeセッションへ**: このドキュメントを最初に読んでから作業してください。

---

## プロジェクト概要

**Kanri System** — 賃貸管理会社向けの業務管理SPA。
- 独立プロジェクト（他法人・他プロダクトには所属させない方針）
- 目標規模: 第1段階1万戸（中規模管理会社）、将来10万戸視野
- 現在: V3デザイン × V2.2ロジック + キャッシュフロー機能完了
- バックエンド: 現状 IndexedDB（ブラウザローカル）、将来 Supabase

## 現在のファイル構成

```
kanri-system/
├── index.html         ← V3デザインCSS（920行）
├── KanriApp.jsx       ← V2.2ロジック+CashflowPage+セキュリティ修正（3,205行）
└── kanri-standalone.html  ← 単一ファイル版（配布用、編集はしない）
```

## 起動方法（Windows / PowerShell）

```powershell
cd path\to\kanri-system
python -m http.server 8000
```

ブラウザで `http://localhost:8000` を開く。
同一Wi-Fi内のスマホからは `http://192.168.0.11:8000`。

---

## これまでの作業履歴（直近〜現在）

### Session 1〜13（V2.2 まで）
- V1〜V2.2 のフル機能実装
- 47単体テスト + 30攻撃テストで防御確認済
- セキュリティ修正サイクル3回（CSV injection, XSS, JSONインポート検証 等）

### V3 設計フェーズ
- **V3バックエンド設計完了** (`v3-backend/` 以下、別ディレクトリ): PostgreSQL/Supabaseスキーマ、RLSポリシー、ビジネスロジック関数。Fortune 500監査で12脆弱性発見、9件修正済み
- **V3デザイン確定**: クリアSaaS風（白背景＋ #2563EB 青＋ステータス色強め、Plus Jakarta Sans + Noto Sans JP）

### B群完了（直近）
- V2.2 KanriApp.jsx を **無修正に近い形** (9行のみ変更) でV3デザイン化
- 手法: index.html の CSS のみ全面書換、JSXは互換クラス名で温存
- 修正した9行: `_validateData()` の null フィルタ強化、`openPrintWindow()` の title エスケープ

### 直近の機能追加：キャッシュフロー + Claude AI 直結 + 学習機構
サイドバー「管理」→「キャッシュフロー」(`view="cashflow"`, glyph="金"):

**実装済み機能**:
- 月次キャッシュフロー算出 (賃貸+工事の全データから純関数で)
- 直近6ヶ月の月次推移SVGチャート
- **ルールベース自動分析**: 純利益・カテゴリ変動・大口取引・業者集中度等のインサイトを実データから自動生成
- **⚡ Claude AI 経営分析 (実API連結)**: 設定でAPIキー登録すれば実APIコール。10〜30秒で自然言語の経営レポートが返る
- **クロスエンティティ統計**: 全エンティティ (家主・建物・契約・業者・修繕・工事 etc) の統計をAIプロンプトに含め、データ間の相関分析をAIが実施
- **★レビュー機構 (学習)**: 各分析に5段階評価・訂正・コメントを記録。次回分析時に過去レビュー履歴がプロンプトに自動含有され、AIが過去の間違いを繰り返さなくなる
- **過去のAI分析履歴**: 当月以外の過去分析が一覧表示、クリックで再表示可能

**AI連携の構造**:
- `callClaudeApi(prompt, settings)` 関数 (KanriApp.jsx 冒頭付近)
- 設定で `aiAuthMode` を "direct"/"gateway" 切替可能
  - direct: x-api-key + anthropic-dangerous-direct-browser-access (今すぐ使える)
  - gateway: Authorization Bearer (将来 BMS API Gateway 接続用)
- エンドポイントURLとモデルは設定から動的変更
- BMS Gateway 完成時は **設定変更のみで切替** 可能 (コード変更不要)

**学習フィードバックの仕組み**:
- `data.aiAnalysis[]` に全分析記録を保存 (id, prompt, response, model, usage, rating, corrections, reviewerComment 等)
- レビュー済 (`reviewStatus="reviewed"`) かつ rating≥3 または訂正ありの分析が、次回プロンプトに「過去分析と人間によるフィードバック」セクションとして自動挿入
- 直近6件をコンテキストとして使用 (トークン制限考慮)
- `buildLearningContext()` 関数 (KanriApp.jsx 冒頭付近) がこのロジックを担当

### 直近の機能追加：工事案件 (`construction` エンティティ)
サイドバー「業務」セクションに **「工事案件」** メニュー追加 (`view="construction"`, glyph="工"):

- フルCRUD（OPSエンティティとして登録、既存EntityPage/FormModalで動作）
- フィールド: projectNo, name, category(大規模修繕/設備更新/内装/外構/新築管理/その他), buildingId, ownerId, mainVendorId, contractAmount, billedAmount, paidAmount, paymentDate, subcontractorCost, subcontractorPaidDate, status(見積→受注→施工中→完了→入金済)
- CashflowPageは `construction.paymentDate` から月次入金、`construction.subcontractorPaidDate` から月次外注費を自動集計
- AIプロンプトには工事の進行中案件・受注額・進捗・粗利率まで含まれる

### セキュリティ強化（B群完了時）
| ID | 対応 |
|---|---|
| F1 | 外部スクリプトに SRI 追加（react/react-dom 18.3.1 + babel 7.29.4 を固定、SHA-384検証） |
| F2 | `openPrintWindow()` の title 引数を `esc()` 化（潜在XSS対策） |
| F3 | `_validateData()` で配列要素の null/型不正を除外 |
| F4 | CSP メタタグ追加（`frame-ancestors none`, `form-action none`, `object-src none`） |
| F5 | `X-Content-Type-Options: nosniff` 追加 |
| F6 | `Referrer-Policy: strict-origin-when-cross-origin` 追加 |

---

## アーキテクチャ重要ポイント

### データ層
- **IndexedDB** (`kanri_v3` データベース / `kv` ストア / `data` キー) が主
- **localStorage** (`kanri_v2_data` キー) は旧V2からの自動移行用フォールバック
- 保存は **500msデバウンス** で連続編集をまとめる
- `_validateData()` で読込時に防御的バリデーション
- 詳細は `KanriApp.jsx` の冒頭 60〜180行を参照

### 状態管理
- すべて React `useState` でApp直下に集約
- `data` オブジェクトに全エンティティ配列が入る形（`{owner:[], building:[], room:[], ...}`）
- 16エンティティ: `owner, building, room, tenant, vendor, application, contract, billing, payment, remittance, vendorPayment, ticket, repair, settings, auditLog`

### 認証
- **なし**。端末を触れる人=全権、という設計前提
- C群（Supabase）で認証導入予定

### マルチテナント
- **なし**。1社単独運用前提
- V3バックエンド設計には `organization_id` を仕込み済み、後で接続するだけ

---

## デザインシステム（V3クリアSaaS）

CSSはすべて `index.html` 内。V2.2のクラス名を温存しスタイルだけ刷新。

### カラートークン (`index.html` :root)
- プライマリ: `#2563EB`（クリアブルー）
- 成功: `#16A34A`
- 警告: `#F59E0B`
- 危険: `#DC2626`
- 背景: `#F8FAFC`（カードは純白）

### フォント
- ディスプレイ（タイトル・数値）: Plus Jakarta Sans
- 日本語本文: Noto Sans JP

### コンポーネント命名規則
- ステータスバッジ: `.badge` + `.badge-success/-warning/-danger/-info/-neutral`
- ボタン: `.btn` + `.btn-primary/-ghost/-danger/-success/-sm`
- KPIカード: `.stat-grid > .stat` （`.stat.success/.warn/.danger`で左バーの色変更）
- ダッシュボードカード: `.dash-card`
- ピル+ドット表示: badge は ::before で自動でドット表示

---

## まだやっていないこと（優先順）

### C群: Supabase バックエンド統合（2〜3ヶ月）
- Vite + TypeScript への移行（Babel CDNを置き換え）
- Supabaseクライアント接続、認証UI
- 全エンティティのCRUDをSupabase APIに置換
- RLS動作確認、テナント分離テスト
- リアルタイム購読
- V2.2 JSON → V3 PostgreSQLマイグレーションスクリプト
- v3-backend/ 配下のSQLファイル4本を実Supabaseで実行

### D群: 本番運用準備（1〜2週間）
- Supabase 2FA、pg_cron設定、Transaction Pooler、バックアップ復元ドリル
- Vercelデプロイ + 独自ドメイン
- 監視・アラート、DR Runbook

### E群: 機能拡張（2〜3週間）
- PDF出力（請求書・督促状・送金明細）→ 既に内部関数はあり、UIに繋ぐだけ
- 仮想スクロール（react-window）→ 1万戸対応の必須機能
- 全文検索（PostgreSQL FTS）
- audit_logs パーティション化（pg_partman）
- インボイス制度対応（T番号・税率別集計）
- **キャッシュフローの Claude API 連携**（自然言語AI分析を実装）
- **工事業務データ連結**（別システムからの取込アダプタ）

### F群: 法務・運用
- 個人情報保護法対応のフロー
- GDPR運用ルール
- 電子帳簿保存法対応（別会計ソフト連携）

---

## 開発上の注意事項（ハマりポイント）

### 1. Babel runtime の制約
- `<script type="text/babel" src="KanriApp.jsx">` は `file://` プロトコルでは動かない（CORS）
- 必ず `python -m http.server` 経由で開く
- ダブルクリックで動かしたい時は `kanri-standalone.html` を使う（編集はしない）

### 2. IndexedDB の origin 分離
- `file://` と `http://localhost:8000` は別origin = 別データ
- standalone版で入れたデータは server版から見えない
- 開発時は必ず http.server 経由で統一する

### 3. デバウンス保存（500ms）
- 連続編集時の負荷軽減のため
- タブを閉じる前の500ms以内の変更は失われる可能性あり（既知の制約）
- C群で `beforeunload` での即時保存を追加予定

### 4. クロスタブ同期なし
- 2タブで同じデータを編集すると後勝ち
- 警告は出るが防げない
- C群で解決

### 5. 認証なし
- localStorage/IndexedDBに個人情報が平文保存
- 設計前提として明示済
- C群でDB暗号化＋RLS

### 6. キャッシュフローの「AI分析」は2層構造
- **第1層: 自動分析レポート** = ルールベースで実データから生成（嘘ではない、計算結果）
- **第2層: Claude AI 詳細経営分析** = プロンプト生成→クリップボード→ユーザーが claude.ai に貼り付け→本物のAI分析
- APIキー不要・サーバー不要・無料で「実質的なAI機能」が動く設計
- 将来 C群でClaude API直接連携する際は、現在の`aiPrompt`生成ロジックをそのまま `messages.create` の content に渡せばよい (差し替えるだけ)

### 7. CashflowPage が参照するフィールド名
- `payment.paidDate, payment.amount, payment.billingId`
- `remittance.year, .month, .managementFee, .netAmount, .totalRentReceived, .repairsDeducted`
- `vendorPayment.paymentDate, .paidDate, .amount, .vendorId, .purpose, .status`
- `repair.completionDate, .paidBy, .cost, .buildingId, .workContent, .status`
- これらの命名はV2.2のENTITIES/OPS定義に従う

---

## 編集ルール

### やってOK
- 新ページの追加（renderViewにエントリ追加 + Sidebarにナビ追加）
- 既存ページのUI改善・機能追加
- バグ修正
- セキュリティ強化

### 慎重に
- データスキーマの変更 → 既存ユーザーのデータ移行を考慮（`_validateData` でフォールバック）
- 共通コンポーネント（FormModal, ConfirmModal等）の変更 → 影響範囲広い
- index.html の CSS → V2.2クラス名との互換性を維持

### NG
- 嘘の機能・実装していないのに「実装済」と書くこと
- AI分析を本物のように見せかけること
- セキュリティ修正 (F1-F6) を巻き戻すこと
- 監査ログ機能の改変

---

## デバッグの起点

問題が起きたら：
1. ブラウザのコンソールを開く（F12）
2. `console.warn` や `console.error` の出力を確認
3. `[Kanri]` プレフィックスがついたログを探す
4. IndexedDB の中身を見る場合: F12 → Application → IndexedDB → kanri_v3 → kv → data

---

## 連絡事項

- ユーザー: 多田氏（プログラミング初心者と申告あり、専門用語は避ける）
- 別プロジェクト: Makasel（マカセル）、ARIS は別プロダクト。Kanri Systemとは無関係
- 編集環境: Windows / PowerShell / Claude Code
- 配信: `python -m http.server 8000` → `http://localhost:8000` (or `192.168.0.11:8000`)

---

最終更新: 2026年5月12日
担当: Claude (前セッション)
