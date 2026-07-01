/* ==========================================================================
   G — Eval: confirm the linter's target anti-patterns are actually present
   --------------------------------------------------------------------------
   Purpose : A static, deterministic check that the known anti-patterns exist in
             dbo.usp_preflight_badexample, so the SLM lint demo is verifiable
             (the SLM should flag at least these). Read-only.
   Note    : Uses CHARINDEX (not LIKE) to avoid '%' being treated as a wildcard.
   ========================================================================== */
SET NOCOUNT ON;
GO

DECLARE @def nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_preflight_badexample'));

IF @def IS NULL
BEGIN
    SELECT 'FAIL: sample object dbo.usp_preflight_badexample missing (run 00_sample_bad_sql.sql)' AS eval_result;
    RETURN;
END

SELECT [rule], detected,
       CASE WHEN detected = 1 THEN 'PASS' ELSE 'CHECK' END AS status
FROM (VALUES
    ('L1 implicit conversion (@region NVARCHAR vs region VARCHAR)',
        CASE WHEN CHARINDEX(N'@region', @def) > 0
              AND CHARINDEX(N'NVARCHAR(16)', @def) > 0
              AND CHARINDEX(N'p.region = @region', @def) > 0 THEN 1 ELSE 0 END),
    ('L2 non-SARGable (YEAR on column)',
        CASE WHEN CHARINDEX(N'YEAR(m.played_at)', @def) > 0 THEN 1 ELSE 0 END),
    ('L3 leading-wildcard LIKE',
        CASE WHEN CHARINDEX(N'LIKE ''%''', @def) > 0 THEN 1 ELSE 0 END)
) AS checks([rule], detected);
GO

PRINT 'Cross-check with the plan-level signal (run after executing the proc once so a plan exists):';
PRINT 'EXEC dbo.usp_preflight_badexample @region = N''KR'', @since_year = 2020;  then re-run 01_collect_objects.sql section 2/3.';
GO
