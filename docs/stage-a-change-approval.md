# 鄰里好店階段 A：public.bookings TRUNCATE 最小撤權 — 正式變更申請

**狀態：草擬／待填／未核准／未執行。** 本次只準備文件，不授權 Codex 或任何操作者執行正式 SQL。不修改 Supabase、不部署、不合併、不提權、不執行階段 B。

本頁為階段 A 的集中審查入口。所有核准／簽名／時間／結果均須由正式責任人填寫，不能以本文件、PR 通過、本機測試或口頭「可以」推定已完成正式核准。

## 1. 唯一變更範圍

| 欄位 | 固定範圍 |
|---|---|
| 系統／環境 | 鄰里好店／正式 Supabase（專案識別待填，不填金鑰） |
| 物件 | 僅 `public.bookings` |
| grantee | 僅 `anon`、`authenticated` |
| privilege | 僅撤銷 `TRUNCATE` |
| 核准執行檔 | [既有最小撤權草稿](../sql/drafts/20261113_truncate_minimum.sql)，含既有交易與斷言；不抽出單句或改寫執行 |
| 正式操作者預期身分 | `postgres`；其 owner／grant-option 條件已由使用者提供的唯讀預檢確認，仍須核對真正連線／active role |
| 排除 | 其他表、其他 privilege、RLS、owner、資料列、預約／付款狀態、庫存規則、default ACL、完整 RPC migration、前端、部署、PR 合併 |

語義只有撤銷上述兩個 grantee 的表級 TRUNCATE，不是新的執行指令清單。不得自動拆 SQL、擴大撤權、補 DML、SET ROLE、GRANT membership 或提權。

## 2. 申請、責任與執行時段（全部待正式填寫）

| 欄位 | 待填內容 |
|---|---|
| 正式變更單／內部審查連結 | **[待填]** |
| 正式 Supabase 專案／環境非機密識別 | **[待填]** |
| 申請人／系統負責人 | **[待填]** |
| 階段 A 風險接受人 | **[待填]** |
| 正式操作者（姓名或內部識別，非密碼／金鑰） | **[待填]** |
| 操作者權限佐證、收集時間與連結 | **[待填]** |
| 執行前複核者／驗收人 | **[待填]** |
| 核准人及其核准依據 | **[待填]** |
| 預定開始／結束時間（臺灣時間 Asia/Taipei） | **[待填]**，不自行指定時段 |
| 允許的實際執行窗口／逾時停止條件 | **[待填]** |
| ACL／DDL 並行控制與負責人 | **[待填]** |
| 異常決策人、回報管道與可聯繫時段 | **[待填]**，Codex 不自行傳送訊息 |
| 未提交交易中止責任人 | **[待填]** |
| 已提交後回滾決策人／核准人／操作者 | **[待填]** |
| 階段 B 追蹤單、負責人與平台處理管道 | **[待填]**，不代表 B 核准 |

角色由正式治理流程指定；填寫名字不授予任何 DB 權限。

## 3. 最新基線與漂移紀錄

已有證據為**使用者提供的修正前基線**，不是本次重新查詢正式庫，也不替代執行時點的基線：

- owner `postgres`，RLS enabled=true／forced=false。
- `anon`／`authenticated` 的 TRUNCATE=true，直接 grantor=postgres，grantable=false；SELECT/INSERT/UPDATE/DELETE=false，其他原有權限不動。
- `postgres` 的 8 項表級有效權限原為 true，全部保留。
- `service_role` 的 SELECT/INSERT/UPDATE/DELETE **全部 false，仍須 false**；MAINTAIN/REFERENCES/TRIGGER/TRUNCATE 原為 true，全部保留。
- `membership_paths` 先前為空；若出現 PUBLIC／繼承／額外 grantor 或角色旗標漂移，不擴權、不擴大 REVOKE，停止並回審。
- 兩個 creator 的 public default ACL 仍含客戶端 TRUNCATE，A 不改它們。

