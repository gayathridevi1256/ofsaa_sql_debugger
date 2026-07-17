-- CTE NAME: Wire_Trxn_Vw

SELECT
  tr.BENEF_ACCT_ID,
  tr.SCND_BENEF_ACCT_ID,
  tr.ORIG_ACCT_ID,
  tr.SCND_ORIG_ACCT_ID,
  tr.data_dump_dt,
  DECODE('B', 'F', tr.TRXN_FUNC_AM, tr.TRXN_BASE_AM) AS Trxn_Am,
  tr.BENEF_ACTVY_RISK_NB,
  tr.SCND_BENEF_ACTVY_RISK_NB,
  tr.ORIG_ACTVY_RISK_NB,
  tr.SCND_ORIG_ACTVY_RISK_NB,
  tr.INTRL_BENEF_ACCT_FL,
  tr.INTRL_SCND_BENEF_ACCT_FL,
  tr.INTRL_ORIG_ACCT_FL,
  tr.INTRL_SCND_ORIG_ACCT_FL,
  (
    CASE
      WHEN tr.PASS_THRU_FL = 'Y'
      THEN DECODE('B', 'F', tr.TRXN_FUNC_AM, tr.TRXN_BASE_AM)
      ELSE 0
    END
  ) AS PASS_THRU_AMT,
  (
    CASE
      WHEN DECODE('B', 'F', tr.TRXN_FUNC_AM, tr.TRXN_BASE_AM) - TRUNC(DECODE('B', 'F', tr.TRXN_FUNC_AM, tr.TRXN_BASE_AM), -4) = 0
      THEN DECODE('B', 'F', tr.TRXN_FUNC_AM, tr.TRXN_BASE_AM)
      WHEN tr.RCV_TRXN_ACTVY_AM - TRUNC(tr.RCV_TRXN_ACTVY_AM, -4) = 0
      THEN DECODE('B', 'F', tr.TRXN_FUNC_AM, tr.TRXN_BASE_AM)
      WHEN tr.SEND_TRXN_ACTVY_AM - TRUNC(tr.SEND_TRXN_ACTVY_AM, -4) = 0
      THEN DECODE('B', 'F', tr.TRXN_FUNC_AM, tr.TRXN_BASE_AM)
      ELSE 0
    END
  ) AS LRF_AMT,
  CASE
    WHEN tr.TRSTD_TRXN_FL = 'Y'
    THEN DECODE('B', 'F', tr.TRXN_FUNC_AM, tr.TRXN_BASE_AM)
    ELSE 0
  END AS Trusted_Trans_Amt,
  tr.FUNC_CRNCY_CD
FROM fccmatomic.WIRE_TRXN tr
WHERE
  (
    'Y' = 'Y' OR tr.SRC_SYS_CD IN ('Inactive')
  )
  AND DECODE('B', 'F', tr.TRXN_FUNC_AM, tr.TRXN_BASE_AM) >= 3000
  AND tr.MANTAS_TRXN_PRDCT_CD IN ('EFT-ACH', 'EFT-TREASURY', 'EFT-FEDWIRE', 'EFT-SWIFT', 'EFT-OTHER', 'EST')
  AND tr.MANTAS_TRXN_PURP_CD = 'GENERAL'
  AND /* 31536090 */ tr.TRXN_EXCTN_DT >= (
    SELECT
      Min_Dt
    FROM clndr_vw
  )
  AND tr.TRXN_EXCTN_DT <= (
    SELECT
      Max_Dt
    FROM clndr_vw
  )
  AND tr.DATA_DUMP_DT >= (
    SELECT
      Min_Dt
    FROM clndr_vw
  )
  AND tr.DATA_DUMP_DT <= (
    SELECT
      Max_Dt
    FROM clndr_vw
  )
  AND (
    'Y' = 'Y' OR (
      tr.UNRLTD_PARTY_FL = 'Y' OR tr.UNRLTD_PARTY_FL IS NULL
    )
  )
  AND (
    'Y' = 'Y' OR NOT (
      tr.BANK_TO_BANK_TRNFR_FL = 'Y' AND tr.PASS_THRU_FL = 'N'
    )
  )
  AND (
    'Y' = 'Y' OR COALESCE(tr.TRSTD_TRXN_FL, 'N') = 'N'
  )
  AND tr.CXL_PAIR_TRXN_INTRL_ID IS NULL