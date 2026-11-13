# 11/13 需求差異、現況及資料模型盤點

本輪輸出限分析／規格／計畫，未改應用、SQL 或正式 Supabase，也未自行簽認。已確認規則見 [商業規格](business-rules-2026-11-13.md)，實作順序／測試／回滾／商用門檻見 [實作計畫](implementation-plan-2026-11-13.md)。

## 1. 證據與可判斷範圍

- GitHub main=`68759ce`，Draft PR 的審查起點 head=`52e5084`，分支 `feat/reservation-cancellation`。讀取 PR 的 open/draft 狀態、說明與分支 metadata，未合併。另有 patch-1 舊分支，未發現新於本需求的上午規格文件。
- repository 主站只有 index.html/config.js/README；PR 新增 cancellation/ 原型、SQL 草稿、測試及文件，沒有可證實的公司／分店／清算後端。
- 使用者提供的正式 public schema：6 張表＋1 個 view，50 欄、17 限制、7 索引、10 RLS policy；以及後續正式業務／ACL／執行者補查。**本輪未對正式 Supabase 執行 SQL 或 Data API，不能把舊 metadata 當作即時全面盤點。** 其他私有 schema／外部後端與 definer 本文未取得。
- 表：bookings、brands、communities、community_registrations、platform_admins、venues；view：public_booking_calendar。get_booked_slots/is_platform_admin 的本文未提供。
- 前輪 40 項本機測試與 PostgreSQL 17.12 的 6 個並行場景有紀錄；不是正式實測，也不包含這輪收費、分店、隱私及發布限制新需求。本輪只靜態讀取測試內容，不重跑。
- 未在 repository 找到 30% 實作或完整上午確認規格；「取代 30%」是使用者決策變更，不虛構既有計算模組。

## 2. 完成程度（不以表存在等同功能完成）

### 已完成的有限範圍

- 程式碼／已提供正式 metadata／PR／歷史測試的比對及本輪需求文件。
- 既有正式 bookings 的時間有效 CHECK、pending/confirmed 的同場地 [) 排他約束有 metadata 證據，前輪本機亦測到真正 GiST 機制。這是庫存基礎，不等於完整預約產品。
- 已有單人階段 A 申請／清單與 SQL 草稿的審查備件；未核准未執行，權限風險沒有修復。

### 各功能判定

