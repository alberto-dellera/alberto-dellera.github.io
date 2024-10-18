drop table t;

create table t as select 10 * mod (rownum-1, 2) x from dual connect by level <= 2000000;

-- add a third distinct value
insert /*+ append */ into t(x) select 6.1 from dual connect by level <= 1000000;
commit;

-- add a fourth distinct value
insert /*+ append */ into t(x) select 7.42 from dual connect by level <= 1000000;
commit;

exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);

set autotrace traceonly explain
-- selection around min_x
select x from t where x >  0 - 1e-6 and x <  0 + 1e-6;
select x from t where x >= 0 - 1e-6 and x <  0 + 1e-6;
select x from t where x >= 0 - 1e-6 and x <= 0 + 1e-6;
select x from t where x >  0 - 1e-6 and x <= 0 + 1e-6;

-- selection near min_x, inside the min_x <--> max_x
select x from t where x >  0 + 1e-6 and x <  0 + 1e-6 + 1e-9;
select x from t where x >= 0 + 1e-6 and x <  0 + 1e-6 + 1e-9;
select x from t where x >= 0 + 1e-6 and x <= 0 + 1e-6 + 1e-9;
select x from t where x >  0 + 1e-6 and x <= 0 + 1e-6 + 1e-9;

-- selection near min_x, outside the min_x <--> max_x
select x from t where x >  0 - 1e-6 - 1e-9 and x <  0 - 1e-6;
select x from t where x >= 0 - 1e-6 - 1e-9 and x <  0 - 1e-6;
select x from t where x >= 0 - 1e-6 - 1e-9 and x <= 0 - 1e-6;
select x from t where x >  0 - 1e-6 - 1e-9 and x <= 0 - 1e-6;
set autotrace off


drop table pdf_calc_spec_results;

create table pdf_calc_spec_results (
  low_x        number constraint pdf_calc_spec_results_pk primary key,
  card         number,
  card_diff    number
);

create or replace procedure pdf_calc_spec (
  p_interval_width  number,
  p_start           number,
  p_stop            number,
  p_num_samples     int,
  p_low#            varchar2,
  p_high#           varchar2)
is
  l_num_rows         number;
  l_table_low        t.x%type;
  l_table_high       t.x%type;
  l_low_x            t.x%type;
  l_our_min          t.x%type;
  l_our_max          t.x%type;
  l_cardinality      number;
  l_cardinality_prev number;
begin
  delete from  pdf_calc_spec_results;
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
    
  for i in 0..p_num_samples-1 loop
    l_low_x := p_start + i/(p_num_samples-1) * (p_stop-p_start);
    
    l_our_min := l_low_x;
    l_our_max := l_low_x + p_interval_width;
    
    delete from plan_table;
    execute immediate 'explain plan for '
     || 'select x from t'
     || ' where x ' || p_low#  || ' ' || l_our_min
     || '   and x ' || p_high# || ' ' || l_our_max;
     
     
    select cardinality
      into l_cardinality
      from plan_table
     where operation = 'SELECT STATEMENT';
    
    
    insert into pdf_calc_spec_results (low_x, card, card_diff)
        values (l_low_x, l_cardinality, l_cardinality - l_cardinality_prev);
    l_cardinality_prev := l_cardinality;
  end loop;  
  commit;
end pdf_calc_spec;
/
show errors;

exec pdf_calc_spec (0.001, -11, +21, 101, '>', '<');
col low_x form 99.999999 
set echo off
set feedback off
spool range_sel_speculation_open_open_data.dat
select * from pdf_calc_spec_results order by low_x;
spool off

exec pdf_calc_spec (0.001, -11, +21, 101, '>=', '<');
col low_x form 99.999999 
set echo off
set feedback off
spool range_sel_speculation_closed_open_data.dat
select * from pdf_calc_spec_results order by low_x;
spool off

exec pdf_calc_spec (0.001, -11, +21, 101, '>=', '<=');
col low_x form 99.999999 
set echo off
set feedback off
spool range_sel_speculation_closed_closed_data.dat
select * from pdf_calc_spec_results order by low_x;
spool off

exec pdf_calc_spec (0.001, -11, +21, 101, '>', '<=');
col low_x form 99.999999 
set echo off
set feedback off
spool range_sel_speculation_open_closed_data.dat
select * from pdf_calc_spec_results order by low_x;
spool off