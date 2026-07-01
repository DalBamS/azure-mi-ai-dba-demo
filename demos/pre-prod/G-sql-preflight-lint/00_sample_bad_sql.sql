/* ==========================================================================
   G — Sample: deliberately anti-pattern SQL for the pre-flight linter to catch
   --------------------------------------------------------------------------
   Purpose : Give the SLM linter (03_run_slm_lint.md) and 04_eval.sql a known
             "bad" object so the demo is repeatable. Every anti-pattern here is
             intentional and documented.
   Safety  : Isolated demo object. Remove with 05_rollback.sql.
   WARNING : Do NOT ship this pattern to production.
   ========================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_preflight_badexample
    @region     NVARCHAR(16),   -- NOTE: players.region is VARCHAR(16) -> implicit conversion
    @since_year INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.player_id, p.username, p.region, COUNT(m.match_id) AS matches
    FROM dbo.players AS p
    LEFT JOIN dbo.matches AS m ON m.player_id = p.player_id
    WHERE
        -- anti-pattern 1: implicit conversion. @region (NVARCHAR) vs region (VARCHAR)
        --                 forces CONVERT_IMPLICIT on the column -> non-SARGable.
        p.region = @region
        -- anti-pattern 2: non-SARGable. Function on the column (YEAR(...)) prevents
        --                 index seeks on matches.played_at.
        AND YEAR(m.played_at) >= @since_year
        -- anti-pattern 3: leading-wildcard LIKE -> guaranteed scan.
        AND p.username LIKE '%' + @region + '%'
    GROUP BY p.player_id, p.username, p.region
    ORDER BY matches DESC;
END
GO

PRINT 'G sample created: dbo.usp_preflight_badexample (3 intentional anti-patterns).';
GO
