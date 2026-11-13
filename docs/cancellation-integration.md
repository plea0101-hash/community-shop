# 預約取消模組：整合與測試說明

## 現在可審查的成果

獨立入口 `/cancellation/`，不改動首頁及既有正式預約資料。提供 Supabase Auth 電子郵件/密碼登入、廠商/社區預約清單、原因及二次確認、取消紀錄、重新申請、頁內通知、管理員查核、取消頻率查詢。沒有前端角色選單授權；每個 RPC 在資料庫檢查 auth.uid()。

使用者已確認：**距開始 ≤24 小時為臨時取消，>24 小時為一般取消**。時計算使用伺服器時間，不以畫面四捨五入判斷；原活動時間與政策門檻會快照保存。臨時取消必填原因；一般取消原因可選填。活動已開始時禁止以此流程取消，後續補登／爭議流程尚未定義。

颱風：臺灣任一縣市政府正式公告因颱風停班或停課即具備事件條件，不受雙方所在地限制；仍由雙方個別決定是否取消，沒有批次自動取消。保存 HTTPS 政府官方來源、公告日、適用日、公告縣市及停班/停課類別。網址及欄位驗證不等於真實公告驗證，送件先待審；管理員人工查核後才列特殊取消。無法驗證可新增待審核查核紀錄；確認不符合才拒絕。核驗通過不計入一般臨時取消次數，待審核暫不計入，拒絕則依原時間分類。審核者不得是預約任一方，審核與通知保留歷史。沒有自動處罰、異常門檻、官方公告爬蟲或自動判真服務。

取消交易鎖定預約及時段、建立唯一取消紀錄、取消預約並通知另一方；重複送出不重複寫入。模組使用固定時段庫存，每時段僅能有一筆 pending/confirmed 預約，取消後釋出。沒有修改原日期的 RPC。重新申請建立新 pending 記錄、連結原取消預約並通知對方；社區僅能為自身時段提出新申請。pending 不是同意或付款確認，須接正式的雙方同意與審核流程才可 confirmed。

頁內通知在同一資料庫交易內持久保存，收件人可標記已讀；**沒有寄送 email/SMS**，也不將入庫視為外送或已讀。外部通知須另定傳送服務、重試與去重機制。

## Migration 草稿，尚未執行

[20261113_cancellation.sql](../sql/drafts/20261113_cancellation.sql) 僅放在 `sql/drafts/`，不是 Supabase 自動套用目錄。它新增 `cs_admins`、`cs_policy`、`cs_slots`、`cs_bookings`、`cs_cancellations`、`cs_typhoon_reviews`、`cs_notifications`、RLS、索引及 RPC，不刪除或更新既有 production 表。

**這不是已接上 public.bookings 的正式 migration。** 目前公開角色無權查看該表結構。`cs_bookings.source_booking_ref` 只是整合對照欄位，不是同步器。取消目前只釋出模組內 cs_slots 的庫存，尚無證據能釋出正式 public.bookings 所占時段。不得先匯入影子資料再把它視為正式取消完成。

執行或啟用前必須完成：

1. 提供去識別化 DDL（bookings、預約/付款/申請狀態、時段唯一性、會員/社區管理關係、現有 RLS/RPC），不用提供 secret key 或真實資料。
2. 決定保留既有 bookings 為唯一資料來源或遷移後以新表為主；不可讓兩套庫存並行。正式取消須在同一交易同步既有預約、申請及庫存，並驗證重複取消與並行重新申請。
3. 將社區/廠商組織會員關係對應到授權。本草稿使用兩位負責 Auth 使用者，尚未支援多人社區權限。管理員只能由受信任的後端/DB 管理者配置，瀏覽器不能自行指定。
4. 確認正式 Auth 登入政策（包含驗證信／MFA／captcha，若現有專案要求）、頁內通知是否已足夠，以及付款退款流程。本變更不退款、不變更付款資料。
5. 檢查既有場地時段重疊與固定 slot 的映射；不得把 starts_at 唯一性誤認為任意區間不重疊。新時段建立、核准、付款、跨時段重疊檢查不是本取消模組提供的 RPC。
6. 人工審查 SQL 草稿、以 staging 合成資料驗證實際 Supabase Auth/PostgREST，再取得明確確認才執行 migration。此 PR 不會執行 SQL、部署、改正式設定、合併或發送真實通知。

## 本機測試

```sh
cd /workspace/community-shop
npm ci --ignore-scripts --cache /tmp/community-shop-npm-cache
npm test
python3 tests/browser_smoke.py
```

Node 24、Python 3.12；瀏覽器測試使用環境現有 Python Playwright 與 `/usr/bin/chromium`。PostgreSQL 測試使用鎖定版本 PGlite（PostgreSQL WASM），在記憶體建構假的 auth schema 及合成使用者，驗證 SQL 可以執行、RLS、取消交易、重複請求、重新申請、通知與查核歷史；不連線 Supabase。這不取代正式 PostgreSQL 多連線競爭、Supabase Auth 整合或 migration 審查。

瀏覽器 smoke 啟動暫時本地伺服器並攔截全部外部請求；假 Supabase 僅回合成資料，沒有外部 API 寫入。測試完成自動關閉瀏覽器與伺服器。若 Chromium 另行存取真實 Supabase，必須修復代理 CA 信任，不應停用 TLS 驗證。

如需手動檢視，從專案目錄執行 `python3 -m http.server 8000 --bind 127.0.0.1`，瀏覽 `/cancellation/`。正式模組 schema 未啟用時登入後會提示尚未啟用，不會偷偷退回 localStorage 當作正式預約。

管理員查詢從 RLS 授權資料逐頁載入，時間篩選為臺灣取消日期。統計為此次載入快照，重新整理取得新資料；大量資料需後續伺服器端分頁/聚合，並行新增可能使分頁快照有差異。目前頻率為次數排名，不宣稱具有經確認的異常或處罰門檻。
