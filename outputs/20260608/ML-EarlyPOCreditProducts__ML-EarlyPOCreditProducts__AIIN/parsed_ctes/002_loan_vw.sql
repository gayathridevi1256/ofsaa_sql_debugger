-- CTE NAME: loan_vw

SELECT
  l.LOAN_INTRL_ID,
  ac.ACCT_INTRL_ID,
  ac.ACCT_SEQ_ID,
  DECODE('B', 'F', l.LOAN_ORIG_FUNC_AM, l.LOAN_ORIG_BASE_AM) AS d_LOAN_ORIG_AM,
  ac.ACCT_EFCTV_RISK_NB AS Effctv_Risk_Lvl,
  CASE WHEN ac.ACCT_EFCTV_RISK_NB >= 5 THEN 'HR' ELSE 'RR' END AS Overall_Risk, /* calculating the days outstanding - How many days LOAN is already opened */
  (
    SELECT
      JCurr_Dt
    FROM clndr_vw
  ) - (
    F_TO_NUMBER(COALESCE(F_DATE_TO_CHAR(l.LOAN_ORIG_DT, 'J'), '0'))
  ) AS Days_Outstanding, /* calculating how much loan remains to be paid in case of paydown - How many days left is till the end/maturity of Loan. */
  (
    F_TO_NUMBER(COALESCE(F_DATE_TO_CHAR(l.LOAN_EXPTD_DUE_DT, 'J'), '0'))
  ) - (
    SELECT
      JCurr_Dt
    FROM clndr_vw
  ) AS Days_Remaining_Loan_Tenor
FROM fccmatomic.ACCT ac, fccmatomic.LOAN l
WHERE
  l.LOAN_INTRL_ID = ac.ACCT_INTRL_ID
  AND /*  Exclude Test Accounts */ COALESCE(ac.TEST_ACCT_FL, 'N') <> 'Y'
  AND /* Include specific account types only */ ac.MANTAS_ACCT_BUS_TYPE_CD IN ('LON')
  AND /*  Exclude Exempt Accounts */ ac.ACCT_EFCTV_RISK_NB <> -2
  AND /* Include only Term loans */ l.LOAN_CLASS_CD = 'NRV'
  AND /* Inlude Accout either from all or specifyed jurisdictions */ (
    'N' = 'Y' OR ac.JRSDCN_CD IN ('AIIN')
  )
  AND /*  Include Loan Accounts Only */ (
    'Y' = 'Y' OR l.LOAN_TYPE_CD IN ('Inactive')
  )
  AND /* Loam Sum > 0 */ DECODE('B', 'F', l.LOAN_ORIG_FUNC_AM, l.LOAN_ORIG_BASE_AM) > 0