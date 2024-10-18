-- Supporting code for the "Join over Histograms" paper
--
-- The package that sets the histogram taking the desired values
-- from a table.
--
-- (c) Alberto Dell'Era, March 2007
-- Tested in 10.2.0.3.

set echo on
set lines 150
set pages 9999
set define on
set escape off
set serveroutput on size 1000000

spool set_histo.lst

create or replace package set_histo is

  -- sets the histogram (and other statistics) for the table p_table_name
  -- using dbms_stats.set_column_stats, dbms_stats.prepare_column_stats, dbms_stats.set_table_stats.
  -- The name of the column you want to set the statistics for, and the 
  -- histogram, are taken from p_hist_table, that has to have the following definition
  --   create table <histogram table name> (<column name> <column_type, diff_ep int).
  --   <column name> must be the same as the column of p_table_name you want to set the statistics for;
  --   diff_ep is the difference in the endpoint_number you want to set.
  -- p_num_rows_per_bkt is the desired number of rows per unpopular bucket for an Height-Based Histogram; 
  -- pass 0 to set a Frequency Histograms. num_rows is set accordingly.
  -- p_density is the density you want to set; pass null to let dbms_stats calculate the
  -- default density.   
  -- num_distinct is always set to the maximum compatible with the statistic (it doesn't affect
  -- the join cardinality formula anyway, unless a fallback to the stanndard formula happens).
  -- Note: only some types for <column name> are currently supported.
  
  procedure set (
    p_table_name        varchar2,
    p_hist_table        varchar2,
    p_num_rows_per_bkt  number,
    p_density           number,
    p_install_also      varchar2 default 'Y'
  );
  
  -- installs the supporting objects.
  -- It needs to be called directly only if you wish to avoid the overhead
  -- of object creations - it is called implicitly by "set" if p_install_also = 'Y',
  -- the default. Useful only for repeated calls from the automatic formula validator
  procedure install (
    p_table_name        varchar2,
    p_hist_table        varchar2
  );
  
end set_histo;
/
show errors;

create or replace package body set_histo is

procedure install (
  p_table_name        varchar2,
  p_hist_table        varchar2
)
is
  l_column_name varchar2(30);
  l_data_type   varchar2(30);
begin
  select column_name, data_type 
    into l_column_name, l_data_type
    from user_tab_columns
   where table_name = upper (p_hist_table)
     and column_name != 'DIFF_EP';
     
  execute immediate 
   'create or replace view '||p_hist_table||'_wanted as
    select x as actual_value, diff_ep, sum (diff_ep) over (order by '||l_column_name||') as ep
      from '||p_hist_table||'
    order by actual_value';  
    
  execute immediate 
   'create or replace view '||p_hist_table||'_wanted_nocompr_hb as
    select h.'||l_column_name||' as actual_value
      from '||p_hist_table||' h, (select rownum i from dual connect by level <= 256) s
     where h.diff_ep >= s.i 
     union all
    select min('||l_column_name||') 
      from '||p_hist_table||' h
     order by actual_value';
     
   execute immediate 
   'create or replace view '||p_hist_table||'_wanted_nocompr_fh as
    select h.'||l_column_name||' as actual_value,  h.diff_ep 
      from '||p_hist_table||' h
     union all
    select min('||l_column_name||'), 0 
      from '||p_hist_table||' h
     order by actual_value';  
     
   execute immediate 
   'create or replace view '||p_hist_table||'_final_hist as
    with x as (
    select endpoint_value value, endpoint_number ep, endpoint_actual_value,
           endpoint_number - nvl (lag (endpoint_number) over (order by endpoint_number), 0) as diff_ep,
           max (endpoint_number) over() as max_ep
      from user_tab_histograms 
     where table_name = '''||upper(p_table_name)||'''
       and column_name = '''||l_column_name||'''
    )
    select value, ep, diff_ep, endpoint_actual_value,
           decode (diff_ep, 1, cast(null as varchar2(7 char)), 0, ''-'', ''POPULAR'') as popularity,
           diff_ep
           * (select num_rows from user_tables  where table_name = '''||upper(p_table_name)||''')
           / max_ep as counts,
           diff_ep
           * (select num_rows from user_tables  where table_name = '''||upper(p_table_name)||''')
           / (max_ep - 1) as counts2
      from x
    ';   
  dbms_output.put_line ('supporting objects installed for '||p_table_name||','||p_hist_table||'.');
