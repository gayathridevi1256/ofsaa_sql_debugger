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
and ((loan_vw.Effctv_Risk_Lvl >= 5 --'HR'
       and (( --Number of days the loan has been outstanding1 <= Days Outstanding 
               loan_vw.Days_Outstanding <=  90
           --Number of days remaining to the loan's maturity >=Remaining Loan Tenor 
           and loan_vw.Days_Remaining_Loan_Tenor >= 90
           -- Min Balance Decrease% <= Loan or lease percentage balance decrease <=Max Balance Decrease% 
           and case when coalesce(loan_sm.MAX_LKBK_BAL_AM,0) <> 0 and record_ct > 1   
		      then ((loan_sm.MAX_LKBK_BAL_AM - coalesce(loan_sm.RMNG_AM_LAST,0))* 100 / (loan_sm.MAX_LKBK_BAL_AM ))
              when  coalesce(loan_vw.d_LOAN_ORIG_AM,0) <> 0 and record_ct = 1
              then ((loan_vw.d_LOAN_ORIG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))* 100 / (loan_vw.d_LOAN_ORIG_AM ))
              else 0 end between 25 and 50
           -- The total amount of loan balance decrease >= Min Balance Decrease Amt
           and case when record_ct > 1
               then (coalesce(loan_sm.MAX_LKBK_BAL_AM,0) - coalesce(loan_sm.RMNG_AM_LAST,0))
               when  record_ct = 1
               then (coalesce(loan_vw.d_LOAN_ORIG_AM,0) - coalesce(loan_sm.RMNG_AM_LAST,0))
               else 0 end >= 150000
           )
         or --The amount that loan has been overpayed >= Min Overpayment Amt 
  		(-1 *coalesce(loan_sm.RMNG_AM_LAST,0)) >= 50000)
         
        and --100x(PreviousMonthOutstandingBalance-Current MonthOutstandingBalance)/PreviousMonthOutstandingBalance>=MinFrequencyPaydown%
            case when (coalesce(loan_sm.PREV_MTH_RMNG_AM,0)) <> 0 and record_ct > 1 
                 then 100 * (loan_sm.PREV_MTH_RMNG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))/ (loan_sm.PREV_MTH_RMNG_AM)
                 when (coalesce(loan_vw.d_LOAN_ORIG_AM,0)) <> 0 and record_ct = 1
                 then 100 * (loan_vw.d_LOAN_ORIG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))/ (loan_vw.d_LOAN_ORIG_AM)
                else 0 end >= 10   
    ) 
   
    
  OR (loan_vw.Effctv_Risk_Lvl < 5 -- 'RR'
       and (( --Number of days the loan has been outstanding1 <= Days Outstanding 
               loan_vw.Days_Outstanding <=  90
           --Number of days remaining to the loan's maturity >=Remaining Loan Tenor 
           and loan_vw.Days_Remaining_Loan_Tenor >= 90
           -- Min Balance Decrease% <= Loan or lease percentage balance decrease <=Max Balance Decrease% 
           and case when coalesce(loan_sm.MAX_LKBK_BAL_AM,0) <> 0 and record_ct > 1   
		      then ((loan_sm.MAX_LKBK_BAL_AM - coalesce(loan_sm.RMNG_AM_LAST,0))* 100 / (loan_sm.MAX_LKBK_BAL_AM ))
              when  coalesce(loan_vw.d_LOAN_ORIG_AM,0) <> 0 and record_ct = 1
              then ((loan_vw.d_LOAN_ORIG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))* 100 / (loan_vw.d_LOAN_ORIG_AM ))
              else 0 end between 25 and 50
           -- The total amount of loan balance decrease >= Min Balance Decrease Amt
           and case when record_ct > 1
               then (coalesce(loan_sm.MAX_LKBK_BAL_AM,0) - coalesce(loan_sm.RMNG_AM_LAST,0))
               when  record_ct = 1
               then (coalesce(loan_vw.d_LOAN_ORIG_AM,0) - coalesce(loan_sm.RMNG_AM_LAST,0))
               else 0 end >= 150000
           )
         or --The amount that loan has been overpayed >= Min Overpayment Amt 
  		(-1 *coalesce(loan_sm.RMNG_AM_LAST,0)) >= 50000)
        
        and --100x(PreviousMonthOutstandingBalance-Current MonthOutstandingBalance)/PreviousMonthOutstandingBalance>=MinFrequencyPaydown%
            case when (coalesce(loan_sm.PREV_MTH_RMNG_AM,0)) <> 0 and record_ct > 1 
                 then 100 * (loan_sm.PREV_MTH_RMNG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))/ (loan_sm.PREV_MTH_RMNG_AM)
                 when (coalesce(loan_vw.d_LOAN_ORIG_AM,0)) <> 0 and record_ct = 1
                 then 100 * (loan_vw.d_LOAN_ORIG_AM - coalesce(loan_sm.RMNG_AM_LAST,0))/ (loan_vw.d_LOAN_ORIG_AM)
                else 0 end >= 15   
)
)