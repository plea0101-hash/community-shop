# community-shop
鄰里好店－社區零售通路平台

## 預約取消系統（開發分支）

獨立介面：`cancellation/index.html`。尚未串接正式預約資料、套用 migration 或部署。

- [架構檢查與實作計畫](docs/cancellation-plan.md)
- [整合、待辦與測試說明](docs/cancellation-integration.md)
- [SQL migration 草稿（需確認後才執行）](sql/drafts/20261113_cancellation.sql)

單元／隔離資料庫測試：`npm ci --ignore-scripts && npm test`。
瀏覽器合成資料測試：`python3 tests/browser_smoke.py`（需 Playwright、Chromium）。

## 正式 bookings SQL 整合草稿

依使用者提供 schema 設計，以 `public.bookings` 為唯一預約與庫存來源；原 cs_ 介面仍為原型，尚未改接。

- [正式結構、RPC 設計與啟用前提](docs/production-booking-integration-design.md)
- [正式 bookings RPC 草稿](sql/drafts/20261113_production_booking_rpcs.sql)（未執行，預設未配置即拒絕寫入）
- [補查被遮蔽的業務狀態與時段邊界](sql/inspection/booking_contract_details.sql)（唯讀）

舊 `20261113_cancellation.sql` 為已取代的獨立庫存原型，不得與新草稿一併套用。

確認後契約：`pending`／`confirmed` 使用同場地 `[)` 排他區間；四表預設狀態已納入漂移檢查。會員／付款審查開關預設 false，不因預設 `pending` 自動開放預約。

- [TRUNCATE 來源與最小修正方案](docs/truncate-privilege-review.md)
- [TRUNCATE 唯讀來源查詢](sql/inspection/truncate_privilege_sources.sql)
- [最小 TRUNCATE 修正草稿](sql/drafts/20261113_truncate_minimum.sql)（不得自行執行）
- [更新的測試報告與 PostgreSQL 並行測試重現方法](docs/production-booking-test-results.md)

`npm test` 執行 Node/PGlite；`npm run test:postgres` 使用一次性、無網路 PostgreSQL 17 容器進行真正多連線測試，需先取得報告中固定 digest 的官方映像。
