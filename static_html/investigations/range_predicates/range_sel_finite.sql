drop table t;

create table t as select 10 * mod (rownum-1, 2) x from dual connect by level <= 2000000;

exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);

select x, count(*) from t group by x;

drop table cdf_calculator_results;

create table cdf_calculator_results (
  low_x        number,
  high_x       number constraint cdf_calculator_results_pk primary key,
  card         number,
  card_diff    number,
  card_stnd_f  number
);

create or replace procedure cdf_calculator (
  p_start           number,
  p_stop            number,
  p_num_samples     int)
is
  l_num_rows         number;
  l_table_low        t.x%type;
  l_table_high       t.x%type;
  l_low_x            t.x%type;
  l_high_x           t.x%type;
  l_our_min          t.x%type;
  l_our_max          t.x%type;
  l_cardinality      number;
  l_cardinality_prev number;
  l_card_stnd_f      number;
begin
  delete from  cdf_calculator_results;
  commit;
  
  select num_rows
    into l_num_rows
    from user_tables
   where table_name = 'T';
   
  select min (endpoint_value), max (endpoint_value)
    into l_table_low, l_table_high
    from user_tab_histograms
   where table_name = 'T'
     and column_name = 'X';
    
  for i in 1..p_num_samples loop
    l_low_x  := p_start;
    l_high_x := p_start + i/p_num_samples * (p_stop-p_start);
    
    l_our_min := l_low_x;
    l_our_max := l_high_x;
    
    delete from plan_table;
    execute immediate 'explain plan for '
     || 'select x from t'
     || ' where x > '|| l_low_x
     || '   and x < '|| l_high_x;
  
    select cardinality
      into l_cardinality
      from plan_table
     where operation = 'SELECT STATEMENT';
    
    l_card_stnd_f := l_num_rows * (l_our_max-l_our_min) / (l_table_high - l_table_low);
    
    insert into cdf_calculator_results (low_x, high_x, card, card_stnd_f, card_diff)
        values (l_low_x, l_high_x, l_cardinality, l_card_stnd_f, l_cardinality - l_cardinality_prev);
    l_cardinality_prev := l_cardinality;
  end loop;  
  commit;
end cdf_calculator;
/
show errors;

exec cdf_calculator (0.1, 9.9, 100);

col low_x  form 99.999999 
col high_x form 99.999999 
set echo off
set feedback off
spool range_sel_finite_02_data.dat
select * from cdf_calculator_results order by low_x, high_x;
spool off

-- add a third distinct value
insert /*+ append */ into t(x) select 6.1 from dual connect by level <= 1000000;
commit;

exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);

exec cdf_calculator (0.1, 9.9, 100);
col low_x  form 99.999999 
col high_x form 99.999999 
set echo off
set feedback off
spool range_sel_finite_03_data.dat
select * from cdf_calculator_results order by low_x, high_x;
spool off

-- add a fourth distinct value
insert /*+ append */ into t(x) select 7.42 from dual connect by level <= 1000000;
commit;
exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);

exec cdf_calculator (0.1, 9.9, 100);
col low_x  form 99.999999 
col high_x form 99.999999 
set echo off
set feedback off
spool range_sel_finite_04_data.dat
select * from cdf_calculator_results order by low_x, high_x;
spool off

set echo on
set autotrace traceonly explain
select x from t where x > 0.1 and x < 7;
select x from t where x > 0.1 and x < 2.5;
select x from t where x > 2.5 and x < 7;
set autotrace off

set echo on
set autotrace traceonly explain
select x from t where x > 0.1 and x < 9;
select x from t where x > 0.1 and x < 2.5;
select x from t where x > 2.5 and x < 7.5;
select x from t where x > 7.5 and x < 9;
set autotrace off

set echo on
set autotrace traceonly explain
select x from t where x > 0 and x < 1;
select x from t where x > 0 and x < 2.5;
select x from t where x > 0 and x < 3;
select x from t where x > 0 and x < 7.5;
select x from t where x > 0 and x < 9;
select x from t where x > 0 and x < 10;
set autotrace off

