-- REFERENCE QUERY
-- Extracted: 2026-06-07 20:39:36.233857

SELECT ot.CUST_SEQ_ID, ot.LRF_PRCTG, ot.CUST_ID, ot.TOT_TRXN_CT_DBT, ot.TOT_TRXN_AM_DBT, ot.ACTVY_RISK, ot.TOT_TRXN_CT_CDT, ot.TOT_TRXN_CT, ot.TOT_TRXN_AM_CDT, ot.TOT_TRXN_AM, ot.HR_PRCTG, ot.OVERALL_RISK, ot.PASS_THRU_PRCTG, ot.SEASONED_CUST_FL, ot.EFFCTV_RISK, ot.CUST_ACCT_CT, ot.TRUSTED_TRANS_AMT, ot.FUNC_CRNCY_CD FROM (--Bug#33838789 Performance update, verification of the same CU in legs
--Bug#31536090 Performance update, splitting BENE/SCND BENE/ ORIG/SCND ORIG to separate UNION ALL parts
--OFSAABD-17684
with clndr_vw as ( --Bug#31536090 
select
(select cal.clndr_dt from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = @Look_Back_Period - 1) as Min_Dt,
(select cal.clndr_dt from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = 0) as Max_Dt,
(select add_days(cal.CLNDR_DT, -@Frequency_Period) from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = 0) as  Freq_Dt,
(select add_days(cal.CLNDR_DT, -@Max_Days_Opened) from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = 0) as Max_Days_Opened_Dt
FROM dual
),

Wire_Trxn_Vw as
(SELECT  
          tr.BENEF_ACCT_ID,
          tr.SCND_BENEF_ACCT_ID,
          tr.ORIG_ACCT_ID,
          tr.SCND_ORIG_ACCT_ID,
          tr.data_dump_dt,
          DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) as Trxn_Am,
          tr.BENEF_ACTVY_RISK_NB,
          tr.SCND_BENEF_ACTVY_RISK_NB,
          tr.ORIG_ACTVY_RISK_NB,
          tr.SCND_ORIG_ACTVY_RISK_NB,
          tr.INTRL_BENEF_ACCT_FL,
          tr.INTRL_SCND_BENEF_ACCT_FL,
          tr.INTRL_ORIG_ACCT_FL,          
          tr.INTRL_SCND_ORIG_ACCT_FL,
          (CASE WHEN tr.PASS_THRU_FL='Y' THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) ELSE 0 END) PASS_THRU_AMT,        
          (CASE WHEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) - TRUNC(DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM), -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) 
                 WHEN tr.RCV_TRXN_ACTVY_AM - TRUNC(tr.RCV_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 WHEN tr.SEND_TRXN_ACTVY_AM - TRUNC(tr.SEND_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 ELSE 0 END) LRF_AMT,
	      	case when tr.TRSTD_TRXN_FL = 'Y' then DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
          tr.FUNC_CRNCY_CD 				 
FROM      fccmatomic.WIRE_TRXN tr
WHERE
   (@All_Trans_Src_Fl='Y' OR tr.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
and DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) >=@Min_Individual_Trans_Amt
AND tr.MANTAS_TRXN_PRDCT_CD in (@Incl_Wire_Trxn_Prdct_Type_Lst)
and tr.MANTAS_TRXN_PURP_CD = 'GENERAL'
--31536090 
and tr.TRXN_EXCTN_DT >= (select Min_Dt from clndr_vw) and tr.TRXN_EXCTN_DT <= (select Max_Dt from clndr_vw)
and tr.DATA_DUMP_DT >= (select Min_Dt from clndr_vw) and tr.DATA_DUMP_DT <= (select Max_Dt from clndr_vw)
and (@Include_Related_Parties_Fl = 'Y' or   (tr.UNRLTD_PARTY_FL = 'Y' or tr.UNRLTD_PARTY_FL IS NULL))
and (@Include_B2B_Trnfr_Fl = 'Y' or NOT(tr.BANK_TO_BANK_TRNFR_FL = 'Y' and tr.PASS_THRU_FL = 'N'))
and (@Include_Trusted_Trans_FL = 'Y' or COALESCE(tr.TRSTD_TRXN_FL,'N') ='N')
and tr.CXL_PAIR_TRXN_INTRL_ID is null
),

