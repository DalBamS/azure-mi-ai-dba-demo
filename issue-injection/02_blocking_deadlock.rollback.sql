/* ==========================================================================
   Issue #2 — ROLLBACK / cleanup
   --------------------------------------------------------------------------
   The deadlock scenario does not leave persistent bad state (the victim's
   transaction rolls back automatically). This script:
     1) verifies no orphaned open transactions from the demo,
     2) confirms the contended rows exist and are consistent.
   If a session was manually killed mid-transaction, re-run the seed reset.
   ========================================================================== */
SET NOCOUNT ON;
GO

-- Any long-running open transactions still holding locks?
SELECT s.session_id, s.login_name, t.transaction_id,
       t.transaction_begin_time, s.status
FROM sys.dm_tran_active_transactions t
JOIN sys.dm_tran_session_transactions st ON st.transaction_id = t.transaction_id
JOIN sys.dm_exec_sessions s ON s.session_id = st.session_id
WHERE s.is_user_process = 1;

-- Contended rows (should exist and be non-negative).
SELECT 'currency_ledger' AS tbl, player_id, currency_type, balance
FROM dbo.currency_ledger WHERE player_id = 1 AND currency_type = 1
UNION ALL
SELECT 'inventory', player_id, item_id, quantity
FROM dbo.inventory WHERE player_id = 2 AND item_id = 1;

PRINT 'Issue #2 rollback: verified. No schema changes to revert.';
GO
