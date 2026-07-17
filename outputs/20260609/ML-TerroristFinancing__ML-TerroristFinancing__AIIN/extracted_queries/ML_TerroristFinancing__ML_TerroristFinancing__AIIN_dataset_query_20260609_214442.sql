-- DATASET QUERY
-- Extracted: 2026-06-09 21:44:42.098393

SELECT  ot.ACCT_INTRL_ID, ot.ACCT_SEQ_ID, ot.TOT_TRANS_CT, ot.NAMES_CT, ot.CNTR_PARTY_CT, ot.TOT_TRANS_AMT, ot.PASS_THRU_PRCTG, ot.HR_PRCTG, ot.LRF_PRCTG, ot.OVERALL_RISK, ot.ACTVTY_RISK_LVL, ot.EFCTV_RISK_LVL, ot.TOT_DEPOSIT_TRANS_AMT, ot.TOT_SMALL_TRANS_AMT, ot.TOT_WTHDRWL_TRANS_AMT, ot.TRUSTED_TRANS_AMT, ot.PRMRY_CUST_INTRL_ID, ot.FUNC_CRNCY_CD, ot.CURR_DT FROM (-- 30/05/2017 update as per Story OFSAABD-8337 Revisions to Terrorist Financing scenario - AC focus
-- 10/25/05 PR 29032  added filter: amount of the transaction <= Max Small Trans Amt
-- 11/07/06 PR 33203  deleted filter amount of the transaction <= Max Small Trans Amt
--                    changed calculation of Names_Ct and Tot_Trans_Ct   
--
-- this dataset goes against MI and WI transaction tables for ORIG, BENEF, SCND ORIG, SCND BENF and REM 
-- join trnasactions for each of the party roles to account table. 
-- it calculates total of small transactions amount (Small_Trans_Amt) which is sum of transacrions whose 
-- amount do not exceed small transaction threshold
-- it calculates Withdrawals and Deposit for all involved accounts based on all transactions
-- for the second party roles (SCND ORIG, SCND BENEF) it exclude transaction records if secondary party role
-- as the same as first. 
--
-- disctinct counter parties:
--
-- the scenario considers ORIG,  as a counter party for both BENEF and SCND BENEF; 
-- BENEF considers as a counter party for ORIG and SCND ORIG
-- "Counter Party" for ORIG and SCND ORIG is concatonation of BENEF INTRL ID, RCV_INSTN_SEQ_ID(ISSUE_INSTN_SEQ_ID)
-- and BENEF_AUG_NM;
-- for BENEF and SCND BENEF is concatonation of ORIG INTRL ID(REM INTRL ID), 
-- SEND_INSTN_SEQ_ID(DEP_INSTN_SEQ_ID) and ORIG AUG NM(REM AUG NM);
--
-- number if disctinct denominators:
--
-- the number of diffirenet AUG NM for an account across all transactions, all NULL values consider as one value 
--
--
--OFSAABD-10438
--OFSAABD-10406
--28112797 
--28154168 
--OFSAABD-31950 QBNAME approach
WITH clndr_vw as (
select                        
(select add_days(cal.CLNDR_DT, -20) from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = 0) as Min_Dt,
(select cal.clndr_dt from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = 0) as Max_Dt,
(select add_days(cal.CLNDR_DT, -5) from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = 0) as  Freq_Dt
FROM dual
),

Wire_vw as (
select /*+ QB_NAME(WIRE)  */ 
w.BENEF_ACCT_ID,
w.BENEF_ACTVY_RISK_NB,
w.BENEF_AUG_NM,
w.DATA_DUMP_DT,
w.FUNC_CRNCY_CD, 
w.INTRL_BENEF_ACCT_FL,
w.INTRL_ORIG_ACCT_FL,
w.INTRL_SCND_BENEF_ACCT_FL,
w.INTRL_SCND_ORIG_ACCT_FL,
w.MANTAS_TRXN_PRDCT_CD,
w.MANTAS_TRXN_PURP_CD,
w.ORIG_ACCT_ID,
w.ORIG_ACTVY_RISK_NB,
w.ORIG_AUG_NM,
w.PASS_THRU_FL,
w.RCV_TRXN_ACTVY_AM,
w.RCV_INSTN_SEQ_ID,
w.SCND_BENEF_ACCT_ID,
w.SCND_BENEF_ACTVY_RISK_NB,
w.SCND_BENEF_AUG_NM,
w.SCND_ORIG_ACCT_ID,
w.SCND_ORIG_ACTVY_RISK_NB,
w.SCND_ORIG_AUG_NM,
w.SEND_TRXN_ACTVY_AM,
w.SEND_INSTN_SEQ_ID,
w.SRC_SYS_CD,
w.TRSTD_TRXN_FL,
w.TRXN_BASE_AM,
w.TRXN_EXCTN_DT,
w.TRXN_FUNC_AM,
w.UNRLTD_PARTY_FL
from fccmatomic.WIRE_TRXN w 
where 
                   w.MANTAS_TRXN_PRDCT_CD in ('EFT-ACH', 'EFT-TREASURY', 'EFT-FEDWIRE', 'EFT-SWIFT', 'EFT-OTHER')
               -- Cover only GENERAL transactions
               and w.MANTAS_TRXN_PURP_CD = 'GENERAL'   
               -- Cover either all transaction or only form the Incl_Trans_Src_Lst
               and ('Y' = 'Y' or w.SRC_SYS_CD IN ('Inactive'))
               -- Getting data for look back period only and Utilize indexes    
               --25222051, OFSAABD-31950   
               and w.TRXN_EXCTN_DT >  (select Min_Dt from clndr_vw) and w.TRXN_EXCTN_DT <= (select Max_Dt from clndr_vw)  
               and w.DATA_DUMP_DT >  (select Min_Dt from clndr_vw) and w.DATA_DUMP_DT <= (select Max_Dt from clndr_vw)  
               -- allow user to include (Y) or exclude (N)  Bank-to-Bank transactions between related parties
               and ('Y' = 'Y' or NOT(w.BANK_TO_BANK_TRNFR_FL = 'Y' and w.PASS_THRU_FL = 'N'))
               and w.CXL_PAIR_TRXN_INTRL_ID is NULL
               and ('Y' = 'Y' or COALESCE(w.TRSTD_TRXN_FL,'N') ='N')      
               -- Divide By Zero error handling
               and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) IS NOT NULL AND DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <> 0
               --30487326
               --Included Related Parties
               and ('N' = 'Y' or COALESCE(w.UNRLTD_PARTY_FL,'Y') <> 'N')               
),