end install;

-- set histogram on table
-- if p_num_rows_per_bkt = 0, computes a frequency histogram
procedure set (
  p_table_name        varchar2,
  p_hist_table        varchar2,
  p_num_rows_per_bkt  number,
  p_density           number,
  p_install_also      varchar2 default 'Y'
)
is
  l_histogram_type varchar2 (20 char);
  l_density number;
  l_avg_col_length number;
  l_max_ep int;
  l_num_diff_ep int;
  l_num_rows int;
  l_num_distinct int;
  l_num_unpopulars int;
  l_actual_values_number   dbms_stats.numarray;
  l_actual_values_varchar2 dbms_stats.chararray;
  l_bucket_counts          dbms_stats.numarray;
  l_srec          dbms_stats.StatRec;
  l_stmt varchar2(1000);
  l_count int;
  l_column_name varchar2(30);
  l_data_type   varchar2(30);
begin
  if p_num_rows_per_bkt = 0 then
    l_histogram_type := 'FREQUENCY';
  else
    l_histogram_type := 'HEIGHT-BALANCED';
  end if;
  
  select column_name, data_type 
    into l_column_name, l_data_type
    from user_tab_columns
   where table_name = upper (p_hist_table)
     and column_name != 'DIFF_EP';
     
  dbms_output.put_line (upper(p_table_name)||'.'||l_column_name||': setting a '||l_histogram_type||' histogram from '
                        ||p_hist_table||'.');   
  
  if upper(p_install_also) = 'Y' then
    install (p_table_name, p_hist_table);
  end if;
  
  execute immediate
  'select 1+avg(length('||l_column_name||')), 
          sum(diff_ep) as max_ep,
          count(*)     as num_diff_ep,
          sum (case when diff_ep = 1 then 1 else 0 end) as num_unpopulars
    from '||p_hist_table
    into l_avg_col_length, l_max_ep, l_num_diff_ep, l_num_unpopulars;
 
  if l_histogram_type = 'HEIGHT-BALANCED' then
    l_num_rows := 0 + p_num_rows_per_bkt * l_max_ep;
  else
    l_num_rows := l_max_ep;
  end if;
  
  dbms_output.put_line ('num_rows='||l_num_rows);
  dbms_stats.set_table_stats (
     ownname       => user, 
     tabname       => p_table_name,
     numrows       => l_num_rows,
     numblks       => greatest (trunc(l_num_rows / 10), 1), -- n/a for card
     avgrlen       => l_avg_col_length,
     no_invalidate => false
  );
  
  if l_histogram_type = 'HEIGHT-BALANCED' then
    -- assume the max number of distinct values possible
    l_num_distinct := l_num_diff_ep + l_num_unpopulars * (p_num_rows_per_bkt-1);
  else
    l_num_distinct := l_num_diff_ep;
  end if;
  
  if l_num_distinct = 0 then
    l_num_distinct := 1;
  end if;
  
  if p_density is not null then
    l_density := p_density;
  else
    if l_histogram_type = 'HEIGHT-BALANCED' then
      l_density := null;
    else
      l_density := 1 / (2 * l_num_rows);
    end if;
  end if;
  
  -- prepare endpoint array
  if l_histogram_type = 'HEIGHT-BALANCED' then   

    l_stmt := 'select actual_value
                 from '||p_hist_table||'_wanted_nocompr_hb
                order by actual_value';         
            
    if l_data_type = 'NUMBER' then             
      execute immediate l_stmt bulk collect into l_actual_values_number;
      l_srec.epc := l_actual_values_number.count;
      dbms_stats.prepare_column_values (l_srec, l_actual_values_number);
    elsif l_data_type = 'VARCHAR2' then
      execute immediate l_stmt bulk collect into l_actual_values_varchar2;
      l_srec.epc := l_actual_values_varchar2.count;
      dbms_stats.prepare_column_values (l_srec, l_actual_values_varchar2);
    end if;
    
  else -- FREQUENCY
   
    l_stmt := 'select actual_value, diff_ep
                 from '||p_hist_table||'_wanted_nocompr_fh
                order by actual_value, diff_ep'; -- diff_ep=0 is the min value
                
    if l_data_type = 'NUMBER' then             
      execute immediate l_stmt bulk collect into l_actual_values_number, l_bucket_counts;
      l_srec.epc    := l_actual_values_number.count;
      l_srec.bkvals := l_bucket_counts;
      dbms_stats.prepare_column_values (l_srec, l_actual_values_number);
    elsif l_data_type = 'VARCHAR2' then
      execute immediate l_stmt bulk collect into l_actual_values_varchar2, l_bucket_counts;
      l_srec.epc    := l_actual_values_varchar2.count;
      l_srec.bkvals := l_bucket_counts;
      dbms_stats.prepare_column_values (l_srec, l_actual_values_varchar2);
    end if;            
  
  end if;
  
  if l_data_type = 'NUMBER' then 
    dbms_output.put_line ( 'minval='||utl_raw.cast_to_number(l_srec.minval) );
    dbms_output.put_line ( 'maxval='||utl_raw.cast_to_number(l_srec.maxval) );
  elsif l_data_type = 'VARCHAR2' then
    dbms_output.put_line ( 'minval='||utl_raw.cast_to_varchar2(l_srec.minval) );
    dbms_output.put_line ( 'maxval='||utl_raw.cast_to_varchar2(l_srec.maxval) );
  else
    dbms_output.put_line ( 'minval='||l_srec.minval );
    dbms_output.put_line ( 'maxval='||l_srec.maxval );
  end if;
  dbms_output.put_line ( 'epc='||l_srec.epc );
  dbms_output.put_line ( 'eavs='||l_srec.eavs );
  dbms_output.put_line ( 'bkvals=');
  for i in l_srec.bkvals.first .. l_srec.bkvals.last loop
    dbms_output.put_line ( l_srec.bkvals (i) );
  end loop;
  dbms_output.put_line ( 'novals=');
  for i in l_srec.novals.first .. l_srec.novals.last loop
    dbms_output.put_line ( l_srec.novals (i) );
  end loop;
  dbms_output.put_line ( 'chvals=');
  for i in l_srec.chvals.first .. l_srec.chvals.last loop
    dbms_output.put_line ( l_srec.chvals (i) );
  end loop;
  dbms_output.put_line ( 'num_distinct='||l_num_distinct);
  dbms_output.put_line ( 'density='||l_density);
  
  dbms_stats.set_column_stats (
    ownname => user,
    tabname => p_table_name,
    colname => l_column_name,
    distcnt => l_num_distinct,
    density => l_density,
    nullcnt => 0,
    srec    => l_srec,
    avgclen => l_avg_col_length,
    no_invalidate => false
  );
  
  -- some sanity checks on the set histogram
  execute immediate 'select count(*) from (select ep from '||p_hist_table||'_final_hist minus select ep from '||p_hist_table||'_wanted)'
     into l_count;
  if l_count > 0 then
    raise_application_error (-20001, 'wrong histogram set - 1');
  end if;
  execute immediate 'select count(*) from (select ep from '||p_hist_table||'_wanted  minus select ep from '||p_hist_table||'_final_hist)'
     into l_count;
  if l_count > 0 then
    raise_application_error (-20002, 'wrong histogram set - 2');
  end if;
 
