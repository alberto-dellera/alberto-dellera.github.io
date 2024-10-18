-- Supporting code for the "Join over Histograms" paper
--
-- Frequency Histograms and the "mystery of halving" example.
-- It shows that if you build a FH on a column with all distinct values,
-- the CBO will estimate a join cardinality that is systematically 
-- half the real cardinality. 
--
-- (c) Alberto Dell'Era, March 2007
-- Tested in 10.2.0.3.

set echo on
set lines 150
set pages 9999
set serveroutput on size 1000000

drop table t2;
drop table t1;
drop table t3;

spool fh_and_mystery_of_halving.lst

col value form 99.9

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

-- table t1 with a skewed distribution, and its Frequency histogram collected
create table t1 (value number);
insert into t1(value) select  10 from dual connect by level <= 73;
insert into t1(value) select  20 from dual connect by level <= 61;
insert into t1(value) select  30 from dual connect by level <= 97;
insert into t1(value) select  40 from dual connect by level <= 82;
insert into t1(value) select  50 from dual connect by level <= 91;
insert into t1(value) select  70 from dual connect by level <= 96;

exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 254', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist_t1;

-- table t2 with all distinct values, and its Frequency histogram collected
create table t2 (value number);
insert into t2(value) values (10);
insert into t2(value) values (20);
insert into t2(value) values (30);
insert into t2(value) values (40);
insert into t2(value) values (50);
insert into t2(value) values (60);
insert into t2(value) values (70);

-- uncomment the following two lines if you want to check that
-- the presence of FK constraints doesn't make any difference
--alter table t2 add primary key (value);
--alter table t1 add constraint fk foreign key (value) references t2 (value);

exec dbms_stats.gather_table_stats (user, 't2', method_opt=>'for all columns size 254', estimate_percent=>100);
select value from t2 order by value;
select * from formatted_hist_t2;

-- uncomment the following two lines if you want to magnify all the contributors
-- with the exception of "populars matching populars"
-- You need of course to install the set_density package
--exec set_density ('t1', 'value', 100);
--exec set_density ('t2', 'value', 100);

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
col lhs_counts     form a5
col value          form 99
col rhs_counts     form a5
col rhs_popularity form a3
select * from join_histogram;

-- uncomment the following two lines if you want to calculate the contributors
-- using the formula implemented in pl/sql and sql
-- You need of course to install the join_over_histograms package 
-- workaround for bug 4626732, 5752903 "ORA-07445 [ACCESS_VIOLATION] [_evaopn2+153]"
--alter session set "_optimizer_native_full_outer_join"=force;
--select join_over_histograms.get ('t1', 'value', 't2', 'value') from dual;

select count(*) as exact_cardinality
  from t1, t2
 where t1.value = t2.value;

set autotrace traceonly explain
select count(*)
  from t1, t2
 where t1.value = t2.value;
set autotrace off 

-- remove the histogram on t2 - so that the CBO uses the standard formula and
-- gets back the exact cardinality.
exec dbms_stats.gather_table_stats (user, 't2', method_opt=>'for all columns size 1', estimate_percent=>100);

set autotrace traceonly explain
select count(*)
  from t1, t2
 where t1.value = t2.value;
set autotrace off 

-- check that the halving will accumulate - an halving for every table with unique values joined
create table t3 as select * from t2;
alter table t1 add (value2 number);
update t1 set value2=value;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 254', estimate_percent=>100);
exec dbms_stats.gather_table_stats (user, 't2', method_opt=>'for all columns size 254', estimate_percent=>100);
exec dbms_stats.gather_table_stats (user, 't3', method_opt=>'for all columns size 254', estimate_percent=>100);

select count(*) as exact_cardinality
  from t1, t2, t3
 where t1.value  = t2.value
   and t1.value2 = t3.value;

set autotrace traceonly explain
select count(*)
  from t1, t2, t3
 where t1.value  = t2.value
   and t1.value2 = t3.value;
set autotrace off 

-- in this case also, if you remove the histogram on the tables with unique values,
-- the CBO uses the standard formula and gets back the exact cardinality.
exec dbms_stats.gather_table_stats (user, 't2', method_opt=>'for all columns size 1', estimate_percent=>100);
exec dbms_stats.gather_table_stats (user, 't3', method_opt=>'for all columns size 1', estimate_percent=>100);

set autotrace traceonly explain
select count(*)
  from t1, t2, t3
 where t1.value  = t2.value
   and t1.value2 = t3.value;
set autotrace off 

spool off
