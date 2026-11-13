# 正式 TRUNCATE 修正執行方案與回滾（待審，不代表執行授權）

**目前僅文件與草稿更新，Codex 不得執行任何正式 SQL、不得自動拆開 SQL 執行，也不得自行授予 supabase_admin 權限。** 最新預檢顯示 postgres 符合現有 bookings 表級修正權限條件，但對 supabase_admin defaults 的 MEMBER/USAGE/SET/candidate 全 false，因此完整 default 草稿目前 blocked。現有表也尚未取得正式變更核准、尚未執行。以 [最新執行限制](truncate-execution-restrictions.md) 為準。

階段 A 正式審查請先使用 [核准申請表與集中連結](stage-a-change-approval.md) 及 [逐步檢查清單](stage-a-execution-checklist.md)；它們只是待填備件，不代表批准本計畫或執行任何階段。

## 待核准的三個目標 DCL（不是自動執行清單）

現有 bookings：

```sql
REVOKE TRUNCATE ON TABLE public.bookings FROM anon, authenticated;
```

未來 public 表：

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE TRUNCATE ON TABLES FROM anon, authenticated;
```

正式操作應使用包含前後斷言與回滾保護的草稿檔，不只執行以上摘錄。它們不含對 service_role/postgres 的撤權，也不需要執行完整預約 RPC migration。

## 正式執行者確認（本工作不在正式庫執行）

使用 `sql/inspection/truncate_executor_preflight.sql` 在真正擬執行的連線／active role 下做另行核准的唯讀確認。檢查 current_user、session_user、owner 可用權限與對兩個 creator 的 MEMBER/USAGE/SET 差異。catalog candidate=true 不等於 Supabase 平台已授權修改 supabase_admin；須由平台／專案管理者確認，不以正式 DCL 後 ROLLBACK 試權、不自行提權或自動 SET ROLE。候選結果不足時，停止而非授予更多角色。

目前已收到修正前 ACL 與執行者預檢：表級條件成立，但 supabase_admin 的角色權限證據為否，並非 superuser。這不是正式修正核准，也不是修正後結果。結論與檢查清單見 [truncate-final-safety-review.md](truncate-final-safety-review.md)。

## 分階段可行性與不得自動拆分

既有 minimum 檔是獨立表級修正，從交易範圍上可在階段 A 的**獨立正式核准後**先由正式操作者處理，不必為了等待平台權限而把它視為必須與 B 綁定。但這是供決策的選項，不是 Codex 現在的執行授權。

完整 default 檔仍保留 postgres＋supabase_admin 兩個 ALTER 的單一原子交易。**不得因目前只能用 postgres，就拆出／自動執行 postgres default 段；不得把 A 核准當成 B 的核准。** B 須等受支援平台管道、獲授權操作者及獨立核准。目前不應嘗試該檔。

## 待獨立核准的操作順序

| 順序 | 待核准操作 | 預期結果／確認 |
|---|---|---|
| 0 | 決定是否獨立核准 A；目前 A 僅具表級權限條件，B 因 supabase_admin 權限受阻 | 明定殘餘風險、操作者／時段與 B 責任人；Codex 不自動執行 |
| 1 | 執行唯讀 `sql/inspection/truncate_fix_verification.sql`，保存完整 JSON，必要時同時執行來源查詢 | owner=postgres；兩個客戶端目前 TRUNCATE=true；保存維護權限、所有 ACL 與 grant options，不能只留 true/false 摘要 |
| 2 | **另行核准後**執行 `sql/drafts/20261113_truncate_minimum.sql` | 只現有 bookings 的客戶端 TRUNCATE 消失；資料、RLS、其他 ACL、postgres/service_role 全不變 |
| 3 | 再執行相同唯讀驗證，與步驟 1 比較 | `bookings_clients_cannot_truncate=true`；future-default 檢查仍 false 是預期，尚未修 future grants |
| 4 | **目前 blocked**；僅在平台確認受支援管道、獲授權操作者及 B 獨立核准後，才由正式操作者處理完整 `sql/drafts/20261113_truncate_default_acl.sql` | 兩個 creator 的 public default ACL 只少掉客戶端 TRUNCATE；service_role 及其他 default privileges 保留 |
| 5 | 再執行相同唯讀驗證，與基線比較並保存 | 兩個檢查都 true，非目標 ACL 與維護權限完全相同。**不在正式庫建立 canary 表、不做 TRUNCATE 或真實預約測試** |

每份草稿各有 BEGIN/COMMIT，不要再盲目包入另一層交易或把完整 RPC 草稿一起執行。發生錯誤時，尚未提交的該份變更必須 ROLLBACK 並驗證。已知目前 B 無足夠權限證據，不能在正式庫執行以求失敗證明。若日後正式授權的步驟 4 仍失敗，步驟 2 已完成的安全修正保持有效，明確記錄「現有表已修、future defaults 待處理」，不用自動恢復漏洞。

## 唯讀結果如何比較

`sql/inspection/truncate_fix_verification.sql` 不讀任何 bookings 資料列，也不建立測試表。輸出包含：

- `bookings_owner`、`bookings_rls`：全程相同。
- `bookings_acl`：步驟 2 後只移除兩個指定 grantee 的 TRUNCATE；其餘 grantor、privilege、grantable 必須相同。
- `effective_permissions`：客戶端 TRUNCATE 由 true 變 false；其原 SELECT/INSERT/UPDATE=false 不變。postgres/service_role 的每一項有效權限均與基線相同，特別是 service_role 的 SELECT/INSERT/UPDATE/DELETE 必須仍為 false，不得為方便而補上。新增 service_role_bookings_dml_still_absent 應保持 true。
- `default_acl`：步驟 4 後只移除兩個 creator 在 public 給兩個客戶端的 TRUNCATE。global／service_role／其他 privilege 不變。
- `checks.future_public_client_truncate_sources_absent`：應在 default 修正後 true；它驗證 metadata 的來源，不假裝在正式庫試建表。
- `rollback_from_snapshot`：從當次實際 ACL 產生 GRANT SQL 文字，保留 grant option。**必須保存修正前輸出**，修正後相關 entries 已不存在，不能再從修正後結果推回基線。

## 預期影響與不涵蓋範圍

- 現有資料／bookings status、時間、原子交易、占位約束不變；不刪行、不 TRUNCATE、不部署。
- 客戶端不能再直接清空 bookings；若某流程依賴這項危險行為，應審查並轉到受控維護流程，不為相容而默默恢復。
- Future default 修正影響兩個 creator 日後在 public 建的表／相關 TABLES 類物件，不能只指定表名。其其他 DML／SELECT defaults、functions、sequences、其他 schema／creator 不變。
- 其他既有表的 TRUNCATE 不被回溯撤銷。兩階段間若仍有建表，或原先已有其他表暴露，應另做 metadata 盤點並另提精確修正，不自動掃表撤權。
- 新增或舊的 definer RPC／服務端維護流程仍需獨立審查；本次不是完整應用授權或付款流程的啟用。

## 回滾方式

優先保留安全修正，針對真正的相容問題另提修復；恢復危險權限須明確核准。

1. **交易還沒提交或執行出錯：** `ROLLBACK;`，再執行唯讀驗證。不要在 aborted transaction 裡繼續執行下一步。
2. **已提交、確有核准要恢復實際已完成的兩個修正：** 先回滾 future default（步驟 4），再回滾現有 bookings（步驟 2）。以保存的基線 `rollback_from_snapshot.defaults`／`.bookings` 為準，在各自短交易中執行，使用記錄的建立者／grantor 權限，保留 WITH GRANT OPTION。不可自行 SET ROLE 到無權角色或提升權限。
3. 已知基線無 grant option 時，對應草稿為 `sql/rollback/20261113_restore_default_truncate.sql`、`sql/rollback/20261113_restore_bookings_truncate.sql`。若與快照有任何不同，先修訂回滾草稿，不能套用近似基線。
4. 再執行唯讀驗證，對比基線確實還原；postgres/service_role／非目標權限仍不得改動。

default 回滾只恢復**往後**的新物件預設，不會把修正期間已建的表補回 TRUNCATE，也不應自動對它們 GRANT。現有 bookings 回滾將讓 anon/authenticated 再次 TRUNCATE=true；future 回滾會讓新表重新暴露，須在變更記錄明確承認。

若只修了一個項目，僅回滾該項目；不為恢復「一致」而授權原本沒有的 privilege。基線檔須妥善保留，不需任何個資、預約資料或金鑰。

B 從未執行時，不執行 B 的回滾 GRANT；A 若已真正完成，不能因 B 受阻就自動恢復 A 的漏洞。目前 A/B 均未執行。