| 功能 | 狀態 | 可證實內容／商用缺口 |
|---|---|---|
| 社區／場地基本瀏覽 | 部分完成 | 主站 GET 已核准 communities 與 available venues；沒有公開檔期資格檢查，精確戶數仍顯示 |
| 地區／場地篩選 | 部分完成 | 前端有篩選；目前沒有戶數篩選／排序，符合該項禁止，但缺 API 層防漏與完整新搜尋條件 |
| 社區申請 | 部分完成 | 真實表有 owner_id、name/city/district/households/status；有「讀自己／建自己」RLS 與指定欄 INSERT grants。主站沒有完整正式申請頁／提交流程證據 |
| 社區資格／審查發布 | 部分完成／未驗證完整 | 有 approved 社區資料條件與管理員 RLS，沒有公開檔期實體／正式發布流程。管理員 UPDATE policy 不等於有 UPDATE grant 或已可操作的審查 RPC |
| 廠商註冊／公司唯一性 | 尚未完成 | 只有舊本機表單的 8 位 taxid 格式檢查；沒有公司／統編唯一約束、公司主帳號或身份驗證流程 |
| 品牌管理 | 部分完成 | brands 只保存名稱／類別／聯絡欄位／status，不能代表公司／分店或授權已完成 |
| 總公司／分店／負責人交接 | 尚未完成 | public schema 無這些模型與權限；原型的 brand membership 草稿不足以支援新組織關係 |
| 正式登入／業務授權 | 部分完成 | cancellation/ 有 Auth 登入 client，頁面角色由資料決定；公司與社區會員配置未完成，實際 JWT/PostgREST 新流程未驗證 |
| 檔期發布／空檔申請 | 尚未完整完成 | available() 永遠 false，apply/admin 導覽停用。不能由場地 available 或日曆顯示推定可預約 |
| 進駐核准／品牌＋實際分店 | 尚未完成 | bookings 只有 brand_id/venue_id/start_time/end_time/status 等 7 欄，無 branch；沒有正式社區核准 RPC |
| 取消／重申請／颱風查核 | 部分完成（草稿與原型） | 有正式表 RPC 草稿與本機保護，但未套正式庫；前端仍接已取代的 cs_ 原型，與正式 bookings 不通 |
| 10%／最低100／免費例外 | 尚未完成 | venues.fee 不等於收費引擎；無平台應收、政策版本或每筆費用快照 |
| 人工／12小時自動完成 | 尚未完成 | bookings現有7欄無completed_at或認定方式；沒有已證實的完成worker、爭議／異常阻擋與完成稽核流程 |
| 線下付款／週結／人工對帳 | 尚未完成 | 舊 pay() 只是 localStorage 模擬，無帳單、完成認定、收款／爭議或週結流程 |
| >15 天限制新發布 | 尚未完成 | 無應收期限、發布 gate、清償恢復規則；不能以停帳／取消活動代替 |
| 戶數區間／私密地址聯絡資訊 | 衝突＋尚未完成 | 目前直接取／顯示 households；無核准後授權取詳細資訊的完整模型／端點 |
| 信用、違規申訴與營運通知 | 部分原型／尚未完成商用 | 有取消統計與頁內通知草稿；未有正式信用判定、申訴、帳款通知／送達 worker |
| 上午設備／資格的完整一致性 | 待確認 | location_type/capacity/has_power 等存在，但不能證明完整設備／資格規則已實作 |

單人專案治理只代表平台開發／營運責任由本人兼任，不表示所有社區／公司／分店的業務帳號是同一人，也不取消租戶授權隔離。

## 3. 主要差異與衝突

| 新規則 | 現況／衝突證據 | 所需調整（本輪不實作） |
|---|---|---|
| 10%／逐筆最低100，免費0 | 源碼沒有費率／清算；首頁只寫「共享進駐收入」 | 新政策、逐筆快照、完成事件、帳單與收款；不假裝替換已存在的30%引擎 |
| 社區人工／滿12小時自動完成、completed_at歸週 | 現有正式表無完成欄位／工作程序，不能將end_time當認定 | 授權人工入口、自動工作、取消／爭議／異常原子檢查及完成稽核；週五09:00結算、下週二23:59前付款；每案防重 |
| 初期平台不處理金流 | 原型 approve→pay→confirmed；畫面有模擬付款 | 核准與線下付款分開，移除線上付款才生效的假設；線下例外未審仍不啟用舊付款 gate |
| 統一「廠商申請」 | 主站 nav「進駐申請」、標題「廠商進駐申請」且入口停用 | 統一前台入口、另作公司 onboarding；後台進駐作業不冒充公司註冊 |
| 公司／總部／分店 | taxid 只本機且無唯一性；正式 brands 連 tax_id 都沒有 | 法律公司、登入者、品牌、分店分離；統編與主帳號併發唯一；各項授權審核 |
| 申請必填品牌＋實際分店 | booking_request 目前只收 venue/brand/time/key | 新參與分店及公司關係驗證、歷史缺失標記，不能把總公司自動補為舊案分店 |
| 僅核准且公開檔期可被搜尋 | loadPublicData 僅社區 approved／場地 available | 新供給視窗／發布流程，搜尋需存在可公開檔期；public_calendar 是活動 view，不能當招商供給 |
| 精確戶數不公開 | communityCard 顯示 c.households，loadPublicData 直接 SELECT households；已提供 ACL 允許 anon 讀 communities | 伺服器回傳區間、不回 raw；單改畫面不夠。公開 API 投影／原表權限須另提審查及切換順序 |
| 詳址／聯絡僅核准後給授權對象 | communities/venues 沒詳址／社區聯絡欄位；brands 有聯絡資料但非社區詳情 | 私密欄位分離、核准狀態與公司／分店授權聯查、不可裸給所有 authenticated |
| 社區決定核准／費用 | 主站後台封鎖、調費只是本機；正式草稿只新建 pending，無核准入口 | 正式社區管理權、核准 RPC、價格版本／快照；與平台資格審查分開 |
| 逾期限制僅新發布 | 無對帳／發布實體 | 只在新發布入口作伺服器驗證，不以一般帳號停權／取消既有 confirmed 取代 |
| 當日全臺颱風機制 | 草稿已有任一縣市／日期核驗／pending；無當日事件總覽與正式接線 | 共用官方事件與取消查核流程；補跨日等邊界確認，不批次取消或猜處罰 |
| 取消／退款／賠償例外 | 既有文件明列付款／退款未定，沒有已確認退款公式 | 保留 24h、取消釋放與重申請；例外待確認，平台不自動處理賠償／退款 |