| 基線／證據欄位 | 執行前必須填寫 |
|---|---|
| 歷史參考 | [metadata 基線 fixture](../tests/fixtures/truncate-baseline.json)；無個資或預約資料，只作比對參考 |
| 新基線收集者、收集時間、正式環境識別 | **[待填]**，只能由獲准的正式操作者另行收集 |
| 完整唯讀驗證 JSON 的保存位置／識別／校驗值 | **[待填]**，不可只保存兩個 checks |
| owner、RLS、完整 ACL／grant option、32 項權限布林值比對 | **[待填：一致／有漂移＋差異證據]** |
| default ACL 與維護權限基線保存位置 | **[待填]**，A 完成後必須完全相同 |
| 執行者預檢與真正 active role 是否一致 | **[待填]** |
| 漂移判定與複核簽認 | **[待填]** |
| 原 grantor／grant option 與回滾文字保存位置 | **[待填]** |

有漂移、環境不明、腳本版本不同、目標已被他人修改或證據不足時，**停止並退回審查**。不因腳本可重複執行就盲目重跑，不把其他權限「重設成舊基線」。

## 4. 審查版本與 SQL 核對

參考 SQL 版本來自 commit `0c3d8c6c66afa88a2aba580dcc7a5145feec701a`；本輪不改 SQL。核准只能涵蓋下列指定檔案與雜湊，不包含整個 PR／其他 migration。檔案若改變即須重新審查。

| 文件 | SHA-256（本輪已靜態核對） |
|---|---|
| [最小撤權 SQL](../sql/drafts/20261113_truncate_minimum.sql) | `2cffe00fab8d6366bf8fff8f3137a22babfd7810631cc7b9d7ae8c6d90bdedff` |
| [前後唯讀驗證 SQL](../sql/inspection/truncate_fix_verification.sql) | `4f8869c97eaae1bce71e5c14ffe4086c614d9c43d6815979de73b115818731a7` |
| [執行者唯讀預檢](../sql/inspection/truncate_executor_preflight.sql) | `faebbd5638ced3b2d190da06085842415fcf10a26d93abe48422fb041434e1bb` |
| [A 回滾草稿](../sql/rollback/20261113_restore_bookings_truncate.sql) | `4d204e5e26c888e12558f992f2611ada2190e2b9922d53f473076c0e73f2e681` |
| [歷史 metadata 基線](../tests/fixtures/truncate-baseline.json) | `d91cd5a7c24b7de1ebfd7c98ea3f06c75221ed6d06f98b066ddccdcc2fb638d0` |

核對結論：最小檔只撤銷目標 TRUNCATE、前後保護非目標 ACL／維護權限；唯讀檔不改資料、其 defaults 回滾文字只是輸出並非執行；A 回滾只恢復兩個目標、原 grantor postgres／無 GRANT OPTION，與已提供基線相符。**A 不使用唯讀輸出中的 defaults 回滾文字，也不執行 B 或其回滾。** 新基線如不同須先重新審查，不套用近似回滾。

## 5. 階段 B 與殘餘風險接受（必填）

目前 active 身分不是 superuser，對 supabase_admin 的 MEMBER／USAGE／SET／catalog candidate 均 false，**完整 B 受阻且未執行**。A 不會改善此權限條件，不能切出 postgres-only default 段，不能自行授予 supabase_admin。

若 A 未來獨立核准並完成，仍有兩個 creator 新建 public 表被預設給客戶端 TRUNCATE 的風險；B 日後完成也不回溯移除窗口中已建表的授權。其他既有表與非目標 privilege 仍不在 A 範圍。

| 風險接受欄位 | 必須明確填寫 |
|---|---|
| 是否接受「僅表級修正，defaults 未修」 | **[待填：接受／不接受及理由]** |
| 風險接受人／日期／佐證 | **[待填]** |
| 窗口中建表／DDL 控制或新物件 ACL 追蹤方案 | **[待填]**，不由 Codex 自行停服務／掃表撤權 |
| B 負責人、平台授權途徑與追蹤里程碑 | **[待填]**，不擅自訂期限或宣稱平台已同意 |
| 若不接受窗口或 B 無管道時的 A 決策 | **[待填：延後／退回審查等]** |

未明確接受風險窗口時，不把 A 當成已批准。B 須由專案管理者透過 Supabase 支援／平台確認受支援的操作者與管道，另行核准完整 B，不能以 A、PR 或本機測試代替。

## 6. 驗收標準與結果紀錄（目前全部未收集）

驗收以 metadata-only [唯讀驗證](../sql/inspection/truncate_fix_verification.sql) 及保存的新基線為準；不用正式 TRUNCATE、建立 canary、真實預約／取消或破壞性測試作驗收。

