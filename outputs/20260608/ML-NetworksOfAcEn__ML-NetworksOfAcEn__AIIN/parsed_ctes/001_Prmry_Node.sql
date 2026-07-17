-- CTE NAME: Prmry_Node

SELECT
  p.ntwrk_id,
  p.prmry_node
FROM (
  SELECT
    n.Ntwrk_Id,
    n.Link_Ct,
    MIN(k.node_bus_id) AS Prmry_Node,
    ROW_NUMBER() OVER (PARTITION BY n.ntwrk_id ORDER BY n.link_ct DESC, MIN(k.node_bus_id) ASC) AS row_num
  FROM (
    SELECT
      ntwrk_id,
      node_id,
      COUNT(1) AS link_ct
    FROM (
      SELECT
        lts.first_node_id AS node_id,
        nw.ntwrk_id
      FROM fccmatomic.KDD_link_type_summary lts
      INNER JOIN fccmatomic.KDD_ntwrk nw
        ON nw.ntwrk_id = lts.ntwrk_id
      INNER JOIN fccmatomic.KDD_link_anlys_ntwrk_defn def
        ON def.ntwrk_defn_id = nw.ntwrk_defn_id
      WHERE
        def.ntwrk_defn_nm = 'ML_NETACENCU_NTWRK'
        AND TRUNC(nw.creat_ts) = (
          SELECT
            TRUNC(cal.clndr_dt)
          FROM fccmatomic.KDD_cal cal
          WHERE
            cal.clndr_nm = 'SYSCAL' AND cal.clndr_day_age = 0
        )
        AND /* batch name verification */ (
          (
            'Y' = 'Y'
            AND nw.PRCSNG_BATCH_NM = (
              SELECT
                prcsng_batch_nm
              FROM fccmatomic.KDD_prcsng_batch_control
            )
          )
          OR (
            'Y' = 'N'
          )
        )
      UNION ALL
      SELECT
        lts.scnd_node_id AS node_id,
        nw.ntwrk_id
      FROM fccmatomic.KDD_link_type_summary lts
      INNER JOIN fccmatomic.KDD_ntwrk nw
        ON nw.ntwrk_id = lts.ntwrk_id
      INNER JOIN fccmatomic.KDD_link_anlys_ntwrk_defn def
        ON def.ntwrk_defn_id = nw.ntwrk_defn_id
      WHERE
        def.ntwrk_defn_nm = 'ML_NETACENCU_NTWRK'
        AND TRUNC(nw.creat_ts) = (
          SELECT
            TRUNC(cal.clndr_dt)
          FROM fccmatomic.KDD_cal cal
          WHERE
            cal.clndr_nm = 'SYSCAL' AND cal.clndr_day_age = 0
        )
        AND /* batch name verification */ (
          (
            'Y' = 'Y'
            AND nw.PRCSNG_BATCH_NM = (
              SELECT
                prcsng_batch_nm
              FROM fccmatomic.KDD_prcsng_batch_control
            )
          )
          OR (
            'Y' = 'N'
          )
        )
    )
    GROUP BY
      ntwrk_id,
      node_id
  ) n, fccmatomic.KDD_NODE k, fccmatomic.KDD_link_anlys_type_cd t
  WHERE
    n.node_id = k.node_id AND t.TYPE_ID = k.NODE_TYPE_CD AND t.type_nm = 'ACCOUNT'
  GROUP BY
    n.ntwrk_id,
    n.link_ct
) p /* -ML_NetAcEnCu_Ntwrk_PrmryNode */
WHERE
  p.row_num = 1