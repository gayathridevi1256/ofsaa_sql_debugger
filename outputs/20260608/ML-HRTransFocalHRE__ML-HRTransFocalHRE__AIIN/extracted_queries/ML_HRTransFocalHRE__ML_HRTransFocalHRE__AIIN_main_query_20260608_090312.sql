-- REFERENCE QUERY
-- Extracted: 2026-06-08 09:03:12.508696

SELECT ot.CUST_INTRL_ID, ot.CUST_SEQ_ID, ot.CUST_EFCTV_RISK_NB, ot.CUST_MATCH_TX, ot.CUST_MATCH_TYPE_CD, ot.TOT_TRANS_AMT, ot.TOT_TRANS_CT, ot.ACCT_CT, ot.PASS_THRU_PRCTG, ot.LRF_PRCTG, ot.HR_PRCTG, ot.TRUSTED_TRANS_AMT, ot.FUNC_CRNCY_CD FROM (-- BUG 30360250
-- PR-47385 added 'CXL_PAIR_TRXN_INTRL_ID' filter on all front office transactions
-- Date 06/23/2009 : PR 40130 Removing the 'MANTAS_ISSUE_DATE'/'MANTAS_POST_DT' from the MI_TRXN logic
-- The following code has been removed as per PR 40130:
-- and w.MANTAS_POST_DT <= (select b.CLNDR_DT from fccmatomic.KDD_CAL b where b.CLNDR_NM = 'SYSCAL'and b.CLNDR_DAY_AGE = 0)  
-- and w.MANTAS_POST_DT >  (select add_days(b.CLNDR_DT, - @Look_Back_Period) from fccmatomic.KDD_CAL b where b.CLNDR_NM = 'SYSCAL'and b.CLNDR_DAY_AGE = 0)
-- and w.MANTAS_ISSUE_DATE <= (select b.CLNDR_DT from fccmatomic.KDD_CAL b where b.CLNDR_NM = 'SYSCAL'and b.CLNDR_DAY_AGE = 0)  
-- and w.MANTAS_ISSUE_DATE >  (select add_days(b.CLNDR_DT, - @Look_Back_Period) from fccmatomic.KDD_CAL b where b.CLNDR_NM = 'SYSCAL'and b.CLNDR_DAY_AGE = 0)
-- M1
--OFSAABD-17784

with wires as (
select
          w.FO_TRXN_SEQ_ID,
          w.BENEF_ACCT_ID,
          w.SCND_BENEF_ACCT_ID,
          w.ORIG_ACCT_ID,
          w.SCND_ORIG_ACCT_ID,
          w.DATA_DUMP_DT,
          DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Trxn_Am,
          w.BENEF_ACTVY_RISK_NB,
          w.SCND_BENEF_ACTVY_RISK_NB,
          w.ORIG_ACTVY_RISK_NB,
          w.SCND_ORIG_ACTVY_RISK_NB,
          w.INTRL_BENEF_ACCT_FL,
          w.INTRL_SCND_BENEF_ACCT_FL,
          w.INTRL_ORIG_ACCT_FL,          
          w.INTRL_SCND_ORIG_ACCT_FL,
          (CASE WHEN w.PASS_THRU_FL='Y' THEN DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) ELSE 0 END) PASS_THRU_AM,        
          (CASE WHEN DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)  - TRUNC(DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) , -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)  
                 WHEN w.RCV_TRXN_ACTVY_AM - TRUNC(w.RCV_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 
                 WHEN w.SEND_TRXN_ACTVY_AM - TRUNC(w.SEND_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 
                 ELSE 0 END) LRF_AM,
	      	case when w.TRSTD_TRXN_FL = 'Y' then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)  else 0 end as Trusted_Trans_Amt,
          w.FUNC_CRNCY_CD 	
                           
from
	fccmatomic.WIRE_TRXN w 
