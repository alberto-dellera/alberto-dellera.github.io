-- Supporting code for the "Join over Histograms" paper
--
-- Some examples used to illustrate the meaning of the important
-- num_rows * density derived statistics, in the context of a join
-- and of a simple selection such as "where value = constant".
--
-- (c) Alberto Dell'Era, March 2007
-- Tested in 10.2.0.3.

set echo on
set lines 150
set pages 9999
set serveroutput on size 1000000

drop table t1;

spool num_rows_times_density.lst

-- a view to format dba_histograms for our example table
create or replace view formatted_hist as
with hist1 as (
  select endpoint_number ep, endpoint_value value
    from user_histograms 
   where table_name  = 'T1'
     and column_name = 'VALUE'
), hist2 as (
  select ep, value, 
         lag (ep) over (order by ep) prev_ep,
         max (ep) over ()            max_ep
    from hist1
)
select value, ep, 
       (select num_rows from user_tables where table_name  = 'T1') 
       * (ep - nvl (prev_ep, 0)) 
       / max_ep as counts,
       decode (ep - nvl (prev_ep, 0), 0, 0, 1, 0, 1) as popularity
 from hist2
order by ep;

-- a view to compute num_rows*density and num_rows/num_distinct
create or replace view derived_stats as
with s1 as (
select num_rows
  from user_tables
 where table_name  = 'T1'
), s2 as (
select density, num_distinct  
  from user_tab_columns 
 where table_name  = 'T1'
   and column_name = 'VALUE'
)
select num_rows*density      as "num_rows*density", 
       num_rows/num_distinct as "num_rows/num_distinct",
       density               as "density",
       num_rows              as "num_rows"
from s1, s2;

-- a procedure to change density, preserving the histogram
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

-- Example 1: num_rows*density for all-distinct not-popular values
create table t1 as select rownum as value from dual connect by level <= 12;

update t1 set value = 99 where value >= 7;

exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 4', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

select count(value) / count (distinct value) avg_table    from t1;
select count(value) / count (distinct value) avg_subtable from t1 where value != 99;

select * from derived_stats;

set autotrace traceonly explain
-- unpopular value in the histogram
select * from t1 where value = 2; 
-- value not in the table
select * from t1 where value = 2.3; 
set autotrace off 

exec set_density ('t1', 'value', 11 * .0833333333333333);

set autotrace traceonly explain
-- unpopular value in the histogram
select * from t1 where value = 2; 
-- value not in the table
select * from t1 where value = 2.3; 
set autotrace off 

-- Example 2: num_rows*density when not-popular values form a perfectly uniform distribution
-- (a) checks that num_rows*density perfectly gives the average number of rows per value
--     in the unpopular subtable
-- (b) checks that num_rows_unpopular*density is far from giving the same figure as above
drop table t1;
create table t1 as
select value 
  from (select rownum as value from dual connect by level <= 1000),
       (select dummy from dual connect by level <= 5);
update t1 set value = 1000 where value >= 251;

exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 250', estimate_percent=>100);
-- uncomment the following line to experiment with a "wild" N that gives the same results
--exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 42', estimate_percent=>100);

select value from t1 order by value;
select * from formatted_hist;

select count(value) / count (distinct value) avg_table    from t1;
select count(value) / count (distinct value) avg_subtable from t1 
 where value not in (select value from formatted_hist where popularity = 1);

select s.*, (select sum(counts) from formatted_hist where popularity != 1) * "density" as "num_rows_unpopular*density" 
  from derived_stats s;
  
spool off