| 項目 | A 成功的預期 | 實際結果／證據／複核人 |
|---|---|---|
| `bookings_clients_cannot_truncate` | true，兩個客戶端有效 TRUNCATE=false | **[待填，未執行]** |
| 目標 ACL | 只少掉指定兩個 TRUNCATE，其餘 grantor／grantable／privilege 相同 | **[待填]** |
| postgres／service_role 全部有效權限 | 與新基線逐項相同 | **[待填]** |
| service_role SELECT/INSERT/UPDATE/DELETE | 四項仍 false；`service_role_bookings_dml_still_absent=true` | **[待填]** |
| owner／RLS／default ACL | 完全不變 | **[待填]** |
| `future_public_client_truncate_sources_absent` | 基線為 false，A 後仍 false；記錄 B 未修，不因它 false 而執行 B／自動回滾 A | **[待填]** |
| SQL 範圍、環境、操作者、時段與提交證據 | 符合核准，僅 A；不含資料操作或其他 DCL | **[待填]** |
| 最終狀態與接受人簽認 | 只能標「A 表級已修，B blocked／未修」，不能稱完整修復 | **[待填]** |

資料與庫存不變的設計依據為腳本只改目標 ACL、無業務 DML／RLS／約束變更，以及前輪本機回歸證據；不得為證明此點而自行查個資或操作真實預約。

## 7. 異常與回滾核准

- 未提交、SQL error、斷言失敗：正式操作者中止該次交易，必要時 ROLLBACK 並確認基線；不拆句、不改腳本自動重試。
- 提交狀態不明或驗收不符：停止新操作，保留證據，交異常決策人；先釐清是否已提交，不盲目重跑或直接 GRANT。
- 已提交後恢復 TRUNCATE 是**重新引入安全暴露**，須有明列條件的獨立／條件式回滾核准；普通 A 核准不包含它。
- B blocked／future check=false 是已知殘餘風險，不是自動回滾 A 的條件。B 未執行就不執行 B 的回滾 GRANT。
- 回滾須按新基線保留 grantor／grant option，由有權的正式操作者處理；目前 A 靜態回滾要求 active postgres／owner postgres。缺權即停止，不提權。

| 回滾控制欄位 | 待正式填寫 |
|---|---|
| 已提交後允許回滾的具體觸發條件 | **[待填]**，不能僅寫「任何失敗」 |
| 是否獨立／條件式核准 A 的恢復授權 | **[待填：核准／不核准／另案審查]** |
| 回滾決策人、核准人、實際操作者 | **[待填]** |
| 已審核的基線回滾文字／A 檔案版本 | **[待填]** |
| 回滾時段、停止條件及驗證責任 | **[待填]** |
| 回滾實際執行／驗證結果及風險再接受 | **[待填，未執行]** |

## 8. 正式核准區（本文件不是核准）

- A 變更決議：**[待填：核准／不核准／退回]**
- 核准範圍／指定 SQL 雜湊／正式環境：**[待填]**
- 操作者／窗口／基線有效條件：**[待填]**
- B 殘餘風險接受與追蹤責任已填：**[待填]**
- 已提交後回滾的獨立決議與條件：**[待填]**
- 核准人／日期／正式核准佐證：**[待填]**
- 複核人／日期／紀錄：**[待填]**

任一必要欄位未完成、文件／腳本變更、基線有漂移或核准已逾窗口，都不得推定可以執行。是否已正式核准只由指定治理程序與佐證判定，Codex 不代簽、不自動執行。

## 9. 集中連結

- [逐步執行前／驗收／異常清單](stage-a-execution-checklist.md)
- [最新正式執行限制與 B 平台途徑](truncate-execution-restrictions.md)
- [完整執行與回滾方案](truncate-execution-plan.md)
- [最後安全審查](truncate-final-safety-review.md)
- [前輪本機測試與本輪文件驗證報告](production-booking-test-results.md)
- [階段 A 最小撤權草稿](../sql/drafts/20261113_truncate_minimum.sql)
- [前後唯讀驗證](../sql/inspection/truncate_fix_verification.sql)／[執行者唯讀預檢](../sql/inspection/truncate_executor_preflight.sql)
- [僅 A 的危險回滾草稿](../sql/rollback/20261113_restore_bookings_truncate.sql)
