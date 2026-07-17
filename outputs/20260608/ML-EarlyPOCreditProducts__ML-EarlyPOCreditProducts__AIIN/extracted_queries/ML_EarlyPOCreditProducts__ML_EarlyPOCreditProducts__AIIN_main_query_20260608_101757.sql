-- REFERENCE QUERY
-- Extracted: 2026-06-08 10:17:57.184730

SELECT ot.ACCT_INTRL_ID, ot.ACCT_SEQ_ID, ot.EFFCTV_RISK_LVL, ot.DAYS_OUTSTANDING, ot.PAYMENT_CT, ot.OVERALL_RISK, ot.LOAN_OVERPAYED_AMT, ot.LOAN_BAL_DECREASE_AMT, ot.LOAN_BAL_PRCTG_DECREASE, ot.DAYS_REMAINING_LOAN_TENOR, ot.FUNC_CRNCY_CD FROM (--33971279  processing cases when loan was payoff/paydown in the 1st month
with clndr_vw as ( 
select
(select cal.clndr_dt from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = 0) as Curr_Dt,
(select (F_TO_NUMBER(COALESCE(F_DATE_TO_CHAR((SELECT CLNDR_DT FROM fccmatomic.KDD_CAL WHERE CLNDR_NM = 'SYSCAL' AND MNTH_BNDRY_CD = 'ED1'), 'J'), '0'))) from dual) as JCurr_Dt,
(select f_trunc_date(kc.CLNDR_DT, 'MM') from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL' and kc.MNTH_BNDRY_CD='ED1')  as ED1_Date,
(select f_trunc_date(kc.CLNDR_DT, 'MM') from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL' and kc.MNTH_BNDRY_CD='ED2')  as ED2_Date,
(select F_TRUNC_DATE(kc.CLNDR_DT, 'MM') from fccmatomic.KDD_CAL kc where kc.CLNDR_NM = 'SYSCAL' and kc.mnth_bndry_cd = 'SD3') as SD3_Date
FROM dual
),

loan_vw as (
select 
     l.LOAN_INTRL_ID
   , ac.ACCT_INTRL_ID
   , ac.ACCT_SEQ_ID
   , DECODE(@Curr_Type,'F',l.LOAN_ORIG_FUNC_AM,l.LOAN_ORIG_BASE_AM) d_LOAN_ORIG_AM
   , ac.ACCT_EFCTV_RISK_NB as Effctv_Risk_Lvl
   , case when ac.ACCT_EFCTV_RISK_NB >= @Effctv_Risk_Cutoff_Lvl 
            then 'HR' else 'RR' end as  Overall_Risk 
        -- calculating the days outstanding - How many days LOAN is already opened
   , (select JCurr_Dt from clndr_vw) - (F_TO_NUMBER(COALESCE(F_DATE_TO_CHAR(l.LOAN_ORIG_DT, 'J'), '0'))) as Days_Outstanding 
    -- calculating how much loan remains to be paid in case of paydown - How many days left is till the end/maturity of Loan.
   , (F_TO_NUMBER(COALESCE(F_DATE_TO_CHAR(l.LOAN_EXPTD_DUE_DT, 'J'), '0'))) - (select JCurr_Dt from clndr_vw) as Days_Remaining_Loan_Tenor   
   
FROM  fccmatomic.ACCT ac,  
fccmatomic.LOAN l 
where 
l.LOAN_INTRL_ID = ac.ACCT_INTRL_ID
--  Exclude Test Accounts
AND  COALESCE(ac.TEST_ACCT_FL,'N') <> 'Y'
-- Include specific account types only 
AND ac.MANTAS_ACCT_BUS_TYPE_CD IN ('LON')
--  Exclude Exempt Accounts
AND ac.ACCT_EFCTV_RISK_NB <> -2 
-- Include only Term loans
AND l.LOAN_CLASS_CD = 'NRV'
-- Inlude Accout either from all or specifyed jurisdictions
AND (@All_Jurisdictions_Fl = 'Y' OR ac.JRSDCN_CD IN (@Incl_Jurisdictions_Lst))
--  Include Loan Accounts Only
AND (@All_Loan_Types='Y' OR l.LOAN_TYPE_CD IN (@Loan_Type_Cd))
-- Loam Sum > 0
AND DECODE(@Curr_Type,'F',l.LOAN_ORIG_FUNC_AM,l.LOAN_ORIG_BASE_AM) > 0
--Bug34973020
--AND ((F_TO_NUMBER(COALESCE(F_DATE_TO_CHAR(l.LOAN_EXPTD_DUE_DT, 'J'), '0'))) -
--     (select JCurr_Dt from clndr_vw)) >= (case when @HR_Remaining_Loan_Tenor < @RR_Remaining_Loan_Tenor then @HR_Remaining_Loan_Tenor else @RR_Remaining_Loan_Tenor end)
--AND ((select JCurr_Dt from clndr_vw) - 
--    (F_TO_NUMBER(COALESCE(F_DATE_TO_CHAR(l.LOAN_ORIG_DT, 'J'), '0')))) <= (case when @HR_Days_Outstanding < @RR_Days_Outstanding then @RR_Days_Outstanding else @HR_Days_Outstanding end)	
),
 -- all payments within lookback period (90 days not tunable)
loan_sm as (
SELECT lb.LOAN_INTRL_ID                            
          --Interest paid before lookback period
     , SUM(case when f_trunc_date(lb.MNTH_SMRY_START_DT,'MM') = (select ED1_Date from clndr_vw)
       then lb.NB_PYMNT_CT else 0 end) AS Payment_Ct
           --last month Remaining balance in lookback period 
     , SUM(case when f_trunc_date(lb.MNTH_SMRY_START_DT,'MM') =  (select ED1_Date from clndr_vw) 
            then DECODE(@Curr_Type,'F',lb.RMNG_BAL_FUNC_AM,lb.RMNG_BAL_BASE_AM) else 0 end) AS RMNG_AM_LAST
            --previous month Remaining balance in lookback period 
     , SUM(case when f_trunc_date(lb.MNTH_SMRY_START_DT,'MM') =  (select ED2_Date from clndr_vw)
            then DECODE(@Curr_Type,'F',lb.RMNG_BAL_FUNC_AM,lb.RMNG_BAL_BASE_AM) else 0 end) AS PREV_MTH_RMNG_AM
     , MAX(DECODE(@Curr_Type,'F',lb.RMNG_BAL_FUNC_AM,lb.RMNG_BAL_BASE_AM)) AS MAX_LKBK_BAL_AM 
     , MAX(lb.FUNC_CRNCY_CD) as FUNC_CRNCY_CD
     -- when it has value 1 it means only current month record was received
     , count(lb.LOAN_INTRL_ID) as record_ct
FROM   fccmatomic.LOAN_SMRY_MNTH lb, loan_vw loan
WHERE  
       --20422198
       lb.MNTH_SMRY_START_DT >=(select SD3_Date from clndr_vw)
      AND lb.MNTH_SMRY_START_DT <=(select ED1_Date from clndr_vw)
      AND loan.loan_intrl_id=lb.loan_intrl_id								 
GROUP BY lb.LOAN_INTRL_ID
-- check on Frequency
having sum(case when f_trunc_date(lb.MNTH_SMRY_START_DT,'MM') = (select ED1_Date from clndr_vw) 
       then lb.NB_PYMNT_CT else 0 end) > 0  
)

SELECT
     loan_vw.ACCT_INTRL_ID
   , loan_vw.ACCT_SEQ_ID
   , loan_vw.Effctv_Risk_Lvl
   , loan_vw.Overall_Risk
   , loan_sm.record_ct  
   , loan_sm.RMNG_AM_LAST
   , loan_sm.PREV_MTH_RMNG_AM
   , loan_sm.MAX_LKBK_BAL_AM
   , loan_vw.d_LOAN_ORIG_AM
    -- calculating the days outstanding
   , loan_vw.Days_Outstanding
    -- calculating how much loan remains to be paid in case of paydown
   , loan_vw.Days_Remaining_Loan_Tenor
    -- calculating the percentage decrease 
   , case when coalesce(loan_sm.MAX_LKBK_BAL_AM,0) <> 0 and record_ct > 1   
		      then ((loan_sm.MAX_LKBK_BAL_AM - coalesce(loan_sm.RMNG_AM_LAST,0))* 100 / (loan_sm.MAX_LKBK_BAL_AM ))
          when  coalesce(loan_vw.d_LOAN_ORIG_AM,0) <> 0 and record_ct = 1
              then ((loan_vw.d_LOAN_ORIG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))* 100 / (loan_vw.d_LOAN_ORIG_AM ))
          else 0 end as Loan_Bal_Prctg_Decrease
    --Loan_Bal_Decrease_Amt = OutstandingBalanceBeforeLookback - Current MonthOutstandingBalance
    , case when record_ct > 1
           then (coalesce(loan_sm.MAX_LKBK_BAL_AM,0) - coalesce(loan_sm.RMNG_AM_LAST,0))
           when  record_ct = 1
           then (coalesce(loan_vw.d_LOAN_ORIG_AM,0) - coalesce(loan_sm.RMNG_AM_LAST,0))
           else 0 end as Loan_Bal_Decrease_Amt
   
   , Payment_Ct
     -- picking the overpayed amount on the loan
   ,    CASE WHEN (coalesce(loan_sm.RMNG_AM_LAST,0)) < 0
            THEN (-1 *loan_sm.RMNG_AM_LAST)
         ELSE 0 END as Loan_Overpayed_Amt
   , loan_sm.FUNC_CRNCY_CD         
		 
FROM  loan_vw,
      loan_sm  
WHERE
loan_sm.LOAN_INTRL_ID = loan_vw.LOAN_INTRL_ID
and ((loan_vw.Effctv_Risk_Lvl >= @Effctv_Risk_Cutoff_Lvl --'HR'
       and (( --Number of days the loan has been outstanding1 <= Days Outstanding 
               loan_vw.Days_Outstanding <=  @HR_Days_Outstanding
           --Number of days remaining to the loan's maturity >=Remaining Loan Tenor 
           and loan_vw.Days_Remaining_Loan_Tenor >= @HR_Remaining_Loan_Tenor
           -- Min Balance Decrease% <= Loan or lease percentage balance decrease <=Max Balance Decrease% 
           and case when coalesce(loan_sm.MAX_LKBK_BAL_AM,0) <> 0 and record_ct > 1   
		      then ((loan_sm.MAX_LKBK_BAL_AM - coalesce(loan_sm.RMNG_AM_LAST,0))* 100 / (loan_sm.MAX_LKBK_BAL_AM ))
              when  coalesce(loan_vw.d_LOAN_ORIG_AM,0) <> 0 and record_ct = 1
              then ((loan_vw.d_LOAN_ORIG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))* 100 / (loan_vw.d_LOAN_ORIG_AM ))
              else 0 end between @HR_Min_Bal_Decrease_Prctg and @HR_Max_Bal_Decrease_Prctg
           -- The total amount of loan balance decrease >= Min Balance Decrease Amt
           and case when record_ct > 1
               then (coalesce(loan_sm.MAX_LKBK_BAL_AM,0) - coalesce(loan_sm.RMNG_AM_LAST,0))
               when  record_ct = 1
               then (coalesce(loan_vw.d_LOAN_ORIG_AM,0) - coalesce(loan_sm.RMNG_AM_LAST,0))
               else 0 end >= @HR_Min_Bal_Decrease_Amt
           )
         or --The amount that loan has been overpayed >= Min Overpayment Amt 
  		(-1 *coalesce(loan_sm.RMNG_AM_LAST,0)) >= @HR_Min_Overpayment_Amt)
         
        and --100x(PreviousMonthOutstandingBalance-Current MonthOutstandingBalance)/PreviousMonthOutstandingBalance>=MinFrequencyPaydown%
            case when (coalesce(loan_sm.PREV_MTH_RMNG_AM,0)) <> 0 and record_ct > 1 
                 then 100 * (loan_sm.PREV_MTH_RMNG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))/ (loan_sm.PREV_MTH_RMNG_AM)
                 when (coalesce(loan_vw.d_LOAN_ORIG_AM,0)) <> 0 and record_ct = 1
                 then 100 * (loan_vw.d_LOAN_ORIG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))/ (loan_vw.d_LOAN_ORIG_AM)
                else 0 end >= @HR_Min_Freq_Paydown_Prctg   
    ) 
   
    
  OR (loan_vw.Effctv_Risk_Lvl < @Effctv_Risk_Cutoff_Lvl -- 'RR'
       and (( --Number of days the loan has been outstanding1 <= Days Outstanding 
               loan_vw.Days_Outstanding <=  @RR_Days_Outstanding
           --Number of days remaining to the loan's maturity >=Remaining Loan Tenor 
           and loan_vw.Days_Remaining_Loan_Tenor >= @RR_Remaining_Loan_Tenor
           -- Min Balance Decrease% <= Loan or lease percentage balance decrease <=Max Balance Decrease% 
           and case when coalesce(loan_sm.MAX_LKBK_BAL_AM,0) <> 0 and record_ct > 1   
		      then ((loan_sm.MAX_LKBK_BAL_AM - coalesce(loan_sm.RMNG_AM_LAST,0))* 100 / (loan_sm.MAX_LKBK_BAL_AM ))
              when  coalesce(loan_vw.d_LOAN_ORIG_AM,0) <> 0 and record_ct = 1
              then ((loan_vw.d_LOAN_ORIG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))* 100 / (loan_vw.d_LOAN_ORIG_AM ))
              else 0 end between @RR_Min_Bal_Decrease_Prctg and @RR_Max_Bal_Decrease_Prctg
           -- The total amount of loan balance decrease >= Min Balance Decrease Amt
           and case when record_ct > 1
               then (coalesce(loan_sm.MAX_LKBK_BAL_AM,0) - coalesce(loan_sm.RMNG_AM_LAST,0))
               when  record_ct = 1
               then (coalesce(loan_vw.d_LOAN_ORIG_AM,0) - coalesce(loan_sm.RMNG_AM_LAST,0))
               else 0 end >= @RR_Min_Bal_Decrease_Amt
           )
         or --The amount that loan has been overpayed >= Min Overpayment Amt 
  		(-1 *coalesce(loan_sm.RMNG_AM_LAST,0)) >= @RR_Min_Overpayment_Amt)
        
        and --100x(PreviousMonthOutstandingBalance-Current MonthOutstandingBalance)/PreviousMonthOutstandingBalance>=MinFrequencyPaydown%
            case when (coalesce(loan_sm.PREV_MTH_RMNG_AM,0)) <> 0 and record_ct > 1 
                 then 100 * (loan_sm.PREV_MTH_RMNG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))/ (loan_sm.PREV_MTH_RMNG_AM)
                 when (coalesce(loan_vw.d_LOAN_ORIG_AM,0)) <> 0 and record_ct = 1
                 then 100 * (loan_vw.d_LOAN_ORIG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))/ (loan_vw.d_LOAN_ORIG_AM)
                else 0 end >= @RR_Min_Freq_Paydown_Prctg   
)
)
 ) ot ORDER BY ot.ACCT_SEQ_ID 