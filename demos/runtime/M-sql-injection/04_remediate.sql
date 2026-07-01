/* M — Remediate: safe parameterized search proc.
   Human approval required before replacing production code.
*/
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_search_players_safe_example
    @name NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT player_id, username, region
    FROM dbo.players
    WHERE username LIKE N'%' + @name + N'%';
END
GO

PRINT 'Reference remediation created: dbo.usp_search_players_safe_example.';
GO
