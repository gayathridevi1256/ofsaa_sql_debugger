-- CTE NAME: Trans_Node_Vw

SELECT
  n.ntwrk_id,
  COUNT(1) AS trxn_node_ct
FROM kdd_node n
INNER JOIN ntwrk_vw nw
  ON nw.ntwrk_id = n.ntwrk_id
WHERE
  NOT n.node_total_measure IS NULL
GROUP BY
  n.ntwrk_id
HAVING
  COUNT(n.node_id) /* 37095735 Number of Nodes in the Entire Network <= Max Node Ct */ <= 50