where
	     (@All_Trans_Src_Fl = 'Y' or w.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
    and w.MANTAS_TRXN_PRDCT_CD in (@Incl_Wire_Trxn_Prdct_Type_Lst)
    and w.MANTAS_TRXN_PURP_CD = 'GENERAL'
  	and (@Include_B2B_Trnfr_Fl = 'Y'  or NOT(w.BANK_TO_BANK_TRNFR_FL = 'Y' and w.PASS_THRU_FL = 'N'))
    and (@Include_Trusted_Trans_FL = 'Y' or COALESCE(w.TRSTD_TRXN_FL, 'N') = 'N')  
    and (@Incl_Rltd_Parties = 'Y'  or COALESCE(w.UNRLTD_PARTY_FL, 'Y') <> 'N')
    and w.TRXN_EXCTN_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and @Look_Back_Period-1)   
  	and w.DATA_DUMP_DT  in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and @Look_Back_Period-1)
 	  and w.CXL_PAIR_TRXN_INTRL_ID is null
    and DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) IS NOT NULL AND DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <> 0
),

  
mitrxn as (
select
          m.FO_TRXN_SEQ_ID,
          m.BENEF_ACCT_ID,
          m.SCND_BENEF_ACCT_ID,
          m.REM_ACCT_ID,
          m.DATA_DUMP_DT,
          m.MANTAS_POST_DT,
          m.MANTAS_ISSUE_DATE,
          DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) as Trxn_Am,
          m.BENEF_ACTVY_RISK_NB,
          m.SCND_BENEF_ACTVY_RISK_NB,
          m.REM_ACTVY_RISK_NB,
          m.INTRL_BENEF_ACCT_FL,
          m.INTRL_SCND_BENEF_ACCT_FL,
          m.INTRL_REM_ACCT_FL,
          (CASE WHEN m.PASS_THRU_FL='Y' THEN DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) ELSE 0 END) PASS_THRU_AM,        
          (CASE WHEN DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) - TRUNC(DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM), -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) 
                 WHEN m.CLR_TRXN_ACTVY_AM - TRUNC(m.CLR_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
                 WHEN m.DEP_TRXN_ACTVY_AM - TRUNC(m.DEP_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
                 WHEN m.ISSUE_TRXN_ACTVY_AM - TRUNC(m.ISSUE_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
                 ELSE 0 END) LRF_AM,
				  case when m.TRSTD_TRXN_FL = 'Y' then DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
          m.FUNC_CRNCY_CD 
from
	fccmatomic.MI_TRXN m
where
	m.MANTAS_TRXN_PURP_CD = 'GENERAL'
	and m.MANTAS_TRXN_PRDCT_CD in (@Incl_MI_Trxn_Prdct_Type_Lst)      
	and (@All_Trans_Src_Fl = 'Y' or m.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
	and (@Include_B2B_Trnfr_Fl = 'Y'  or NOT(m.BANK_TO_BANK_TRNFR_FL = 'Y' and m.PASS_THRU_FL = 'N'))
  and (@Include_Trusted_Trans_FL = 'Y' or COALESCE(m.TRSTD_TRXN_FL, 'N') = 'N')  
	and (@Incl_Rltd_Parties = 'Y' or COALESCE(m.unrltd_party_fl, 'Y') <> 'N')	 
	and m.DATA_DUMP_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and @Look_Back_Period-1)
	and m.CXL_PAIR_TRXN_INTRL_ID is null
  and DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) IS NOT NULL AND DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <> 0
),

