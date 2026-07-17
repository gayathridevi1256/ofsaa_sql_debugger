-- CTE NAME: Link_Vw

SELECT
  SUM(ls.tot_link_ct) AS trans_ct,
  SUM(ls.tot_link_weight) AS total_trans_am,
  ls.ntwrk_id
FROM kdd_link_type_summary ls
INNER JOIN kdd_link_anlys_type_cd t
  ON t.type_id = ls.link_type_cd
INNER JOIN (
  SELECT DISTINCT
    MAX(lk.link_ts) OVER (PARTITION BY lk.ntwrk_id) AS link_ts,
    lk.ntwrk_id
  FROM kdd_link lk
  INNER JOIN ntwrk_vw netw
    ON netw.ntwrk_id = lk.ntwrk_id
  WHERE
    lk.link_type_cd IN (116000007, 116000006) /* 'JOURNALS', 'WIRES' */
) l
  ON ls.ntwrk_id = l.ntwrk_id
WHERE
  t.type_nm IN ('JOURNALS', 'WIRES')
  AND (
    TRUNC(l.link_ts) > (
      SELECT
        TRUNC(ADD_DAYS(c.clndr_dt, -7))
      FROM kdd_cal c
      WHERE
        c.clndr_day_age = 0 AND c.clndr_nm = 'SYSCAL'
    )
    OR 'N' /* This parameter allows generate alert for common attributes without verification at least one transaction in the frequency period. */ = 'Y'
  )
GROUP BY
  ls.ntwrk_id
HAVING
  SUM(ls.tot_link_ct) /* 37095735 Number of links in the Entire Network <= Max Link Ct */ <= 100