end set;
  
end set_histo;
/
show errors;

-- installation sanity check

/* 

drop table hb_t1;
drop table t1;
drop table hb_t2;
drop table t2;

define data_type=varchar2(20)
define data_type=number

create table t1 (x &data_type.);
create table t2 (x &data_type.);

create table hb_t1 (x &data_type. not null, diff_ep int not null);
insert into hb_t1 (x,  diff_ep) values (0  ,  1);
--insert into hb_t1 (x,  diff_ep) values (10,  1);
--insert into hb_t1 (x,  diff_ep) values (20,  1);
--insert into hb_t1 (x,  diff_ep) values (30,  1);
--insert into hb_t1 (x,  diff_ep) values (40,  1);
--insert into hb_t1 (x,  diff_ep) values (50,  1);
--insert into hb_t1 (x,  diff_ep) values (60,  1);
--insert into hb_t1 (x,  diff_ep) values (70,  1);
--insert into hb_t1 (x,  diff_ep) values (80,  1);
--insert into hb_t1 (x,  diff_ep) values (90,  1);
--insert into hb_t1 (x,  diff_ep) values (100,  1);
insert into hb_t1 (x,  diff_ep) values (9999, 10);
insert into hb_t1 (x,  diff_ep) values (10000, 1);
insert into hb_t1 (x,  diff_ep) values (10001, 1);
--insert into hb_t1 (x,  diff_ep) values (10002, 1);
--insert into hb_t1 (x,  diff_ep) values (10003, 1);
--insert into hb_t1 (x,  diff_ep) values (10004, 1);
--insert into hb_t1 (x,  diff_ep) values (10005, 1);
--insert into hb_t1 (x,  diff_ep) values (10006, 1);
--insert into hb_t1 (x,  diff_ep) values (10007, 1);
--update hb_t1 set diff_ep =diff_ep * 100;
update hb_t1 set x = lpad (x, 20, '0');
commit;

create table hb_t2 (x &data_type. not null, diff_ep int not null);
insert into hb_t2 (x,  diff_ep) values (0 ,  1);
--insert into hb_t2 (x,  diff_ep) values (10,  1);
--insert into hb_t2 (x,  diff_ep) values (20,  6);
--insert into hb_t2 (x,  diff_ep) values (30.8,  2);
--insert into hb_t2 (x,  diff_ep) values (40,  1);
--insert into hb_t2 (x,  diff_ep) values (50.8,  1);
--insert into hb_t2 (x,  diff_ep) values (60.8,  1);
--insert into hb_t2 (x,  diff_ep) values (70.5,  1);
--insert into hb_t2 (x,  diff_ep) values (80,  1);
--insert into hb_t2 (x,  diff_ep) values (90,  1);
--insert into hb_t2 (x,  diff_ep) values (100,  1);
insert into hb_t2 (x,  diff_ep) values (9999, 15);
insert into hb_t2 (x,  diff_ep) values (10000, 3);
insert into hb_t2 (x,  diff_ep) values (10001, 1);
--insert into hb_t2 (x,  diff_ep) values (10002, 1);
--insert into hb_t2 (x,  diff_ep) values (10003, 1);
--insert into hb_t2 (x,  diff_ep) values (10004, 1);
--insert into hb_t2 (x,  diff_ep) values (10005, 1);
--insert into hb_t2 (x,  diff_ep) values (10006, 1);
update hb_t2 set x = lpad (x, 20, '0');
commit;

select * from  hb_t1 order by x;

exec set_histo.set ('t1', 'hb_t1', 0, 0.03846153);
exec set_histo.set ('t2', 'hb_t2', 10, 1);

col endpoint_actual_value form a20
col lv form a20
col hv form a20

select num_rows from user_tables where table_name = 'T1';
select num_distinct, density, num_buckets, histogram, utl_raw.cast_to_varchar2(low_value) lv, utl_raw.cast_to_varchar2(high_value) hv from user_tab_columns where table_name = 'T1';
select * from hb_t1_final_hist;

select num_rows from user_tables where table_name = 'T2';
select num_distinct, density, num_buckets, histogram, utl_raw.cast_to_varchar2(low_value) lv, utl_raw.cast_to_varchar2(high_value) hv from user_tab_columns where table_name = 'T2';
select * from hb_t2_final_hist;

set autotrace traceonly explain
select count(*)
  from t1 a, t2 b
 where a.x = b.x;
set autotrace off

*/

spool off