## 4. 真實資料結構與必須變更的模型（概念方案，非 migration）

下表為「若實作這輪需求必需處理的資料能力」，名稱／欄位為設計候選，不代表已核准 schema；不可直接執行或推測有同名正式表。既有 bigint／UUID 型別保留，新 FK 須按原型別精確映射。若其他私有 schema／外部系統已有權威公司、會員、帳本或審核能力，先取得去識別化契約並評估復用，不直接再造第二套來源。

| 既有表／能力 | 已知欄位與限制 | 必需處理／候選變更 |
|---|---|---|
| communities | bigint id、name/city/district/households/status 等；精確戶數可被既有公開查詢讀取 | 保留精確值在受控來源；公開投影只給區間與核准／發布後的最小欄位；不提供戶數 sort/filter |
| community_registrations | UUID id/owner_id，申請欄位與審核 status；沒有已核准 community_id 關聯 | 審查紀錄與 bigint 社區的可信映射（如 approved_community_id）；不按名稱或 UUID↔bigint 猜配；精確戶數／私密申請資料不公開 |
| brands | bigint id、name/category/contact_*、status | 保留品牌實體。以品牌授權關聯接公司／分店；單一 owner 或加盟多方模型待 Q-BRAND，不硬綁公司主帳號 |
| venues | bigint id、community_id、name/location_type/capacity/has_power/fee/status | 費用非負及版本／快照方案；保留設備資訊，不用 available 代替發布，不猜上午設備規則 |
| bookings | bigint id、venue_id/brand_id、timestamptz 起訖、status 等7欄；pending/confirmed [) 排他 | 新增實際 branch 關聯與申請主體／追溯資訊，或以1:1參與表承載；新案必填並由 RPC 驗證，舊案明標缺失不造資料；不另建占位表、不直接改期 |
| platform_admins | user_id、created_at；管理員身分 | 沿用平台審查／信用／財務管理來源，非租戶組織管理權，不因本人是平台負責人就讓客戶自我授權 |
| public_booking_calendar / get_booked_slots | 公開活動 view／definer RPC，本文與部分條件未完整取得 | 審查狀態與公開欄位；空檔計算仍覆蓋 pending/confirmed，不能漏掉 pending；不能洩漏精確戶數／聯絡資料 |

新增能力候選：

