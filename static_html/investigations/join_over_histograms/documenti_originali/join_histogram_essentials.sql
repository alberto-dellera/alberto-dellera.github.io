-- Supporting code for the "Join over Histograms" paper
--
-- The example used to illustrate the essentials of the formula;
-- completely overlapping ranges with matches at both ends.
--
-- (c) Alberto Dell'Era, March 2007
-- Tested in 10.2.0.3.

set echo on
set lines 150
set pages 9999

drop table t1;
drop table t2;

spool join_histogram_essentials.lst

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

-- table t1 with its Height-Based histogram collected
create table t1 (value number);
insert into t1(value) select  10 from dual connect by level <= 4;
insert into t1(value) values (10.5);
insert into t1(value) values (20  );
insert into t1(value) select  30 from dual connect by level <= 4;
insert into t1(value) values (30.5);
insert into t1(value) values (40  );
insert into t1(value) values (40.5);
insert into t1(value) values (50  );
insert into t1(value) values (50.5);
insert into t1(value) values (60  );
insert into t1(value) select  70 from dual connect by level <= 4;

exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 10', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist_t1;

-- table t2 with its Frequency histogram collected
create table t2 (value number);
insert into t2(value) select  10 from dual connect by level <= 2;
insert into t2(value) values (20);
insert into t2(value) select  50 from dual connect by level <= 3;
insert into t2(value) values (60);
insert into t2(value) select  70 from dual connect by level <= 4;

exec dbms_stats.gather_table_stats (user, 't2', method_opt=>'for all columns size 254', estimate_percent=>100);
select value from t2 order by value;
select * from formatted_hist_t2;

-- table statistics
col table_name form a5
select t.table_name, t.num_rows, c.density, t.num_rows * c.density "num_rows*density", t.num_rows / c.num_distinct 
  from user_tables t, user_tab_columns c 
 where t.table_name = c.table_name
   and t.table_name in ('T1','T2')
   and c.column_name = 'VALUE'
  order by table_name;

-- The Join Histogram (in this scenario, it's the chopped and chopped+2 histogram as well)
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

set autotrace traceonly explain
select count(*)
  from t1, t2
 where t1.value = t2.value;
set autotrace off 

spool off

