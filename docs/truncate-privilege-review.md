# 已確認 ACL 的安全分析與最小修正（未執行正式 SQL）

## 正式證據更新

來源為使用者提供的正式唯讀盤點，本工作沒有連線或查詢正式 Supabase：

- anon/authenticated 對 public.bookings 有效 TRUNCATE=true，兩者都有 postgres 給的直接 TRUNCATE ACL。
- bookings 擁有者 postgres；membership_paths 為空，未發現角色繼承來源。本次最小修正不撤銷 PUBLIC 或共享父角色，也不改擁有權。
- public 的 per-schema default ACL：postgres、supabase_admin 各自建立的表，對 anon/authenticated/service_role 含 TRUNCATE。
- 先前確認客戶端的 bookings SELECT/INSERT/UPDATE=false。不能因這些是 false 就認為 TRUNCATE 安全，RLS 不保護 TRUNCATE。

因此目前有兩個獨立暴露面：現有 bookings 的直接授權，以及未來兩個建立者的 public 表預設授權。修正其中一個不會自動修正另一個。`membership_paths` 是 DB 角色圖，不是應用的社區／廠商會員資格；不能因此啟用未審核的預約授權。

## 精確修改範圍

1. `sql/drafts/20261113_truncate_minimum.sql`：只對 public.bookings 撤銷 anon/authenticated 的 TRUNCATE。不改 PUBLIC、其他表、DML、SELECT、RLS、role membership、owner，也不給任何新權限。
2. `sql/drafts/20261113_truncate_default_acl.sql`：只對 postgres、supabase_admin 這兩個 creator，在 public 的 TABLES default ACL 撤銷 anon/authenticated 的 TRUNCATE。不改 service_role、擁有者、其他權限、其他 schema、其他 creator、global defaults、functions 或 sequences。

PostgreSQL 的 TABLES default ACL 依「建立者＋schema」套用，不能只依未來表名 bookings 篩選，且 table-like objects 如 views 也屬此類。此改動會讓兩個建立者未來在 public 建的此類物件不再預設給客戶端 TRUNCATE；**不會回溯改既有物件**。

兩份腳本各自是短交易。現有表草稿會對比所有非目標 ACL（含 grantor、grant option）與 postgres/service_role 的有效維護權限，任何非目標差異即回滾；default ACL 草稿會對比全庫所有非目標 default ACL entries，保證沒有順手撤銷其他必要權限。

## 來源漂移與權限不足

雖然目前沒有繼承路徑，執行時若新出現 PUBLIC／父角色、owner 繼承或 superuser 等來源，現有表腳本會拒絕部分修正。default ACL 若仍有 global、PUBLIC 或可繼承來源，也拒絕。不能以 public schema 的 REVOKE 抵銷 global default GRANT，腳本不擅自修改 global 或共享角色。

執行者必須同時有權修改兩個建立者的 default privileges。Supabase 可能限制修改 supabase_admin；如果被平台拒絕，該份交易整體回滾，需由平台授權操作者處理，不能自行提升角色、GRANT membership 或假裝完成。已提交的 bookings 修正不必因此恢復不安全權限。

## 保留維護權限及應用限制

腳本不以 service_role/postgres 為撤權對象；bookings owner 不變，service_role 原有 table ACL／default ACL 與 grant options 均保留。本機以額外必要權限作 sentinel 驗證未受影響，不假設正式所有其他 privileges 都是 ALL。

修正後普通客戶端 TRUNCATE 應失敗，這是預期效果。正常預約、取消、庫存原子操作不依賴客戶端 TRUNCATE；本機在套用修正後驗證兩個建立者新表及六個真實並行預約場景。會員／付款的拒絕預設沒有解除，沒有安裝正式 RPC 或改接前端。

這只修 TRUNCATE；其他既有表可能仍暴露，其他 creator／schema 不在修正範圍。保留的其他 default SELECT/DML 也不代表新表自動具有合適的 RLS，須另行審查，不在此擴大撤權。

## 驗證與回滾

完整步驟、兩階段預期結果與回滾順序見 [truncate-execution-plan.md](truncate-execution-plan.md)。`truncate_fix_verification.sql` 同一個唯讀 SELECT 可在每一步前後執行，應保留修正前完整 JSON；其中會從實際 ACL 產生回滾 SQL 字串，包含真實 grant option／grantor，而不執行它們。

`sql/rollback/` 提供已知 no-GRANT-OPTION 基線的危險回滾草稿；若保存的基線不同，以修正前 JSON 的精確授權為準，先審查再執行。回滾會重新引入安全暴露，不應作為預約功能出問題時的預設補救。default rollback 不回溯改修正期間已建立的表。

本機 7 項 ACL 測試及真正 PostgreSQL 的快照回滾／預約回歸均已驗證；沒有修改任何正式資料或權限，不宣稱正式漏洞已排除。
