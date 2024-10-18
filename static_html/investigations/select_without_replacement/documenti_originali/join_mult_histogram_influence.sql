--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Suggests that the selectivity of single-column join predicates WITH histograms
--    does not factor in the intervals. They use their own formula, identical to
--    the single-predicate join case.
--    So only when the second join predicate has histogram collected,
--    the intervals influence the cardinality.
--    
--    Alberto Dell'Era, August 2007
--    
--    tested in 10.2.0.3 only


start setenv.sql
start distinctBallsPlSql.sql
set timing off

exec dbms_random.seed(0)

exec execute immediate 'purge recyclebin'; exception when others then null;

spool join_mult_histogram_influence.lst

-- end of initialization section

drop table t2;
drop table t1;

purge recyclebin;

-- max 250
define num_rows_t1=100
-- max 250
define num_rows_t2=100

define num_dist_t1_x = 2    
define num_dist_t2_x = 10
define num_dist_t1_y = 17
define num_dist_t2_y = 32
define cbo_card_filt_t1=50
define cbo_card_filt_t2=100

create table t1 as
select trunc(dbms_random.value(0, &num_dist_t1_x.)) x, trunc(dbms_random.value(0,  &num_dist_t1_y.)) y, rownum filter from dual connect by level <= &num_rows_t1. ;

--update t1 set x = least (rownum, &num_dist_t1_x.); 
--update t1 set y = least (rownum, &num_dist_t1_y.);

create table t2 as
select trunc(dbms_random.value(0, &num_dist_t2_x.)) x, trunc(dbms_random.value(0,  &num_dist_t2_y.)) y, rownum filter from dual connect by level <= &num_rows_t2. ;

--update t2 set x = least (rownum, &num_dist_t2_x.); 
--update t2 set y = least (rownum, &num_dist_t2_y.);



-- collect baseline stats, build an histogram on the "filter" column
exec dbms_stats.gather_table_stats (user, 't1', cascade=>true, method_opt => 'for columns x size 1, y size 1, filter size 254', estimate_percent=>100);
exec dbms_stats.gather_table_stats (user, 't2', cascade=>true, method_opt => 'for columns x size 1, y size 1, filter size 254', estimate_percent=>100);

-- this is meaningful in 10g only to prevent the 10g "multi-column join key sanity check" from masking the core algorithm

alter session set "_optimizer_join_sel_sanity_check"=false;

--alter session set events '10053 trace name context forever, level 1';
set autotrace traceonly explain

select /*+ ordered use_nl(t2) singletest */ t1.*, t2.*
  from t1, t2 
 where t1.x = t2.x
   and t1.y = t2.y 
   and t1.filter < &cbo_card_filt_t1.
   and t2.filter < &cbo_card_filt_t2.
;
set autotrace off
alter session set events '10053 trace name context off';

-- histograms on both the joined columns
--exec dbms_stats.gather_table_stats (user, 't1', cascade=>true, method_opt => 'for all columns size 254', estimate_percent=>100);
--exec dbms_stats.gather_table_stats (user, 't2', cascade=>true, method_opt => 'for all columns size 254', estimate_percent=>100);
-- histograms on only the first  join pred (t1.x = t2.x)
exec dbms_stats.gather_table_stats (user, 't1', cascade=>true, method_opt => 'for columns x size 254, y size 1, filter size 254', estimate_percent=>100);
exec dbms_stats.gather_table_stats (user, 't2', cascade=>true, method_opt => 'for columns x size 254, y size 1, filter size 254', estimate_percent=>100);
-- histograms on only the second  join pred (t1.y = t2.y )
--exec dbms_stats.gather_table_stats (user, 't1', cascade=>true, method_opt => 'for columns x size 1, y size 254, filter size 254', estimate_percent=>100);
--exec dbms_stats.gather_table_stats (user, 't2', cascade=>true, method_opt => 'for columns x size 1, y size 254, filter size 254', estimate_percent=>100);


alter session set events '10053 trace name context forever, level 1';
set autotrace traceonly explain

prompt only the first  join pred (t1.x = t2.x)
select /*+ ordered use_nl(t2) singletest only_x  */ t1.*, t2.*
  from t1, t2 
 where t1.x = t2.x
   --and t1.y = t2.y 
   and t1.filter < &cbo_card_filt_t1.
   and t2.filter < &cbo_card_filt_t2.
;

prompt only the second join pred (t1.y = t2.y)
select /*+ ordered use_nl(t2) singletest only_y */ t1.*, t2.*
  from t1, t2 
 where --t1.x = t2.x
       t1.y = t2.y 
   and t1.filter < &cbo_card_filt_t1.
   and t2.filter < &cbo_card_filt_t2.
;


prompt both join pred
select /*+ ordered use_nl(t2) singletest both */ t1.*, t2.*
  from t1, t2 
 where t1.x = t2.x
   and t1.y = t2.y 
   and t1.filter < &cbo_card_filt_t1.
   and t2.filter < &cbo_card_filt_t2.
;
set autotrace off
alter session set events '10053 trace name context off';

select min(x), max(x), min(y), max(y) from t1;
select min(x), max(x), min(y), max(y) from t2;

select t.table_name, c.column_name, c.num_distinct, c.num_buckets, 
       exp_dist_balls_uniform ( c.num_distinct, decode (c.table_name, 'T1', &cbo_card_filt_t1., 'T2', &cbo_card_filt_t2.), t.num_rows ) f_num_distinct
 from user_tab_columns c, user_tables t 
 where t.table_name in ('T1','T2')
   and t.table_name = c.table_name
   and c.column_name in ('X', 'Y', 'FILTER')
 order by column_name, table_name;

doc 
      MIN(X)     MAX(X)     MIN(Y)     MAX(Y)
---------- ---------- ---------- ----------
         0          1          0         16
         0          9          0         31
  
  frequency histograms on both the sides of single joined predicates or none.
  selectivities from 10053 trace
  
  -- Histograms of both the first and the second join predicate:
  only first  join pred: sel_x  = 0.14745
  only second join pred: sel_y  = 0.03035
  both        join pred: sel_xy = 0.0044751 (0.14745*0.03035 = .004475108, the same)
  -- Histograms on only the first join predicate: 
  only first  join pred: sel_x  = 0.14745
  only second join pred: sel_y  = 0.033333
  both        join pred: sel_xy = 0.0086735 (0.14745 * 0.033333 = .004914951 DIFFERENT)
  
  in fact since
  t1.x interval=[0-1] t2.x interval=[0-9]
  first_pred_sel ( t1.y ) = 1
  first_pred_sel ( t2.y ) = (1-0)/(9-0) = 1 / 9
  f_num_distinct (t1.y) = swru (  17,  50 * 1    , 100) =  16.7437574
  f_num_distinct (t2.y) = swru (  30, 100 * 1 / 9, 100) =   9.81176513
  join_sel_y = 1 / ceil (greatest (16.7437574, 1) = 1 / 17
  
  0.14745 * (1 / 17) = .008673529 (as required)
  
  note that the interval correction is significat, without that we would have
  f_num_distinct (t2.y) = swru (  30, 100, 100 ) = 30
  so join_sel_y = 1 / 30
  
  -- Histograms on only the second join predicate:
  only first  join pred: sel_x  = 0.1
  only second join pred: sel_y  = 0.03035
  both        join pred: sel_xy = 0.003035 (0.1 * 0.03035 = .003035)
#
