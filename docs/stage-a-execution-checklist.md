# 階段 A 執行前、驗收與異常處理清單（尚未核准，尚未執行）

**目前所有格子皆未簽認，不代表已完成。** 本案正式操作、核准、自行複核、驗收、異常／回滾決策均由**同一位專案負責人（本人）**兼任，這是供本人日後分項簽認的清單；不是 Codex 自動執行指示。本輪不得在正式庫執行任何 SQL，包括唯讀探查，不執行 B／部署／合併／提權。

ChatGPT／Codex 僅為技術輔助，不是第二位人工審核或正式核准人。「分開／獨立簽認」指不同事項分項記錄，不聲稱有不同人員。如適用正式規則要求不同人員獨立核准，單人尚未滿足，停止該項核准且不得以 AI 或本文件豁免。

主申請及簽認欄位：[階段 A 正式變更申請](stage-a-change-approval.md)。每一項未完成或結果不符合時，記錄差異並停止，不以其他未核准操作補救。

## A0 — 核准與範圍檢查（執行前）

- [ ] 正式變更單、專案環境識別、A 核准決議／佐證已完成，並非只有 PR／本文件通過。
- [ ] 核准明列唯一目標：public.bookings → anon/authenticated → 撤銷 TRUNCATE。
- [ ] 已記錄本人統一簽認識別；申請／核准／正式操作／自行複核／驗收／風險接受／異常與回滾均由本人兼任，各項紀錄 ID、時間、決議／證據及簽認分開；無虛構他人、AI 代簽或獨立人工審核聲明。
- [ ] 已記錄適用的外部獨立人員要求及依據；如明文要求不同人工，標示尚未滿足並停止，未自行豁免；不適用則由本人記錄依據。
- [ ] 臺灣時間執行窗口、逾時／中止條件、ACL／DDL 控制方案已核准。
- [ ] 已明確接受 B blocked 的殘餘風險、新表授權窗口，以及 B 的追蹤責任；否則退回決策。
- [ ] 明確認定 A 不核准 B／postgres-only defaults／其他表／完整 RPC／應用啟用或回滾 GRANT。
- [ ] 無自動拆檔／SQL 執行器；不自行 SET ROLE、GRANT membership、提權或從 service_role／密鑰繞道。

## A1 — 執行者與最新基線（僅在獲准後，由正式操作者收集）

- [ ] 真正連線及 active role 與核准一致；預期 postgres，owner／grant-option 條件仍成立，無需自行切換角色。
- [ ] 專案／環境識別正確，沒有把測試結果或另一連線的預檢當成正式證據。
- [ ] [唯讀預檢](../sql/inspection/truncate_executor_preflight.sql) 與 [完整驗證](../sql/inspection/truncate_fix_verification.sql) 結果已存為帶收集者／時間的基線；不記錄金鑰或個資。
- [ ] owner=postgres、RLS enabled=true/forced=false；直接目標 grantor=postgres、TRUNCATE=true、grantable=false。
- [ ] 客戶端 SELECT/INSERT/UPDATE/DELETE=false；其他原有 grant 不動。
- [ ] postgres 的全部原有權限不變；service_role 的 SELECT/INSERT/UPDATE/DELETE=false、維護類原值=true，不補權。
- [ ] 比對完整 ACL／grant option、所有有效權限、default ACL；沒有未知 PUBLIC／父角色或權限漂移。任何差異先停止審查，不自動調回舊值。
- [ ] 保存精確的 `rollback_from_snapshot.bookings` 與原 grantor／grant option；A 不使用 `.defaults` 的回滾指令。
- [ ] A 正式核准仍有效；新基線與核准條件一致。目標已改變或已由他人修正時，不盲目重跑。

## A2 — 指定 SQL 與執行邊界

