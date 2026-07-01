/* C — Remediate: stable-plan variant using OPTIMIZE FOR UNKNOWN.
   Human approval required before replacing production code.
*/
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_matches_summary_stable_example
    @maxPlayer BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT player_id, COUNT(*) AS matches_played, SUM(score) AS total_score
    FROM dbo.matches
    WHERE player_id <= @maxPlayer
    GROUP BY player_id
    ORDER BY total_score DESC
    OPTION (OPTIMIZE FOR (@maxPlayer UNKNOWN));
END
GO

PRINT 'Reference remediation created: dbo.usp_matches_summary_stable_example.';
PRINT 'Alternative fixes to discuss: Query Store plan forcing, targeted RECOMPILE, filtered stats, or query rewrite.';
GO