| 能力／候選實體 | 關鍵資料與約束 |
|---|---|
| companies / company_applications | 正規化統編 UNIQUE、申請人、驗證狀態、可信主帳號；伺服器並行查重＋DB唯一約束，不能只靠UI |
| branches / company_members / branch_members | 法律公司與實際營運分店、有效成員／角色／範圍、加入申請與總部同意；單一權威成員來源 |
| brand_authorizations／可選 company_affiliations | 品牌可用範圍；跨不同統編的母子公司／加盟授權先確認，不讓 affiliation 繞過各統編申請 |
| organization_audit_events | actor、伺服器時間、主體、動作、前後差異／理由、關聯授權紀錄；交接不得靠永久 JWT 舊權限 |
| community_members / registration_review_events | 社區主體到管理員的可信授權、核准／退回、操作紀錄；現有申請 owner 不自動等於社區管理權 |
| venue_availability_windows | 場地、開放起訖、發布狀態／時間／決定者；是供給規則，**不是第二套庫存或 booking holds** |
| community_private_profiles | 詳細地址／聯絡資料最小集合、查閱授權／稽核；不放公開 projection，具體欄位依上午規格及隱私需求確認 |
| booking_terms / booking_fulfillments | 原約定場地費、費率／政策版本、公司／品牌／實際分店、completed_at、認定方式、操作人／系統來源與操作紀錄、取消／爭議／異常阻擋。不可用 mutable venues.fee 回算舊帳，或只用 end_time 代替完成 |
| fee_policy_versions / statement_lines / community_statements | 逐案10%／最低100／免費例外、週期、應收／due_at、每案去重與調整追溯；每筆服務費無條件進位至整數元已確認；上一完整週一至週日（Asia/Taipei）已確認；completed_at歸週、週五09:00及下週二23:59前付款已確認；基數為核准時雙方確認場地費、平台費含稅不另加5%已確認；稅務開票、生效點、完成後例外與補跑仍待確認 |
| platform_fee_receipts / allocations | 社區向平台的線下付款、人工確認、分配到應收與餘額；不代收廠商場地費、不自動退款 |
| publishing_eligibility（可即時計算） | 由應收餘額／期限導出只擋新發布的結果；若快取，非第二本帳，須可重建與有稽核 |
| cancellation／typhoon／credit／notification | 優先修訂既有正式 bookings 附屬草稿，不另起 cs_ 庫存；事件／判定／申訴／對方與帳款通知，送達不等於入庫 |

### 不得暗中改寫的歷史資料

舊 bookings 沒有分店、約定費、政策與完成快照。新案可要求完整欄位，舊案只標示待人工對應／資訊不足；不能預設一個分店、偽造完成、以新費率回收歷史案件或刪除無法映射資料。任何既有資料映射／回填另提去識別化計畫與可回復方案。

## 5. 既有測試／安全證據能證明甚麼

- 可支持：草稿的 RLS／RPC 權限、24h邊界、重複請求、取消／新案、GiST重疊、交易回滾、精確 ACL 保留；真正 PostgreSQL 的6個並行場景。
- 不能支持：公司統編唯一／總部分店、線下收款、10%逐筆最低、週結／下週二、15天發布限制、戶數API隱私、地址授權或上午完整資格。新測試須另設，不能把40通過視為新商規已完成。
- 階段 A 仍只申請文件，未核准未執行；B 明確被 supabase_admin 權限阻擋。service_role 對 bookings 的四個讀寫權限仍 false，不為新業務補 ALL。所有新權限／RLS／definer 先走計畫與測試，不自動套用。

## 6. 需確認後才能定稿的部分

[商業規格第6節](business-rules-2026-11-13.md) 的 Q 項為待決清單，尤其上午原文、付款時間證據與截止分鐘比較細節、異常處理及完成後更正／退款／付款例外、公司／分店跨統編關係、私密資料授權及區間端點。新提供的規則以外，不在本輪自訂處罰／賠償／期限或放寬既有安全限制。

## 7. 會員與費用最新差異

[會員盤點](membership-application-review-2026-11-13.md)列實際入口／Auth／RLS證據、缺漏、資料分層與畫面流程。新確認但尚未實作：每社區唯一正式管理員、三天交接與爭議凍結、公司商業登記自動查驗＋代表權驗證、欠款平台審核／限制與解限。既有booking_community_members草稿允許多成員，缺唯一管理員及凍結／任期，不可直接當正式模型啟用。

