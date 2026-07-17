-- DATASET QUERY
-- Extracted: 2026-06-08 09:05:27.246210

SELECT  ot.NTWRK_ID, ot.NODE_CT, ot.AVG_LINK_WT, ot.MAX_LINK_WT, ot.PRMRY_NODE, ot.TRXN_NODE_CT, ot.TOTAL_TRANS_AM, ot.TRANS_CT, ot.LINK_CT, ot.LINK_SUMMARY_CT FROM (--Bug18966229 
With Prmry_Node as
(select p.ntwrk_id, p.prmry_node
 from (select n.Ntwrk_Id, n.Link_Ct, min(k.node_bus_id) as Prmry_Node, 
        row_number() over (partition by n.ntwrk_id order by n.link_ct desc,  min(k.node_bus_id) asc) row_num
from 
                (select ntwrk_id, node_id, count(1) link_ct
                        from
                            (select  lts.first_node_id node_id, nw.ntwrk_id 
                             from 
                                  fccmatomic.KDD_link_type_summary lts 
                                  inner join fccmatomic.KDD_ntwrk nw on nw.ntwrk_id=lts.ntwrk_id
                                  inner join fccmatomic.KDD_link_anlys_ntwrk_defn def on def.ntwrk_defn_id=nw.ntwrk_defn_id
                             where
                                  def.ntwrk_defn_nm= 'ML_NETACENCU_NTWRK' 
                              and trunc(nw.creat_ts) = (select trunc(cal.clndr_dt) from fccmatomic.KDD_cal cal where cal.clndr_nm = 'SYSCAL' and cal.clndr_day_age = 0)
                              -- batch name verification
                               and 
                               (('Y' = 'Y' and nw.PRCSNG_BATCH_NM = (select prcsng_batch_nm from fccmatomic.KDD_prcsng_batch_control))
                                 OR       
                                ('Y' = 'N')
                                ) 
                              
                              UNION ALL
                              select lts.scnd_node_id node_id, nw.ntwrk_id 
                              from 
                                  fccmatomic.KDD_link_type_summary lts 
                                  inner join fccmatomic.KDD_ntwrk nw on nw.ntwrk_id=lts.ntwrk_id
                                  inner join fccmatomic.KDD_link_anlys_ntwrk_defn def on def.ntwrk_defn_id=nw.ntwrk_defn_id
                              where
                                  def.ntwrk_defn_nm= 'ML_NETACENCU_NTWRK' 
                              and trunc(nw.creat_ts) = (select trunc(cal.clndr_dt) from fccmatomic.KDD_cal cal where cal.clndr_nm = 'SYSCAL' and cal.clndr_day_age = 0)
                              -- batch name verification
                              and 
                               (('Y' = 'Y' and nw.PRCSNG_BATCH_NM = (select prcsng_batch_nm from fccmatomic.KDD_prcsng_batch_control))
                                 OR       
                                ('Y' = 'N')
                                )                               
                              
                        )
                        group by ntwrk_id,node_id
                       ) n,
                        fccmatomic.KDD_NODE k,
                        fccmatomic.KDD_link_anlys_type_cd t 
                        where n.node_id = k.node_id
                        and t.TYPE_ID = k.NODE_TYPE_CD
                        and t.type_nm = 'ACCOUNT'
group by  n.ntwrk_id, n.link_ct
 ) p ---ML_NetAcEnCu_Ntwrk_PrmryNode
 where p.row_num = 1),
 
Ntwrk_Vw AS (
SELECT nw.*
FROM
    kdd_ntwrk nw
WHERE
    trunc(nw.creat_ts) = (SELECT trunc(c.clndr_dt) FROM kdd_cal c
                          WHERE c.clndr_day_age = 0 AND c.clndr_nm = 'SYSCAL'
    )
 --Number of Nodes in the Entire Network >= Min Node Ct and Number of Nodes in the Entire Network <= Max Node Ct
   and nw.node_ct between 3 and 50
 --Number of links in the Entire Network >= Min Link Ct and Number of links in the Entire Network <= Max Link Ct
   and nw.link_ct between 2 and 100
),

Node_Vw AS (
SELECT nd.ntwrk_id
FROM kdd_node nd
    INNER JOIN kdd_link_anlys_type_cd lt ON lt.type_id = nd.node_type_cd AND lt.type_nm = 'ACCOUNT'
    INNER JOIN acct a ON nd.node_bus_id = a.acct_intrl_id
    INNER JOIN ntwrk_vw netw ON netw.ntwrk_id = nd.ntwrk_id
WHERE
    a.mantas_acct_holdr_type_cd = 'CR'
    AND a.acct_efctv_risk_nb <> - 2
GROUP BY
    nd.ntwrk_id
HAVING
    --Number of households in the Entire Network >= Min Household Ct 
	COUNT(DISTINCT coalesce(a.hh_acct_grp_id, 'NULL')) >= 3
	--37095735  Number of Nodes in the Entire Network <= Max Node Ct
	and count(node_id) <= 50	
), 

Link_Vw AS (
SELECT
    SUM(ls.tot_link_ct)     trans_ct,
    SUM(ls.tot_link_weight) total_trans_am,
    ls.ntwrk_id
FROM
    kdd_link_type_summary ls
    INNER JOIN kdd_link_anlys_type_cd t ON t.type_id = ls.link_type_cd
    INNER JOIN (
        SELECT DISTINCT MAX(lk.link_ts)
            OVER(PARTITION BY lk.ntwrk_id) link_ts,
            lk.ntwrk_id
        FROM
            kdd_link lk
            INNER JOIN ntwrk_vw netw ON netw.ntwrk_id = lk.ntwrk_id
        WHERE
            lk.link_type_cd IN ( 116000007, 116000006 )--'JOURNALS', 'WIRES'

    ) l ON ls.ntwrk_id = l.ntwrk_id
WHERE
    t.type_nm IN ( 'JOURNALS', 'WIRES' )
AND (TRUNC(l.link_ts) > (SELECT TRUNC(add_days(c.clndr_dt, - 7))
        FROM kdd_cal c WHERE c.clndr_day_age = 0 AND c.clndr_nm = 'SYSCAL')
    OR
--This parameter allows generate alert for common attributes without verification at least one transaction in the frequency period.
    'N' = 'Y' )
GROUP BY
    ls.ntwrk_id
HAVING
	--37095735 Number of links in the Entire Network <= Max Link Ct
	sum(ls.tot_link_ct) <= 100 
	
),

Trans_Node_Vw AS (
SELECT
    n.ntwrk_id,
    COUNT(1) AS trxn_node_ct
FROM
    kdd_node n
    INNER JOIN ntwrk_vw nw ON nw.ntwrk_id = n.ntwrk_id
WHERE
    n.node_total_measure IS NOT NULL
GROUP BY
    n.ntwrk_id
HAVING 
	--37095735 Number of Nodes in the Entire Network <= Max Node Ct
	count(n.node_id) <= 50
)


SELECT /*+ parallel(8)*/
    nt.ntwrk_id
  , pn.prmry_node    
  , nt.node_ct  
  , nt.link_ct
  , tr.trans_ct
  , tr.total_trans_am  
  , nt.avg_link_wt 
  , nt.max_link_wt 
  , nt.link_summary_ct 
  , tn.trxn_node_ct
FROM 
    Ntwrk_Vw nt
    inner join  fccmatomic.KDD_LINK_ANLYS_NTWRK_DEFN def 
        on def.ntwrk_defn_id = nt.ntwrk_defn_id and def.ntwrk_defn_nm='ML_NETACENCU_NTWRK'
    inner join Prmry_Node pn on pn.ntwrk_id = nt.ntwrk_id 
    inner join Node_Vw hh on nt.ntwrk_id=hh.ntwrk_id  
    inner join Link_Vw tr on tr.ntwrk_id = nt.ntwrk_id   
  -- PR 44388 starts
    inner join Trans_Node_Vw  tn     on nt.ntwrk_id = tn.ntwrk_id
  -- PR 44388 ends         
WHERE 
     --Number of transactions in the Entire Network >= Min Trans Ct
       tr.trans_ct >= 5
     --Total amount of transactions in the Entire Network >= Min Trans Am
   and tr.total_trans_am >= 25000
   and tn.trxn_node_ct >= 1 -- PR 44388
   -- batch name verification
   and 
   (('Y' = 'Y' and nt.PRCSNG_BATCH_NM = (select prcsng_batch_nm from fccmatomic.KDD_prcsng_batch_control))
     OR       
      ('Y' = 'N')
    )
 ) ot ORDER BY ot.NTWRK_ID