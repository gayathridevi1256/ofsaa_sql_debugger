-- REFERENCE QUERY
-- Extracted: 2026-06-07 18:49:47.244824

SELECT ot.ACCT_INTRL_ID, ot.ACCT_SEQ_ID, ot.ACTVTY_RISK_LVL, ot.EFFCTV_RISK_LVL, ot.TRANS_CT_DBT, ot.TRANS_AMT_CDT, ot.TRANS_CT_CDT, ot.TRANS_CT, ot.TRANS_AMT, ot.TRANS_AMT_DBT, ot.OVERALL_RISK, ot.HR_AMT, ot.PASS_THRU_AMT, ot.LRF_AMT, ot.AGE, ot.TRUSTED_TRANS_AMT, ot.FUNC_CRNCY_CD, ot.CURR_DT FROM (--PR 44122
--Replaced Filter: COALESCE(w.CXL_FL,'NULL')<>'Y'  by  w.CXL_PAIR_TRXN_INTRL_ID is null
-- Date: 03/18/2009 As per PR 39564 : Added filter mantas_trxn_purp_cd = 'GENERAL' for mi_trxn and cash_trxn tables
--Date:05/06/2009 Added Trusted Pair Functionality
-- 06/10/2022 34237111 functional currency, clndr_vw added for better performance
WITH clndr_vw as (
select
(select add_days(cal.CLNDR_DT, -@Look_Back_Period) from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = 0) as Min_Dt,
(select cal.clndr_dt from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = 0) as Max_Dt,
(select add_days(cal.CLNDR_DT, -@Frequency_Period) from fccmatomic.KDD_CAL cal where cal.CLNDR_NM = 'SYSCAL' and cal.CLNDR_DAY_AGE = 0) as Freq_Dt
FROM dual
),

wire_vw as (
select
w.BANK_TO_BANK_TRNFR_FL,
w.BENEF_ACCT_ID,
w.BENEF_ACTVY_RISK_NB,
w.CXL_PAIR_TRXN_INTRL_ID,
w.DATA_DUMP_DT,
w.FO_TRXN_SEQ_ID,
w.INTRL_BENEF_ACCT_FL,
w.INTRL_ORIG_ACCT_FL,
w.INTRL_SCND_BENEF_ACCT_FL,
w.INTRL_SCND_ORIG_ACCT_FL,
w.MANTAS_TRXN_PRDCT_CD,
w.MANTAS_TRXN_PURP_CD,
w.ORIG_ACCT_ID,
w.ORIG_ACTVY_RISK_NB,
w.PASS_THRU_FL,
w.RCV_TRXN_ACTVY_AM,
w.SCND_BENEF_ACCT_ID,
w.SCND_BENEF_ACTVY_RISK_NB,
w.SCND_ORIG_ACCT_ID,
w.SCND_ORIG_ACTVY_RISK_NB,
w.SEND_TRXN_ACTVY_AM,
w.SRC_SYS_CD,
w.TRSTD_TRXN_FL,
w.TRXN_BASE_AM,
DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) as Trxn_Am,
w.TRXN_EXCTN_DT,
w.UNRLTD_PARTY_FL,
case when  DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) - trunc(DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM), -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) 
     when  w.RCV_TRXN_ACTVY_AM - trunc(w.RCV_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
     when  w.SEND_TRXN_ACTVY_AM - trunc(w.SEND_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM)
     else 0 end Lrf_Am,
case when  w.PASS_THRU_FL = 'Y' then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end Pass_Thru_Am,   
case when w.TRSTD_TRXN_FL = 'Y' then DECODE(@Curr_Type,'F',w.TRXN_FUNC_AM,w.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
w.FUNC_CRNCY_CD
from WIRE_TRXN w
where 
        w.MANTAS_TRXN_PURP_CD = 'GENERAL'
    and (@All_Trans_Src_Fl = 'Y' or w.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
    and w.MANTAS_TRXN_PRDCT_CD in (@Incl_Wire_Trxn_Prdct_Type_Lst)
    --20039324, 34237111 
    and w.TRXN_EXCTN_DT > (select Min_Dt from clndr_vw) and w.TRXN_EXCTN_DT <= (select Max_Dt from clndr_vw)  
    and w.DATA_DUMP_DT > (select Min_Dt from clndr_vw) and w.DATA_DUMP_DT <= (select Max_Dt from clndr_vw) 
    and (@Include_B2B_Trnfr_Fl = 'Y' or NOT(w.BANK_TO_BANK_TRNFR_FL = 'Y' and w.PASS_THRU_FL = 'N'))
    --21034264 
    and (@Include_Trusted_Trans_FL = 'Y' or COALESCE(w.TRSTD_TRXN_FL, 'N') = 'N')  
    and (@Incl_Rltd_Parties = 'Y' or COALESCE(w.unrltd_party_fl, 'Y') <> 'N')
    and w.CXL_PAIR_TRXN_INTRL_ID is null                      
),

mi_vw as (
select
m.BANK_TO_BANK_TRNFR_FL,
m.BENEF_ACCT_ID,
m.BENEF_ACTVY_RISK_NB,
m.CLR_TRXN_ACTVY_AM,
m.CXL_PAIR_TRXN_INTRL_ID,
m.DATA_DUMP_DT,
m.DEP_TRXN_ACTVY_AM,
m.FO_TRXN_SEQ_ID,
m.INTRL_BENEF_ACCT_FL,
m.INTRL_REM_ACCT_FL,
m.INTRL_SCND_BENEF_ACCT_FL,
m.ISSUE_TRXN_ACTVY_AM,
m.MANTAS_ISSUE_DATE,
m.MANTAS_POST_DT,
m.MANTAS_TRXN_PRDCT_CD,
m.MANTAS_TRXN_PURP_CD,
m.PASS_THRU_FL,
m.REM_ACCT_ID,
m.REM_ACTVY_RISK_NB,
m.SCND_BENEF_ACCT_ID,
m.SCND_BENEF_ACTVY_RISK_NB,
m.SRC_SYS_CD,
m.TRSTD_TRXN_FL,
m.TRXN_BASE_AM,
DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) as Trxn_Am,
m.UNRLTD_PARTY_FL,
case when m.PASS_THRU_FL = 'Y' then DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end Pass_Thru_Am,
case when DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) - trunc(DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM), -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) 
   when m.DEP_TRXN_ACTVY_AM - trunc(m.DEP_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
   when m.ISSUE_TRXN_ACTVY_AM - trunc(m.ISSUE_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)
   when m.CLR_TRXN_ACTVY_AM - trunc(m.CLR_TRXN_ACTVY_AM, -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM)		 
else 0 end Lrf_Am,
case when m.TRSTD_TRXN_FL = 'Y' then DECODE(@Curr_Type,'F',m.TRXN_FUNC_AM,m.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt,
m.FUNC_CRNCY_CD
from  fccmatomic.MI_TRXN m 
where 
         m.MANTAS_TRXN_PURP_CD = 'GENERAL'
     and m.MANTAS_TRXN_PRDCT_CD in (@Incl_MI_Trxn_Prdct_Type_Lst)     
     and (@All_Trans_Src_Fl = 'Y' or m.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
     --20039324, 34237111 
     and m.DATA_DUMP_DT > (select Min_Dt from clndr_vw) and m.DATA_DUMP_DT <= (select Max_Dt from clndr_vw)                   
     and (@Include_B2B_Trnfr_Fl = 'Y' or NOT(m.BANK_TO_BANK_TRNFR_FL = 'Y' and m.PASS_THRU_FL = 'N'))  
     --21034264 
     and (@Include_Trusted_Trans_FL = 'Y' or COALESCE(m.TRSTD_TRXN_FL, 'N') = 'N')  
     and (@Incl_Rltd_Parties = 'Y' or COALESCE(m.unrltd_party_fl, 'Y') <> 'N')     
     and m.CXL_PAIR_TRXN_INTRL_ID is null  
)

select 
        v.Acct_Intrl_Id   
      , v.Acct_Seq_Id   
      , v.Effctv_Risk_Lvl
      , v.Actvty_Risk_Lvl
      , v.Trans_Amt_Cdt
      , v.Trans_Amt_Dbt
      , v.Trans_Ct_Cdt
      , v.Trans_Ct_Dbt
      , v.Trans_Amt
      , v.Trans_Ct
      , v.Overall_Risk
      , v.Age
      , v.Hr_Amt
      , v.Pass_Thru_Amt
      , v.Lrf_Amt     
      , v.Trusted_Trans_Amt
      , v.FUNC_CRNCY_CD
--37496977
     ,   (select Max_Dt from clndr_vw) as Curr_Dt
from 
(
    select 
          t.Acct_Intrl_Id
        , max(t.acct_seq_id) as Acct_Seq_Id   
        , max(t.ACCT_EFCTV_RISK_NB) as Effctv_Risk_Lvl
        , max(t.d_ACTVTY_RISK_LVL)  as Actvty_Risk_Lvl
        , sum(t.d_TRXN_BASE_AM_CDT) as Trans_Amt_Cdt
        , sum(t.d_TRXN_BASE_AM_DBT) as Trans_Amt_Dbt
        , sum(t.d_TRXN_CT_CDT)      as Trans_Ct_Cdt
        , sum(t.d_TRXN_CT_DBT)      as Trans_Ct_Dbt
        , sum(t.Trxn_Am)            as Trans_Amt
        , count(1)                  as Trans_Ct
    --        , count(distinct t.acct_intrl_id) as Acct_Ct
        , case when max(t.ACCT_EFCTV_RISK_NB)>= @Effctv_Risk_Cutoff_Lvl and max(t.d_ACTVTY_RISK_LVL) >= @Actvty_Risk_Cutoff_Lvl then 'HR' 
               when max(t.ACCT_EFCTV_RISK_NB)<  @Effctv_Risk_Cutoff_Lvl and max(t.d_ACTVTY_RISK_LVL) <  @Actvty_Risk_Cutoff_Lvl then 'RR'
               else 'MR' 
           end Overall_Risk
        --, max(k.clndr_dt - t.acct_open_dt) as Age
        , max((select Max_Dt from clndr_vw) - t.acct_open_dt) as Age
        , sum(t.Hr_Am)        as Hr_Amt
        , sum(t.Pass_Thru_am) as Pass_Thru_Amt
        , sum(t.Lrf_Am)       as Lrf_Amt 
        , sum(t.Trusted_Trans_Amt) as Trusted_Trans_Amt
        , max(t.FUNC_CRNCY_CD) as  FUNC_CRNCY_CD
    from 
        (
                -- ML_RapidMvmtFundsAll_AC_Wi
                select 
                      w.ORIG_ACCT_ID as Acct_Intrl_Id
                    , a.ACCT_SEQ_ID      
                    , w.FO_TRXN_SEQ_ID
                    , a.ACCT_OPEN_DT
                    , w.DATA_DUMP_DT
                    , a.ACCT_EFCTV_RISK_NB
                    , w.Trxn_Am
                    , case when  w.ORIG_ACTVY_RISK_NB > 5 then w.Trxn_Am else 0 end Hr_Am                     
                    , w.Pass_Thru_Am
                    , w.Lrf_Am
                    , w.Trusted_Trans_Amt
                    , w.ORIG_ACTVY_RISK_NB as d_ACTVTY_RISK_LVL
                    , w.Trxn_Am as d_TRXN_BASE_AM_DBT
                    , 1 d_TRXN_CT_DBT
                    , 0 d_TRXN_BASE_AM_CDT
                    , 0 d_TRXN_CT_CDT 
                    , 0 as Not_EFT_Trans
                    , w.FUNC_CRNCY_CD
                from 
                    wire_vw w 
                              inner join fccmatomic.ACCT a on w.ORIG_ACCT_ID = a.ACCT_INTRL_ID
                where 
                     w.INTRL_ORIG_ACCT_FL = 'Y'
                 and a.mantas_acct_holdr_type_cd in (@Incld_Acct_Hldr_Typ_Cd)
                 and a.acct_efctv_risk_nb <> -2 
                 and (@All_Jurisdictions_Fl = 'Y' or a.jrsdcn_cd in (@Incl_Jurisdictions_Lst)) 
                 and a.mantas_acct_bus_type_cd in (@Mantas_Bus_Acct_Type_Lst)
                -- ---------------------------------------------------------------------------------------------------------------     
                UNION ALL     
                -- ---------------------------------------------------------------------------------------------------------------     
                select 
                      w.SCND_ORIG_ACCT_ID as Acct_Intrl_Id,
                      a.ACCT_SEQ_ID,      
                      w.FO_TRXN_SEQ_ID,
                      a.ACCT_OPEN_DT,
                      w.DATA_DUMP_DT,
                      a.ACCT_EFCTV_RISK_NB,
                      w.Trxn_Am,
                      case when  w.SCND_ORIG_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then w.Trxn_Am else 0 end Hr_Am,
                      w.Pass_Thru_Am,
                      w.Lrf_Am,
                      w.Trusted_Trans_Amt,
                      w.SCND_ORIG_ACTVY_RISK_NB d_ACTVTY_RISK_LVL,	
                      w.Trxn_Am d_TRXN_BASE_AM_DBT,
                      1 d_TRXN_CT_DBT,
                      0 d_TRXN_BASE_AM_CDT,
                      0 d_TRXN_CT_CDT, 
                      0 as Not_EFT_Trans,
                      w.FUNC_CRNCY_CD
                from 
                  wire_vw w 
                                inner join fccmatomic.ACCT a on w.SCND_ORIG_ACCT_ID = a.ACCT_INTRL_ID
                where 
                       w.INTRL_SCND_ORIG_ACCT_FL = 'Y'
                 and ((w.INTRL_ORIG_ACCT_FL = 'Y' and COALESCE(w.ORIG_ACCT_ID,'-') <> w.SCND_ORIG_ACCT_ID) or w.INTRL_ORIG_ACCT_FL <> 'Y')
                 and a.mantas_acct_holdr_type_cd in (@Incld_Acct_Hldr_Typ_Cd) 
                 and a.acct_efctv_risk_nb <> -2 
                 and (@All_Jurisdictions_Fl = 'Y' or a.jrsdcn_cd in (@Incl_Jurisdictions_Lst)) 
                 and a.mantas_acct_bus_type_cd in (@Mantas_Bus_Acct_Type_Lst)  
                -- ---------------------------------------------------------------------------------------------------------------     
                UNION ALL     
                -- ---------------------------------------------------------------------------------------------------------------     
                select 
                      w.BENEF_ACCT_ID as Acct_Intrl_Id,
                      a.ACCT_SEQ_ID,            
                      w.FO_TRXN_SEQ_ID,
                      a.ACCT_OPEN_DT,
                      w.DATA_DUMP_DT,
                      a.ACCT_EFCTV_RISK_NB,      
                      w.Trxn_Am,
                      case when w.BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then w.Trxn_Am else 0 end Hr_Am,
                      w.Pass_Thru_Am,
                      w.Lrf_Am,
                      w.Trusted_Trans_Amt, 
                      w.BENEF_ACTVY_RISK_NB d_ACTVTY_RISK_LVL, 
                      0 d_TRXN_BASE_AM_DBT,
                      0 d_TRXN_CT_DBT,
                      w.Trxn_Am d_TRXN_BASE_AM_CDT,
                      1 d_TRXN_CT_CDT,
                      0 as Not_EFT_Trans,
                      w.FUNC_CRNCY_CD
                from 
                  wire_vw w 
                              inner join fccmatomic.ACCT a on w.BENEF_ACCT_ID = a.ACCT_INTRL_ID  
                where 
                      w.INTRL_BENEF_ACCT_FL = 'Y'  
                 and ((w.INTRL_ORIG_ACCT_FL = 'Y' and COALESCE(w.ORIG_ACCT_ID,'-') <> w.BENEF_ACCT_ID) or w.INTRL_ORIG_ACCT_FL <> 'Y')
                 and ((w.INTRL_SCND_ORIG_ACCT_FL = 'Y' and COALESCE(w.SCND_ORIG_ACCT_ID,'-') <> w.BENEF_ACCT_ID) or COALESCE(w.INTRL_SCND_ORIG_ACCT_FL,'-') <> 'Y')
                 and a.mantas_acct_holdr_type_cd in (@Incld_Acct_Hldr_Typ_Cd) 
                 and a.acct_efctv_risk_nb <> -2 
                 and (@All_Jurisdictions_Fl = 'Y' or a.jrsdcn_cd in (@Incl_Jurisdictions_Lst)) 
                 and a.mantas_acct_bus_type_cd in (@Mantas_Bus_Acct_Type_Lst)
                -- ---------------------------------------------------------------------------------------------------------------     
                UNION ALL     
                -- ---------------------------------------------------------------------------------------------------------------     
                -- ML_RapidMvmtFundsAll_AC_Wi4
                select 
                      w.SCND_BENEF_ACCT_ID as Acct_Intrl_Id,
                      a.ACCT_SEQ_ID,            
                      w.FO_TRXN_SEQ_ID,
                      a.ACCT_OPEN_DT,
                      w.DATA_DUMP_DT,
                      a.ACCT_EFCTV_RISK_NB,      
                      w.Trxn_Am,
                      case when w.SCND_BENEF_ACTVY_RISK_NB > 5 then w.Trxn_Am else 0 end Hr_Am,                        
                      w.Pass_Thru_Am,
                      w.Lrf_Am,
                      w.Trusted_Trans_Amt, 
                      w.SCND_BENEF_ACTVY_RISK_NB d_ACTVTY_RISK_LVL, 
                      0 d_TRXN_BASE_AM_DBT,
                      0 d_TRXN_CT_DBT,
                      w.Trxn_Am d_TRXN_BASE_AM_CDT,
                      1 d_TRXN_CT_CDT,
                      0 as Not_EFT_Trans,
                      w.FUNC_CRNCY_CD
                from 
                  wire_vw w      
                                inner join fccmatomic.ACCT a on w.SCND_BENEF_ACCT_ID = a.ACCT_INTRL_ID  
                where 
                      w.INTRL_SCND_BENEF_ACCT_FL = 'Y'
                 and ((w.INTRL_ORIG_ACCT_FL = 'Y' and COALESCE(w.ORIG_ACCT_ID,'-') <> w.SCND_BENEF_ACCT_ID) or w.INTRL_ORIG_ACCT_FL <> 'Y')
                 and ((w.INTRL_SCND_ORIG_ACCT_FL = 'Y' and COALESCE(w.SCND_ORIG_ACCT_ID,'-') <> w.SCND_BENEF_ACCT_ID) or COALESCE(w.INTRL_SCND_ORIG_ACCT_FL,'-') <> 'Y')
                 and ((w.INTRL_BENEF_ACCT_FL = 'Y' and COALESCE(w.BENEF_ACCT_ID,'-') <> w.SCND_BENEF_ACCT_ID) or w.INTRL_BENEF_ACCT_FL <> 'Y')
                 and a.mantas_acct_holdr_type_cd in (@Incld_Acct_Hldr_Typ_Cd) 
                 and a.acct_efctv_risk_nb <> -2 
                 and (@All_Jurisdictions_Fl = 'Y' or a.jrsdcn_cd in (@Incl_Jurisdictions_Lst)) 
                 and a.mantas_acct_bus_type_cd in (@Mantas_Bus_Acct_Type_Lst)  
                -- ---------------------------------------------------------------------------------------------------------------     
                UNION ALL     
                -- ---------------------------------------------------------------------------------------------------------------     
                -- mi transaction records
                -- ---------------------------------------------------------------------------------------------------------------   
                -- Remitter 
                select 
                      a.ACCT_INTRL_ID,
                      a.ACCT_SEQ_ID,            
                      mi.FO_TRXN_SEQ_ID,
                      a.ACCT_OPEN_DT,
                      mi.DATA_DUMP_DT,
                      a.ACCT_EFCTV_RISK_NB,      
                      mi.Trxn_Am,
                      case when mi.REM_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then mi.Trxn_Am else 0 end Hr_Am,
                      mi.Pass_Thru_Am,
                      mi.Lrf_Am,
                      mi.Trusted_Trans_Amt, 
                      --  (b.clndr_dt - a.acct_open_dt) d_AGE,		
                      mi.REM_ACTVY_RISK_NB as d_ACTVTY_RISK_LVL,  
                      mi.Trxn_Am as d_TRXN_BASE_AM_DBT,
                      1 d_TRXN_CT_DBT,
                      0 d_TRXN_BASE_AM_CDT,
                      0 d_TRXN_CT_CDT,
                      1 as Not_EFT_Trans,
                      mi.FUNC_CRNCY_CD
                from 
                     mi_vw mi 
                              inner join fccmatomic.ACCT a on mi.REM_ACCT_ID = a.ACCT_INTRL_ID
                where 
                      mi.INTRL_REM_ACCT_FL = 'Y' 
                 --20039324, 34237111 
                 and mi.MANTAS_ISSUE_DATE > (select Min_Dt from clndr_vw) and mi.MANTAS_ISSUE_DATE <= (select Max_Dt from clndr_vw)  
                 and a.mantas_acct_holdr_type_cd in (@Incld_Acct_Hldr_Typ_Cd) 
                 and a.acct_efctv_risk_nb <> -2 
                 and (@All_Jurisdictions_Fl = 'Y' or a.jrsdcn_cd in (@Incl_Jurisdictions_Lst)) 
                 and a.mantas_acct_bus_type_cd in (@Mantas_Bus_Acct_Type_Lst) 
                -- ---------------------------------------------------------------------------------------------------------------     
                UNION ALL     
                -- ---------------------------------------------------------------------------------------------------------------     
                -- BENEF
                select 
                      a.ACCT_INTRL_ID,
                      a.ACCT_SEQ_ID,            
                      mi.FO_TRXN_SEQ_ID,
                      a.ACCT_OPEN_DT,
                      mi.DATA_DUMP_DT,
                      a.ACCT_EFCTV_RISK_NB,      
                      mi.Trxn_Am,
                      case when mi.BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then mi.Trxn_Am else 0 end Hr_Am,
                      mi.Pass_Thru_Am,
                      mi.Lrf_Am,
                      mi.Trusted_Trans_Amt, 
                      --  (b.clndr_dt - a.acct_open_dt) d_AGE,	
                      mi.BENEF_ACTVY_RISK_NB as d_ACTVTY_RISK_LVL,   
                      0 d_TRXN_BASE_AM_DBT,
                      0 d_TRXN_CT_DBT,
                      mi.Trxn_Am as d_TRXN_BASE_AM_CDT,
                      1 d_TRXN_CT_CDT,
                      1 as Not_EFT_Trans,
                      mi.FUNC_CRNCY_CD
                from 
                    mi_vw mi 
                           inner join fccmatomic.ACCT a on mi.BENEF_ACCT_ID = a.ACCT_INTRL_ID
                where 
                      mi.INTRL_BENEF_ACCT_FL = 'Y' 
				 and ((mi.INTRL_REM_ACCT_FL = 'Y' and COALESCE(mi.REM_ACCT_ID,'-') <> mi.BENEF_ACCT_ID) or mi.INTRL_REM_ACCT_FL <> 'Y')
                 --20039324, 34237111 
                 and mi.MANTAS_POST_DT > (select Min_Dt from clndr_vw) and mi.MANTAS_POST_DT <= (select Max_Dt from clndr_vw)  
                 and a.mantas_acct_holdr_type_cd in (@Incld_Acct_Hldr_Typ_Cd) 
                 and a.acct_efctv_risk_nb <> -2 
                 and (@All_Jurisdictions_Fl = 'Y' or a.jrsdcn_cd in (@Incl_Jurisdictions_Lst)) 
                 and a.mantas_acct_bus_type_cd in (@Mantas_Bus_Acct_Type_Lst) 
                -- ---------------------------------------------------------------------------------------------------------------     
                UNION ALL     
                -- ---------------------------------------------------------------------------------------------------------------     
                -- Scnd Benef
                select 
                      a.ACCT_INTRL_ID,
                      a.ACCT_SEQ_ID,            
                      mi.FO_TRXN_SEQ_ID,
                      a.ACCT_OPEN_DT,
                      mi.DATA_DUMP_DT,
                      a.ACCT_EFCTV_RISK_NB,      
                      mi.Trxn_Am,
                      case when mi.SCND_BENEF_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then mi.Trxn_Am else 0 end Hr_Am,
                      mi.Pass_Thru_Am,
                      mi.Lrf_Am,
                      mi.Trusted_Trans_Amt, 
                      --  (b.clndr_dt - a.acct_open_dt) d_AGE,
                      mi.SCND_BENEF_ACTVY_RISK_NB as d_ACTVTY_RISK_LVL,  
                      0 d_TRXN_BASE_AM_DBT,
                      0 d_TRXN_CT_DBT,
                      mi.Trxn_Am as d_TRXN_BASE_AM_CDT,
                      1 d_TRXN_CT_CDT,
                      1 as Not_EFT_Trans,
                      mi.FUNC_CRNCY_CD
                from 
                    mi_vw mi 
                           inner join fccmatomic.ACCT a on mi.SCND_BENEF_ACCT_ID = a.ACCT_INTRL_ID
                where 
                      mi.INTRL_SCND_BENEF_ACCT_FL = 'Y'
                 and ((mi.INTRL_REM_ACCT_FL = 'Y' and COALESCE(mi.REM_ACCT_ID,'-') <> mi.SCND_BENEF_ACCT_ID) or mi.INTRL_REM_ACCT_FL <> 'Y')
                 and ((mi.INTRL_BENEF_ACCT_FL = 'Y' and COALESCE(mi.BENEF_ACCT_ID,'-') <> mi.SCND_BENEF_ACCT_ID) or mi.INTRL_BENEF_ACCT_FL <> 'Y')
                 --20039324, 34237111 
                 and mi.MANTAS_POST_DT > (select Min_Dt from clndr_vw) and mi.MANTAS_POST_DT <= (select Max_Dt from clndr_vw)  
                 and a.mantas_acct_holdr_type_cd in (@Incld_Acct_Hldr_Typ_Cd) 
                 and a.acct_efctv_risk_nb <> -2 
                 and (@All_Jurisdictions_Fl = 'Y' or a.jrsdcn_cd in (@Incl_Jurisdictions_Lst)) 
                 and a.mantas_acct_bus_type_cd in (@Mantas_Bus_Acct_Type_Lst) 
                -- ---------------------------------------------------------------------------------------------------------------     
                UNION ALL     
                -- ---------------------------------------------------------------------------------------------------------------     
                -- 10/15/2004
                select 
                      c.ACCT_INTRL_ID,
                      a.ACCT_SEQ_ID,            
                      c.FO_TRXN_SEQ_ID,
                      a.ACCT_OPEN_DT,
                      c.DATA_DUMP_DT,
                      a.ACCT_EFCTV_RISK_NB,      
                      DECODE(@Curr_Type,'F',c.TRXN_FUNC_AM,c.TRXN_BASE_AM) as Trxn_Am,
                      case when c.CASH_TRXN_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then DECODE(@Curr_Type,'F',c.TRXN_FUNC_AM,c.TRXN_BASE_AM) else 0 end Hr_Am,
                      0 Pass_Thru_Am,
                      case when DECODE(@Curr_Type,'F',c.TRXN_FUNC_AM,c.TRXN_BASE_AM) - trunc(DECODE(@Curr_Type,'F',c.TRXN_FUNC_AM,c.TRXN_BASE_AM), -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',c.TRXN_FUNC_AM,c.TRXN_BASE_AM) 
                      when c.TRXN_ACTVY_AM - trunc(c.TRXN_ACTVY_AM, -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',c.TRXN_FUNC_AM,c.TRXN_BASE_AM)		 
                      else 0 end Lrf_Am,
                       0 as Trusted_Trans_Amt, 
                      --   (b.clndr_dt - a.acct_open_dt) d_AGE,	
                      c.CASH_TRXN_ACTVY_RISK_NB d_ACTVTY_RISK_LVL,  	
                      (CASE WHEN c.DBT_CDT_CD = 'D' THEN DECODE(@Curr_Type,'F',c.TRXN_FUNC_AM,c.TRXN_BASE_AM) ELSE 0 END) d_TRXN_BASE_AM_DBT,
                      (CASE WHEN c.DBT_CDT_CD = 'D' THEN 1 ELSE 0 END) d_TRXN_CT_DBT,
                      (CASE WHEN c.DBT_CDT_CD = 'C' THEN DECODE(@Curr_Type,'F',c.TRXN_FUNC_AM,c.TRXN_BASE_AM) ELSE 0 END) d_TRXN_BASE_AM_CDT,
                      (CASE WHEN c.DBT_CDT_CD = 'C' THEN 1 ELSE 0 END) d_TRXN_CT_CDT,
                      1 as Not_EFT_Trans,
                      c.FUNC_CRNCY_CD
                from 
                    fccmatomic.CASH_TRXN c 
                             inner join fccmatomic.ACCT a on c.ACCT_INTRL_ID = a.ACCT_INTRL_ID
                where 
                    (@All_Trans_Src_Fl = 'Y' or c.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
				 and c.MANTAS_TRXN_PURP_CD = 'GENERAL'
                 and c.MANTAS_TRXN_PRDCT_CD in (@Incl_Cash_Trxn_Prdct_Type_Lst)  
                 --20039324, 34237111 
                 and c.TRXN_EXCTN_DT > (select Min_Dt from clndr_vw) and c.TRXN_EXCTN_DT <= (select Max_Dt from clndr_vw)  
                 and c.DATA_DUMP_DT > (select Min_Dt from clndr_vw) and c.DATA_DUMP_DT <= (select Max_Dt from clndr_vw)                   
                 and a.mantas_acct_holdr_type_cd in (@Incld_Acct_Hldr_Typ_Cd) 
                 and a.acct_efctv_risk_nb <> -2 
                 and (@All_Jurisdictions_Fl = 'Y' or a.jrsdcn_cd in (@Incl_Jurisdictions_Lst)) 
                 and a.mantas_acct_bus_type_cd in (@Mantas_Bus_Acct_Type_Lst)  
                 and (@Incl_Rltd_Parties = 'Y' or COALESCE(c.unrltd_party_fl, 'Y') <> 'N')  
                 and c.CXL_PAIR_TRXN_INTRL_ID is null                      
                -- ---------------------------------------------------------------------------------------------------------------     
                UNION ALL     
                -- ---------------------------------------------------------------------------------------------------------------  
                select 
                      bo.ACCT_INTRL_ID,
                      a.ACCT_SEQ_ID,            
                      bo.BO_TRXN_SEQ_ID,
                      a.ACCT_OPEN_DT,
                      bo.DATA_DUMP_DT,
                      a.ACCT_EFCTV_RISK_NB,      
                      DECODE(@Curr_Type,'F',bo.TRXN_FUNC_AM,bo.TRXN_BASE_AM) as Trxn_Am,
                      case when bo.BO_TRXN_ACTVY_RISK_NB > @Actvty_Risk_Cutoff_Lvl then bo.TRXN_BASE_AM else 0 end Hr_Am,
                      0 Pass_Thru_Am,
                      case when DECODE(@Curr_Type,'F',bo.TRXN_FUNC_AM,bo.TRXN_BASE_AM) - trunc(DECODE(@Curr_Type,'F',bo.TRXN_FUNC_AM,bo.TRXN_BASE_AM), -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',bo.TRXN_FUNC_AM,bo.TRXN_BASE_AM)
                           when bo.TRXN_RPTNG_AM - trunc(bo.TRXN_RPTNG_AM, -@Lrf_Digits) = 0 then DECODE(@Curr_Type,'F',bo.TRXN_FUNC_AM,bo.TRXN_BASE_AM)		 
                      else 0 
                      end Lrf_Am,
                      case when bo.TRSTD_TRXN_FL = 'Y' then DECODE(@Curr_Type,'F',bo.TRXN_FUNC_AM,bo.TRXN_BASE_AM) else 0 end as Trusted_Trans_Amt, 
                      --  (b.clndr_dt - a.acct_open_dt) d_AGE,
                      bo.BO_TRXN_ACTVY_RISK_NB d_ACTVTY_RISK_LVL,	
                      (CASE WHEN bo.DBT_CDT_CD = 'D' THEN DECODE(@Curr_Type,'F',bo.TRXN_FUNC_AM,bo.TRXN_BASE_AM) ELSE 0 END) d_TRXN_BASE_AM_DBT,
                      (CASE WHEN bo.DBT_CDT_CD = 'D' THEN 1 ELSE 0 END) d_TRXN_CT_DBT,
                      (CASE WHEN bo.DBT_CDT_CD = 'C' THEN DECODE(@Curr_Type,'F',bo.TRXN_FUNC_AM,bo.TRXN_BASE_AM) ELSE 0 END) d_TRXN_BASE_AM_CDT,
                      (CASE WHEN bo.DBT_CDT_CD = 'C' THEN 1 ELSE 0 END) d_TRXN_CT_CDT,
                      1 as Not_EFT_Trans,
                      bo.FUNC_CRNCY_CD                      
                from
                    fccmatomic.BACK_OFFICE_TRXN bo
                            inner join fccmatomic.ACCT a on bo.ACCT_INTRL_ID = a.ACCT_INTRL_ID
                where 
                     bo.MANTAS_TRXN_PRDCT_CD in (@Incl_BO_Trxn_Prdct_Type_Lst)
                 and bo.MANTAS_TRXN_PURP_CD = 'GENERAL'
                 and bo.CXL_PAIR_TRXN_INTRL_ID is null
                 and (@All_Trans_Src_Fl = 'Y' or bo.SRC_SYS_CD IN (@Incl_Trans_Src_Lst))
                 --20039324, 34237111 
                 and bo.EXCTN_DT > (select Min_Dt from clndr_vw) and bo.EXCTN_DT <= (select Max_Dt from clndr_vw)  
                 and bo.DATA_DUMP_DT > (select Min_Dt from clndr_vw) and bo.DATA_DUMP_DT <= (select Max_Dt from clndr_vw)                 
                 and a.mantas_acct_holdr_type_cd in (@Incld_Acct_Hldr_Typ_Cd) 
                 and a.acct_efctv_risk_nb <> -2 
                 and (@All_Jurisdictions_Fl = 'Y' or a.jrsdcn_cd in (@Incl_Jurisdictions_Lst)) 
                 and a.mantas_acct_bus_type_cd in (@Mantas_Bus_Acct_Type_Lst)     
                 --21034264 
                 and (@Include_Trusted_Trans_FL = 'Y' or COALESCE(bo.TRSTD_TRXN_FL, 'N') = 'N')  
                 and (@Incl_Rltd_Parties = 'Y' or bo.unrltd_party_cd is not null)    
    ) t
     --(select * from fccmatomic.KDD_cal b where b.CLNDR_NM = 'SYSCAL' and b.CLNDR_DAY_AGE = 0) k
    group by 
           t.ACCT_INTRL_ID
        having 
        -- Frequency Period
        --20039324, 34237111  
           -- max(t.data_dump_dt) in (select b.CLNDR_DT from fccmatomic.KDD_CAL b where b.CLNDR_NM = 'SYSCAL' and b.CLNDR_DAY_AGE between 0 and @Frequency_Period-1) 
           max(t.data_dump_dt) > (select Freq_Dt from clndr_vw) and max(t.data_dump_dt) <= (select Max_Dt from clndr_vw)               
        -- looking if there  any other then EFT (WIRE_TRXN)transactions          
        and  (@Alert_on_EFT_Only = 'Y' or sum(t.Not_EFT_Trans) <>0)
    ) v
where
(
    (
    v.Overall_Risk = 'HR' and
    v.Age <= @Open_Days and
    v.Trans_Amt_Cdt >= @HR_Min_Credit_Amt_New and 
    v.Trans_Amt_Cdt <= @HR_Max_Credit_Amt_New and
    v.Trans_Ct_Cdt >= @HR_Min_Credit_Ct_New and 
    v.Trans_Ct_Cdt <= @HR_Max_Credit_Ct_New and
    v.Trans_Ct_Dbt >= @HR_Min_Debit_Ct_New and
    v.Trans_Ct_Dbt <= @HR_Max_Debit_Ct_New and
    v.Trans_Amt_Dbt >= v.Trans_Amt_Cdt * (1- (@HR_Min_Percentage_New / 100)) and
    v.Trans_Amt_Dbt <= v.Trans_Amt_Cdt * (1+ (@HR_Min_Percentage_New / 100))
    )
    or
    (
    v.Overall_Risk = 'MR' and
    v.Age <= @Open_Days and
    v.Trans_Amt_Cdt >= @MR_Min_Credit_Amt_New and 
    v.Trans_Amt_Cdt <= @MR_Max_Credit_Amt_New and
    v.Trans_Ct_Cdt >= @MR_Min_Credit_Ct_New and 
    v.Trans_Ct_Cdt <= @MR_Max_Credit_Ct_New and
    v.Trans_Ct_Dbt >= @MR_Min_Debit_Ct_New and
    v.Trans_Ct_Dbt <= @MR_Max_Debit_Ct_New and
    v.Trans_Amt_Dbt >= v.Trans_Amt_Cdt * (1- (@MR_Min_Percentage_New / 100)) and
    v.Trans_Amt_Dbt <= v.Trans_Amt_Cdt * (1+ (@MR_Min_Percentage_New / 100))
    )
    or
    (
    v.Overall_Risk = 'RR' and
    v.Age <= @Open_Days and
    v.Trans_Amt_Cdt >= @RR_Min_Credit_Amt_New and 
    v.Trans_Amt_Cdt <= @RR_Max_Credit_Amt_New and
    v.Trans_Ct_Cdt >= @RR_Min_Credit_Ct_New and 
    v.Trans_Ct_Cdt <= @RR_Max_Credit_Ct_New and
    v.Trans_Ct_Dbt >= @RR_Min_Debit_Ct_New and
    v.Trans_Ct_Dbt <= @RR_Max_Debit_Ct_New and
    v.Trans_Amt_Dbt >= v.Trans_Amt_Cdt * (1- (@RR_Min_Percentage_New / 100)) and
    v.Trans_Amt_Dbt <= v.Trans_Amt_Cdt * (1+ (@RR_Min_Percentage_New / 100))
    )
)  
or  
(
   (
   v.Overall_Risk = 'HR' and
   v.Age > @Open_Days and
   v.Trans_Amt_Cdt >= @HR_Min_Credit_Amt_Seasoned and 
   v.Trans_Amt_Cdt <= @HR_Max_Credit_Amt_Seasoned and
   v.Trans_Ct_Cdt >= @HR_Min_Credit_Ct_Seasoned and 
   v.Trans_Ct_Cdt <= @HR_Max_Credit_Ct_Seasoned and
   v.Trans_Ct_Dbt >= @HR_Min_Debit_Ct_Seasoned and
   v.Trans_Ct_Dbt <= @HR_Max_Debit_Ct_Seasoned and
   v.Trans_Amt_Dbt >= v.Trans_Amt_Cdt * (1- (@HR_Min_Percentage_Seasoned / 100)) and
   v.Trans_Amt_Dbt <= v.Trans_Amt_Cdt * (1+ (@HR_Min_Percentage_Seasoned / 100)) 
   --and v.Trans_Amt_Cdt >= v.Tot_Net_Wrth * @HR_Net_Worth_Percentage_Seasoned / 100
)
or
(
   v.Overall_Risk = 'MR' and
   v.Age > @Open_Days and
   v.Trans_Amt_Cdt >= @MR_Min_Credit_Amt_Seasoned and 
   v.Trans_Amt_Cdt <= @MR_Max_Credit_Amt_Seasoned and
   v.Trans_Ct_Cdt >= @MR_Min_Credit_Ct_Seasoned and 
   v.Trans_Ct_Cdt <= @MR_Max_Credit_Ct_Seasoned and
   v.Trans_Ct_Dbt >= @MR_Min_Debit_Ct_Seasoned and
   v.Trans_Ct_Dbt <= @MR_Max_Debit_Ct_Seasoned and
   v.Trans_Amt_Dbt >= v.Trans_Amt_Cdt * (1- (@MR_Min_Percentage_Seasoned / 100)) and
   v.Trans_Amt_Dbt <= v.Trans_Amt_Cdt * (1+ (@MR_Min_Percentage_Seasoned / 100)) 
   --and v.Trans_Amt_Cdt >= v.Tot_Net_Wrth * @MR_Net_Worth_Percentage_Seasoned / 100
)
or
(
   v.Overall_Risk = 'RR' and
   v.Age > @Open_Days and
   v.Trans_Amt_Cdt >= @RR_Min_Credit_Amt_Seasoned and 
   v.Trans_Amt_Cdt <= @RR_Max_Credit_Amt_Seasoned and
   v.Trans_Ct_Cdt >= @RR_Min_Credit_Ct_Seasoned and 
   v.Trans_Ct_Cdt <= @RR_Max_Credit_Ct_Seasoned and
   v.Trans_Ct_Dbt >= @RR_Min_Debit_Ct_Seasoned and
   v.Trans_Ct_Dbt <= @RR_Max_Debit_Ct_Seasoned and
   v.Trans_Amt_Dbt >= v.Trans_Amt_Cdt * (1- (@RR_Min_Percentage_Seasoned / 100)) and
   v.Trans_Amt_Dbt <= v.Trans_Amt_Cdt * (1+ (@RR_Min_Percentage_Seasoned / 100)) 
   --and v.Trans_Amt_Cdt >= v.Tot_Net_Wrth * @RR_Net_Worth_Percentage_Seasoned / 100
 )
)
 ) ot ORDER BY ot.ACCT_SEQ_ID 