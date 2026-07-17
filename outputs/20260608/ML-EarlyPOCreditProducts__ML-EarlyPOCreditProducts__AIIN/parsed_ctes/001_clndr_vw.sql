-- CTE NAME: clndr_vw

SELECT
  (
    SELECT
      cal.clndr_dt
    FROM fccmatomic.KDD_CAL cal
    WHERE
      cal.CLNDR_NM = 'SYSCAL' AND cal.CLNDR_DAY_AGE = 0
  ) AS Curr_Dt,
  (
    SELECT
      (
        F_TO_NUMBER(
          COALESCE(
            F_DATE_TO_CHAR(
              (
                SELECT
                  CLNDR_DT
                FROM fccmatomic.KDD_CAL
                WHERE
                  CLNDR_NM = 'SYSCAL' AND MNTH_BNDRY_CD = 'ED1'
              ),
              'J'
            ),
            '0'
          )
        )
      )
    FROM dual
  ) AS JCurr_Dt,
  (
    SELECT
      F_TRUNC_DATE(kc.CLNDR_DT, 'MM')
    FROM fccmatomic.KDD_CAL kc
    WHERE
      kc.CLNDR_NM = 'SYSCAL' AND kc.MNTH_BNDRY_CD = 'ED1'
  ) AS ED1_Date,
  (
    SELECT
      F_TRUNC_DATE(kc.CLNDR_DT, 'MM')
    FROM fccmatomic.KDD_CAL kc
    WHERE
      kc.CLNDR_NM = 'SYSCAL' AND kc.MNTH_BNDRY_CD = 'ED2'
  ) AS ED2_Date,
  (
    SELECT
      F_TRUNC_DATE(kc.CLNDR_DT, 'MM')
    FROM fccmatomic.KDD_CAL kc
    WHERE
      kc.CLNDR_NM = 'SYSCAL' AND kc.mnth_bndry_cd = 'SD3'
  ) AS SD3_Date
FROM dual