基數由未定改為核准時雙方確認最終費，平台費含稅不另加5%；申請前揭露、收款變動不改基數。正常完成未付款仍計費，正式爭議暫緩；社區欠款回報須平台確認才限制廠商新申請，不能取消既有活動。原模擬付款流程與新制仍衝突，沒有因文件更新而修復。所需收款／爭議／限制／交接／代表權資料均為候選附屬模型，不取代community_registrations或唯一public.bookings。

會員盤點前輪估算50–75專注人日，原39–60當時被取代；本輪營運／年度需求後最新66–100。資料必填、佐證與核驗、三天起算／異議、稅務開票、退款／付款證據等仍待確認，沒有SQL／正式權限變更。

## 8. 社區證明文件與草稿缺口

已確認可存草稿，正式送審需組織身分與申請人授權兩證明；同檔可雙引用分別審核。現有8欄community_registrations及grants不證明草稿補件／上傳、私人Storage或文件審核已可用；缺申請附件與兩資格引用／版本／審核紀錄，以及說明／範例／FAQ／客服。需先設計相容擴充，復用原申請來源。

[詳細文件上傳設計](community-document-upload-design.md)補私人儲存、檔案檢查與個資防漏測試，例示文件不代表唯一標準。具體格式容量、佐證充分性、其他欄位必填、客服與保存政策仍未定；本輪未查核正式Storage或更動任何設定。

## 9. 營運參數版本與年度驗證缺口

目前只能證實未套用booking_workflow_config安全gate與cs_policy取消原型；沒有可用營運設定頁、分域政策版本／生效／撤回／回復、影響預覽、年度案件／提醒／補件與任期並行。不能將文件或原型參數等同已存在後台，更不能把安全gate變成可關閉的營運參數。

新增候選資料能力：policy_versions／change_events／confirmations、生效區間、已核准booking費用快照與policy_version、批次執行政策／期限快照；community_revalidation_cases關聯社區／管理任期、週期版本、聲明、文件版本、查驗分類與決定、觸發事件／通知outbox。復用既有申請／私人文件／單一bookings，實際schema/RPC/RLS另提，不產SQL。

[整合設計](operating-policy-revalidation-design.md)已涵蓋兩份指令，主任委員異動即時重驗補明列。12個月及系統初檢／人工複核已確認；正常無異常進低風險快速審核，最終正式通過仍未定；提醒已確認為Asia/Taipei前30／14／1天及當天，正式完成停該次後續提醒；一般逾期限制新發布／新核准、保留既有活動／必要聯絡與補件／提交／進度，正式通過恢復年度原因限制。通道／重試、具體到期／發送時刻與特殊風險另待定（首次／每次正式核准日起算及2/29例外已確認），不再列提醒節點及一般逾期矩陣為待決。政策版本防回算、交接任期防越權、通知重試／稽核與12個月候選邊界測試已規劃，並無執行證據。

新需求估算增16–25人日至66–100，取代50–75作現行總估算；權限漂移／原A未修與B受阻風險保留，不將文件更新當正式修復或人工風險接受。

本次相對9b33258僅細化既有年度／通知設計：缺的實作仍包括伺服器到期發布／核准檢查、分原因解除限制、四節點提醒去重／正式完成後停止及低風險分類。未改任何權限或正式排程。未擴張業務模組，估算評估維持66–100；全部測試仍是後續規劃，不是已執行／通過證據。

本次以911ef0b補核准日期與週期規則：首次正式管理資格核准日起算、每次正式重驗核准日重設12個月，2/29次年無該日則2/28到期；非正式核准動作不改日期。缺的實作仍含可信核准／到期紀錄、週期前後關聯、核准證據／文件版本、取消舊週期未發提醒與安排新週期的一致處理／重試防重。日期案例與待實作測試見營運設計及計畫，未把它們當已完成功能。具體時間、證據標準、特殊風險、歷史缺核准日期仍待確認；既有單一bookings庫存與費用快照不變，維持66–100估算。
