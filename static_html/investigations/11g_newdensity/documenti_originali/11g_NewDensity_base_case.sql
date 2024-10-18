-- Supporting code for the "New Density calculation in 11g" paper (www.adellera.it).
-- 
-- Example of 11g "NewDensity"
-- 
-- For Height-Balanced Histograms, NewDensity is set as 1/num_distinct(not-popular subtable),
-- plus adjustment to cather for num_rows(table) / num_rows(not-popular subtable)
--
-- For Frequency  Histograms, NewDensity is still set to the pre-11g 0.5 / num_rows.
--
-- But the histogram type is determined at run-time, and manually changing
-- the density via dbms_stats can change the histogram type in some cases. 
--
-- (c) Alberto Dell'Era, November 2007
-- Tested in 11.1.0.6.

set echo on
set lines 150
set pages 9999
set serveroutput on size 1000000

drop table t;

spool 11g_NewDensity_base_case.lst

-- a utility procedure to change density, preserving the histogram
create or replace procedure set_density (
  p_table_name  varchar2,
  p_column_name varchar2,
  p_new_density number
)
is
  l_distcnt number;
  l_density number;
  l_nullcnt number;
  l_srec    dbms_stats.statrec;
  l_avgclen number;
begin
  -- get the current column statistics
  dbms_stats.get_column_stats (
    ownname => user,
    tabname => p_table_name,
    colname => p_column_name,
    distcnt => l_distcnt,
    density => l_density,
    nullcnt => l_nullcnt,
    srec    => l_srec,
    avgclen => l_avgclen
  );

  -- reset them, overwriting "density"
  dbms_stats.set_column_stats (
    ownname => user,
    tabname => p_table_name,
    colname => p_column_name,
    distcnt => l_distcnt,
    density => p_new_density,
    nullcnt => l_nullcnt,
    srec    => l_srec,
    avgclen => l_avgclen,
    no_invalidate => false
  );

  dbms_output.put_line ('density of '||p_table_name||'.'||p_column_name||' changed from '||l_density||' to '|| p_new_density);

end set_density;
/
show errors;

-- a table with "random" values
create table t as select rownum as value from dual connect by level <= 15;
update t set value = 2  where value between 3 and 8;
update t set value = 15 where value >= 12;

-- stats
exec dbms_stats.gather_table_stats (user, 'T', method_opt=>'for all columns size 5', estimate_percent=>null);
--exec dbms_stats.gather_table_stats (user, 'T', method_opt=>'for all columns size 254', estimate_percent=>null);
--exec set_density ('T', 'value', 0.2);

-- a view to format dba_histograms for our example table
create or replace view formatted_hist as
with hist1 as (
  select endpoint_number ep, endpoint_value value
    from user_histograms 
   where table_name  = 'T'
     and column_name = 'VALUE'
), hist2 as (
  select ep, value, 
         lag (ep) over (order by ep) prev_ep,
         max (ep) over ()            max_ep
    from hist1
)
select value, ep, ep - nvl(prev_ep,0) as bkt,
       decode (ep - nvl (prev_ep, 0), 0, 0, 1, 0, 1) as popularity
 from hist2
order by ep;

select * from formatted_hist;

-- views to automatically compute the NewDensity formula for HBs
create or replace view newdensity_factors as
select max(ep) as BktCnt, -- should be equal to sum(bkt)
       sum (case when popularity=1 then bkt else 0 end) as PopBktCnt,
       sum (case when popularity=1 then 1   else 0 end) as PopValCnt,
       max ((select num_distinct as NDV from user_tab_cols where table_name = 'T' and column_name = 'VALUE')) as NDV,
       max ((select density      from user_tab_cols where table_name = 'T' and column_name = 'VALUE')) as density
  from formatted_hist;
       
create or replace view newdensity as
select ( (BktCnt - PopBktCnt) / BktCnt ) / (NDV - PopValCnt) as newdensity, 
       density as OldDensity,
       BktCnt, PopBktCnt, PopValCnt, NDV
  from newdensity_factors;
  
select * from newdensity;

select histogram from user_tab_columns where table_name = 'T' and column_name = 'VALUE';

--alter session set "_optimizer_enable_density_improvements"=false;

-- 10053 trace for a not-popular value
alter session set events '10053 trace name context forever, level 1';
select * from t where value = 2.4; 
alter session set events '10053 trace name context off';

doc
  --------------------------------------------------------------------------------------
  HB histogram (SIZE=5) :
  
  Column (#1): 
    NewDensity:0.050000, OldDensity:0.066667 BktCnt:5, PopBktCnt:4, PopValCnt:2, NDV:6
  Using density: 0.050000 of col #1 as selectivity of unpopular value pred
 
  NewDensity = [ (BktCnt - PopBktCnt) / BktCnt ] / (NDV - PopValCnt) =
             = [ (5 - 4) / 5 ] / (6-2) = .05 (as required)
             
  SQL> select histogram from user_tab_columns where table_name = 'T' and column_name = 'VALUE';

  HISTOGRAM
  ---------------------------------------------
  HEIGHT BALANCED           
             
  --------------------------------------------------------------------------------------             
  Frequency histogram (SIZE=254) :   
  Column (#1): 
    NewDensity:0.033333, OldDensity:0.033333 BktCnt:15, PopBktCnt:11, PopValCnt:2, NDV:6
  Using density: 0.033333 of col #1 as selectivity of unpopular value pred
  
  NewDensity = 0.5 / num_rows = 0.5 / 15 = .033333333 (as required)
                
  SQL> select histogram from user_tab_columns where table_name = 'T' and column_name = 'VALUE';

  HISTOGRAM
  ---------------------------------------------
  FREQUENCY
  
  --------------------------------------------------------------------------------------
  Frequency histogram (SIZE=254) and density manually set to 0.2:              
  Column (#1): 
    NewDensity:0.066667, OldDensity:0.200000 BktCnt:15, PopBktCnt:11, PopValCnt:2, NDV:6
  Using density: 0.066667 of col #1 as selectivity of unpopular value pred 
  
  NewDensity = [ (BktCnt - PopBktCnt) / BktCnt ] / (NDV - PopValCnt) = 
               [ (15 - 11) / 15 ] / (6 - 2) = .066666667 (as required)
               
  NewDensity = 1.0 / num_rows = 1.0 / 15 = .066666667
  
  SQL> select histogram from user_tab_columns where table_name = 'T' and column_name = 'VALUE';

  HISTOGRAM
  ---------------------------------------------
  HEIGHT BALANCED
                
#

spool off

