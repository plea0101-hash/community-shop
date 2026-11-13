# 正式 bookings 整合設計（依使用者提供的真實 schema 更新）

盤點日期：2026-11-13。來源為使用者提供的 `schema_inventory` 與後續正式唯讀補查契約，不是本機猜測或重新連線正式庫。未將上傳內容／個資／金鑰寫入測試資料。本階段只產生 SQL 草稿、文件及本機測試。

## 1. 已確認結構

| 實體 | 真實 schema 的證據 | 整合用途 |
|---|---|---|
| public.bookings | bigint identity id；created_at timestamptz；venue_id bigint FK venues；brand_id bigint FK brands；start_time/end_time timestamptz NOT NULL；status text NOT NULL | 唯一正式預約／占位來源 |
| public.venues | bigint id、community_id FK communities；status、capacity、fee 等 | 經場地找所屬社區。capacity 不視為可同時預約幾組廠商 |
| public.brands | bigint id；name/category/contact_*；status text NOT NULL | 廠商實體，不取聯絡電話／email 作為授權依據 |
| public.communities | bigint id；name/city/district/households；status text 可 NULL | 社區實體 |
| public.community_registrations | UUID id、owner_id UUID、申請名稱與狀態等，沒有 community_id FK | 申請人不直接等於已核准社區管理員；禁止以名稱或不同型別 id 猜測關聯 |
| public.platform_admins | user_id UUID FK auth.users | 沿用管理員名單，不新建 cs_admins |
| public.public_booking_calendar | bookings JOIN venues/communities/brands 的公開日曆 view，含狀態過濾 | 需確認其未遮蔽狀態條件，才可宣稱新預約／取消會正確反映日曆 |
| get_booked_slots / is_platform_admin | SECURITY DEFINER、固定 search_path 設定存在；本文省略 | 必須審查實際本文與 predicate，不能只看函式名稱就視為安全 |

共 7 個公開關聯、50 個欄位、17 個限制、7 個索引、10 個 RLS policy；此份 public 盤點沒有使用者 trigger。其他 schema、外部服務、排程與函式內動態 SQL 未包含，不能當作不存在。

## 2. 庫存與狀態的重要發現

- `bookings_valid_time` 已檢查 `end_time > start_time`。
- `bookings_no_overlap` 是已驗證、非延後檢查的 GiST exclusion constraint：相同 venue_id（=）且 `tstzrange(start_time,end_time,邊界)` 重疊（&&）時禁止插入；它的 predicate 僅涵蓋兩個 status。
- **後續補查已確認 active 狀態為 pending、confirmed，range 為 [)。** bookings、brands、communities 的 status 預設 pending，venues 預設 available；這些不再是測試假設。草稿配置已填入 active_states、create_state=pending、venue_state=available，並驗證真實 schema 的預設值及有效時間 CHECK；契約漂移則拒絕。會員／付款審查開關仍預設 false，資格與取消終態配置仍須明確審核。
- pending 只是初始狀態，**不代表品牌／社區已通過資格審核**。不以預設 pending 自動開放預約。
- bookings 沒有 status CHECK／enum（本次 17 個限制中只有其時間 CHECK）。普通文字欄位本身不會保證狀態機正確。新 RPC 不接受客戶端 status，僅採人工核准的工作流程配置；無法識別的舊狀態不允許以此取消。不新增猜測的全表狀態 CHECK 或更新歷史資料。
- 取消必須把同一筆 bookings 狀態轉為排他 predicate 之外的取消狀態，原始起訖不改；因此新申請可重新競爭該 range。絕不建立 cs_slots、cs_bookings 或另加庫存計數。
- `public_booking_calendar` 與 `get_booked_slots()` 是否也使用相同狀態集合尚待確認。排他約束是最後裁決，前端的空檔查詢不是鎖，也不代表一定申請成功。

## 3. 權限與現有風險

bookings RLS 目前只有平台管理員 ALL policy，沒有廠商／社區會員 policy。表級 ACL 中 anon/authenticated 沒有 SELECT/INSERT/UPDATE/DELETE，卻有 TRUNCATE、TRIGGER、REFERENCES、MAINTAIN。**TRUNCATE 不受 RLS 保護，不能因 anon 無 SELECT 就判定資料安全。** 後續補查確認 anon/authenticated 的 SELECT、INSERT、UPDATE 有效值 false，TRUNCATE true。先前 ACL 已列直接授權；是否另有 PUBLIC／父角色路徑、授權人及 default ACL 則仍未提供。本階段不查詢正式庫、不試做破壞性操作，詳細來源分析與最小修正見 [truncate-privilege-review.md](truncate-privilege-review.md)。

