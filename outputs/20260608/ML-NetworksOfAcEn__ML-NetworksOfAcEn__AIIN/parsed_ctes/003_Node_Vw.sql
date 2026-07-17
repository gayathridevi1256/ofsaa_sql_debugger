-- CTE NAME: Node_Vw

SELECT
  nd.ntwrk_id
FROM kdd_node nd
INNER JOIN kdd_link_anlys_type_cd lt
  ON lt.type_id = nd.node_type_cd AND lt.type_nm = 'ACCOUNT'
INNER JOIN acct a
  ON nd.node_bus_id = a.acct_intrl_id
INNER JOIN ntwrk_vw netw
  ON netw.ntwrk_id = nd.ntwrk_id
WHERE
  a.mantas_acct_holdr_type_cd = 'CR' AND a.acct_efctv_risk_nb <> -2
GROUP BY
  nd.ntwrk_id
HAVING
  COUNT(DISTINCT COALESCE(a.hh_acct_grp_id, 'NULL')) /* Number of households in the Entire Network >= Min Household Ct */ >= 3
  AND /* 37095735  Number of Nodes in the Entire Network <= Max Node Ct */ COUNT(node_id) <= 50