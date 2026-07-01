/* ==========================================================================
   O — 1) 민감정보 자동분류 (Data Discovery & Classification)
   --------------------------------------------------------------------------
   PART A : (읽기전용) 컬럼명/타입 패턴으로 PII 후보 발견 → 분류 제안 목록.
   PART B : ADD SENSITIVITY CLASSIFICATION 으로 실제 태깅(메타데이터, 저위험).
   대상   : dbo.players (username=닉네임, email=이메일, region=위치),
            [선택] dbo.payment_methods (card_holder/card_last4/billing_email).
   원복   : 05_rollback.sql
   ========================================================================== */
SET NOCOUNT ON;
GO

/* --------------------------------------------------------------------------
   PART A — 발견(Discovery): 이름/타입 패턴 기반 PII 후보 (읽기전용)
   AI 하네스가 "무엇을 분류해야 하나"를 제안하는 근거로 사용.
   -------------------------------------------------------------------------- */
SELECT
    s.name  AS schema_name,
    t.name  AS table_name,
    c.name  AS column_name,
    ty.name AS data_type,
    CASE
        WHEN c.name LIKE '%email%' OR c.name LIKE '%mail%'      THEN 'Contact Info / Email'
        WHEN c.name LIKE '%card%'  OR c.name LIKE '%pan%'
          OR c.name LIKE '%holder%'                             THEN 'Financial / Payment'
        WHEN c.name LIKE '%user%'  OR c.name LIKE '%nick%'
          OR c.name LIKE '%name%'                               THEN 'Personal / Name'
        WHEN c.name LIKE '%region%' OR c.name LIKE '%country%'
          OR c.name LIKE '%addr%'                               THEN 'Location'
        ELSE 'Review'
    END AS suggested_information_type,
    CASE
        WHEN c.name LIKE '%card%' OR c.name LIKE '%pan%'
          OR c.name LIKE '%email%' OR c.name LIKE '%mail%'      THEN 'Confidential - GDPR'
        WHEN c.name LIKE '%user%' OR c.name LIKE '%nick%'
          OR c.name LIKE '%name%' OR c.name LIKE '%holder%'     THEN 'Confidential'
        ELSE 'General'
    END AS suggested_label
FROM sys.columns  AS c
JOIN sys.tables   AS t  ON t.object_id = c.object_id
JOIN sys.schemas  AS s  ON s.schema_id = t.schema_id
JOIN sys.types    AS ty ON ty.user_type_id = c.user_type_id
WHERE s.name = 'dbo'
  AND (
        c.name LIKE '%email%' OR c.name LIKE '%mail%'
     OR c.name LIKE '%user%'  OR c.name LIKE '%nick%'  OR c.name LIKE '%name%'
     OR c.name LIKE '%card%'  OR c.name LIKE '%pan%'   OR c.name LIKE '%holder%'
     OR c.name LIKE '%region%' OR c.name LIKE '%country%' OR c.name LIKE '%addr%'
      )
ORDER BY table_name, column_name;
GO

/* --------------------------------------------------------------------------
   PART B — 태깅: ADD SENSITIVITY CLASSIFICATION (승인 후 실행)
   재실행 시 기존 분류를 갱신(idempotent). 순수 메타데이터.
   -------------------------------------------------------------------------- */
ADD SENSITIVITY CLASSIFICATION TO dbo.players.email
    WITH (LABEL = 'Confidential - GDPR', INFORMATION_TYPE = 'Contact Info', RANK = HIGH);

ADD SENSITIVITY CLASSIFICATION TO dbo.players.username
    WITH (LABEL = 'Confidential', INFORMATION_TYPE = 'Name', RANK = MEDIUM);

ADD SENSITIVITY CLASSIFICATION TO dbo.players.region
    WITH (LABEL = 'General', INFORMATION_TYPE = 'Location', RANK = LOW);
GO

/* [선택] payment_methods가 있으면 결제 PII도 태깅 */
IF OBJECT_ID(N'dbo.payment_methods', N'U') IS NOT NULL
BEGIN
    EXEC(N'ADD SENSITIVITY CLASSIFICATION TO dbo.payment_methods.card_holder
             WITH (LABEL = ''Confidential - GDPR'', INFORMATION_TYPE = ''Name'', RANK = HIGH);');
    EXEC(N'ADD SENSITIVITY CLASSIFICATION TO dbo.payment_methods.card_last4
             WITH (LABEL = ''Confidential - GDPR'', INFORMATION_TYPE = ''Financial'', RANK = HIGH);');
    EXEC(N'ADD SENSITIVITY CLASSIFICATION TO dbo.payment_methods.billing_email
             WITH (LABEL = ''Confidential - GDPR'', INFORMATION_TYPE = ''Contact Info'', RANK = HIGH);');
    PRINT 'O classify: payment_methods columns classified.';
END
GO

PRINT 'O classify: sensitivity classifications applied. Verify with 04_eval.sql.';
GO