本 schema 沒有 brands／communities 對 Auth 使用者的正式會員關係。因此草稿提議增加 `booking_brand_members`／`booking_community_members`，只保存已經受信任審核的組織授權，普通使用者無讀寫或自助加入權限。若其他私有 schema 已有相應關係，正式版應改接既有來源，不能重複建立兩套會員權限。

草稿撤銷 bookings 的普通角色直接 DML／TRUNCATE 等權限，再授予 RLS 保護的 SELECT 與明列 RPC；另撤銷 brands/communities/venues 的 TRUNCATE、TRIGGER、REFERENCES、MAINTAIN。草稿最後會檢查角色繼承後的有效危險權限及 superuser/bypassrls，若仍存在則整份安裝交易失敗，不能把 REVOKE 直接授權誤當已完整收斂。不刪除既有管理員 RLS policy，也不改公開社區／場地的既有 SELECT 權限。這會使直接 DML 的管理後台必須改接核准入口，**執行前必須確認既有管理流程、付款回呼及服務角色權限**，不可直接上正式庫。

## 4. SQL 草稿與 RPC 契約

檔案：`sql/drafts/20261113_production_booking_rpcs.sql`。不是自動 migration 目錄；未執行於正式 Supabase。舊 `20261113_cancellation.sql` 已加註 SUPERSEDED，兩份不得一起套用。

| RPC | 受控行為 |
|---|---|
| booking_request(venue bigint, brand bigint, start timestamptz, end timestamptz, key uuid) | 僅授權品牌管理員建立新預約；資格／未來有效區間檢查；不接受自報身分或 status；由現有排他約束拒絕重疊 |
| booking_cancel(booking bigint, reason text, typhoon jsonb) | 僅雙方授權組織管理員；同時代表雙方時拒絕，以免誤記取消身分；鎖後重驗權限；保存快照、更新原 bookings、寫取消事件與對方通知 outbox，在同一交易提交 |
| booking_reapply(cancelled bigint, venue bigint, start timestamptz, end timestamptz, key uuid) | 僅原品牌的授權管理員；原預約須已取消且有稽核事件；呼叫同一私有建立流程，產生新 ID，保留原預約與取消歷史。社區不代替廠商同意或預訂 |
| booking_review_typhoon(event uuid, decision text, note text) | 既有 platform_admins 成員且非本案任一方；pending 保留待審，verified 列特殊取消，rejected 恢復原時間分類；每次追加查核歷史與雙方通知，不恢復預約、不改庫存 |

對外 booking_request／booking_reapply 回傳十進位文字 ID；呼叫端亦應以字串傳 bigint，避免 JavaScript Number 超過安全整數精度。

私有實作/helper 全部撤銷 PUBLIC/anon/authenticated EXECUTE，僅授予必要 RPC／RLS 查詢 helper。所有 SECURITY DEFINER 函式以空 search_path 與完整名稱存取表；須由受信任且有正式表權限的擁有者安裝，不提供 service_role 給瀏覽器。

### 工作流程配置不等於第二套庫存

`booking_workflow_config` 保存工作流程代碼與兩個審查開關。已確認 active_states=[pending,confirmed]、create_state=pending、venue_state=available，並用 CHECK 固定；brand_state/community_state 資格代碼及 cancelled_state 仍為 NULL，membership_reviewed/payment_reviewed 仍為 false，因此所有建立／取消／重新申請均預設拒絕。只有受信任 DB 管理流程可以配置。新增 restrictive SELECT guard，將既有 permissive policy 的 OR 結果再限縮至伺服器核驗的管理員／會員；不依賴未審查舊 policy 自行正確隔離。會員審查為 false 時，品牌／社區會員 helper 與 RLS 亦拒絕，不能只靠事先插入 can_manage=true 的會員資料就開放讀取；颱風查核 RPC 也先檢查啟用契約。不能只因建立會員資料或填入狀態就繞過會員／付款審查；測試才在一次性資料庫明確設為 true。執行時驗證實際排他約束的狀態 predicate、=／&& 操作符及 [) range 形式完全相符。這是防止錯誤啟用的契約檢查，**不是自動判斷品牌已核准、退款或上線核准**。

### 鎖與冪等性

