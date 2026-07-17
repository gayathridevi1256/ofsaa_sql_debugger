select 
       g.cust_seq_id
     , g.cust_id
     , g.Cust_Acct_Ct
     , g.SEASONED_CUST_FL
     , g.Tot_Trxn_Am_Cdt
     , g.Tot_trxn_ct_cdt
     , g.Tot_trxn_am_dbt
     , g.Tot_trxn_ct_dbt
     , g.Tot_trxn_am
     , g.Tot_trxn_ct
     , g.ACTVY_RISK
     , g.effctv_risk
     , g.Hr_Prctg, 
       g.Lrf_Prctg, 
       g.Pass_Thru_Prctg ,
       g.Overall_Risk
	 , g.Trusted_Trans_Amt
   , g.FUNC_CRNCY_CD
from 
(
SELECT
 max(t.cust_seq_id) AS cust_seq_id,
 t.cust_id,
 COUNT(DISTINCT t.acct_intrl_id) AS cust_acct_ct,
 MAX(SEAS_FL) SEASONED_CUST_FL,
 SUM(t.d_amt_cdt) AS tot_trxn_am_cdt,
 SUM(t.d_ct_cdt) AS tot_trxn_ct_cdt,
 SUM(t.d_amt_dbt) AS tot_trxn_am_dbt,
 SUM(t.d_ct_dbt) AS tot_trxn_ct_dbt,
 SUM(t.d_amt_cdt) + SUM(t.d_amt_dbt) AS tot_trxn_am,
 SUM(t.d_ct_cdt) + SUM(t.d_ct_dbt) AS tot_trxn_ct, 
 SUM(t.hr_amt) AS tot_hr_amt,
 SUM(t.lrf_amt) AS tot_lrf_amt,
 SUM(t.pass_thru_amt) AS tot_pass_thru_amt,
 MAX(t.activity_risk) AS ACTVY_RISK,
 MAX(t.effctv_risk) AS EFFCTV_RISK,
 CASE WHEN SUM(t.d_amt_cdt) + SUM(t.d_amt_dbt) = 0 THEN 0
  ELSE (SUM(t.hr_amt)*100) / (SUM(t.d_amt_cdt) + SUM(t.d_amt_dbt))
 END AS Hr_Prctg, 
 CASE WHEN SUM(t.d_amt_cdt) + SUM(t.d_amt_dbt) = 0 THEN 0
  ELSE (sum(t.lrf_amt)*100) / (SUM(t.d_amt_cdt) + SUM(t.d_amt_dbt))
 END AS Lrf_Prctg, 
 CASE WHEN SUM(t.d_amt_cdt) + SUM(t.d_amt_dbt) = 0 THEN 0
  ELSE (sum(t.pass_thru_amt)*100) / (SUM(t.d_amt_cdt) + SUM(t.d_amt_dbt))
 END AS Pass_Thru_Prctg ,
 CASE WHEN (max(t.effctv_risk) >= 5 AND max(t.activity_risk) >= 5) THEN 'HR'
      WHEN (max(t.effctv_risk) < 5 AND max(t.activity_risk) < 5) THEN 'RR'
    ELSE 'MR' 
 END AS OVERALL_RISK,
 sum(t.Trusted_Trans_Amt) as Trusted_Trans_Amt,
 max(t.FUNC_CRNCY_CD) as FUNC_CRNCY_CD

FROM (
-- WIRE Credit BENE 
SELECT 
          ca.CUST_SEQ_ID,
          ca.CUST_ID,
          ca.ACCT_INTRL_ID,
          tr.data_dump_dt as Dump_Dt,
          ca.CUST_EFCTV_RISK_NB AS effctv_risk,
          --31536090 
          CASE WHEN (ca.Min_Acct_Open_Dt) >= (select Max_Days_Opened_Dt from clndr_vw) THEN 0 
           ELSE 1 END SEAS_FL,
          tr.Trxn_Am AS d_amt_cdt,
          1 AS d_ct_cdt,
          0 AS d_amt_dbt,
          0 AS d_ct_dbt,
          --21153210
          CASE WHEN (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y')
               THEN tr.BENEF_ACTVY_RISK_NB 
               ELSE tr.SCND_BENEF_ACTVY_RISK_NB END ACTIVITY_RISK,
         (CASE WHEN
                 (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y' and tr.BENEF_ACTVY_RISK_NB > 5)  
                 OR
                 (tr.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_BENEF_ACCT_FL = 'Y' AND tr.SCND_BENEF_ACTVY_RISK_NB > 5)
               THEN tr.Trxn_Am
               ELSE 0 END) HR_AMT,    
          tr.PASS_THRU_AMT,        
          tr.LRF_AMT,
		      tr.Trusted_Trans_Amt,
          tr.FUNC_CRNCY_CD				 
FROM      Wire_Trxn_Vw tr,
          Cust_Accounts ca
          
WHERE     
--21153210
--31536090 
(tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y')

UNION ALL

-- WIRE Credit SCND_BENE 
SELECT 
          ca.CUST_SEQ_ID,
          ca.CUST_ID,
          ca.ACCT_INTRL_ID,
          tr.data_dump_dt as Dump_Dt,
          ca.CUST_EFCTV_RISK_NB AS effctv_risk,
          --31536090 
          CASE WHEN (ca.Min_Acct_Open_Dt) >= (select Max_Days_Opened_Dt from clndr_vw) THEN 0 
           ELSE 1 END SEAS_FL,
          tr.Trxn_Am AS d_amt_cdt,
          1 AS d_ct_cdt,
          0 AS d_amt_dbt,
          0 AS d_ct_dbt,
          --21153210
          CASE WHEN (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y')
               THEN tr.BENEF_ACTVY_RISK_NB 
               ELSE tr.SCND_BENEF_ACTVY_RISK_NB END ACTIVITY_RISK,
         (CASE WHEN
                 (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y' and tr.BENEF_ACTVY_RISK_NB > 5)  
                 OR
                 (tr.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_BENEF_ACCT_FL = 'Y' AND tr.SCND_BENEF_ACTVY_RISK_NB > 5)
               THEN tr.Trxn_Am
               ELSE 0 END) HR_AMT,    
          tr.PASS_THRU_AMT,        
          tr.LRF_AMT,
		      tr.Trusted_Trans_Amt,
          tr.FUNC_CRNCY_CD				 
FROM      Wire_Trxn_Vw tr,
          Cust_Accounts ca
          
WHERE     
--21153210, 31536090,         
tr.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_SCND_BENEF_ACCT_FL = 'Y'
-- 33838789 
 -- verification that accounts in SCND_BENE and BENE are not impacted to the same Customer
and (case when tr.INTRL_BENEF_ACCT_FL <> 'Y'  then 1
          when ca.CUST_ID not in (select ca2.CUST_ID from Cust_Accounts ca2 where ca2.ACCT_INTRL_ID = COALESCE(tr.BENEF_ACCT_ID, 'NULL')) then 1
          else 0 end) = 1

UNION ALL

-- WIRE Debit ORIG 
SELECT 
          ca.CUST_SEQ_ID,
          ca.CUST_ID,
          ca.ACCT_INTRL_ID,
          tr.data_dump_dt as Dump_Dt,
          ca.CUST_EFCTV_RISK_NB AS effctv_risk,
          --31536090 
          CASE WHEN (ca.Min_Acct_Open_Dt) >= (select Max_Days_Opened_Dt from clndr_vw) THEN 0 
           ELSE 1 END SEAS_FL,
          0 AS d_amt_cdt,
          0 AS d_ct_cdt,
          tr.Trxn_Am AS d_amt_dbt,
          1 AS d_ct_dbt,
          --21153210
          CASE WHEN (tr.ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_ORIG_ACCT_FL = 'Y')
               THEN tr.ORIG_ACTVY_RISK_NB 
               ELSE tr.SCND_ORIG_ACTVY_RISK_NB END ACTIVITY_RISK,
          (CASE WHEN
                 (tr.ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_ORIG_ACCT_FL = 'Y' and tr.ORIG_ACTVY_RISK_NB > 5)  OR
                 (tr.SCND_ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_ORIG_ACCT_FL = 'Y' AND tr.SCND_ORIG_ACTVY_RISK_NB > 5)
                 THEN tr.Trxn_Am
                 ELSE 0 END) HR_AMT,           
          tr.PASS_THRU_AMT,        
          tr.LRF_AMT,
		      tr.Trusted_Trans_Amt,
          tr.FUNC_CRNCY_CD				 
FROM      Wire_Trxn_Vw tr,
          Cust_Accounts ca
WHERE     
--21153210, 31536090 

tr.ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_ORIG_ACCT_FL = 'Y'

UNION ALL

-- WIRE Debit SCND_ORIG 
SELECT 
          ca.CUST_SEQ_ID,
          ca.CUST_ID,
          ca.ACCT_INTRL_ID,
          tr.data_dump_dt as Dump_Dt,
          ca.CUST_EFCTV_RISK_NB AS effctv_risk,
          --31536090 
          CASE WHEN (ca.Min_Acct_Open_Dt) >= (select Max_Days_Opened_Dt from clndr_vw) THEN 0 
           ELSE 1 END SEAS_FL,
          0 AS d_amt_cdt,
          0 AS d_ct_cdt,
          tr.Trxn_Am AS d_amt_dbt,
          1 AS d_ct_dbt,
          --21153210
          CASE WHEN (tr.ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_ORIG_ACCT_FL = 'Y')
               THEN tr.ORIG_ACTVY_RISK_NB 
               ELSE tr.SCND_ORIG_ACTVY_RISK_NB END ACTIVITY_RISK,
          (CASE WHEN
                 (tr.ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_ORIG_ACCT_FL = 'Y' and tr.ORIG_ACTVY_RISK_NB > 5)  OR
                 (tr.SCND_ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_ORIG_ACCT_FL = 'Y' AND tr.SCND_ORIG_ACTVY_RISK_NB > 5)
                 THEN tr.Trxn_Am
                 ELSE 0 END) HR_AMT,           
          tr.PASS_THRU_AMT,        
          tr.LRF_AMT,
		      tr.Trusted_Trans_Amt,
          tr.FUNC_CRNCY_CD				 
FROM      Wire_Trxn_Vw tr,
          Cust_Accounts ca
WHERE     
--21153210,31536090 
tr.SCND_ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_SCND_ORIG_ACCT_FL = 'Y'
--33838789 verification that accounts in SCND_ORIG and ORIG are not impacted to the same Customer
and (case when tr.INTRL_ORIG_ACCT_FL <> 'Y'  then 1
          when ca.CUST_ID not in (select ca2.CUST_ID from Cust_Accounts ca2 where ca2.ACCT_INTRL_ID = COALESCE(tr.ORIG_ACCT_ID, 'NULL')) then 1
          else 0 end) = 1

UNION ALL
-- MI Credit BENE 
SELECT 
          ca.CUST_SEQ_ID,
          ca.CUST_ID,
          ca.acct_intrl_id,
          tr.data_dump_dt as Dump_Dt,
          ca.CUST_EFCTV_RISK_NB AS effctv_risk,
          --31536090 
          CASE WHEN (ca.Min_Acct_Open_Dt) >= (select Max_Days_Opened_Dt from clndr_vw) THEN 0 
           ELSE 1 END SEAS_FL,
          tr.Trxn_Am AS d_amt_cdt,
          1 AS d_ct_cdt,
          0 AS d_amt_dbt,
          0 AS d_ct_dbt,
          --21153210
          CASE WHEN (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y')
               THEN tr.BENEF_ACTVY_RISK_NB 
               ELSE tr.SCND_BENEF_ACTVY_RISK_NB END ACTIVITY_RISK,
         (CASE WHEN
                 (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y' and tr.BENEF_ACTVY_RISK_NB > 5)  
                 OR
                 (tr.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_BENEF_ACCT_FL = 'Y' AND tr.SCND_BENEF_ACTVY_RISK_NB > 5)
               THEN tr.Trxn_Am
               ELSE 0 END) HR_AMT,    
          tr.PASS_THRU_AMT,        
          tr.LRF_AMT,
				  tr.Trusted_Trans_Amt,
          tr.FUNC_CRNCY_CD
FROM      Mi_Trxn_Vw tr,
          Cust_Accounts ca
WHERE     
--21153210, 31536090 
tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y'
and tr.MANTAS_POST_DT >= (select Min_Dt from clndr_vw) and tr.MANTAS_POST_DT <= (select Max_Dt from clndr_vw)

UNION ALL

-- MI Credit SCND_BENE 
SELECT 
          ca.CUST_SEQ_ID,
          ca.CUST_ID,
          ca.acct_intrl_id,
          tr.data_dump_dt as Dump_Dt,
          ca.CUST_EFCTV_RISK_NB AS effctv_risk,
          --31536090 
          CASE WHEN (ca.Min_Acct_Open_Dt) >= (select Max_Days_Opened_Dt from clndr_vw) THEN 0 
           ELSE 1 END SEAS_FL,
          tr.Trxn_Am AS d_amt_cdt,
          1 AS d_ct_cdt,
          0 AS d_amt_dbt,
          0 AS d_ct_dbt,
          --21153210
          CASE WHEN (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y')
               THEN tr.BENEF_ACTVY_RISK_NB 
               ELSE tr.SCND_BENEF_ACTVY_RISK_NB END ACTIVITY_RISK,
         (CASE WHEN
                 (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y' and tr.BENEF_ACTVY_RISK_NB > 5)  
                 OR
                 (tr.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_BENEF_ACCT_FL = 'Y' AND tr.SCND_BENEF_ACTVY_RISK_NB > 5)
               THEN tr.Trxn_Am
               ELSE 0 END) HR_AMT,    
          tr.PASS_THRU_AMT,        
          tr.LRF_AMT,
				  tr.Trusted_Trans_Amt,
          tr.FUNC_CRNCY_CD
FROM      Mi_Trxn_Vw tr,
          Cust_Accounts ca
WHERE     
--21153210, 31536090 
tr.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_SCND_BENEF_ACCT_FL = 'Y'
--33838789 verification that accounts in SCND_BENE and BENE are not impacted to the same Customer
and (case when tr.INTRL_BENEF_ACCT_FL <> 'Y'  then 1
           when ca.CUST_ID not in (select ca2.CUST_ID from Cust_Accounts ca2 where ca2.ACCT_INTRL_ID = COALESCE(tr.BENEF_ACCT_ID, 'NULL')) then 1
         else 0 end) = 1

and tr.MANTAS_POST_DT >= (select Min_Dt from clndr_vw) and tr.MANTAS_POST_DT <= (select Max_Dt from clndr_vw)


UNION ALL
-- MI Debit 
SELECT
          ca.CUST_SEQ_ID,
          ca.CUST_ID,
          ca.acct_intrl_id,
          tr.data_dump_dt as Dump_Dt,
          ca.CUST_EFCTV_RISK_NB AS effctv_risk,
          --31536090 
          CASE WHEN (ca.Min_Acct_Open_Dt) >= (select Max_Days_Opened_Dt from clndr_vw) THEN 0 
           ELSE 1 END SEAS_FL,
          0 AS d_amt_cdt,
          0 AS d_ct_cdt,
          tr.Trxn_Am AS d_amt_dbt,
          1 AS d_ct_dbt,
          tr.REM_ACTVY_RISK_NB ACTIVITY_RISK,
          (CASE WHEN tr.REM_ACTVY_RISK_NB > 5
                 THEN tr.Trxn_Am
                 ELSE 0 END) HR_AMT,                 
          tr.PASS_THRU_AMT,        
          tr.LRF_AMT,
				  tr.Trusted_Trans_Amt,
          tr.FUNC_CRNCY_CD
FROM      Mi_Trxn_Vw tr,
          Cust_Accounts ca

WHERE     tr.REM_ACCT_ID = ca.ACCT_INTRL_ID
and tr.INTRL_REM_ACCT_FL = 'Y'
--21153210, 31536090 
and tr.MANTAS_ISSUE_DATE >= (select Min_Dt from clndr_vw) and tr.MANTAS_ISSUE_DATE <= (select Max_Dt from clndr_vw)

UNION ALL
-- Cash Credit/Debit  
SELECT 
          ca.CUST_SEQ_ID,
          ca.CUST_ID,
          ca.acct_intrl_id,
          tr.data_dump_dt as Dump_Dt,
          ca.CUST_EFCTV_RISK_NB AS effctv_risk,
          --31536090 
          CASE WHEN (ca.Min_Acct_Open_Dt) >= (select Max_Days_Opened_Dt from clndr_vw) THEN 0 
           ELSE 1 END SEAS_FL,
          case when tr.DBT_CDT_CD = 'C' then DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end AS d_amt_cdt,
          case when tr.DBT_CDT_CD = 'C' then 1 else 0 end AS d_ct_cdt,
          case when tr.DBT_CDT_CD = 'D' then DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end AS d_amt_dbt,
          case when tr.DBT_CDT_CD = 'D' then 1 else 0 end AS d_ct_dbt,
          tr.CASH_TRXN_ACTVY_RISK_NB ACTIVITY_RISK,
          (CASE WHEN tr.CASH_TRXN_ACTVY_RISK_NB > 5
                 THEN DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 ELSE 0 END) HR_AMT,                 
        0 PASS_THRU_AMT,        
        (CASE WHEN DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) - TRUNC(DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM), -4) = 0 THEN DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) 
                 WHEN tr.TRXN_ACTVY_AM - TRUNC(tr.TRXN_ACTVY_AM, -4) = 0 THEN DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 ELSE 0 END) LRF_AMT
		,0 as Trusted_Trans_Amt
        ,tr.FUNC_CRNCY_CD
FROM      fccmatomic.CASH_TRXN tr,
          Cust_Accounts ca

WHERE     tr.ACCT_INTRL_ID = ca.ACCT_INTRL_ID
AND       ('Y'='Y' OR tr.SRC_SYS_CD IN ('Inactive'))
and       tr.MANTAS_TRXN_PURP_CD = 'GENERAL'
and       tr.MANTAS_TRXN_PRDCT_CD in ('DEBIT-CARD', 'SVC', 'CREDIT-CARD', 'CURRENCY', 'PHYS')
and       DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) >=3000
--31536090 
and tr.TRXN_EXCTN_DT >= (select Min_Dt from clndr_vw) and tr.TRXN_EXCTN_DT <= (select Max_Dt from clndr_vw)
and tr.DATA_DUMP_DT >= (select Min_Dt from clndr_vw) and tr.DATA_DUMP_DT <= (select Max_Dt from clndr_vw)
and tr.CXL_PAIR_TRXN_INTRL_ID is null

UNION ALL
-- Jrnl Credit/Debit 
SELECT 
          ca.CUST_SEQ_ID,
          ca.CUST_ID,
          ca.acct_intrl_id,
          tr.data_dump_dt as Dump_Dt,
          ca.CUST_EFCTV_RISK_NB AS effctv_risk,
          --31536090 
          CASE WHEN (ca.Min_Acct_Open_Dt) >= (select Max_Days_Opened_Dt from clndr_vw) THEN 0 
           ELSE 1 END SEAS_FL,
          case when tr.DBT_CDT_CD = 'C' then DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end AS d_amt_cdt,
          case when tr.DBT_CDT_CD = 'C' then 1 else 0 end AS d_ct_cdt,
          case when tr.DBT_CDT_CD = 'D' then DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end AS d_amt_dbt,
          case when tr.DBT_CDT_CD = 'D' then 1 else 0 end AS d_ct_dbt,
          tr.BO_TRXN_ACTVY_RISK_NB ACTIVITY_RISK,
          (CASE WHEN tr.BO_TRXN_ACTVY_RISK_NB > 5
                 THEN DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 ELSE 0 END) HR_AMT,                 
        0 PASS_THRU_AMT,        
        (CASE WHEN DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) - TRUNC(DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM), -4) = 0 THEN DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) 
                 WHEN tr.TRXN_RPTNG_AM - TRUNC(tr.TRXN_RPTNG_AM, -4) = 0 THEN DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 ELSE 0 END) LRF_AMT
		,case when tr.TRSTD_TRXN_FL = 'Y' then DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt	
        ,tr.FUNC_CRNCY_CD			 
FROM      fccmatomic.BACK_OFFICE_TRXN tr,
          Cust_Accounts ca
          
WHERE     ca.ACCT_INTRL_ID = tr.ACCT_INTRL_ID
AND       ('Y'='Y' OR tr.SRC_SYS_CD IN ('Inactive'))
and       DECODE('B','F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) >=3000 
AND       tr.MANTAS_TRXN_PRDCT_CD in ('JOURNAL')
and       tr.MANTAS_TRXN_PURP_CD = 'GENERAL'
AND       tr.CXL_PAIR_TRXN_INTRL_ID is null
--31536090 
and tr.EXCTN_DT >= (select Min_Dt from clndr_vw) and tr.EXCTN_DT <= (select Max_Dt from clndr_vw)
and tr.DATA_DUMP_DT >= (select Min_Dt from clndr_vw) and tr.DATA_DUMP_DT <= (select Max_Dt from clndr_vw)
and ('Y' = 'Y' or (tr.UNRLTD_PARTY_CD IS NOT NULL))
and ('Y' = 'Y' or COALESCE(tr.TRSTD_TRXN_FL,'N') ='N')

) t 
 GROUP BY  t.cust_id
having 
      --31536090 
      max(t.dump_dt) > (select Freq_Dt from clndr_vw) and max(t.dump_dt) <= (select Max_Dt from clndr_vw)
) g 
where
 (( Overall_Risk = 'HR' and 
    SEASONED_CUST_FL = 1 and
   (g.Tot_Trxn_Am_Cdt >= 100000 or g.Tot_Trxn_Am_Dbt >= 100000)
   )
    or
    (Overall_Risk = 'MR' and 
    SEASONED_CUST_FL = 1 and
       (g.Tot_Trxn_Am_Cdt >= 100000 or g.Tot_Trxn_Am_Dbt >= 100000))
    or
    ( Overall_Risk = 'RR'and 
    SEASONED_CUST_FL = 1 and
       (g.Tot_Trxn_Am_Cdt >= 100000 or g.Tot_Trxn_Am_Dbt >= 100000))
    or
    (Overall_Risk = 'HR' and
     SEASONED_CUST_FL = 0 and
       (g.Tot_Trxn_Am_Cdt >= 100000 or g.Tot_Trxn_Am_Dbt >= 100000))
    or
    (Overall_Risk = 'MR' and
     SEASONED_CUST_FL = 0 and
       (g.Tot_Trxn_Am_Cdt >= 3000 or g.Tot_Trxn_Am_Dbt >= 3000))
    or
    ( Overall_Risk = 'RR'and
     SEASONED_CUST_FL = 0 and
       (g.Tot_Trxn_Am_Cdt >= 100000 or g.Tot_Trxn_Am_Dbt >= 100000)))