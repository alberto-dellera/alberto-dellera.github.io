-- Supporting code for the "Join over Histograms" paper
--
-- Some simple examples of Frequency and Height-based Histograms
-- used in the paper for illustrating purposes.
--
-- (c) Alberto Dell'Era, March 2007
-- Tested in 10.2.0.3.

set echo on
set lines 150
set pages 9999

drop table t1;

spool fh_hb_simple_examples.lst

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

-- a Frequency histogram
create table t1 (value int);

insert into t1(value) select 1 from dual connect by level <= 2;
insert into t1(value) select 2 from dual connect by level <= 1;
insert into t1(value) select 3 from dual connect by level <= 4;

exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 254', estimate_percent=>100);

select value from t1 order by value;

select * from formatted_hist;

-- an Heigth-Based histogram with no popular values
drop table t1;
create table t1 as select rownum as value from dual connect by level <= 9;

exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 3', estimate_percent=>100);

select value from t1 order by value;

select * from formatted_hist;

-- an Heigth-Based histogram with popular values
update t1 set value = 9 where value >= 5;

exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 3', estimate_percent=>100);

select value from t1 order by value;

select * from formatted_hist;

-- different data that give the same Heigth-Based histogram with value "6" unpopular

drop table t1;
create table t1 as select rownum as value from dual connect by level <= 9;

exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 3', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

update t1 set value = 6 where value = 7;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 3', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

update t1 set value = 6 where value = 8;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 3', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

update t1 set value = 6 where value = 5;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 3', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

update t1 set value = 6 where value = 4;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 3', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

drop table t1;
create table t1 as select rownum as value from dual connect by level <= 9;
update t1 set value = 6 where value between 5 and 7;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 3', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

-- different data that give the same Heigth-Based histogram with value "9" popular
drop table t1;
create table t1 as select rownum as value from dual connect by level <= 12;

update t1 set value = 9 where value between 6 and 8;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 4', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

update t1 set value = 9 where value = 10;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 4', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

update t1 set value = 9 where value = 11;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 4', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

update t1 set value = 9 where value = 5;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 4', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

update t1 set value = 9 where value = 4;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 4', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

drop table t1;
create table t1 as select rownum as value from dual connect by level <= 12;

update t1 set value = 9 where value between 5 and 10;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 4', estimate_percent=>100);
select value from t1 order by value;
select * from formatted_hist;

spool off

