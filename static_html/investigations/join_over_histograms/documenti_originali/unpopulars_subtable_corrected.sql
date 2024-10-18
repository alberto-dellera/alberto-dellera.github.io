-- Supporting code for the "Join over Histograms" paper
--
-- It shows a case where the "not-populars subtable" contributor
-- makes the CBO underestimate the cardinality, which comes out
-- as exact once the contributor is corrected by the factor
-- num_rows / num_rows_unpopular.
--
-- (c) Alberto Dell'Era, March 2007
-- Tested in 10.2.0.3.

set echo on
set lines 150
set pages 9999
set serveroutput on size 1000000

drop table t1;
drop table t2;

spool unpopulars_subtable_corrected.lst

-- some views to format dba_histograms for our example tables
create or replace view formatted_hist_t1 as
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

create or replace view formatted_hist_t2 as
with hist1 as (
  select endpoint_number ep, endpoint_value value
    from user_histograms 
   where table_name  = 'T2'
     and column_name = 'VALUE'
), hist2 as (
  select ep, value, 
         lag (ep) over (order by ep) prev_ep,
         max (ep) over ()            max_ep
    from hist1
)
select value, ep, 
       (select num_rows from user_tables where table_name  = 'T2') 
       * (ep - nvl (prev_ep, 0)) 
       / max_ep as counts,
       decode (ep - nvl (prev_ep, 0), 0, 0, 1, 0, 1) as popularity
 from hist2
order by ep;

-- two tables whose value distribution is symmetrical around their central value,
-- with a peak at one end
create table t1 as select rownum value from dual connect by level <= 250;
insert into t1 select * from t1;
insert into t1 select * from t1;
insert into t1 select 1 from t1;

create table t2 as select rownum value from dual connect by level <= 250;
insert into t2 select * from t2;
insert into t2 select * from t2;
insert into t2 select 250 from t2;

exec dbms_stats.gather_table_stats (user, 't1', method_opt => 'for all columns size 100');
exec dbms_stats.gather_table_stats (user, 't2', method_opt => 'for all columns size 100');

--select value from t1 order by value;
select * from formatted_hist_t1;

--select value from t2 order by value;
select * from formatted_hist_t2;

-- table statistics
col table_name form a5
select t.table_name, t.num_rows, c.density, t.num_rows * c.density "num_rows*density", t.num_rows / c.num_distinct 
  from user_tables t, user_tab_columns c 
 where t.table_name = c.table_name
   and t.table_name in ('T1','T2')
   and c.column_name = 'VALUE'
  order by table_name;

-- The Join Histogram 
create or replace view join_histogram as
select decode (lhs.popularity, 1, 'POP', 0, 'UN', '-') as lhs_popularity,
       nvl(to_char(lhs.counts),'-')                    as lhs_counts,
       nvl(lhs.value, rhs.value)                       as value, 
       nvl(to_char(rhs.counts),'-')                    as rhs_counts,
       decode (rhs.popularity, 1, 'POP', 0, 'UN', '-') as rhs_popularity,
       nvl(lhs.popularity,0) + nvl(rhs.popularity,0)   as join_popularity
 from (select * from formatted_hist_t1) lhs -- select * necessary for "table does not exist" workaround
      full outer join 
      (select * from formatted_hist_t2) rhs -- select * necessary for "table does not exist" workaround
   on (lhs.value = rhs.value)
order by nvl(lhs.value, rhs.value);

col lhs_popularity form a3
col lhs_counts     form a7
--col value          form 99
col rhs_counts     form a7
col rhs_popularity form a3
select * from join_histogram;

-- uncomment the following two lines if you want to calculate the contributors
-- using the formula implemented in pl/sql and sql
-- You need of course to install the join_over_histograms package 
-- workaround for bug 4626732, 5752903 "ORA-07445 [ACCESS_VIOLATION] [_evaopn2+153]"
-- alter session set "_optimizer_native_full_outer_join"=force;
-- select join_over_histograms.get ('t1', 'value', 't2', 'value') from dual;

set autotrace traceonly explain
select count(*)
  from t1, t2
 where t1.value = t2.value;
set autotrace off 

select count(*) as real_cardinality
  from t1, t2
 where t1.value = t2.value;

-- card estimation error = about 20%
-- here 
-- "populars not matching populars" = 8080
-- "not-populars subtables" = 1960
-- total = 8080 + 1960 = 10040
 
-- the card corrected by the factor num_rows / num_rows_unpopular = 2
select  8080 + 2 * 1960 from dual;

-- EXACT - even if there's an error in the computation of counts 
-- for the popular value t2.value = 250 (it's 1004, not 1020)

spool off

