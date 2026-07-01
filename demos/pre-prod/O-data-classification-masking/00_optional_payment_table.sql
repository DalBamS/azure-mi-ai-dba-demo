/* ==========================================================================
   O — (선택) 결제 PII 예시용 데모 테이블
   --------------------------------------------------------------------------
   목적 : 게임사 결제/PII 소구를 위한 격리 데모 테이블. 기본 스키마에는 없음.
   주의 : 기본 미적용. 결제 마스킹/분류 데모를 강화하고 싶을 때만 실행.
          합성 데이터만 삽입(실 카드번호 금지). 데모 후 05_rollback.sql이 제거.
   ========================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.payment_methods', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.payment_methods
    (
        payment_id   BIGINT        IDENTITY(1,1) NOT NULL,
        player_id    BIGINT        NOT NULL,
        card_holder  NVARCHAR(100) NOT NULL,   -- 실명(PII)
        card_last4   CHAR(4)       NOT NULL,    -- 카드 끝 4자리(합성)
        card_brand   VARCHAR(16)   NOT NULL,    -- VISA/MASTER/...
        billing_email NVARCHAR(256) NULL,       -- 청구 이메일(PII)
        created_at   DATETIME2(3)  NOT NULL CONSTRAINT DF_pay_created DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_payment_methods PRIMARY KEY CLUSTERED (payment_id)
    );

    /* 합성 샘플(실제 결제정보 아님) — 상위 20명 플레이어에 매핑 */
    INSERT INTO dbo.payment_methods (player_id, card_holder, card_last4, card_brand, billing_email)
    SELECT TOP (20)
           p.player_id,
           CONCAT(N'Holder_', p.player_id),
           RIGHT(CONCAT('0000', CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4))), 4),
           CASE ABS(CHECKSUM(NEWID())) % 3 WHEN 0 THEN 'VISA' WHEN 1 THEN 'MASTER' ELSE 'AMEX' END,
           CONCAT(N'billing_', p.player_id, N'@example.com')
    FROM dbo.players AS p
    ORDER BY p.player_id;

    PRINT 'O optional: created dbo.payment_methods with synthetic rows.';
END
ELSE
    PRINT 'O optional: dbo.payment_methods already exists.';
GO
