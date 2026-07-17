SELECT 
     t.CUST_SEQ_ID
   , t.CUST_INTRL_ID
   , t.CUST_EFCTV_RISK_NB
   , t.CUST_MATCH_TX
   , t.CUST_MATCH_TYPE_CD
   , count(1) as Tot_Trans_Ct
   , count(distinct t.ACCT_INTRL_ID) as Acct_Ct  
   , sum(t.Trxn_Am) as Tot_Trans_Amt
   , sum(t.Hr_Am)/sum(t.Trxn_Am)*100 as Hr_Prctg
   , sum(t.Lrf_Am)/sum(t.Trxn_Am)*100 as Lrf_Prctg   
   , sum(t.Pass_Thru_Am)/sum(t.Trxn_Am)*100 as Pass_Thru_Prctg
   , sum(t.Trusted_Trans_Amt) as Trusted_Trans_Amt   
   , max(t.FUNC_CRNCY_CD) as FUNC_CRNCY_CD   
 
FROM 
(
            --Wire ORIG
            select 
                  ca.CUST_SEQ_ID,
                  ca.CUST_INTRL_ID,
                  ca.CUST_EFCTV_RISK_NB, 
                  ca.CUST_MATCH_TX,
                  ca.CUST_MATCH_TYPE_CD,
                  ca.ACCT_INTRL_ID,
                  w.Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.ORIG_ACTVY_RISK_NB > 5 then w.Trxn_Am else 0 end Hr_Am,
                  w.Pass_Thru_Am,    
                  w.Lrf_Am,			
	                w.Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
                       
            from 

              wires w,
              Cust_Accounts ca 

            where 
                   w.ORIG_ACCT_ID = ca.ACCT_INTRL_ID
               and w.INTRL_ORIG_ACCT_FL = 'Y'               

    UNION ALL
            --Wire SCND_ORIG              			   
            select 
                  ca.CUST_SEQ_ID,
                  ca.CUST_INTRL_ID,
                  ca.CUST_EFCTV_RISK_NB, 
                  ca.CUST_MATCH_TX,
                  ca.CUST_MATCH_TYPE_CD,
                  ca.ACCT_INTRL_ID,
                  w.Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.SCND_ORIG_ACTVY_RISK_NB > 5 then w.Trxn_Am else 0 end Hr_Am,
                  w.Pass_Thru_Am,    
                  w.Lrf_Am,			
	                w.Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
                                    
            from 

              wires w,
              Cust_Accounts ca  
     
            where 
                  w.SCND_ORIG_ACCT_ID = ca.ACCT_INTRL_ID
             and  w.INTRL_SCND_ORIG_ACCT_FL = 'Y'
             --SCND_ORIG <> ORIG
             and (('Y' = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                        where a1.ACCT_INTRL_ID = w.ORIG_ACCT_ID
                                        and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                        and w.INTRL_ORIG_ACCT_FL = 'Y'
                                        and a1.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')
                                        and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                  )
                 OR
                 ('Y' = 'N'
                 and
                 (w.INTRL_ORIG_ACCT_FL <> 'Y' OR  ca.CUST_INTRL_ID not in (select COALESCE(cta.cust_intrl_id,'NULL') 
                                                                                  from fccmatomic.CUST_ACCT cta,
                                                                                       fccmatomic.ACCT act,
                                                                                       fccmatomic.CUST_ACCT_ROLE car2
                                                                                  where act.acct_intrl_id = cta.acct_intrl_id
                                                                                        and cta.cust_acct_role_cd = car2.cust_acct_role_cd
                                                                                        and (car2.trdng_auth_fl = 'Y' or car2.wdrwl_auth_fl = 'Y' or car2.poa_fl = 'Y')
                                                                                        and act.ACCT_INTRL_ID = w.ORIG_ACCT_ID))) 
                 )   
    UNION ALL
            --Wire BENEF                              
            select 
                  ca.CUST_SEQ_ID,
                  ca.CUST_INTRL_ID,
                  ca.CUST_EFCTV_RISK_NB, 
                  ca.CUST_MATCH_TX,
                  ca.CUST_MATCH_TYPE_CD,
                  ca.ACCT_INTRL_ID,
                  w.Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.BENEF_ACTVY_RISK_NB > 5 then w.Trxn_Am else 0 end Hr_Am,
                  w.Pass_Thru_Am,    
                  w.Lrf_Am,			
	                w.Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
            from 
                wires w,
                Cust_Accounts ca   

            where 
                  w.BENEF_ACCT_ID = ca.ACCT_INTRL_ID
              and w.INTRL_BENEF_ACCT_FL = 'Y'  
              --BENEF <> ORIG
              and (('Y' = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                          where a1.ACCT_INTRL_ID = w.ORIG_ACCT_ID
                                          and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                          and w.INTRL_ORIG_ACCT_FL = 'Y'
                                          and a1.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')
                                          and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                   )
                 OR
                 ('Y' = 'N'
                 and
                 (w.INTRL_ORIG_ACCT_FL <> 'Y' OR  ca.CUST_INTRL_ID not in (select COALESCE(cta.cust_intrl_id,'NULL') 
                                                                                  from fccmatomic.CUST_ACCT cta,
                                                                                       fccmatomic.ACCT act,
                                                                                       fccmatomic.CUST_ACCT_ROLE car2
                                                                                  where act.acct_intrl_id = cta.acct_intrl_id
                                                                                        and cta.cust_acct_role_cd = car2.cust_acct_role_cd
                                                                                        and (car2.trdng_auth_fl = 'Y' or car2.wdrwl_auth_fl = 'Y' or car2.poa_fl = 'Y')
                                                                                        and act.ACCT_INTRL_ID = w.ORIG_ACCT_ID))) 
                 ) 
              --BENEF <> SCND_ORIG
              and (('Y' = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a2
                                               where a2.ACCT_INTRL_ID = w.SCND_ORIG_ACCT_ID
                                               and a2.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                               and w.INTRL_SCND_ORIG_ACCT_FL = 'Y'
                                               and a2.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')
                                               and a2.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                   )                             
                 OR
                 ('Y' = 'N'
                 and
                 (COALESCE(w.INTRL_SCND_ORIG_ACCT_FL,'-') <> 'Y' OR  ca.CUST_INTRL_ID not in (select COALESCE(cta.cust_intrl_id,'NULL') 
                                                                                  from fccmatomic.CUST_ACCT cta,
                                                                                       fccmatomic.ACCT act,
                                                                                       fccmatomic.CUST_ACCT_ROLE car2
                                                                                  where act.acct_intrl_id = cta.acct_intrl_id
                                                                                        and cta.cust_acct_role_cd = car2.cust_acct_role_cd
                                                                                        and (car2.trdng_auth_fl = 'Y' or car2.wdrwl_auth_fl = 'Y' or car2.poa_fl = 'Y')
                                                                                        and act.ACCT_INTRL_ID = w.SCND_ORIG_ACCT_ID))) 
                 )  
    UNION ALL
            --Wire SCND_BENEF                   
            select 
                  ca.CUST_SEQ_ID,
                  ca.CUST_INTRL_ID,
                  ca.CUST_EFCTV_RISK_NB, 
                  ca.CUST_MATCH_TX,
                  ca.CUST_MATCH_TYPE_CD,
                  ca.ACCT_INTRL_ID,
                  w.Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.SCND_BENEF_ACTVY_RISK_NB > 5 then w.Trxn_Am else 0 end Hr_Am,
                  w.Pass_Thru_Am,    
                  w.Lrf_Am,			
	                w.Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
            from 
                wires w,
                Cust_Accounts ca 

            where 
                  w.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID
              and w.INTRL_SCND_BENEF_ACCT_FL = 'Y'
              --SCND_BENEF <> ORIG
              and (('Y' = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                          where a1.ACCT_INTRL_ID = w.ORIG_ACCT_ID
                                          and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                          and w.INTRL_ORIG_ACCT_FL = 'Y'
                                          and a1.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')
                                          and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                   )
                 OR
                 ('Y' = 'N'
                 and
                 (w.INTRL_ORIG_ACCT_FL <> 'Y' OR  ca.CUST_INTRL_ID not in (select COALESCE(cta.cust_intrl_id,'NULL') 
                                                                                  from fccmatomic.CUST_ACCT cta,
                                                                                       fccmatomic.ACCT act,
                                                                                       fccmatomic.CUST_ACCT_ROLE car2
                                                                                  where act.acct_intrl_id = cta.acct_intrl_id
                                                                                        and cta.cust_acct_role_cd = car2.cust_acct_role_cd
                                                                                        and (car2.trdng_auth_fl = 'Y' or car2.wdrwl_auth_fl = 'Y' or car2.poa_fl = 'Y')
                                                                                        and act.ACCT_INTRL_ID = w.ORIG_ACCT_ID))) 
                 ) 
              --SCND_BENEF <> SCND_ORIG
              and (('Y' = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a2
                                               where a2.ACCT_INTRL_ID = w.SCND_ORIG_ACCT_ID
                                               and a2.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                               and w.INTRL_SCND_ORIG_ACCT_FL = 'Y'
                                               and a2.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')
                                               and a2.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                   )
                 OR
                 ('Y' = 'N'
                 and
                 (COALESCE(w.INTRL_SCND_ORIG_ACCT_FL,'-') <> 'Y' OR  ca.CUST_INTRL_ID not in (select COALESCE(cta.cust_intrl_id,'NULL') 
                                                                                  from fccmatomic.CUST_ACCT cta,
                                                                                       fccmatomic.ACCT act,
                                                                                       fccmatomic.CUST_ACCT_ROLE car2
                                                                                  where act.acct_intrl_id = cta.acct_intrl_id
                                                                                        and cta.cust_acct_role_cd = car2.cust_acct_role_cd
                                                                                        and (car2.trdng_auth_fl = 'Y' or car2.wdrwl_auth_fl = 'Y' or car2.poa_fl = 'Y')
                                                                                        and act.ACCT_INTRL_ID = w.SCND_ORIG_ACCT_ID))) 
                 )   
              --SCND_BENEF <> BENEF
              and (('Y' = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a2
                                               where a2.ACCT_INTRL_ID = w.BENEF_ACCT_ID
                                               and a2.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                               and w.INTRL_BENEF_ACCT_FL = 'Y'
                                               and a2.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')
                                               and a2.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                   )
                 OR
                 ('Y' = 'N'
                 and
                 (w.INTRL_BENEF_ACCT_FL <> 'Y' OR  ca.CUST_INTRL_ID not in (select COALESCE(cta.cust_intrl_id,'NULL') 
                                                                                  from fccmatomic.CUST_ACCT cta,
                                                                                       fccmatomic.ACCT act,
                                                                                       fccmatomic.CUST_ACCT_ROLE car2
                                                                                  where act.acct_intrl_id = cta.acct_intrl_id
                                                                                        and cta.cust_acct_role_cd = car2.cust_acct_role_cd
                                                                                        and (car2.trdng_auth_fl = 'Y' or car2.wdrwl_auth_fl = 'Y' or car2.poa_fl = 'Y')
                                                                                        and act.ACCT_INTRL_ID = w.BENEF_ACCT_ID))) 
                 )    
                 
    UNION ALL
            --MI REM                   
            select 
                  ca.CUST_SEQ_ID,
                  ca.CUST_INTRL_ID,
                  ca.CUST_EFCTV_RISK_NB, 
                  ca.CUST_MATCH_TX,
                  ca.CUST_MATCH_TYPE_CD,
                  ca.ACCT_INTRL_ID,
                  w.Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.REM_ACTVY_RISK_NB > 5 then w.Trxn_Am else 0 end Hr_Am,
                  w.Pass_Thru_Am,    
                  w.Lrf_Am,			
	                w.Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
            from 
                mitrxn w,
                Cust_Accounts ca  
            where 
                  w.REM_ACCT_ID = ca.ACCT_INTRL_ID
              and w.INTRL_REM_ACCT_FL = 'Y'  			 
              and w.MANTAS_ISSUE_DATE in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and 1-1)                                          

    UNION ALL
            --MI BENEF                   
            select 
                  ca.CUST_SEQ_ID,
                  ca.CUST_INTRL_ID,
                  ca.CUST_EFCTV_RISK_NB, 
                  ca.CUST_MATCH_TX,
                  ca.CUST_MATCH_TYPE_CD,
                  ca.ACCT_INTRL_ID,
                  w.Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.BENEF_ACTVY_RISK_NB > 5 then w.Trxn_Am else 0 end Hr_Am,
                  w.Pass_Thru_Am,    
                  w.Lrf_Am,			
	                w.Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
                                                       
            from 
                 mitrxn w,
                 Cust_Accounts ca
 
            where 
                  w.BENEF_ACCT_ID = ca.ACCT_INTRL_ID
              and w.MANTAS_POST_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and 1-1)
              and w.INTRL_BENEF_ACCT_FL = 'Y'			              
              --BENEF <> REM
              and (('Y' = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                          where a1.ACCT_INTRL_ID = w.REM_ACCT_ID
                                          and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                          and w.INTRL_REM_ACCT_FL = 'Y'
                                          and a1.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')
                                          and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')    
                   )
                 OR
                 ('Y' = 'N'
                 and
                 (w.INTRL_REM_ACCT_FL <> 'Y' OR  ca.CUST_INTRL_ID not in (select COALESCE(cta.cust_intrl_id,'NULL') 
                                                                                  from fccmatomic.CUST_ACCT cta,
                                                                                       fccmatomic.ACCT act,
                                                                                       fccmatomic.CUST_ACCT_ROLE car2
                                                                                  where act.acct_intrl_id = cta.acct_intrl_id
                                                                                        and cta.cust_acct_role_cd = car2.cust_acct_role_cd
                                                                                        and (car2.trdng_auth_fl = 'Y' or car2.wdrwl_auth_fl = 'Y' or car2.poa_fl = 'Y')
                                                                                        and act.ACCT_INTRL_ID = w.REM_ACCT_ID))) 
                 ) 
                 
    UNION ALL
            --MI SCND_BENEF                   
            select 
                  ca.CUST_SEQ_ID,
                  ca.CUST_INTRL_ID,
                  ca.CUST_EFCTV_RISK_NB, 
                  ca.CUST_MATCH_TX,
                  ca.CUST_MATCH_TYPE_CD,
                  ca.ACCT_INTRL_ID,
                  w.Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.SCND_BENEF_ACTVY_RISK_NB > 5 then w.Trxn_Am else 0 end Hr_Am,
                  w.Pass_Thru_Am,    
                  w.Lrf_Am,			
	                w.Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
                                      
            from 
                mitrxn w,
                Cust_Accounts ca

            where 
                  w.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID
              and w.MANTAS_POST_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and 1-1)    
              and w.INTRL_SCND_BENEF_ACCT_FL = 'Y'			
              --SCND_BENEF <> REM
              and (('Y' = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                          where a1.ACCT_INTRL_ID = w.REM_ACCT_ID
                                          and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                          and w.INTRL_REM_ACCT_FL = 'Y'
                                          and a1.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')
                                          and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')    
                   )                 
                 OR
                 ('Y' = 'N'
                 and
                 (w.INTRL_REM_ACCT_FL <> 'Y' OR  ca.CUST_INTRL_ID not in (select COALESCE(cta.cust_intrl_id,'NULL') 
                                                                                  from fccmatomic.CUST_ACCT cta,
                                                                                       fccmatomic.ACCT act,
                                                                                       fccmatomic.CUST_ACCT_ROLE car2
                                                                                  where act.acct_intrl_id = cta.acct_intrl_id
                                                                                        and cta.cust_acct_role_cd = car2.cust_acct_role_cd
                                                                                        and (car2.trdng_auth_fl = 'Y' or car2.wdrwl_auth_fl = 'Y' or car2.poa_fl = 'Y')
                                                                                        and act.ACCT_INTRL_ID = w.REM_ACCT_ID))) 
                 ) 
              --SCND_BENEF <> BENEF
              and (('Y' = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                          where a1.ACCT_INTRL_ID = w.BENEF_ACCT_ID
                                          and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                          and w.INTRL_BENEF_ACCT_FL = 'Y'
                                          and a1.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')
                                          and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')    
                   )                 
                 OR
                 ('Y' = 'N'
                 and
                 (w.INTRL_BENEF_ACCT_FL <> 'Y' OR  ca.CUST_INTRL_ID not in (select COALESCE(cta.cust_intrl_id,'NULL') 
                                                                                  from fccmatomic.CUST_ACCT cta,
                                                                                       fccmatomic.ACCT act,
                                                                                       fccmatomic.CUST_ACCT_ROLE car2
                                                                                  where act.acct_intrl_id = cta.acct_intrl_id
                                                                                        and cta.cust_acct_role_cd = car2.cust_acct_role_cd
                                                                                        and (car2.trdng_auth_fl = 'Y' or car2.wdrwl_auth_fl = 'Y' or car2.poa_fl = 'Y')
                                                                                        and act.ACCT_INTRL_ID = w.BENEF_ACCT_ID))) 
                 )                                     
               			 
    UNION ALL
            --CASH
            select 
                  ca.CUST_SEQ_ID,
                  ca.CUST_INTRL_ID,
                  ca.CUST_EFCTV_RISK_NB, 
                  ca.CUST_MATCH_TX,
                  ca.CUST_MATCH_TYPE_CD,
                  ca.ACCT_INTRL_ID,
                  DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.CASH_TRXN_ACTVY_RISK_NB > 5 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Hr_Am,
                  0 as Pass_Thru_Am,        
                  case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)  - trunc(DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) , -4) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 
                       when w.TRXN_ACTVY_AM - trunc(w.TRXN_ACTVY_AM, -4) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 		 
                       else 0 end Lrf_Am ,                  
	                0 as Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
            from 
                 fccmatomic.CASH_TRXN w,
                 Cust_Accounts ca 

            where 
                  w.ACCT_INTRL_ID = ca.ACCT_INTRL_ID
               and ('Y' = 'Y' or w.SRC_SYS_CD IN ('Inactive'))
				       and w.MANTAS_TRXN_PURP_CD = 'GENERAL'
               and w.MANTAS_TRXN_PRDCT_CD in ('DEBIT-CARD', 'SVC', 'CREDIT-CARD', 'CURRENCY', 'PHYS')
               and ('Y' = 'Y' or COALESCE(w.unrltd_party_fl, 'Y') <> 'N')   
               and w.TRXN_EXCTN_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and 1-1)
               and w.DATA_DUMP_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and 1-1)
               and w.CXL_PAIR_TRXN_INTRL_ID is null		
               and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) IS NOT NULL AND DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <> 0	   
               			 
    UNION ALL
            --Journal
            select 
                  ca.CUST_SEQ_ID,
                  ca.CUST_INTRL_ID,
                  ca.CUST_EFCTV_RISK_NB, 
                  ca.CUST_MATCH_TX,
                  ca.CUST_MATCH_TYPE_CD,
                  ca.ACCT_INTRL_ID,
                  DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.BO_TRXN_ACTVY_RISK_NB > 5 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Hr_Am,
                  0 as Pass_Thru_Am,        
                  case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)  - trunc(DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) , -4) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 
                       when w.TRXN_ACTVY_AM - trunc(w.TRXN_ACTVY_AM, -4) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 		 
                       else 0 end Lrf_Am ,                  
	                case when w.TRSTD_TRXN_FL = 'Y' then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
             from
                  fccmatomic.BACK_OFFICE_TRXN w,
                  Cust_Accounts ca  

            where 
                  w.ACCT_INTRL_ID = ca.ACCT_INTRL_ID
              and w.MANTAS_TRXN_PRDCT_CD  in ('JOURNAL')
              and w.MANTAS_TRXN_PURP_CD = 'GENERAL'
              and w.CXL_PAIR_TRXN_INTRL_ID is null
              and ('Y' = 'Y' or w.SRC_SYS_CD IN ('Inactive'))	
              and ('Y' = 'Y' or COALESCE(w.TRSTD_TRXN_FL, 'N') = 'N')  
              and ('Y' = 'Y' or w.unrltd_party_cd is not null)
              and w.EXCTN_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and 1-1)
              and w.DATA_DUMP_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and 1-1)
              and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) IS NOT NULL AND DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <> 0
                                             
) t    

GROUP BY 
       t.CUST_SEQ_ID,
       t.CUST_INTRL_ID,
       t.CUST_EFCTV_RISK_NB,
       t.CUST_MATCH_TX,
       t.CUST_MATCH_TYPE_CD

HAVING 
-- Frequency Period
     max(t.data_dump_dt) <= (select b.CLNDR_DT from fccmatomic.KDD_CAL b where b.CLNDR_NM = 'SYSCAL'and b.CLNDR_DAY_AGE = 0)  
and  max(t.data_dump_dt) >  (select add_days(b.CLNDR_DT, - 1) from fccmatomic.KDD_CAL b where b.CLNDR_NM = 'SYSCAL'and b.CLNDR_DAY_AGE = 0)
-- Exclude Customers Containing only One Account
and     count(distinct t.ACCT_INTRL_ID) >= 2
-- applying constraints      
and (sum(t.Trxn_Am) >= 1000 and count(1) >= 5)