- [ ] [A 最小撤權檔](../sql/drafts/20261113_truncate_minimum.sql) 的版本／SHA-256 與申請表一致，含完整 BEGIN/DO/COMMIT 與斷言。
- [ ] 未抽成單句、未改 grantee／privilege、未附加 ALTER DEFAULT PRIVILEGES／GRANT／資料 DML／其他檔案。
- [ ] [A 回滾檔](../sql/rollback/20261113_restore_bookings_truncate.sql) 已對照新基線，但不在正常操作中一起執行；其恢復危險權限需獨立明確核准。
- [ ] B 檔及 B 回滾保持不執行，未嘗試已知無權的 supabase_admin 操作。
- [ ] 若 A 真正獲准，由指定正式操作者在核准窗口處理**僅 A 的完整交易**；本文件本身不授權此動作，也不交給 Codex 自動處理。
- [ ] 記錄開始／結束、提交是否成功、操作者、腳本識別及執行紀錄；不含憑證。

## A3 — 驗收（不能用破壞性或真實預約測試代替）

- [ ] 正式操作者在獲准範圍重跑同一 [唯讀驗證](../sql/inspection/truncate_fix_verification.sql)，保存 AFTER JSON。
- [ ] 兩個客戶端有效 TRUNCATE=false，表級 check=true。
- [ ] 除兩個目標 TRUNCATE 外，全部 ACL、grantor、grantable、postgres/service_role 有效權限與 BEFORE 完全相同。
- [ ] service_role 四項讀寫仍 false，`service_role_bookings_dml_still_absent=true`；沒有補權。
- [ ] owner／RLS／default ACL 完全不變；沒有處理其他表、資料、庫存約束或應用狀態。
- [ ] future-default check 仍 false，記錄「A 表級已修，B blocked／未修」；它不是 A 失敗或自動回滾觸發條件。
- [ ] 沒有在正式庫做 TRUNCATE、canary 建表、真實預約／取消、付款或壓測；資料不變的設計與本機回歸證據僅按原範圍引用。
- [ ] 本人以驗收角色在申請表另記實際結果、佐證、接受決議、日期及簽認（與 A 核准分開）；沒有將預期值預填成實測結果。
- [ ] 本人以 B 追蹤角色接續記錄平台受支援管道；沒有自動執行 B 或宣稱全部問題已修復。

## A4 — 停止與異常決策

- [ ] 未核准、錯環境／身分、過窗口、基線／腳本漂移：不開始；記錄並退回。
- [ ] SQL error／斷言失敗且未提交：操作者中止並處理其交易回滾，再核對基線；不拆 SQL 重試、不擴大撤權、不提權。
- [ ] 提交狀態不明／驗收不符：停止新操作，保存證據，由本人以異常決策角色另留判讀紀錄；不盲目重跑或立即 GRANT。
- [ ] 不因 B 無權、future check=false 或本機與正式差異而自動回滾已成功的 A。
- [ ] 如已提交且真的需要恢復 TRUNCATE，先確認具體觸發條件、獨立／條件式回滾核准、本人以回滾決策／核准／有權操作角色各留紀錄；缺任一條件即停止與回報，不擅自操作。

## A5 — 僅在有權且已獨立核准時的回滾驗收

- [ ] 只回滾實際已提交的 A；B 未執行就不跑 B 的 GRANT。
- [ ] 使用保存的新基線及已審 A 回滾檔，原 grantor／grant option 相符；若漂移先回審，不用近似版本。
- [ ] 回滾會重新引入兩個客戶端 TRUNCATE=true 的暴露，已由本人以回滾風險決策角色另行簽認接受。
- [ ] 回滾後由本人以操作／驗收角色分項記錄唯讀比對原 ACL，postgres/service_role 及非目標權限不變，記錄實際狀態與簽認。
- [ ] 不因回滾而授予其他權限、修改 default ACL、補 service_role DML 或自動授予其他新表。

所有紀錄與正式核准欄位回填 [申請表](stage-a-change-approval.md)，本清單不單獨充當核准。完整硬限制見 [最新正式執行限制](truncate-execution-restrictions.md)。
