# TRUNCATE 來源分析與最小權限修正（僅草稿）

## 已知證據與邊界

使用者的最新正式補查：bookings 的 anon/authenticated 有效 SELECT、INSERT、UPDATE=false，TRUNCATE=true。先前上傳的 table_grants 另列明兩個角色各有直接 TRUNCATE ACL。這可證明已有直接授權暴露，不足以排除同時存在的 PUBLIC、父角色、擁有權或其他來源；目前未取得最新 grantor、角色圖與 default ACL。**本工作沒有執行任何正式 SQL 或遠端探查。**

TRUNCATE 不透過 RLS，也不走一般逐列 DELETE policy。不能因 SELECT=false／RLS=true 就把該權限視為安全。直接 REVOKE 也不能消除另一個可繼承角色的授權；若角色為表擁有者或 superuser，更不能靠 REVOKE 普通 ACL 達成隔離。bypassrls 雖不等於取得 TRUNCATE，但表示不能依賴 RLS 的其他保護，應另外拒絕不安全客戶端角色。

## 只讀來源盤點

`sql/inspection/truncate_privilege_sources.sql` 是單一 metadata SELECT，預設只查 public.bookings：

- 每個客戶端的有效 TRUNCATE、角色旗標、owner 與 owner 繼承。
- ACL grantor/grantee，分直接／PUBLIC／其他角色，並以 pg_has_role(...,'USAGE') 標明是否無需 SET ROLE 即生效。
- 角色遞迴路徑、inherit_option、set_option；列出路徑不代表每條路徑都自動授權，以有效結果區分。
- 實際建立者的 global／public schema default ACL，辨識未來建表再次授權的來源。

不讀業務資料、Auth 使用者、金鑰、Vault、應用函式本文。這份查詢本次只在本機合成庫執行；留待使用者另行審查來源，不由代理連線正式庫執行。

## 最小修正提案

`sql/drafts/20261113_truncate_minimum.sql` 只撤銷 **public.bookings 的 TRUNCATE**，對象限已知直接角色與 PUBLIC。不授予 SELECT/DML，不改 RLS，不刪資料，不撤銷角色成員、不使用 CASCADE，也不全域 REVOKE ALL。其後驗證有效權限；若仍 true 或角色不安全，整份交易拒絕並回滾，不能把部分直接撤銷稱為修復完成。

若來源報告指出父角色仍授權，應另提「對該確定 grantee、只對 public.bookings 撤銷 TRUNCATE」的精確方案。若該角色共用，先確認其維護用途，不改整個角色繼承圖。若客戶端繼承表擁有權，需獨立檢討角色與擁有權，不能用 REVOKE 形式偽裝修好。

Default ACL 不會回溯修正現有表；現有表 REVOKE 也不會更改未來建表預設。須辨識實際 creator／grantee 與 global 或 per-schema 範圍後另提 ALTER DEFAULT PRIVILEGES 修正。**schema-specific REVOKE 無法抵銷 global default GRANT**；不應猜建立者、清空未知設定或自動改全域預設。此階段只提供來源證據查詢與方案，沒有執行 default ACL 修正。

完整 RPC 草稿包含新稽核表保護、直接 DML 收斂與必要 SELECT/RPC grants，範圍比本最小修正大；兩者不是同一個核准事項。即使最小 TRUNCATE 修好，也不代表會員／付款流程可啟用。完整草稿遇到繼承的預約／會員／稽核寫入或維護權限，仍會拒絕安裝。

## 本機測試證據

3 項獨立測試通過：

1. 直接與 PUBLIC ACL 來源被辨識；在 RLS 開啟、anon 無 SELECT 的本機庫，TRUNCATE 可成功而後 ROLLBACK 恢復合成資料；最小草稿修正後 TRUNCATE=false，原 REFERENCES 及 SELECT 權限不被改動。
2. 父角色仍給 TRUNCATE 時，顯示繼承路徑；最小草稿拒絕部分修正並回滾。
3. global 與 per-schema default ACL 都被列出；即使現有 bookings 修正，新的合成表仍會因原 default ACL 再次取得 TRUNCATE，證明需獨立處理未來授權。

實際正式來源、預設授權建立者與其他共享角色尚未檢視；不宣稱正式風險已修復。
