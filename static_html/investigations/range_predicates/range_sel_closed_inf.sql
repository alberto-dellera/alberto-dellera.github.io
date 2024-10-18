
drop table t;

create table t as select 10 * mod (rownum-1, 2) x from dual connect by level <= 2000000;

exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);

select x, count(*) from t group by x;

drop table pdf_calc_closed_results;

create table pdf_calc_closed_results (
  low_x        number constraint pdf_calc_closed_results_pk primary key,
  card         number,
  card_diff    number,
  card_stnd_f  number
);

create or replace procedure pdf_calculator_closed (
  p_interval_width  number,
  p_start           number,
  p_stop            number,
  p_num_samples     int)
is
  l_num_rows         number;
  l_num_distinct     number;
  l_table_low        t.x%type;
  l_table_high       t.x%type;
  l_low_x            t.x%type;
  l_our_min          t.x%type;
  l_our_max          t.x%type;
  l_cardinality      number;
  l_cardinality_prev number;
  l_card_stnd_f      number;
begin
  delete from  pdf_calc_closed_results;
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
     
  select num_distinct
    into l_num_distinct
    from user_tab_columns
   where table_name = 'T'
     and column_name = 'X';
    
  for i in 0..p_num_samples-1 loop
    l_low_x := p_start + i/(p_num_samples-1) * (p_stop-p_start);
    
    l_our_min := l_low_x;
    l_our_max := l_low_x + p_interval_width;
    
    delete from plan_table;
    execute immediate 'explain plan for '
     || 'select x from t'
     || ' where x >= '|| l_our_min
     || '   and x <= '|| l_our_max;
     
     
    select cardinality
      into l_cardinality
      from plan_table
     where operation = 'SELECT STATEMENT';
    
    l_card_stnd_f := l_num_rows * (l_our_max-l_our_min) / (l_table_high - l_table_low)
                   + 2 * l_num_rows / l_num_distinct;
    
    insert into pdf_calc_closed_results (low_x, card, card_stnd_f, card_diff)
        values (l_low_x, l_cardinality, l_card_stnd_f, l_cardinality - l_cardinality_prev);
    l_cardinality_prev := l_cardinality;
  end loop;  
  commit;
end pdf_calculator_closed;
/
show errors;

exec pdf_calculator_closed (0.001, 0.1, 9.9-0.001, 101);
col low_x form 99.999999 
set echo off
set feedback off
spool range_sel_closed_inf_02_data.dat
select * from pdf_calc_closed_results order by low_x;
spool off


-- add a third distinct value
insert /*+ append */ into t(x) select 6.1 from dual connect by level <= 1000000;
commit;

exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);
exec pdf_calculator_closed (0.001, 0.1, 9.9-0.001, 101);
col low_x form 99.999999 
set echo off
set feedback off
spool range_sel_closed_inf_03_data.dat
select * from pdf_calc_closed_results order by low_x;
spool off

-- add a fourth distinct value
insert /*+ append */ into t(x) select 7.42 from dual connect by level <= 1000000;
commit;

exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);
exec pdf_calculator_closed (0.001, 0.1, 9.9-0.001, 101);
col low_x form 99.999999 
set echo off
set feedback off
spool range_sel_closed_inf_04_data.dat
select * from pdf_calc_closed_results order by low_x;
spool off

set autotrace traceonly explain 
select x from t where x >= 2 - 0.001 and x <= 2;
select x from t where x >= 2 - 2     and x <= 2;
select x from t where x >= 0 and x <= 2.123;
select x from t where x >= 2 and x <= 2.123;
set autotrace off




