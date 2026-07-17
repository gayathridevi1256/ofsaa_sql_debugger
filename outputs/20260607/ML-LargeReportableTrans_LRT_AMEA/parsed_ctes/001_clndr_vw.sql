-- CTE NAME: clndr_vw

SELECT
  (
    SELECT
      cal.clndr_dt
    FROM fccmatomic.KDD_CAL cal
    WHERE
      cal.CLNDR_NM = 'SYSCAL' AND cal.CLNDR_DAY_AGE = 14 - 1
  ) AS Min_Dt,
  (
    SELECT
      cal.clndr_dt
    FROM fccmatomic.KDD_CAL cal
    WHERE
      cal.CLNDR_NM = 'SYSCAL' AND cal.CLNDR_DAY_AGE = 0
  ) AS Max_Dt,
  (
    SELECT
      ADD_DAYS(cal.CLNDR_DT, -7)
    FROM fccmatomic.KDD_CAL cal
    WHERE
      cal.CLNDR_NM = 'SYSCAL' AND cal.CLNDR_DAY_AGE = 0
  ) AS Freq_Dt,
  (
    SELECT
      ADD_DAYS(cal.CLNDR_DT, -90)
    FROM fccmatomic.KDD_CAL cal
    WHERE
      cal.CLNDR_NM = 'SYSCAL' AND cal.CLNDR_DAY_AGE = 0
  ) AS Max_Days_Opened_Dt
FROM dual