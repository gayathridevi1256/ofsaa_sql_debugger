-- CTE NAME: loan_sm

SELECT
  lb.LOAN_INTRL_ID, /* Interest paid before lookback period */
  SUM(
    CASE
      WHEN F_TRUNC_DATE(lb.MNTH_SMRY_START_DT, 'MM') = (
        SELECT
          ED1_Date
        FROM clndr_vw
      )
      THEN lb.NB_PYMNT_CT
      ELSE 0
    END
  ) AS Payment_Ct, /* last month Remaining balance in lookback period */
  SUM(
    CASE
      WHEN F_TRUNC_DATE(lb.MNTH_SMRY_START_DT, 'MM') = (
        SELECT
          ED1_Date
        FROM clndr_vw
      )
      THEN DECODE('B', 'F', lb.RMNG_BAL_FUNC_AM, lb.RMNG_BAL_BASE_AM)
      ELSE 0
    END
  ) AS RMNG_AM_LAST, /* previous month Remaining balance in lookback period */
  SUM(
    CASE
      WHEN F_TRUNC_DATE(lb.MNTH_SMRY_START_DT, 'MM') = (
        SELECT
          ED2_Date
        FROM clndr_vw
      )
      THEN DECODE('B', 'F', lb.RMNG_BAL_FUNC_AM, lb.RMNG_BAL_BASE_AM)
      ELSE 0
    END
  ) AS PREV_MTH_RMNG_AM,
  MAX(DECODE('B', 'F', lb.RMNG_BAL_FUNC_AM, lb.RMNG_BAL_BASE_AM)) AS MAX_LKBK_BAL_AM,
  MAX(lb.FUNC_CRNCY_CD) AS FUNC_CRNCY_CD, /* when it has value 1 it means only current month record was received */
  COUNT(lb.LOAN_INTRL_ID) AS record_ct
FROM fccmatomic.LOAN_SMRY_MNTH lb, loan_vw loan
WHERE
  lb.MNTH_SMRY_START_DT /* 20422198 */ >= (
    SELECT
      SD3_Date
    FROM clndr_vw
  )
  AND lb.MNTH_SMRY_START_DT <= (
    SELECT
      ED1_Date
    FROM clndr_vw
  )
  AND loan.loan_intrl_id = lb.loan_intrl_id
GROUP BY
  lb.LOAN_INTRL_ID
/* check on Frequency */
HAVING
  SUM(
    CASE
      WHEN F_TRUNC_DATE(lb.MNTH_SMRY_START_DT, 'MM') = (
        SELECT
          ED1_Date
        FROM clndr_vw
      )
      THEN lb.NB_PYMNT_CT
      ELSE 0
    END
  ) > 0