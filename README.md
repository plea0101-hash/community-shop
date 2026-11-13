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
