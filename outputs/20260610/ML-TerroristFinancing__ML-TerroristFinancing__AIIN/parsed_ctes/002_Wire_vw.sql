-- CTE NAME: Wire_vw

SELECT /*+ QB_NAME(WIRE) */
  w.BENEF_ACCT_ID,
  w.BENEF_ACTVY_RISK_NB,
  w.BENEF_AUG_NM,
  w.DATA_DUMP_DT,
  w.FUNC_CRNCY_CD,
  w.INTRL_BENEF_ACCT_FL,
  w.INTRL_ORIG_ACCT_FL,
  w.INTRL_SCND_BENEF_ACCT_FL,
  w.INTRL_SCND_ORIG_ACCT_FL,
  w.MANTAS_TRXN_PRDCT_CD,
  w.MANTAS_TRXN_PURP_CD,
  w.ORIG_ACCT_ID,
  w.ORIG_ACTVY_RISK_NB,
  w.ORIG_AUG_NM,
  w.PASS_THRU_FL,
  w.RCV_TRXN_ACTVY_AM,
  w.RCV_INSTN_SEQ_ID,
  w.SCND_BENEF_ACCT_ID,
  w.SCND_BENEF_ACTVY_RISK_NB,
  w.SCND_BENEF_AUG_NM,
  w.SCND_ORIG_ACCT_ID,
  w.SCND_ORIG_ACTVY_RISK_NB,
  w.SCND_ORIG_AUG_NM,
  w.SEND_TRXN_ACTVY_AM,
  w.SEND_INSTN_SEQ_ID,
  w.SRC_SYS_CD,
  w.TRSTD_TRXN_FL,
  w.TRXN_BASE_AM,
  w.TRXN_EXCTN_DT,
  w.TRXN_FUNC_AM,
  w.UNRLTD_PARTY_FL
FROM fccmatomic.WIRE_TRXN w
WHERE
  w.MANTAS_TRXN_PRDCT_CD IN ('EFT-ACH', 'EFT-TREASURY', 'EFT-FEDWIRE', 'EFT-SWIFT', 'EFT-OTHER')
  AND /* Cover only GENERAL transactions */ w.MANTAS_TRXN_PURP_CD = 'GENERAL'
  AND /* Cover either all transaction or only form the Incl_Trans_Src_Lst */ (
    'Y' = 'Y' OR w.SRC_SYS_CD IN ('Inactive')
  )
  AND /* Getting data for look back period only and Utilize indexes    */ /* 25222051, OFSAABD-31950   */ w.TRXN_EXCTN_DT > (
    SELECT
      Min_Dt
    FROM clndr_vw
  )
  AND w.TRXN_EXCTN_DT <= (
    SELECT
      Max_Dt
    FROM clndr_vw
  )
  AND w.DATA_DUMP_DT > (
    SELECT
      Min_Dt
    FROM clndr_vw
  )
  AND w.DATA_DUMP_DT <= (
    SELECT
      Max_Dt
    FROM clndr_vw
  )
  AND /* allow user to include (Y) or exclude (N)  Bank-to-Bank transactions between related parties */ (
    'Y' = 'Y' OR NOT (
      w.BANK_TO_BANK_TRNFR_FL = 'Y' AND w.PASS_THRU_FL = 'N'
    )
  )
  AND w.CXL_PAIR_TRXN_INTRL_ID IS NULL
  AND (
    'Y' = 'Y' OR COALESCE(w.TRSTD_TRXN_FL, 'N') = 'N'
  )
  AND /* Divide By Zero error handling */ NOT DECODE('B', 'F', w.TRXN_FUNC_AM, w.TRXN_BASE_AM) IS NULL
  AND DECODE('B', 'F', w.TRXN_FUNC_AM, w.TRXN_BASE_AM) <> 0
  AND /* 30487326 */ /* Included Related Parties */ (
    'N' = 'Y' OR COALESCE(w.UNRLTD_PARTY_FL, 'Y') <> 'N'
  )