Mi_vw as (
select /*+ QB_NAME(MI)  */
m.BANK_TO_BANK_TRNFR_FL,
m.BENEF_ACCT_ID,
m.BENEF_ACTVY_RISK_NB,
m.BENEF_AUG_NM,
m.CLR_TRXN_ACTVY_AM,
m.CXL_PAIR_TRXN_INTRL_ID,
m.DATA_DUMP_DT,
m.DEP_TRXN_ACTVY_AM,
m.DEP_INSTN_SEQ_ID,
m.FUNC_CRNCY_CD, 
m.INTRL_BENEF_ACCT_FL,
m.INTRL_REM_ACCT_FL,
m.INTRL_SCND_BENEF_ACCT_FL,
m.ISSUE_TRXN_ACTVY_AM,
m.ISSUE_INSTN_SEQ_ID,
m.MANTAS_ISSUE_DATE,
m.MANTAS_POST_DT,
m.MANTAS_TRXN_PRDCT_CD,
m.MANTAS_TRXN_PURP_CD,
m.PASS_THRU_FL,
m.REM_ACCT_ID,
m.REM_ACTVY_RISK_NB,
m.REM_AUG_NM,
m.SCND_BENEF_ACCT_ID,
m.SCND_BENEF_ACTVY_RISK_NB,
m.SCND_BENEF_AUG_NM,
m.SRC_SYS_CD,
m.TRSTD_TRXN_FL,
m.TRXN_BASE_AM,
m.TRXN_FUNC_AM,
m.UNRLTD_PARTY_FL
from fccmatomic.MI_TRXN m 
where 
                    m.MANTAS_TRXN_PRDCT_CD in ('CASH-EQ-CASHIER-CHECK', 'CASH-EQ-CERT-CHECK', 'CASH-EQ-MONEY-ORDER', 'CASH-EQ-TRAVELERS-CHECK', 'CASH-EQ-OTHER', 'CASH-LETTER', 'CHECK', 'PAPER-OTHER', 'CHECK-ACH')        
               -- Cover either all transaction or only form the Incl_Trans_Src_Lst
               and ('Y' = 'Y' or m.SRC_SYS_CD IN ('Inactive'))
               -- Cover only GENERAL transactions
               and m.MANTAS_TRXN_PURP_CD = 'GENERAL' 
               -- Getting data for look back period only and Utilize indexes     
               --25222051, OFSAABD-31950   
               and m.DATA_DUMP_DT >  (select Min_Dt from clndr_vw) and m.DATA_DUMP_DT <= (select Max_Dt from clndr_vw)                 
               -- allow user to include (Y) or exclude (N)  Bank-to-Bank transactions between related parties
               and ('Y' = 'Y' or NOT(m.BANK_TO_BANK_TRNFR_FL = 'Y' and m.PASS_THRU_FL = 'N'))
               and m.CXL_PAIR_TRXN_INTRL_ID is NULL
               and ('Y' = 'Y' or COALESCE(m.TRSTD_TRXN_FL,'N') ='N')       
               -- Divide By Zero error handling
               and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) IS NOT NULL AND DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <> 0
               --30487326
               --Included Related Parties
               and ('N' = 'Y' or COALESCE(m.UNRLTD_PARTY_FL,'Y') <> 'N')    
)
select 
            g.ACCT_INTRL_ID 
          , g.ACCT_SEQ_ID  
          , g.Prmry_Cust_Intrl_Id
          , g.Efctv_Risk_Lvl
          , g.Actvty_Risk_Lvl
          , g.Tot_Small_Trans_Amt
          , g.Tot_Trans_Amt
          , g.Tot_Trans_Ct
          , g.Tot_Wthdrwl_Trans_Amt
          , g.Tot_Deposit_Trans_Amt
          , g.Cntr_Party_Ct
           -- consider not providing a name as using another name, so NULL will end up as NO_NAME_PROVIDED name 
          , g.Names_Ct
          , g.Overall_Risk  
          , g.Lrf_Prctg
          , g.Pass_Thru_Prctg
          , g.Hr_Prctg
          , g.Trusted_Trans_Amt
          , g.Func_Crncy_Cd
          , (select Max_Dt from clndr_vw)  as Curr_Dt

   from
     (
       select 
            t.ACCT_INTRL_ID 
          , max(t.ACCT_SEQ_ID) as Acct_Seq_Id  
           --OFSAABD-8337
          , max(t.PRMRY_CUST_INTRL_ID) as Prmry_Cust_Intrl_Id -- pseudo max
          , sum(t.Small_Trans_Amt)  as Tot_Small_Trans_Amt
          , sum(t.Trxn_Am)     as Tot_Trans_Amt
          --25238037 
          --, sum(t.Small_Trans_Ct)   as Tot_Trans_Ct
          , count(1)   as Tot_Trans_Ct
          , max(t.Efctv_Risk_Lvl)   as Efctv_Risk_Lvl
          , max(t.Actvty_Risk_Lvl)  as Actvty_Risk_Lvl
          , sum(t.Wthdrwl_Amt)      as Tot_Wthdrwl_Trans_Amt
          , sum(t.Deposit_Amt)      as Tot_Deposit_Trans_Amt
          , count(distinct (t.Cntr_Party_Nm)) as Cntr_Party_Ct
           -- consider not providing a name as using another name, so NULL will end up as NO_NAME_PROVIDED name 
          , count(distinct(case when t.Aug_Nm is null then 'NO_NAME_PROVIDED' 
                                when t.Aug_Nm = '--'  then null
                           else t.Aug_Nm end)) as Names_Ct
          , CASE WHEN (max(t.Efctv_Risk_Lvl) >= 5 AND max(t.Actvty_Risk_Lvl) >= 5) THEN 'HR'
                 WHEN (max(t.Efctv_Risk_Lvl) < 5 AND max(t.Actvty_Risk_Lvl) < 5) THEN 'RR'
                 ELSE 'MR' 
            END AS Overall_Risk 
          , case when sum(t.Trxn_Am) = 0 then 0 else sum(t.Lrf_Amt)*100/sum(t.Trxn_Am)  end       as Lrf_Prctg 
          , case when sum(t.Trxn_Am) = 0 then 0 else sum(t.Pass_Thru_Amt)*100/sum(t.Trxn_Am)  end as Pass_Thru_Prctg
          , case when sum(t.Trxn_Am) = 0 then 0 else sum(t.Hr_Amt)*100/sum(t.Trxn_Am)  end        as Hr_Prctg
          , sum(t.Trusted_Trans_Amt) as Trusted_Trans_Amt
          , max(t.Func_Crncy_Cd) as Func_Crncy_Cd    
        from
        ( 
              -- Wire trans - ORIG - Counter Party (BENEF)
              select /*+ QB_NAME(WIRE_ORG) */
                 a.ACCT_INTRL_ID,
                 a.ACCT_SEQ_ID,
                 a.PRMRY_CUST_INTRL_ID, 
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then w.ORIG_AUG_NM else '--' end as Aug_Nm,
                 -- Counter Party Name
                 w.BENEF_ACCT_ID||w.RCV_INSTN_SEQ_ID||w.BENEF_AUG_NM as Cntr_Party_Nm,
                 a.ACCT_EFCTV_RISK_NB   as Efctv_Risk_Lvl,  
                 w.ORIG_ACTVY_RISK_NB   as Actvty_Risk_Lvl,         
                 w.DATA_DUMP_DT,
                 case when  DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then w.DATA_DUMP_DT else to_date('01/01/1999','MM/DD/YYYY') end as Small_Data_Dump_Dt,
                 DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Trxn_Am,
                 DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Wthdrwl_Amt, -- Debit
                 0                      as Deposit_Amt, -- Credit         
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Small_Trans_Amt,                  
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then 1 else 0 end as Small_Trans_Ct,                  
                 case when  w.orig_actvy_risk_nb > 5 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Hr_Amt,
                 case when  w.PASS_THRU_FL = 'Y' then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Pass_Thru_Amt,
                 case when  DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) - trunc(DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM), -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 
                       when  w.RCV_TRXN_ACTVY_AM - trunc(w.RCV_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
                       when  w.SEND_TRXN_ACTVY_AM - trunc(w.SEND_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
                       else 0 end Lrf_Amt,
                 case when w.TRSTD_TRXN_FL = 'Y' then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
                 w.FUNC_CRNCY_CD  
              from 
                Wire_vw w, 
                fccmatomic.ACCT a 
              where 
                   w.ORIG_ACCT_ID = a.ACCT_INTRL_ID
               and w.INTRL_ORIG_ACCT_FL = 'Y'
               -- allows coverage of all jurisdictions without enumerating them in the Included Jurisdiction Codes 
               and ('N' = 'Y' OR a.JRSDCN_CD IN ('AIIN'))
               -- Cover only specific accounts
               and a.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')   
               --  Include Retail Customer Accounts Only 
               and a.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR' 
               -- Exclude Test Accounts
               and coalesce(a.TEST_ACCT_FL,'N') <> 'Y'
               --Exclude Exempted Accounts 
               and a.ACCT_EFCTV_RISK_NB <> -2     
              -- --------------------------    
              union all
              -- Wire trans - SCND  Counter Party (BENEF)
              select /*+ QB_NAME(WIRE_SORG) */
                 a.ACCT_INTRL_ID,
                 a.ACCT_SEQ_ID,
                 a.PRMRY_CUST_INTRL_ID,
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then w.SCND_ORIG_AUG_NM else '--' end as Aug_Nm,
                 -- Counter Party Name                 
                 w.BENEF_ACCT_ID||w.RCV_INSTN_SEQ_ID||w.BENEF_AUG_NM         as Cntr_Party_Nm,         
                 a.ACCT_EFCTV_RISK_NB   as Efctv_Risk_Lvl,  
                 w.SCND_ORIG_ACTVY_RISK_NB   as Actvty_Risk_Lvl,         
                 w.DATA_DUMP_DT,
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then w.DATA_DUMP_DT else to_date('01/01/1999','MM/DD/YYYY') end as Small_Data_Dump_Dt,            
                 DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Trxn_Am,
                 DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Wthdrwl_Amt, -- Debit
                 0                      as Deposit_Amt, -- Credit         
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Small_Trans_Amt,                  
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then 1 else 0 end as Small_Trans_Ct,                  
                    case when  w.scnd_orig_actvy_risk_nb > 5 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Hr_Am,
                    case when  w.PASS_THRU_FL = 'Y' then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Pass_Thru_Am,
                    case when  DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) - trunc(DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM), -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
                         when  w.RCV_TRXN_ACTVY_AM - trunc(w.RCV_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
                         when  w.SEND_TRXN_ACTVY_AM - trunc(w.SEND_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
                    else 0 end Lrf_Am,
                 case when w.TRSTD_TRXN_FL = 'Y' then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
                 w.FUNC_CRNCY_CD  
              from 
                Wire_vw w, 
                fccmatomic.ACCT a 
              where 
                   w.SCND_ORIG_ACCT_ID = a.ACCT_INTRL_ID
               and w.INTRL_SCND_ORIG_ACCT_FL = 'Y'
               -- Exlude transaction where SCND_ORIG = ORIG
               and ((w.INTRL_ORIG_ACCT_FL = 'Y' and coalesce(w.ORIG_ACCT_ID,'-')<>w.SCND_ORIG_ACCT_ID) or  w.INTRL_ORIG_ACCT_FL <> 'Y')
               -- allows coverage of all jurisdictions without enumerating them in the Included Jurisdiction Codes 
               and ('N' = 'Y' OR a.JRSDCN_CD IN ('AIIN'))
               -- Cover only specific accounts
               and a.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')   
               --  Include Retail Customer Accounts Only 
               and a.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR' 
               -- Exclude Test Accounts
               and coalesce(a.TEST_ACCT_FL,'N') <> 'Y'
               --Exclude Exempted Accounts 
               and a.ACCT_EFCTV_RISK_NB <> -2     
              -- --------------------------    
              union all
              -- Wire trans - BENEF  - Counter Party (ORIG)
              select /*+ QB_NAME(WIRE_BENE) */
                 a.ACCT_INTRL_ID,
                 a.ACCT_SEQ_ID,
                 a.PRMRY_CUST_INTRL_ID,
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then w.BENEF_AUG_NM else '--' end as Aug_Nm,
                 -- Counter Party Name                 
                 w.ORIG_ACCT_ID||w.SEND_INSTN_SEQ_ID||w.ORIG_AUG_NM         as Cntr_Party_Nm, 
                 a.ACCT_EFCTV_RISK_NB  as Efctv_Risk_Lvl,
                 w.BENEF_ACTVY_RISK_NB   as Actvty_Risk_Lvl,         
                 w.DATA_DUMP_DT,  
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then w.DATA_DUMP_DT else to_date('01/01/1999','MM/DD/YYYY') end as Small_Data_Dump_Dt,          
                 DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Trxn_Am,
                 0                     as Wthdrwl_Amt, -- Debit
                 DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Deposit_Amt, -- Credit         
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Small_Trans_Amt,                  
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then 1 else 0 end as Small_Trans_Ct,                  
                 case when  w.benef_actvy_risk_nb > 5 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Hr_Am,
                 case when  w.PASS_THRU_FL = 'Y' then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Pass_Thru_Am,
                 case when  DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) - trunc(DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM), -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 
                       when  w.RCV_TRXN_ACTVY_AM - trunc(w.RCV_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
                       when  w.SEND_TRXN_ACTVY_AM - trunc(w.SEND_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
                       else 0 end Lrf_Am,
                 case when w.TRSTD_TRXN_FL = 'Y' then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
                 w.FUNC_CRNCY_CD  
              from 
                  Wire_vw w, 
                  fccmatomic.ACCT a 
              where 
                   w.BENEF_ACCT_ID = a.ACCT_INTRL_ID
               and w.INTRL_BENEF_ACCT_FL = 'Y'  
                   -- Exlude transaction where BENEF = ORIG  or BENEF = SCND_ORIG 
               and ((w.INTRL_ORIG_ACCT_FL = 'Y' and coalesce(w.ORIG_ACCT_ID,'-') <> w.BENEF_ACCT_ID) or  w.INTRL_ORIG_ACCT_FL <> 'Y')     
               and ((coalesce(w.INTRL_SCND_ORIG_ACCT_FL,'-') = 'Y' and coalesce(w.SCND_ORIG_ACCT_ID,'-') <> w.BENEF_ACCT_ID) or  (coalesce(w.INTRL_SCND_ORIG_ACCT_FL,'-') <> 'Y'))    
               -- allows coverage of all jurisdictions without enumerating them in the Included Jurisdiction Codes 
               and ('N' = 'Y' OR a.JRSDCN_CD IN ('AIIN'))
               -- Cover only specific accounts
               and a.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')   
               --  Include Retail Customer Accounts Only 
               and a.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR' 
               -- Exclude Test Accounts
               and coalesce(a.TEST_ACCT_FL,'N') <> 'Y'
               --Exclude Exempted Accounts 
               and a.ACCT_EFCTV_RISK_NB <> -2              
              -- --------------------------    
              union all       
              -- Wire trans - SCND BENEF - Counter Party (ORIG)
              select /*+ QB_NAME(WIRE_SBENE) */
                 a.ACCT_INTRL_ID,
                 a.ACCT_SEQ_ID,
                 a.PRMRY_CUST_INTRL_ID,
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then w.SCND_BENEF_AUG_NM else '--' end as Aug_Nm,
                 -- Counter Party Name                 
                 w.ORIG_ACCT_ID||w.SEND_INSTN_SEQ_ID||w.ORIG_AUG_NM  as Cntr_Party_Nm,
                 a.ACCT_EFCTV_RISK_NB  as Efctv_Risk_Lvl,
                 w.SCND_BENEF_ACTVY_RISK_NB   as Actvty_Risk_Lvl,           
                 w.DATA_DUMP_DT,
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then w.DATA_DUMP_DT else to_date('01/01/1999','MM/DD/YYYY') end as Small_Data_Dump_Dt,            
                 DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Trxn_Am,
                 0                     as Wthdrwl_Amt, -- Debit
                 DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Deposit_Amt, -- Credit         
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Small_Trans_Amt,                  
                 case when DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) >= 1000 and DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) <= 5000 
                      then 1 else 0 end as Small_Trans_Ct,                  
                 case when  w.scnd_benef_actvy_risk_nb > 5 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Hr_Am,
                 case when  w.PASS_THRU_FL = 'Y' then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Pass_Thru_Am,
                 case when  DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) - trunc(DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM), -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 
                      when  w.RCV_TRXN_ACTVY_AM - trunc(w.RCV_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
                      when  w.SEND_TRXN_ACTVY_AM - trunc(w.SEND_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
                      else 0 end Lrf_Am,
                 case when w.TRSTD_TRXN_FL = 'Y' then DECODE('B','F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
                 w.FUNC_CRNCY_CD  
              from 
                 Wire_vw w, 
                 fccmatomic.ACCT a 
              where 
                   w.SCND_BENEF_ACCT_ID = a.ACCT_INTRL_ID
               and w.INTRL_SCND_BENEF_ACCT_FL = 'Y'
               -- Exlude transaction where SCND_BENEF = BENEF
               and ((w.INTRL_BENEF_ACCT_FL = 'Y' and coalesce(w.BENEF_ACCT_ID,'-') <> w.SCND_BENEF_ACCT_ID)  or w.INTRL_BENEF_ACCT_FL <> 'Y')    
                -- Exlude transaction where BENEF = ORIG  or BENEF = SCND_ORIG 
               and ((w.INTRL_ORIG_ACCT_FL = 'Y' and coalesce(w.ORIG_ACCT_ID,'-') <> w.SCND_BENEF_ACCT_ID) or  w.INTRL_ORIG_ACCT_FL <> 'Y')     
               and ((coalesce(w.INTRL_SCND_ORIG_ACCT_FL,'-') = 'Y' and coalesce(w.SCND_ORIG_ACCT_ID,'-') <> w.SCND_BENEF_ACCT_ID) or  (coalesce(w.INTRL_SCND_ORIG_ACCT_FL,'-') <> 'Y'))                   
               -- allows coverage of all jurisdictions without enumerating them in the Included Jurisdiction Codes 
               and ('N' = 'Y' OR a.JRSDCN_CD IN ('AIIN'))
               -- Cover only specific accounts
               and a.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')   
               -- include Retail Customer Accounts only
               and a.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR' 
               -- Exclude Test Accounts
               and coalesce(a.TEST_ACCT_FL,'N') <> 'Y'
               -- Exclude Exempted Accounts
               and a.ACCT_EFCTV_RISK_NB <> -2
              -- --------------------------    
              union all
              -- MI transaction -- REM  
              select /*+ QB_NAME(MI_REM) */
                 a.ACCT_INTRL_ID,
                 a.ACCT_SEQ_ID,
                 a.PRMRY_CUST_INTRL_ID,
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then m.REM_AUG_NM else '--' end as Aug_Nm,
                 -- Counter Party Name                 
                 m.BENEF_ACCT_ID||m.DEP_INSTN_SEQ_ID||m.BENEF_AUG_NM  as Cntr_Party_Nm,
                 a.ACCT_EFCTV_RISK_NB  as Efctv_Risk_Lvl, 
                 m.REM_ACTVY_RISK_NB   as Actvty_Risk_Lvl,          
                 m.DATA_DUMP_DT, 
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then m.DATA_DUMP_DT else to_date('01/01/1999','MM/DD/YYYY') end as Small_Data_Dump_Dt,           
                 DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) as Trxn_Am,
                 DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) as Wthdrwl_Amt, -- Debit
                 0                    as Deposit_Amt, -- Credit         
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end as Small_Trans_Amt,                  
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then 1 else 0 end as Small_Trans_Ct,                  
                    case when m.rem_actvy_risk_nb > 5 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end Hr_Am,
                    case when m.PASS_THRU_FL = 'Y' then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end Pass_Thru_Am,
                    case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) - trunc(DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM), -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) 
                          when m.DEP_TRXN_ACTVY_AM - trunc(m.DEP_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
                          when m.ISSUE_TRXN_ACTVY_AM - trunc(m.ISSUE_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
                          when m.CLR_TRXN_ACTVY_AM - trunc(m.CLR_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)     
                    else 0 end Lrf_Am,
                 case when m.TRSTD_TRXN_FL = 'Y' then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
                 m.FUNC_CRNCY_CD  
              from 
                 Mi_vw m, 
                 fccmatomic.ACCT a 
              where 
                   m.REM_ACCT_ID = a.ACCT_INTRL_ID
               and m.INTRL_REM_ACCT_FL = 'Y'
               -- allows coverage of all jurisdictions without enumerating them in the Included Jurisdiction Codes 
               and ('N' = 'Y' OR a.JRSDCN_CD IN ('AIIN'))
               -- Cover only specific accounts
               and a.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')   
               --  Include Retail Customer Accounts Only 
               and a.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR'
               -- Exclude Test Accounts
               and coalesce(a.TEST_ACCT_FL,'N') <> 'Y'
               --Exclude Exempted Accounts 
               and a.ACCT_EFCTV_RISK_NB <> -2                  
               -- Getting data for look back period only and Utilize indexes     
               --25222051, OFSAABD-31950   
               and m.MANTAS_ISSUE_DATE >  (select Min_Dt from clndr_vw) and m.MANTAS_ISSUE_DATE <= (select Max_Dt from clndr_vw)                   
              -- --------------------------    
              union all      
              -- MI transaction   - BENEF      
              select /*+ QB_NAME(MI_BENE) */
                 a.ACCT_INTRL_ID,
                 a.ACCT_SEQ_ID,
                 a.PRMRY_CUST_INTRL_ID,
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then m.BENEF_AUG_NM else '--' end as Aug_Nm,
                 -- Counter Party Name                 
                 m.REM_ACCT_ID||m.ISSUE_INSTN_SEQ_ID||m.REM_AUG_NM  as Cntr_Party_Nm,
                 a.ACCT_EFCTV_RISK_NB  as Efctv_Risk_Lvl, 
                 m.BENEF_ACTVY_RISK_NB   as Actvty_Risk_Lvl,          
                 m.DATA_DUMP_DT,
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then m.DATA_DUMP_DT else to_date('01/01/1999','MM/DD/YYYY') end as Small_Data_Dump_Dt,            
                 DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) as Trxn_Am,
                 0                   as Wthdrwl_Amt, -- Debit
                 DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) as Deposit_Amt, -- Credit         
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end as Small_Trans_Amt,                  
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then 1 else 0 end as Small_Trans_Ct,                  
                    case when m.benef_actvy_risk_nb > 5 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end Hr_Am,
                    case when m.PASS_THRU_FL = 'Y' then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end Pass_Thru_Am,
                    case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) - trunc(DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM), -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) 
                          when m.DEP_TRXN_ACTVY_AM - trunc(m.DEP_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
                          when m.ISSUE_TRXN_ACTVY_AM - trunc(m.ISSUE_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
                          when m.CLR_TRXN_ACTVY_AM - trunc(m.CLR_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)     
                    else 0 end Lrf_Am,
                 case when m.TRSTD_TRXN_FL = 'Y' then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
                 m.FUNC_CRNCY_CD  
               from 
                 Mi_vw m, 
                 fccmatomic.ACCT a 
              where 
                   m.BENEF_ACCT_ID = a.ACCT_INTRL_ID
               and m.INTRL_BENEF_ACCT_FL = 'Y' 
               -- Exlude transaction where BENEF = REM
               and ((m.INTRL_REM_ACCT_FL = 'Y' and coalesce(m.REM_ACCT_ID,'-') <> m.BENEF_ACCT_ID) or  m.INTRL_REM_ACCT_FL <> 'Y')     
               -- allows coverage of all jurisdictions without enumerating them in the Included Jurisdiction Codes 
               and ('N' = 'Y' OR a.JRSDCN_CD IN ('AIIN'))
               -- Cover only specific accounts
               and a.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')   
               --  Include Retail Customer Accounts Only 
               and a.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR'
               -- Exclude Test Accounts
               and coalesce(a.TEST_ACCT_FL,'N') <> 'Y'
               --Exclude Exempted Accounts 
               and a.ACCT_EFCTV_RISK_NB <> -2            
               -- Getting data for look back period only and Utilize indexes    
               --25222051, OFSAABD-31950   
               and m.MANTAS_POST_DT >  (select Min_Dt from clndr_vw) and m.MANTAS_POST_DT <= (select Max_Dt from clndr_vw)               
              -- --------------------------    
               -- MI transaction SCND BENEF
              union all
              select /*+ QB_NAME(MI_SBENE) */
                 a.ACCT_INTRL_ID,
                 a.ACCT_SEQ_ID,
                 a.PRMRY_CUST_INTRL_ID,
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then m.SCND_BENEF_AUG_NM else '--' end as Aug_Nm,
                 -- Counter Party Name                 
                 m.REM_ACCT_ID||m.ISSUE_INSTN_SEQ_ID||m.REM_AUG_NM  as Cntr_Party_Nm,
                 a.ACCT_EFCTV_RISK_NB        as Efctv_Risk_Lvl,  
                 m.SCND_BENEF_ACTVY_RISK_NB  as Actvty_Risk_Lvl,
                 m.DATA_DUMP_DT,
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then m.DATA_DUMP_DT else to_date('01/01/1999','MM/DD/YYYY') end as Small_Data_Dump_Dt,            
                 DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) as Trxn_Am,
                 0                   as Wthdrwl_Amt, -- Debit
                 DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) as Deposit_Amt, -- Credit         
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end as Small_Trans_Amt,                  
                 case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) >= 1000 and DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) <= 5000 
                      then 1 else 0 end as Small_Trans_Ct,                  
                 case when m.scnd_benef_actvy_risk_nb > 5 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end Hr_Am,
                    case when m.PASS_THRU_FL = 'Y' then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end Pass_Thru_Am,
                    case when DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) - trunc(DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM), -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) 
                          when m.DEP_TRXN_ACTVY_AM - trunc(m.DEP_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
                          when m.ISSUE_TRXN_ACTVY_AM - trunc(m.ISSUE_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
                          when m.CLR_TRXN_ACTVY_AM - trunc(m.CLR_TRXN_ACTVY_AM, -3) = 0 then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)     
                    else 0 end Lrf_Am,
                 case when m.TRSTD_TRXN_FL = 'Y' then DECODE('B','F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
                 m.FUNC_CRNCY_CD  
             from 
                 Mi_vw m, 
                 fccmatomic.ACCT a 
             where
                   m.SCND_BENEF_ACCT_ID = a.ACCT_INTRL_ID
               and m.INTRL_SCND_BENEF_ACCT_FL = 'Y' 
               -- Exlude transaction where SCND_BENEF = BENEF
               and((m.INTRL_BENEF_ACCT_FL = 'Y' and coalesce(m.BENEF_ACCT_ID,'-') <> m.SCND_BENEF_ACCT_ID) or  m.INTRL_BENEF_ACCT_FL <> 'Y')
               -- Exlude transaction where SCND_BENEF = REM
               and ((m.INTRL_REM_ACCT_FL = 'Y' and coalesce(m.REM_ACCT_ID,'-') <> m.SCND_BENEF_ACCT_ID) or  m.INTRL_REM_ACCT_FL <> 'Y')               
               -- allows coverage of all jurisdictions without enumerating them in the Included Jurisdiction Codes 
               and ('N' = 'Y' OR a.JRSDCN_CD IN ('AIIN'))
               -- Cover only specific accounts
               and a.MANTAS_ACCT_BUS_TYPE_CD IN ('RBK','RBR')   
               --  Include Retail Customer Accounts Only 
               and a.MANTAS_ACCT_HOLDR_TYPE_CD = 'CR'
               -- Exclude Test Accounts
               and coalesce(a.TEST_ACCT_FL,'N') <> 'Y'
               --Exclude Exempted Accounts 
               and a.ACCT_EFCTV_RISK_NB <> -2            
               -- Getting data for look back period only and Utilize indexes   
               --25222051, OFSAABD-31950   
               and m.MANTAS_POST_DT >  (select Min_Dt from clndr_vw) and m.MANTAS_POST_DT <= (select Max_Dt from clndr_vw)  
              -- --------------------------    
        ) t
        group by 
            t.ACCT_INTRL_ID       
        having
          -- Frequency_Period Period
          --25222051   
           max(t.Small_Data_Dump_Dt) >  (select Freq_Dt from clndr_vw) and max(t.Small_Data_Dump_Dt) <= (select Max_Dt from clndr_vw)   
) g
WHERE   
    -- determine if divisor is equal to zero  
    g.Tot_Wthdrwl_Trans_Amt > 0 and g.Tot_Trans_Amt > 0 
    and 
