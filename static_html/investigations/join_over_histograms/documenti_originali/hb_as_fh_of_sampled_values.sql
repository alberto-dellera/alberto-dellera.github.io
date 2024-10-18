-- Supporting code for the "Join over Histograms" paper
--
-- Shows how an HB can be thought (is really) the Frequency Histogram
-- of the values sampled by the Height-Balanced histogram.
--
-- (c) Alberto Dell'Era, April 2007
-- Tested in 10.2.0.3.

set echo on
set lines 150
set pages 9999

drop table t1;
drop table t1_sampled;

spool hb_as_fh_of_sampled_values.lst

create table t1 as select rownum as value from dual connect by level <= 9;
update t1 set value = 9 where value >= 5;

exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 3', estimate_percent=>100);

select value from t1 order by value;

select endpoint_value as value,
       endpoint_number as ep
  from user_histograms
 where table_name = 'T1' and column_name = 'VALUE'
 order by endpoint_number;

-- create a table with the sampled values, minus the first 
create table t1_sampled (value number);
insert into t1_sampled (value) values (3);
insert into t1_sampled (value) values (9);
insert into t1_sampled (value) values (9);

exec dbms_stats.gather_table_stats (user, 't1_sampled', method_opt=>'for all columns size 254', estimate_percent=>100);

select endpoint_value as value,
       endpoint_number as ep
  from user_histograms
 where table_name = 'T1_SAMPLED' and column_name = 'VALUE'
union all
select 1 as value, 0 as ep from dual
 order by ep;

spool off

