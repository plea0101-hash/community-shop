# community-shop
鄰里好店－社區零售通路平台

## 預約取消系統（開發分支）

獨立介面：`cancellation/index.html`。尚未串接正式預約資料、套用 migration 或部署。

- [架構檢查與實作計畫](docs/cancellation-plan.md)
- [整合、待辦與測試說明](docs/cancellation-integration.md)
- [SQL migration 草稿（需確認後才執行）](sql/drafts/20261113_cancellation.sql)

單元／隔離資料庫測試：`npm ci --ignore-scripts && npm test`。
瀏覽器合成資料測試：`python3 tests/browser_smoke.py`（需 Playwright、Chromium）。