先依 actor＋request_key 取得交易鎖，再依場地 ID 遞增鎖定相關 venues，最後鎖原 bookings；建立與取消採同一場地→預約順序。場地鎖粗粒度但可避免新 RPC 互相超賣，排他約束仍保護其他不採相同鎖順序的寫入路徑。重複 key＋相同請求回傳同 ID，不同 payload 拒絕；時間以 epoch 標準化避免 session 時區導致誤判。重複取消回原事件，不重發通知。舊取消但缺稽核時拒絕捏造歷史。

現有 service-role、其他 definer RPC、付款與核准入口必須另查是否遵守相同狀態前置條件，避免取消後又被回呼設成 confirmed。僅此草稿無法證明外部流程沒有該風險。

### 取消分類與通知

鎖後取伺服器時間計算精確差值：≤24 小時臨時、>24 一般，臨時原因必填；活動已開始時不允許此流程。颱風主張保留白名單欄位：官方來源、公告日、適用日、臺灣任一縣市、因颱風停班／停課類別，先 pending，人工核驗。verified 另列 `typhoon_special`；pending/verified 不計一般臨時取消次數，rejected 且原 timing=late 才計入；沒有自動處罰。

組織 outbox 與目前已授權會員的頁內通知同交易保存。即使目前沒有對方收件會員，組織事件仍為 pending，不把「找不到收件者」當成已通知。沒有外送 worker、email/SMS 或已送達保證。`booking_cancellation_classification` 使用 security_invoker view，統計不繞過事件表 RLS。

## 5. 尚需補齊，不可直接啟用

1. active 狀態、[) 邊界、時間 CHECK 及四表預設值已確認，不再重複索取。仍需審查品牌／社區資格狀態、取消終態與具體會員授權流程；來源查詢 `sql/inspection/truncate_privilege_sources.sql` 僅供之後由使用者自行檢閱／執行，不由本工作連線正式庫。
2. 提供經人工去識別化的 get_booked_slots、is_platform_admin 本文，以及其他 schema 是否已有組織會員；不需要 key 或真實使用者資料。`community_registrations.owner_id` 不能直接接 community bigint。
3. 確認未列在此公開 schema 的實際核准、付款、退款、排程及後台 DML 來源。草稿只建立待審／占位狀態，沒有核准／付款／退款 RPC；確認前不得因撤銷直接 DML 而中斷既有管理流程。
4. 社區重新申請目前採「由原廠商重新提出」；若要社區發邀請，另設不占位的邀請資料及廠商同意流程，不能直接建立已同意預約。
5. 會員配置、通知 worker、實際 Supabase Auth/PostgREST、付款回呼及 staging 驗證仍未完成。本機真正 PostgreSQL 多連線競爭已有 6 個場景通過；這不替代正式環境服務流程驗證。資料庫安裝、配置、舊 UI 改接新 RPC、部署分別需要後續確認，不能因本機測試通過就啟用。

## 6. 測試範圍

`tests/production-booking.test.js` 以收到的 bigint/FK/timestamptz/time CHECK／GiST 結構建立一次性 PGlite PostgreSQL，並使用 btree_gist；active=pending/confirmed、建立 pending、四表預設及 [) 已確認。所有身分、聯絡欄位及測試預約均合成。資格 approved、取消終態 cancelled、會員配置與審查開關 true 仍只是受控本機 fixture，不代表正式審查已完成。

新增涵蓋會員／付款未審的三種寫入拒絕、重複取消不改原原因且不釋放替代預約、取消中途 outbox 失敗整體回滾、預設值／CHECK 漂移拒絕、pending 不自動合格。`tests/truncate-privileges.test.js` 驗證直接／PUBLIC／繼承及全域／schema default ACL，並在可回滾的本機合成交易證明 RLS 不防護 TRUNCATE。

`tests/postgres_concurrency.py` 在固定官方映像 digest 的 PostgreSQL 17.12 容器，以獨立 psql 連線及 pg_blocking_pids 證明競爭等待，驗證六個場景：同時重疊預約、相同請求 key、雙方重複取消、建立回滾後另一方取得時段、取消回滾後仍占位、取消與重新申請競爭。容器 network=none、listen_addresses 空、無公開埠、資料在 tmpfs，結束移除；不連 Supabase。

完整結果見 [production-booking-test-results.md](production-booking-test-results.md)。未涵蓋正式 Supabase JWT／角色設定、實際核准與付款回呼、外送服務或高負載壓測。舊瀏覽器測試仍只覆蓋 cs_ UI 原型，前端未改接新 RPC。
