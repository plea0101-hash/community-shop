# 測試結果（2026-11-13）

基底 main：68759ce99eeb85de4d4d96a65a26641b45a103a9。開發分支：feat/reservation-cancellation。

- `npm test`：15 項通過，0 失敗、0 跳過。含 8 項記憶體 PostgreSQL/PGlite 交易及 RLS 測試、4 項領域規則測試、3 項 API client 測試。
- `python3 tests/browser_smoke.py`：廠商、社區、管理員 3 組流程通過；零 JavaScript 執行錯誤，390px 手機寬度無頁面水平溢出。涵蓋登入、XSS 跳脫、臨時原因、颱風僅停課、取消、重新申請、對方通知/已讀、無法驗證仍待審、核驗豁免、歷史與查詢。
- SQL：雙方取消、無權者拒絕、禁止直接 DML、匿名角色拒絕、取消原因與開始後限制、原時段快照、重複送出去重、唯一庫存限制、釋出及新 pending 申請、社區僅限自身場地、通知、獨立管理員與追加查核歷史、不自動取消其他預約。
- 規則：恰好 24 小時列臨時，24 小時加 1 毫秒列一般；臺灣日期跨日；任一縣市停課有效；惡意來源拒絕；颱風待審/核驗排除、拒絕恢復原時間分類；沒有自動處罰。
- 瀏覽器攔截所有外部請求；全部使用合成資料，遠端 Supabase 寫入 0。SQL 只在記憶體 PGlite 執行，未套用遠端 migration。
- `index.html`、`config.js` 無修改；main 不變；未執行 Vercel 部署或環境設定更新。

## 尚未驗證或完成

正式 bookings 欄位與組織授權不可見，正式預約/付款/庫存整合尚未完成；不可宣稱已能取消正式預約。SQL 僅草稿，需取得 schema、完成映射與審查、明確核准後才能執行。未對正式預約做任何測試。

尚未進行真實 Supabase Auth/PostgREST 的完整登入寫入測試、真正 PostgreSQL 多連線競爭測試、正式官方公告人工核驗、email/SMS 外送、既有退款或雙方同意/核准流程。這些限制及啟用條件見 cancellation-integration.md。