Mi_Trxn_Vw as
(SELECT
          tr.BENEF_ACCT_ID,
          tr.SCND_BENEF_ACCT_ID,
          tr.REM_ACCT_ID,
          tr.data_dump_dt,
          --21153210
          tr.MANTAS_POST_DT,
          tr.MANTAS_ISSUE_DATE,
          DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) as Trxn_Am,
          tr.BENEF_ACTVY_RISK_NB,
          tr.SCND_BENEF_ACTVY_RISK_NB,
          tr.REM_ACTVY_RISK_NB,
          tr.INTRL_BENEF_ACCT_FL,
          tr.INTRL_SCND_BENEF_ACCT_FL,
          tr.INTRL_REM_ACCT_FL,
          (CASE WHEN tr.PASS_THRU_FL='Y' THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) ELSE 0 END) PASS_THRU_AMT,        
          (CASE WHEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) - TRUNC(DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM), -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) 
                 WHEN tr.CLR_TRXN_ACTVY_AM - TRUNC(tr.CLR_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 WHEN tr.DEP_TRXN_ACTVY_AM - TRUNC(tr.DEP_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 WHEN tr.ISSUE_TRXN_ACTVY_AM - TRUNC(tr.ISSUE_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 ELSE 0 END) LRF_AMT,
				  case when tr.TRSTD_TRXN_FL = 'Y' then DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
          tr.FUNC_CRNCY_CD
FROM      fccmatomic.MI_TRXN tr

WHERE
   (@All_Trans_Src_Fl='Y' OR tr.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
and tr.MANTAS_TRXN_PURP_CD = 'GENERAL'
and tr.MANTAS_TRXN_PRDCT_CD in (@Incl_MI_Trxn_Prdct_Type_Lst)
and DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) >=@Min_Individual_Trans_Amt
--31536090 
--21153210
--and tr.MANTAS_POST_DT IN (SELECT KC.CLNDR_DT FROM fccmatomic.KDD_CAL KC WHERE KC.CLNDR_NM='SYSCAL' AND KC.CLNDR_DAY_AGE between 0 and @Look_Back_Period - 1)
and tr.DATA_DUMP_DT >= (select Min_Dt from clndr_vw) and tr.DATA_DUMP_DT <= (select Max_Dt from clndr_vw)
and (@Include_Related_Parties_Fl = 'Y' or   (tr.UNRLTD_PARTY_FL = 'Y' or tr.UNRLTD_PARTY_FL IS NULL))
and (@Include_B2B_Trnfr_Fl = 'Y' or NOT(tr.BANK_TO_BANK_TRNFR_FL = 'Y' and tr.PASS_THRU_FL = 'N'))
and (@Include_Trusted_Trans_FL = 'Y' or COALESCE(tr.TRSTD_TRXN_FL,'N') ='N')
and tr.CXL_PAIR_TRXN_INTRL_ID is null
),

--27476375 
Cust_Accounts as
(SELECT 
        c.CUST_SEQ_ID,
        ac.PRMRY_CUST_INTRL_ID CUST_ID,
        ac.ACCT_INTRL_ID,
        c.CUST_EFCTV_RISK_NB,
        min(ac.ACCT_OPEN_DT) over (partition by c.CUST_SEQ_ID) Min_Acct_Open_Dt
        
FROM        
 fccmatomic.ACCT ac,
 fccmatomic.CUST c 
WHERE     
    c.CUST_INTRL_ID = ac.PRMRY_CUST_INTRL_ID
AND ac.MANTAS_ACCT_HOLDR_TYPE_CD in (@Incld_Acct_Hldr_Typ_Cd)
AND c.CUST_EFCTV_RISK_NB <> -2 
AND ac.MANTAS_ACCT_BUS_TYPE_CD in (@Mantas_Bus_Acct_Type_Lst)
AND (@All_Jurisdictions_Fl = 'Y' or c.JRSDCN_CD in (@Incl_Jurisdictions_Lst))
AND @Primary_Cust_Fl = 'Y'

UNION ALL
SELECT 
        c.CUST_SEQ_ID,
        c.CUST_INTRL_ID CUST_ID,
        ac.ACCT_INTRL_ID,
        c.CUST_EFCTV_RISK_NB,
        min(ac.ACCT_OPEN_DT) over (partition by c.CUST_SEQ_ID) Min_Acct_Open_Dt
FROM        
  fccmatomic.ACCT ac,
  fccmatomic.CUST_ACCT ca, 
  fccmatomic.CUST c,
  fccmatomic.CUST_ACCT_ROLE car
WHERE     
    ac.ACCT_INTRL_ID = ca.ACCT_INTRL_ID
AND ca.CUST_INTRL_ID = c.CUST_INTRL_ID
AND ca.CUST_ACCT_ROLE_CD = car.CUST_ACCT_ROLE_CD
AND ac.MANTAS_ACCT_HOLDR_TYPE_CD in (@Incld_Acct_Hldr_Typ_Cd)
AND c.CUST_EFCTV_RISK_NB <> -2 
AND ac.MANTAS_ACCT_BUS_TYPE_CD in (@Mantas_Bus_Acct_Type_Lst)
AND (@All_Jurisdictions_Fl = 'Y' or c.JRSDCN_CD in (@Incl_Jurisdictions_Lst))
AND (car.TRDNG_AUTH_FL = 'Y' or car.WDRWL_AUTH_FL = 'Y' or car.POA_FL = 'Y')
AND @Primary_Cust_Fl = 'N'
)

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
 CASE WHEN (max(t.effctv_risk) >= @Effctv_Risk_Cutoff_Lvl AND max(t.activity_risk) >= @Actvty_Risk_Cutoff_Lvl) THEN 'HR'
      WHEN (max(t.effctv_risk) < @Effctv_Risk_Cutoff_Lvl AND max(t.activity_risk) < @Actvty_Risk_Cutoff_Lvl) THEN 'RR'
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
                 (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y' and tr.BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)  
                 OR
                 (tr.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_BENEF_ACCT_FL = 'Y' AND tr.SCND_BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)
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
                 (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y' and tr.BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)  
                 OR
                 (tr.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_BENEF_ACCT_FL = 'Y' AND tr.SCND_BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)
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
                 (tr.ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_ORIG_ACCT_FL = 'Y' and tr.ORIG_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)  OR
                 (tr.SCND_ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_ORIG_ACCT_FL = 'Y' AND tr.SCND_ORIG_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)
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
                 (tr.ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_ORIG_ACCT_FL = 'Y' and tr.ORIG_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)  OR
                 (tr.SCND_ORIG_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_ORIG_ACCT_FL = 'Y' AND tr.SCND_ORIG_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)
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
                 (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y' and tr.BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)  
                 OR
                 (tr.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_BENEF_ACCT_FL = 'Y' AND tr.SCND_BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)
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
                 (tr.BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND tr.INTRL_BENEF_ACCT_FL = 'Y' and tr.BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)  
                 OR
                 (tr.SCND_BENEF_ACCT_ID = ca.ACCT_INTRL_ID AND  tr.INTRL_SCND_BENEF_ACCT_FL = 'Y' AND tr.SCND_BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl)
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
          (CASE WHEN tr.REM_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl
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
          case when tr.DBT_CDT_CD = 'C' then DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end AS d_amt_cdt,
          case when tr.DBT_CDT_CD = 'C' then 1 else 0 end AS d_ct_cdt,
          case when tr.DBT_CDT_CD = 'D' then DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end AS d_amt_dbt,
          case when tr.DBT_CDT_CD = 'D' then 1 else 0 end AS d_ct_dbt,
          tr.CASH_TRXN_ACTVY_RISK_NB ACTIVITY_RISK,
          (CASE WHEN tr.CASH_TRXN_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl
                 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 ELSE 0 END) HR_AMT,                 
        0 PASS_THRU_AMT,        
        (CASE WHEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) - TRUNC(DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM), -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) 
                 WHEN tr.TRXN_ACTVY_AM - TRUNC(tr.TRXN_ACTVY_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 ELSE 0 END) LRF_AMT
		,0 as Trusted_Trans_Amt
        ,tr.FUNC_CRNCY_CD
FROM      fccmatomic.CASH_TRXN tr,
          Cust_Accounts ca

WHERE     tr.ACCT_INTRL_ID = ca.ACCT_INTRL_ID
AND       (@All_Trans_Src_Fl='Y' OR tr.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
and       tr.MANTAS_TRXN_PURP_CD = 'GENERAL'
and       tr.MANTAS_TRXN_PRDCT_CD in (@Incl_Cash_Trxn_Prdct_Type_Lst)
and       DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) >=@Min_Individual_Trans_Amt
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
          case when tr.DBT_CDT_CD = 'C' then DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end AS d_amt_cdt,
          case when tr.DBT_CDT_CD = 'C' then 1 else 0 end AS d_ct_cdt,
          case when tr.DBT_CDT_CD = 'D' then DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end AS d_amt_dbt,
          case when tr.DBT_CDT_CD = 'D' then 1 else 0 end AS d_ct_dbt,
          tr.BO_TRXN_ACTVY_RISK_NB ACTIVITY_RISK,
          (CASE WHEN tr.BO_TRXN_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl
                 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 ELSE 0 END) HR_AMT,                 
        0 PASS_THRU_AMT,        
        (CASE WHEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) - TRUNC(DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM), -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) 
                 WHEN tr.TRXN_RPTNG_AM - TRUNC(tr.TRXN_RPTNG_AM, -@Lrf_Digits) = 0 THEN DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM)
                 ELSE 0 END) LRF_AMT
		,case when tr.TRSTD_TRXN_FL = 'Y' then DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt	
        ,tr.FUNC_CRNCY_CD			 
FROM      fccmatomic.BACK_OFFICE_TRXN tr,
          Cust_Accounts ca
          
WHERE     ca.ACCT_INTRL_ID = tr.ACCT_INTRL_ID
AND       (@All_Trans_Src_Fl='Y' OR tr.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
and       DECODE(@Curr_Type,'F',tr.TRXN_FUNC_AM,tr.TRXN_BASE_AM) >=@Min_Individual_Trans_Amt 
AND       tr.MANTAS_TRXN_PRDCT_CD in (@Incl_BO_Trxn_Prdct_Type_Lst)
and       tr.MANTAS_TRXN_PURP_CD = 'GENERAL'
AND       tr.CXL_PAIR_TRXN_INTRL_ID is null
--31536090 
and tr.EXCTN_DT >= (select Min_Dt from clndr_vw) and tr.EXCTN_DT <= (select Max_Dt from clndr_vw)
and tr.DATA_DUMP_DT >= (select Min_Dt from clndr_vw) and tr.DATA_DUMP_DT <= (select Max_Dt from clndr_vw)
and (@Include_Related_Parties_Fl = 'Y' or (tr.UNRLTD_PARTY_CD IS NOT NULL))
and (@Include_Trusted_Trans_FL = 'Y' or COALESCE(tr.TRSTD_TRXN_FL,'N') ='N')

) t 
 GROUP BY  t.cust_id
having 
      --31536090 
      max(t.dump_dt) > (select Freq_Dt from clndr_vw) and max(t.dump_dt) <= (select Max_Dt from clndr_vw)
) g 
where
 (( Overall_Risk = 'HR' and 
    SEASONED_CUST_FL = 1 and
   (g.Tot_Trxn_Am_Cdt >= @HR_Seasoned_Amt or g.Tot_Trxn_Am_Dbt >= @HR_Seasoned_Amt)
   )
    or
    (Overall_Risk = 'MR' and 
    SEASONED_CUST_FL = 1 and
       (g.Tot_Trxn_Am_Cdt >= @MR_Seasoned_Amt or g.Tot_Trxn_Am_Dbt >= @MR_Seasoned_Amt))
    or
    ( Overall_Risk = 'RR'and 
    SEASONED_CUST_FL = 1 and
       (g.Tot_Trxn_Am_Cdt >= @RR_Seasoned_Amt or g.Tot_Trxn_Am_Dbt >= @RR_Seasoned_Amt))
    or
    (Overall_Risk = 'HR' and
     SEASONED_CUST_FL = 0 and
       (g.Tot_Trxn_Am_Cdt >= @HR_New_Amt or g.Tot_Trxn_Am_Dbt >= @HR_New_Amt))
    or
    (Overall_Risk = 'MR' and
     SEASONED_CUST_FL = 0 and
       (g.Tot_Trxn_Am_Cdt >= @MR_New_Amt or g.Tot_Trxn_Am_Dbt >= @MR_New_Amt))
    or
    ( Overall_Risk = 'RR'and
     SEASONED_CUST_FL = 0 and
       (g.Tot_Trxn_Am_Cdt >= @RR_New_Amt or g.Tot_Trxn_Am_Dbt >= @RR_New_Amt)))
 ) ot ORDER BY ot.CUST_SEQ_ID 