# 最後安全審查：正式基線、技術條件與執行者（未執行正式修正）

## 結論

**目前 postgres 對現有 public.bookings 具備表級修正的權限條件，但正式核准與修正均未執行；對 supabase_admin defaults 的角色權限證據為否，完整 default ACL 修正受阻。** 可評估獨立核准階段 A 先處理既有表，但不能讓 Codex 自動拆 SQL、部分執行 default 修正或自行授權。權威限制見 [truncate-execution-restrictions.md](truncate-execution-restrictions.md)。

本次沒有執行任何正式 SQL（包括唯讀探查）、沒有連線正式 Supabase、沒有資料／權限／部署／合併。正式狀態只來自使用者提供的修正前 JSON。

## 正式快照與本機預期，必須分開

| 項目 | 正式修正前快照（仍是現況證據） | 本機套用後的預期 |
|---|---|---|
| anon/authenticated 的 bookings TRUNCATE | true，風險存在 | false |
| future public client TRUNCATE sources absent | false，兩個 creator 仍有來源 | true |
| bookings owner / RLS | postgres / enabled=true, forced=false | 完全不變 |
| postgres 的 8 項 bookings 有效權限 | 都 true | 都 true，不變 |
| service_role 的 SELECT/INSERT/UPDATE/DELETE | **都 false** | **都 false，不能補權** |
| service_role 的 MAINTAIN/REFERENCES/TRIGGER/TRUNCATE | 都 true | 都 true，不變 |

兩個建立者的 default ACL **並不相同**：postgres 對客戶端與 service_role 只給 4 個維護類權限；supabase_admin 對這些 grantee 給 8 個表權限，並對 postgres 給表權限。修正只移除客戶端 TRUNCATE，保留這些差異，不能把 supabase_admin 的較廣 defaults 套到既有 postgres-owned bookings。

## 兩份最小草稿審查

- `20261113_truncate_minimum.sql`：只對 public.bookings 撤銷 anon/authenticated 的 TRUNCATE；不改其他表、PUBLIC、RLS、owner、資料、DML、service_role 或 postgres 維護權限。前後比較全部非目標 ACL 與維護有效權限，出現差異會回滾。
- `20261113_truncate_default_acl.sql`：只對 postgres/supabase_admin 的 public TABLES defaults 撤銷兩個客戶端 TRUNCATE；不改 service_role、其他 privileges、global／其他 schema／creator，也不回溯已有表。未清除的額外來源、權限不足或非目標差異會回滾。
- 根據實際基線，不需要增加任何 GRANT 或擴大撤權範圍，原三個目標 REVOKE 精確符合修正需求。

最新 fixture 已由使用者提供的 metadata 建立，逐項比對 **20 個 bookings ACL entries、52 個 default ACL entries、32 個有效權限布林值**。不再以「service_role 有 ALL」作正式基線模型；沒有真實使用者、聯絡資料或預約資料。

## 驗證與回滾完整性

`truncate_fix_verification.sql` 同一唯讀 SELECT 用於前後比較；新增 `service_role_bookings_dml_still_absent`，預期修正前後都 true。它不代表維護權限越多越好，必須保留原本 false 的項目。

使用者的修正前快照已包含完整 2 個表級、4 個 default ACL 回滾 GRANT，目標 entries 的 grantable 均 false。現有 no-GRANT-OPTION 回滾草稿與這份基線相符。若執行前基線漂移，應以新保存快照產生的 grantor／creator／grant option 為準；不能套近似的舊基線。

本機已驗證：前後非目標與維護權限完全相同；靜態回滾與快照生成回滾能精確恢復原 ACL；另測 WITH GRANT OPTION 案例。先 default 再 bookings 的回滾會重新暴露風險，需明確核准。default 回滾不改修正期間建立的表，也不應替它們自動補權。未提交／失敗交易直接 ROLLBACK。

## 已確認的正式執行者結果

使用者提供：active_identity=postgres、bookings_owner=postgres、can_use_owner_privileges=true、has_truncate_grant_option=true、active_is_superuser=false；對 supabase_admin 的 MEMBER/USAGE/SET 與 catalog candidate 均 false。這支持現有表修正的權限條件，不支持完整 default ACL 執行，更不是正式變更核准或已修復證據。

Codex 不自動 SET ROLE、GRANT membership 或提權；不以「先跑 postgres 部分」繞過受阻的完整 default 草稿。經獨立正式核准後，階段 A 可由正式操作者先處理；本輪只改文件及草稿註記，不執行。

## 正式執行者的確認方式

另提供 `sql/inspection/truncate_executor_preflight.sql`，留待真正執行者另行核准後，以**同一 SQL Editor／連線及 active role**唯讀檢查，不由本工作在正式庫執行。

輸出區分：

1. session_user 與 current_user；不能拿另一個管理帳號的結果代替真正執行者。
2. bookings owner 可用權限、TRUNCATE grant option，以及 active role 的 superuser 旗標。
3. 對 postgres/supabase_admin 各自的 MEMBER、USAGE、SET；**MEMBER 或可 SET ROLE 不等於目前身分已能執行 DCL**。NOINHERIT 情況在本機有反例測試。
4. `current_identity_catalog_candidate` 只是 catalog 層級候選結果；即使 true，仍需專案／平台管理者確認該身分獲准修改 supabase_admin defaults，及其保留角色限制。不能從 SELECT 結果推定平台一定會放行。

不在正式庫以「BEGIN → ALTER/REVOKE → ROLLBACK」試探權限，不自動 SET ROLE，不把 postgres/supabase_admin 授予操作者或自行提權。目前僅確認 bookings 表級條件；完整 default 檔保持 blocked，不能自動切出 postgres default 段，也不能宣稱兩個 creator 已修好。B 只能交由獲授權的平台操作者另行審查完整交易。

## 執行前仍須確認

- [x] 目前身分對現有 bookings 的 owner／grant-option 條件已由正式唯讀結果確認，尚未核准或執行修正。
- [ ] 若要先做表級階段 A，取得其獨立正式核准、操作者／時段與殘餘風險接受。
- [ ] 對 supabase_admin defaults 目前明確缺乏角色權限證據；由平台指定獲授權管道與操作者，不能自動拆開 default SQL。
- [ ] default 階段 B 取得獨立正式核准；A 不授權 B，不因 PR 通過就執行任何正式 SQL。
- [ ] 保存執行當下完整修正前 JSON、回滾指令與權限布林矩陣，確認無來源漂移。
- [ ] 若 A 已獨立核准才由正式操作者處理；B 目前不執行、不試探、不自動切出 postgres 段。A 若未來完成而 B 仍受阻，不自動回滾 A 或宣稱完整修復。
- [ ] 完成後由正式操作者提供新的唯讀結果，才能聲稱正式修復；本機成功不能替代此證據。

應用的會員／付款／退款／核准回呼、通知 worker、前端改接仍是另案啟用前提；不能為了讓 service_role 直接操作預約而在本次順便補 DML。ACL 修正也不回溯清理其他既有表的 TRUNCATE，其他權限與來源須另行審查。

操作順序與影響見 [truncate-execution-plan.md](truncate-execution-plan.md)，完整本機結果見 [production-booking-test-results.md](production-booking-test-results.md)。

## 階段 A 核准文件準備狀態

已產出 [階段 A 申請表](stage-a-change-approval.md) 與 [執行前／驗收／異常清單](stage-a-execution-checklist.md)。尚缺實際操作者、窗口、正式核准、最新正式基線、回滾與驗收責任及 B 風險接受。沒有代填簽名、結果或時段；備件完成不等於正式核准／修復。
