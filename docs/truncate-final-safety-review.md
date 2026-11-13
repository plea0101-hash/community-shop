# 最後安全審查：正式基線、技術條件與執行者（未執行正式修正）

## 結論

**兩份最小修正的 SQL 設計與本機技術驗證已具備；正式執行準備尚未全部具備。** 尚須確認真正執行身分能修改兩個 creator 的 default ACL、Supabase 平台授權、變更核准／時段及最新基線／回滾保存。這不是「可以直接執行」或「正式漏洞已修復」的結論。

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

## 正式執行者的確認方式

另提供 `sql/inspection/truncate_executor_preflight.sql`，留待真正執行者另行核准後，以**同一 SQL Editor／連線及 active role**唯讀檢查，不由本工作在正式庫執行。

輸出區分：

1. session_user 與 current_user；不能拿另一個管理帳號的結果代替真正執行者。
2. bookings owner 可用權限、TRUNCATE grant option，以及 active role 的 superuser 旗標。
3. 對 postgres/supabase_admin 各自的 MEMBER、USAGE、SET；**MEMBER 或可 SET ROLE 不等於目前身分已能執行 DCL**。NOINHERIT 情況在本機有反例測試。
4. `current_identity_catalog_candidate` 只是 catalog 層級候選結果；即使 true，仍需專案／平台管理者確認該身分獲准修改 supabase_admin defaults，及其保留角色限制。不能從 SELECT 結果推定平台一定會放行。

不在正式庫以「BEGIN → ALTER/REVOKE → ROLLBACK」試探權限，不自動 SET ROLE，不把 postgres/supabase_admin 授予操作者或自行提權。若只能處理 postgres，不能宣稱兩個 creator 已修好；須交由獲授權的平台操作者處理第二份完整交易。

## 執行前仍須確認

- [ ] 真正執行者及其平台授權，尤其 supabase_admin default ACL；目前未確認。
- [ ] 另行取得兩階段正式變更核准與無並行 ACL／建表的短時段。
- [ ] 保存執行當下完整修正前 JSON、回滾指令與權限布林矩陣，確認無來源漂移。
- [ ] 按執行方案先修 bookings、驗證，再修兩個 default ACL、驗證；如果第二步無權，保留第一步安全修正，不自動恢復漏洞。
- [ ] 完成後由正式操作者提供新的唯讀結果，才能聲稱正式修復；本機成功不能替代此證據。

應用的會員／付款／退款／核准回呼、通知 worker、前端改接仍是另案啟用前提；不能為了讓 service_role 直接操作預約而在本次順便補 DML。ACL 修正也不回溯清理其他既有表的 TRUNCATE，其他權限與來源須另行審查。

操作順序與影響見 [truncate-execution-plan.md](truncate-execution-plan.md)，完整本機結果見 [production-booking-test-results.md](production-booking-test-results.md)。