Cust_Accounts as
(SELECT 
        c.CUST_SEQ_ID,
        ac.PRMRY_CUST_INTRL_ID as CUST_INTRL_ID,
        ac.ACCT_INTRL_ID,
        c.CUST_EFCTV_RISK_NB,
        c.CUST_MATCH_TX, 
        c.CUST_MATCH_TYPE_CD
        
FROM        
 fccmatomic.ACCT ac,
 fccmatomic.CUST c 
WHERE     
    c.CUST_INTRL_ID = ac.PRMRY_CUST_INTRL_ID
AND ac.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR' 
AND c.CUST_EFCTV_RISK_NB <> -2 
--BUG 30360250
AND c.CUST_EFCTV_RISK_NB >= @Efctv_Risk_Lvl
AND ac.MANTAS_ACCT_BUS_TYPE_CD in (@Mantas_Bus_Acct_Type_Lst)
AND (@All_Jurisdictions_Fl = 'Y' or c.JRSDCN_CD in (@Incl_Jurisdictions_Lst))
AND @Prmry_Cust_Fl = 'Y'

UNION ALL
SELECT 
        c.CUST_SEQ_ID,
        c.CUST_INTRL_ID as CUST_INTRL_ID,
        ac.ACCT_INTRL_ID,
        c.CUST_EFCTV_RISK_NB,
        c.CUST_MATCH_TX, 
        c.CUST_MATCH_TYPE_CD
FROM        
  fccmatomic.ACCT ac,
  fccmatomic.CUST_ACCT ca, 
  fccmatomic.CUST c,
  fccmatomic.CUST_ACCT_ROLE car
WHERE     
    ac.ACCT_INTRL_ID = ca.ACCT_INTRL_ID
AND ca.CUST_INTRL_ID = c.CUST_INTRL_ID
AND ca.CUST_ACCT_ROLE_CD = car.CUST_ACCT_ROLE_CD
AND ac.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR' 
AND c.CUST_EFCTV_RISK_NB <> -2 
--BUG 30360250
AND c.CUST_EFCTV_RISK_NB >= @Efctv_Risk_Lvl 
AND ac.MANTAS_ACCT_BUS_TYPE_CD in (@Mantas_Bus_Acct_Type_Lst)
AND (@All_Jurisdictions_Fl = 'Y' or c.JRSDCN_CD in (@Incl_Jurisdictions_Lst))
AND (car.TRDNG_AUTH_FL = 'Y' or car.WDRWL_AUTH_FL = 'Y' or car.POA_FL = 'Y')
AND @Prmry_Cust_Fl = 'N'
)


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
                  case when  w.ORIG_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then w.Trxn_Am else 0 end Hr_Am,
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
                  case when  w.SCND_ORIG_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then w.Trxn_Am else 0 end Hr_Am,
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
             and ((@Prmry_Cust_Fl = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                        where a1.ACCT_INTRL_ID = w.ORIG_ACCT_ID
                                        and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                        and w.INTRL_ORIG_ACCT_FL = 'Y'
                                        and a1.MANTAS_ACCT_BUS_TYPE_CD IN (@Mantas_Bus_Acct_Type_Lst)
                                        and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                  )
                 OR
                 (@Prmry_Cust_Fl = 'N'
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
                  case when  w.BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then w.Trxn_Am else 0 end Hr_Am,
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
              and ((@Prmry_Cust_Fl = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                          where a1.ACCT_INTRL_ID = w.ORIG_ACCT_ID
                                          and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                          and w.INTRL_ORIG_ACCT_FL = 'Y'
                                          and a1.MANTAS_ACCT_BUS_TYPE_CD IN (@Mantas_Bus_Acct_Type_Lst)
                                          and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                   )
                 OR
                 (@Prmry_Cust_Fl = 'N'
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
              and ((@Prmry_Cust_Fl = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a2
                                               where a2.ACCT_INTRL_ID = w.SCND_ORIG_ACCT_ID
                                               and a2.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                               and w.INTRL_SCND_ORIG_ACCT_FL = 'Y'
                                               and a2.MANTAS_ACCT_BUS_TYPE_CD IN (@Mantas_Bus_Acct_Type_Lst)
                                               and a2.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                   )                             
                 OR
                 (@Prmry_Cust_Fl = 'N'
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
                  case when  w.SCND_BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then w.Trxn_Am else 0 end Hr_Am,
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
              and ((@Prmry_Cust_Fl = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                          where a1.ACCT_INTRL_ID = w.ORIG_ACCT_ID
                                          and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                          and w.INTRL_ORIG_ACCT_FL = 'Y'
                                          and a1.MANTAS_ACCT_BUS_TYPE_CD IN (@Mantas_Bus_Acct_Type_Lst)
                                          and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                   )
                 OR
                 (@Prmry_Cust_Fl = 'N'
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
              and ((@Prmry_Cust_Fl = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a2
                                               where a2.ACCT_INTRL_ID = w.SCND_ORIG_ACCT_ID
                                               and a2.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                               and w.INTRL_SCND_ORIG_ACCT_FL = 'Y'
                                               and a2.MANTAS_ACCT_BUS_TYPE_CD IN (@Mantas_Bus_Acct_Type_Lst)
                                               and a2.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                   )
                 OR
                 (@Prmry_Cust_Fl = 'N'
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
              and ((@Prmry_Cust_Fl = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a2
                                               where a2.ACCT_INTRL_ID = w.BENEF_ACCT_ID
                                               and a2.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                               and w.INTRL_BENEF_ACCT_FL = 'Y'
                                               and a2.MANTAS_ACCT_BUS_TYPE_CD IN (@Mantas_Bus_Acct_Type_Lst)
                                               and a2.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')
                   )
                 OR
                 (@Prmry_Cust_Fl = 'N'
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
                  case when  w.REM_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then w.Trxn_Am else 0 end Hr_Am,
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
              and w.MANTAS_ISSUE_DATE in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and @Look_Back_Period-1)                                          

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
                  case when  w.BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then w.Trxn_Am else 0 end Hr_Am,
                  w.Pass_Thru_Am,    
                  w.Lrf_Am,			
	                w.Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
                                                       
            from 
                 mitrxn w,
                 Cust_Accounts ca
 
            where 
                  w.BENEF_ACCT_ID = ca.ACCT_INTRL_ID
              and w.MANTAS_POST_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and @Look_Back_Period-1)
              and w.INTRL_BENEF_ACCT_FL = 'Y'			              
              --BENEF <> REM
              and ((@Prmry_Cust_Fl = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                          where a1.ACCT_INTRL_ID = w.REM_ACCT_ID
                                          and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                          and w.INTRL_REM_ACCT_FL = 'Y'
                                          and a1.MANTAS_ACCT_BUS_TYPE_CD IN (@Mantas_Bus_Acct_Type_Lst)
                                          and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')    
                   )
                 OR
                 (@Prmry_Cust_Fl = 'N'
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
                  case when  w.SCND_BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then w.Trxn_Am else 0 end Hr_Am,
                  w.Pass_Thru_Am,    
                  w.Lrf_Am,			
	                w.Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
                                      
            from 
                mitrxn w,
                Cust_Accounts ca

            where 
                  w.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID
              and w.MANTAS_POST_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and @Look_Back_Period-1)    
              and w.INTRL_SCND_BENEF_ACCT_FL = 'Y'			
              --SCND_BENEF <> REM
              and ((@Prmry_Cust_Fl = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                          where a1.ACCT_INTRL_ID = w.REM_ACCT_ID
                                          and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                          and w.INTRL_REM_ACCT_FL = 'Y'
                                          and a1.MANTAS_ACCT_BUS_TYPE_CD IN (@Mantas_Bus_Acct_Type_Lst)
                                          and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')    
                   )                 
                 OR
                 (@Prmry_Cust_Fl = 'N'
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
              and ((@Prmry_Cust_Fl = 'Y'
                 and not exists (select 1 from fccmatomic.ACCT a1
                                          where a1.ACCT_INTRL_ID = w.BENEF_ACCT_ID
                                          and a1.PRMRY_CUST_INTRL_ID = ca.CUST_INTRL_ID
                                          and w.INTRL_BENEF_ACCT_FL = 'Y'
                                          and a1.MANTAS_ACCT_BUS_TYPE_CD IN (@Mantas_Bus_Acct_Type_Lst)
                                          and a1.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR')    
                   )                 
                 OR
                 (@Prmry_Cust_Fl = 'N'
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
                  DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.CASH_TRXN_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Hr_Am,
                  0 as Pass_Thru_Am,        
                  case when DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)  - trunc(DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) , -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 
                       when w.TRXN_ACTVY_AM - trunc(w.TRXN_ACTVY_AM, -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 		 
                       else 0 end Lrf_Am ,                  
	                0 as Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
            from 
                 fccmatomic.CASH_TRXN w,
                 Cust_Accounts ca 

            where 
                  w.ACCT_INTRL_ID = ca.ACCT_INTRL_ID
               and (@All_Trans_Src_Fl = 'Y' or w.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
				       and w.MANTAS_TRXN_PURP_CD = 'GENERAL'
               and w.MANTAS_TRXN_PRDCT_CD in (@Incl_Cash_Trxn_Prdct_Type_Lst)
               and (@Incl_Rltd_Parties = 'Y' or COALESCE(w.unrltd_party_fl, 'Y') <> 'N')   
               and w.TRXN_EXCTN_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and @Look_Back_Period-1)
               and w.DATA_DUMP_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and @Look_Back_Period-1)
               and w.CXL_PAIR_TRXN_INTRL_ID is null		
               and DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) IS NOT NULL AND DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <> 0	   
               			 
    UNION ALL
            --Journal
            select 
                  ca.CUST_SEQ_ID,
                  ca.CUST_INTRL_ID,
                  ca.CUST_EFCTV_RISK_NB, 
                  ca.CUST_MATCH_TX,
                  ca.CUST_MATCH_TYPE_CD,
                  ca.ACCT_INTRL_ID,
                  DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Trxn_Am,
                  w.DATA_DUMP_DT,
                  case when  w.BO_TRXN_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Hr_Am,
                  0 as Pass_Thru_Am,        
                  case when DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)  - trunc(DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) , -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 
                       when w.TRXN_ACTVY_AM - trunc(w.TRXN_ACTVY_AM, -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 		 
                       else 0 end Lrf_Am ,                  
	                case when w.TRSTD_TRXN_FL = 'Y' then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
                  w.FUNC_CRNCY_CD 
             from
                  fccmatomic.BACK_OFFICE_TRXN w,
                  Cust_Accounts ca  

            where 
                  w.ACCT_INTRL_ID = ca.ACCT_INTRL_ID
              and w.MANTAS_TRXN_PRDCT_CD  in (@Incl_BO_Trxn_Prdct_Type_Lst)
              and w.MANTAS_TRXN_PURP_CD = 'GENERAL'
              and w.CXL_PAIR_TRXN_INTRL_ID is null
              and (@All_Trans_Src_Fl = 'Y' or w.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))	
              and (@Include_Trusted_Trans_FL = 'Y' or COALESCE(w.TRSTD_TRXN_FL, 'N') = 'N')  
              and (@Incl_Rltd_Parties = 'Y' or w.unrltd_party_cd is not null)
              and w.EXCTN_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and @Look_Back_Period-1)
              and w.DATA_DUMP_DT in (select kc.CLNDR_DT from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL'and kc.CLNDR_DAY_AGE between 0 and @Look_Back_Period-1)
              and DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) IS NOT NULL AND DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <> 0
                                             
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
and  max(t.data_dump_dt) >  (select add_days(b.CLNDR_DT, - @Frequency_Period) from fccmatomic.KDD_CAL b where b.CLNDR_NM = 'SYSCAL'and b.CLNDR_DAY_AGE = 0)
-- Exclude Customers Containing only One Account
and     count(distinct t.ACCT_INTRL_ID) >= @Min_Acct_Ct
-- applying constraints      
and (sum(t.Trxn_Am) >= @Min_Trans_Am and count(1) >= @Min_Trans_Ct)
 ) ot ORDER BY ot.CUST_SEQ_ID 