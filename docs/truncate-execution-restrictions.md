# 最新正式執行限制與分階段核准（權威狀態，尚未執行）

## 已取得的正式執行者證據

以下為使用者提供的 SQL Editor 唯讀預檢；本工作沒有在正式庫執行任何 SQL：

| 欄位 | 結果 | 判讀 |
|---|---|---|
| active_identity / bookings_owner | postgres / postgres | 目前身分是現有 bookings 擁有者 |
| can_use_owner_privileges | true | 具備該表的 owner 權限條件 |
| has_truncate_grant_option | true | 具備該表 TRUNCATE 授權管理條件 |
| active_is_superuser | false | 不可推定能管理保留角色 |
| 對 supabase_admin 的 MEMBER / USAGE / SET | 全 false | 目前沒有可修改該 creator defaults 的角色權限證據，也不能切換到它 |
| supabase_admin catalog candidate | false | **完整 default ACL 修正對目前身分受阻**，不是「權限尚不明」 |

結論：**現有 public.bookings 的表級修正權限條件具備，但尚未取得本次正式變更核准，也未執行。完整 default ACL 修正仍受阻。** 本機測試通過不代表正式已修復，資料庫擁有者也不等於平台保留角色的管理者。

## Codex 的執行邊界

- 本輪及目前授權範圍僅更新文件與草稿、更新 Draft PR；Codex 不執行任何正式 SQL，不部署、不合併。
- **不得自動拆開 default ACL 檔案、只執行 postgres 那一段，或建立／執行替代的部分 default 修正。** 既有兩個 creator 的 default 草稿保持完整原子交易，現階段整體標示 blocked。
- 不因 postgres 擁有 bookings、某個 SELECT 候選值 true 或 PR 審查通過，就自動執行表級修正。
- 不自行 SET ROLE、GRANT supabase_admin／postgres membership、提升角色、使用 service_role／金鑰作繞道，或直接改系統目錄。
- 不用正式 ALTER／REVOKE 後 ROLLBACK 試探權限，不重試已知無權的 default 操作。
- 階段 A 的獨立核准不包含 default ACL、其他表、完整 RPC migration、應用啟用或回滾 GRANT；需要分別核准。

## 可供正式決策的分階段選項（不是自動執行計畫）

| 階段 | 當前狀態 | 何時才可處理 | 範圍與驗證 |
|---|---|---|---|
| A：現有 bookings | 表級權限條件具備；**未核准／未執行** | 獨立正式核准明列此表、兩個 grantee、TRUNCATE、操作者、時段、前後驗證與回滾保存後，由正式操作者處理 | 既有 minimum 草稿；不改任何 default。成功後表級 check=true、future check 仍 false，不能稱完整修復 |
| B：兩個 creator 的 public default ACL | **目前 postgres 身分受阻** | 獲授權平台操作者及受支援執行管道確認、另行正式核准後，才審查是否執行整份 default 草稿 | 保留原兩個 ALTER 的原子交易；不是先自動做其中一個。完成前未來表風險仍存在 |

從交易／權限範圍看，A 不依賴 B，可在獨立核准後先降低現有 bookings 風險；這是可行性評估，**不構成現在執行 A 的授權**。如果決策者不接受分階段窗口，則兩者都保持未執行。

## 階段窗口的剩餘風險

若未來 A 真正完成但 B 尚未完成：兩個 creator 的未來 public TABLES defaults 仍給客戶端 TRUNCATE；窗口中建立的表可能保留該權限。日後修好 defaults 也不會回溯撤銷已建表的授權；其他既有表也不在 A 的修正範圍。

因此 A 的核准須明確接受殘餘風險，指定 B 的追蹤責任與窗口策略；可由正式管理者決定暫停相關建表／DDL，或另審新物件 ACL 的精確修正，但 Codex 不自動停服務、掃表撤權或改 creator。不得讓 postgres/supabase_admin 的預設差異被「統一權限」改寫。

service_role 對 bookings 的 SELECT/INSERT/UPDATE/DELETE **仍須全部 false**；postgres/service_role 的其餘原有權限、owner、RLS、資料與庫存規則保持不變。ACL 修正不解除會員／付款拒絕預設。

## 失敗與回滾條件

- A 未提交／斷言失敗：該次交易回滾，保留基線並比對權限；不擴大撤權、不改成其他腳本自動重試。
- B 尚無權限：**不執行、不試探**。若經另行授權的實際執行仍失敗，整份 B 交易回滾；不能留下 postgres-only default 修正。
- A 若已核准且真正提交，B 的受阻／失敗不應自動恢復 A 的危險授權；應記錄「僅表級已修，defaults 未修」。目前 A 並未執行，不能使用此狀態描述現況。
- 已提交的變更只有另行核准的相容性／安全決策才能回滾；以執行前快照恢復原 grantor、creator、grant option。僅回滾實際已完成項目。B 從未執行時，不運行它的回滾 GRANT。
- 恢復 A 會重新讓兩個客戶端 TRUNCATE=true；恢復 B 會重新暴露未來表，且不會回溯改窗口中新表。不能因「保持一致」而自動回滾或補權。

## supabase_admin 的正式處理途徑

由專案／組織管理者向 Supabase 支援或實際平台管理方確認：此受管角色的 default ACL 是否允許本案修改、應由哪個已授權的身分及受支援管道處理、可否保持 service_role／owner／非目標權限，以及失敗與回滾責任。

可交付完整兩個 creator 的精確 default 草稿、metadata 基線、驗證與回滾方案供平台審查；不交付任何金鑰、真實預約或個資。專案管理介面的管理身分不自動等於 DB supabase_admin 權限。如果平台不提供支援的變更管道，B 保持 blocked 並記錄正式限制，不自行授予 membership、取得／索取保留角色密碼、改擁有權或繞過平台。

## 仍待正式核准／確認

1. 是否接受獨立階段 A，以及其明確範圍、操作者、時段、最新基線與回滾責任。
2. 是否接受 A→B 之間的風險窗口、DDL／新表追蹤策略與 B 的負責人。
3. 平台對 supabase_admin defaults 的可修改性、獲授權操作者及管道；目前 postgres 不具備該證據。
4. B 整份草稿的獨立核准；不可用 A 的核准或本機結果替代。
5. 各階段真正完成後的正式唯讀結果，才能更新修復狀態。
