# 正式 bookings SQL 草稿測試結果（契約確認後更新）

日期：2026-11-13。所有測試僅在本機合成環境執行。

## 結果

- `npm test`：**33 通過、0 失敗、0 跳過**。15 項正式 bookings 測試、3 項 TRUNCATE 來源／最小修正測試，以及保留的 15 項原型／領域／API 測試。
- `npm run test:postgres`：**6 個真正多連線競爭場景全部通過**；另驗證未配置 RPC 拒絕與 anon/authenticated TRUNCATE 拒絕。實測 PostgreSQL **17.12 (Debian 17.12-1.pgdg12+1)**，非 PGlite 的模擬並行。
- `git diff --check`：通過。首頁、config.js 與 cancellation/ 前端未變；沒有正式 SQL、部署或合併。

## 已確認契約與本機 fixture 的區別

已確認並納入 SQL 配置與漂移檢查：active=pending/confirmed、[)、end_time>start_time、bookings/brands/communities 預設 pending、venues 預設 available。這些不再列為未知值。

所有身分、聯絡欄位、預約、來源網址與事件均合成。品牌／社區資格 approved、取消終態 cancelled、會員與付款審查 true 是**僅供本機測試的顯式配置**；不代表正式授權或付款流程已核准。草稿預設兩個審查開關 false，資格／取消終態未配置，不會自動開放。

## Node／PGlite 重點

- 契約缺漏、預設／時間 CHECK／range 漂移時拒絕；pending 不被當成資格核准。
- 會員或付款尚未審查時，建立、取消、重新申請都拒絕，沒有副作用；會員未審查時亦不能僅憑事先插入的會員資料經 RLS 讀取預約。
- 禁止直接 DML、TRUNCATE、私有 helper 呼叫；陌生人隔離；管理員不冒名代取消。
- 真正 btree_gist/GiST 排他約束的部分／包含重疊拒絕，相鄰／異場地允許；取消後可用原時段建立新 ID。
- 重複請求、時區標準化、重複取消保留原 actor／reason；重複取消舊預約不會取消後來的新預約。
- 取消已更新狀態後，故意讓 outbox 觸發器失敗：原狀態、稽核、通知、outbox 全部回滾。
- 24 小時微秒邊界、原因、開始後拒絕；颱風待審／核驗／拒絕的歷史、統計與 RLS。
- TRUNCATE 直接／PUBLIC／繼承來源與 global／schema default ACL；最小修正保留其他權限；未清除繼承來源則拒絕部分修正。
- 完整草稿遇到繼承寫入權限時安裝失敗並回滾，不留下半套 schema。

## PostgreSQL 17 真正並行證據

每個場景使用兩個獨立 psql 連線，holder 保持開啟交易，觀察 pg_blocking_pids 確認 contender **實際被另一連線阻擋**後，才提交或回滾 holder：

1. 重疊預約：首筆提交後，另一筆由 bookings_no_overlap 拒絕，最後只有一筆。
2. 相同 request_key：並行重試回傳同 ID，只有一筆請求紀錄。
3. 雙方同時取消：同一取消 ID、一筆稽核、一筆 outbox 與對方通知；原 range 可重用。
4. 建立回滾：等待者取得時段，回滾者無請求 ledger 殘留或重複 outbox。
5. 取消回滾：原 pending 與占位保留；等待的衝突申請被拒，取消事件／outbox 不存在。
6. 取消與重新申請競爭：取消提交後建立新 ID，新 pending／舊 cancelled 與稽核同時正確保留。

PostgreSQL sequence 可能正常跳號；測試保證資料與庫存一致，不要求序號回滾或連號。

## 重現與隔離

```sh
npm test
# 先從官方 registry 取得固定 digest，保留 TLS 驗證：
docker --host=unix:///var/run/docker.sock pull postgres@sha256:40865bc877a289da75963d97d72b59633f639fc5af7a4e856bfa3714cae5b536
npm run test:postgres
```

需 Docker 與 Python 3。腳本固定本機 Unix daemon，清除 endpoint/context/TLS 選擇器，避免誤連其他 daemon；保留 Docker registry 設定。使用 --pull=never、network=none、listen_addresses 空、不公開埠、不掛載專案或任何憑證、資料在 tmpfs。僅透過 docker exec 的 Unix socket psql 注入合成 fixture 與草稿；finally 移除該腳本建立的唯一容器。實測清理成功，不影響其他容器或正式服務。

## 尚未完成的正式驗證

未連 Supabase，也未取得新的正式 ACL grantor／繼承圖／default ACL 來源；不宣稱正式 TRUNCATE 已修復。未測正式 JWT/PostgREST、會員核准來源、付款／退款／核准回呼、通知外送、staging 安裝及高負載壓測。前端仍為 cs_ 原型，未改接新 RPC。這些須審查後另行實作／驗證，不因本次本機並行通過就解除啟用限制。