(  
 (
       g.Overall_Risk = 'HR'
     -- the aggregated low dollar transaction amount;  OFSAABD-8337
  and   g.Tot_Small_Trans_Amt >= 5000 and g.Tot_Small_Trans_Amt <= 50000
    --OFSAABD-10438 
    -- Bug32949720
         -- the low dollar amount over total transaction amount
  and case when  g.Tot_Trans_Amt > 0 then g.Tot_Small_Trans_Amt*100/g.Tot_Trans_Amt else 0 end >= 90
       -- the depost over withdrawal transactions amount percentage.
  and case when  g.Tot_Wthdrwl_Trans_Amt > 0  then g.Tot_Deposit_Trans_Amt*100/g.Tot_Wthdrwl_Trans_Amt else 0 end >= 75
  and case when  g.Tot_Wthdrwl_Trans_Amt > 0  then g.Tot_Deposit_Trans_Amt*100/g.Tot_Wthdrwl_Trans_Amt else 0 end <= 95  
     -- the number of different Counter Parties assosiated with the account; OFSAABD-8337
     -- count(distinct (t.Cntr_Party_Acct||t.Cntr_Party_Instn||t.Cntr_Party_Nm)) 
  and   g.Cntr_Party_Ct >= 3 and g.Cntr_Party_Ct <= 10
     -- the number of different Names assosoated with the account
     -- count(distinct(case when t.Aug_Nm id null then 'NO_NAME_PROVIDED' else t.Aug_Nm end
  and Names_Ct >= 2 
  )
  OR
 (
       g.Overall_Risk = 'RR'
     -- the aggregated low dollar transaction amount ;  OFSAABD-8337
  and   g.Tot_Small_Trans_Amt >= 5000 and g.Tot_Small_Trans_Amt <= 50000
    --OFSAABD-10438 
    -- Bug32949720
         -- the low dollar amount over total transaction amount
  and case when  g.Tot_Trans_Amt > 0 then g.Tot_Small_Trans_Amt*100/g.Tot_Trans_Amt else 0 end >= 90
       -- the depost over withdrawal transactions amount percentage.
  and case when  g.Tot_Wthdrwl_Trans_Amt > 0  then g.Tot_Deposit_Trans_Amt*100/g.Tot_Wthdrwl_Trans_Amt else 0 end >= 75
  and case when  g.Tot_Wthdrwl_Trans_Amt > 0  then g.Tot_Deposit_Trans_Amt*100/g.Tot_Wthdrwl_Trans_Amt else 0 end <= 95  
     -- the number of different Counter Parties assosiated with the account ; OFSAABD-8337
     -- count(distinct (t.Cntr_Party_Acct||t.Cntr_Party_Instn||t.Cntr_Party_Nm)) 
  and   g.Cntr_Party_Ct >= 3 and g.Cntr_Party_Ct <= 10
     -- the number of different Names assosoated with the account
     -- count(distinct(case when t.Aug_Nm id null then 'NO_NAME_PROVIDED' else t.Aug_Nm end
  and Names_Ct >= 2 
  )
  OR
(
       g.Overall_Risk = 'MR'
     -- the aggregated low dollar transaction amount ;  OFSAABD-8337
  and   g.Tot_Small_Trans_Amt >= 5000 and g.Tot_Small_Trans_Amt <= 50000
    --OFSAABD-10438 
    -- Bug32949720
         -- the low dollar amount over total transaction amount
  and case when  g.Tot_Trans_Amt > 0 then g.Tot_Small_Trans_Amt*100/g.Tot_Trans_Amt else 0 end >= 90
       -- the depost over withdrawal transactions amount percentage.
  and case when  g.Tot_Wthdrwl_Trans_Amt > 0  then g.Tot_Deposit_Trans_Amt*100/g.Tot_Wthdrwl_Trans_Amt else 0 end >= 75
  and case when  g.Tot_Wthdrwl_Trans_Amt > 0  then g.Tot_Deposit_Trans_Amt*100/g.Tot_Wthdrwl_Trans_Amt else 0 end <= 95  
  
     -- the number of different Counter Parties assosiated with the account ; OFSAABD-8337
     -- count(distinct (t.Cntr_Party_Acct||t.Cntr_Party_Instn||t.Cntr_Party_Nm)) 
  and   g.Cntr_Party_Ct >= 3 and g.Cntr_Party_Ct <= 10
     -- the number of different Names assosoated with the account
     -- count(distinct(case when t.Aug_Nm id null then 'NO_NAME_PROVIDED' else t.Aug_Nm end
  and  Names_Ct >= 2 
  )  
 )
 ) ot ORDER BY ot.ACCT_SEQ_ID