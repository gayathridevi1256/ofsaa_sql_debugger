-- CTE NAME: Ntwrk_Vw

SELECT
  nw.*
FROM kdd_ntwrk nw
WHERE
  TRUNC(nw.creat_ts) = (
    SELECT
      TRUNC(c.clndr_dt)
    FROM kdd_cal c
    WHERE
      c.clndr_day_age = 0 AND c.clndr_nm = 'SYSCAL'
  )
  AND /* Number of Nodes in the Entire Network >= Min Node Ct and Number of Nodes in the Entire Network <= Max Node Ct */ nw.node_ct BETWEEN 3 AND 50
  AND /* Number of links in the Entire Network >= Min Link Ct and Number of links in the Entire Network <= Max Link Ct */ nw.link_ct BETWEEN 2 AND 100