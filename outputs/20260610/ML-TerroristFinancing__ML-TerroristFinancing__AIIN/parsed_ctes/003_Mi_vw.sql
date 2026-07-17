-- CTE NAME: Mi_vw

SELECT /*+ QB_NAME(MI) */
  m.BANK_TO_BANK_TRNFR_FL,
  m.BENEF_ACCT_ID,
  m.BENEF_ACTVY_RISK_NB,
  m.BENEF_AUG_NM,
  m.CLR_TRXN_ACTVY_AM,
  m.CXL_PAIR_TRXN_INTRL_ID,
  m.DATA_DUMP_DT,
  m.DEP_TRXN_ACTVY_AM,
  m.DEP_INSTN_SEQ_ID,
  m.FUNC_CRNCY_CD,
  m.INTRL_BENEF_ACCT_FL,
  m.INTRL_REM_ACCT_FL,
  m.INTRL_SCND_BENEF_ACCT_FL,
  m.ISSUE_TRXN_ACTVY_AM,
  m.ISSUE_INSTN_SEQ_ID,
  m.MANTAS_ISSUE_DATE,
  m.MANTAS_POST_DT,
  m.MANTAS_TRXN_PRDCT_CD,
  m.MANTAS_TRXN_PURP_CD,
  m.PASS_THRU_FL,
  m.REM_ACCT_ID,
  m.REM_ACTVY_RISK_NB,
  m.REM_AUG_NM,
  m.SCND_BENEF_ACCT_ID,
  m.SCND_BENEF_ACTVY_RISK_NB,
  m.SCND_BENEF_AUG_NM,
  m.SRC_SYS_CD,
  m.TRSTD_TRXN_FL,
  m.TRXN_BASE_AM,
  m.TRXN_FUNC_AM,
  m.UNRLTD_PARTY_FL
FROM fccmatomic.MI_TRXN m
WHERE
  m.MANTAS_TRXN_PRDCT_CD IN (
    'CASH-EQ-CASHIER-CHECK',
    'CASH-EQ-CERT-CHECK',
    'CASH-EQ-MONEY-ORDER',
    'CASH-EQ-TRAVELERS-CHECK',
    'CASH-EQ-OTHER',
    'CASH-LETTER',
    'CHECK',
    'PAPER-OTHER',
    'CHECK-ACH'
  )
  AND /* Cover either all transaction or only form the Incl_Trans_Src_Lst */ (
    'Y' = 'Y' OR m.SRC_SYS_CD IN ('Inactive')
  )
  AND /* Cover only GENERAL transactions */ m.MANTAS_TRXN_PURP_CD = 'GENERAL'
  AND /* Getting data for look back period only and Utilize indexes     */ /* 25222051, OFSAABD-31950   */ m.DATA_DUMP_DT > (
    SELECT
      Min_Dt
    FROM clndr_vw
  )
  AND m.DATA_DUMP_DT <= (
    SELECT
      Max_Dt
    FROM clndr_vw
  )
  AND /* allow user to include (Y) or exclude (N)  Bank-to-Bank transactions between related parties */ (
    'Y' = 'Y' OR NOT (
      m.BANK_TO_BANK_TRNFR_FL = 'Y' AND m.PASS_THRU_FL = 'N'
    )
  )
  AND m.CXL_PAIR_TRXN_INTRL_ID IS NULL
  AND (
    'Y' = 'Y' OR COALESCE(m.TRSTD_TRXN_FL, 'N') = 'N'
  )
  AND /* Divide By Zero error handling */ NOT DECODE('B', 'F', m.TRXN_FUNC_AM, m.TRXN_BASE_AM) IS NULL
  AND DECODE('B', 'F', m.TRXN_FUNC_AM, m.TRXN_BASE_AM) <> 0
  AND /* 30487326 */ /* Included Related Parties */ (
    'N' = 'Y' OR COALESCE(m.UNRLTD_PARTY_FL, 'Y') <> 'N'
  )