# 正式 bookings SQL 草稿測試結果

日期：2026-11-13。命令：`npm test`。

結果：26 項通過、0 失敗、0 跳過；其中 11 項為新增的 `tests/production-booking.test.js`，其餘 15 項保留原型／領域／API 測試。

## 新增驗證

1. 狀態契約未配置時拒絕寫入；配置與現有排他 predicate 不符時拒絕。
2. booking_request 只寫 public.bookings；key 重放回同 ID、不同 payload 拒絕；時區變更不影響重放；禁止直接 UPDATE、TRUNCATE 及呼叫私有實作。
3. 真正 btree_gist／GiST exclusion constraint 拒絕同場地部分重疊、完全包含、內含；[) 相鄰及異場地通過；無效區間拒絕。沒有用 JavaScript 模擬 constraint。
4. 更新原 bookings 為取消後，原 range 重新可申請；新 ID／原始取消事件都保留；不得直接改期；重複重新申請不重複占位。
5. 廠商與社區組織管理員可取消；陌生人與僅平台管理員不可冒名；RLS 隔離其他預約與取消紀錄。
6. 伺服器函式驗證恰好 24 小時為臨時、24 小時加一微秒為一般；臨時原因必填，開始後拒絕。
7. 任一臺灣縣市因颱風停課可主張；保留 pending／verified 查核歷史，不自動取消其他預約，查核不恢復庫存。
8. 對方暫無收件會員，仍保存 pending 組織 outbox；衝突失敗不留下新預約。
9. pending／verified 不計一般臨時取消，rejected 恢復原 timing；security_invoker view 不繞過 RLS。
10. 補查 SQL 在 READ ONLY 本機交易內執行，沒有讀取業務資料；有效 anon TRUNCATE 權限在套用本機草稿後為 false。
11. 另一個全新本機實例模擬 authenticated 繼承 INSERT 權限：草稿拒絕安裝，ROLLBACK 後新配置表不存在、原權限保持，沒有半套安裝。

## 證據範圍

只在 PGlite 記憶體 PostgreSQL 測試，沒有連線正式 Supabase，也沒有使用真實預約或個資。fixture 使用收到的 bigint、FK、timestamptz、有效時間 CHECK、排他結構，但被遮蔽的狀態常數與區間邊界明確採合成假設 pending/confirmed/cancelled 與 [)。尚待唯讀補查取得真實值，不能將 fixture 當成正式值。

未進行真正 PostgreSQL 多連線等待／死結測試、Supabase Auth/PostgREST 寫入、實際角色繼承盤點、付款／核准回呼競爭、staging 安裝、外部通知投遞。前端仍接舊 cs_ 原型，本階段不宣稱新 RPC 已串上前端或可正式啟用。

正式資料庫、main、index.html、config.js 與 cancellation/ 程式碼未變；沒有執行正式 migration、部署或寄出通知。SQL 僅草稿，需使用者確認後才可進一步處理。
