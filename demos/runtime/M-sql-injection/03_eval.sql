/* M — Eval: detect vulnerable dynamic SQL pattern.
*/
SET NOCOUNT ON;
GO

DECLARE @definition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_search_players_unsafe'));

SELECT CASE
           WHEN @definition IS NULL THEN 'FAIL: vulnerable proc missing'
           WHEN @definition LIKE '%EXEC (@sql)%' AND @definition LIKE '%+ @name +%'
                THEN 'PASS: vulnerable concatenated dynamic SQL detected'
           ELSE 'CHECK: proc exists but expected pattern not detected'
       END AS eval_vulnerable_pattern;
GO
