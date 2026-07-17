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