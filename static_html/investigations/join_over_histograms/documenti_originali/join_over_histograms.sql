-- Supporting code for the "Join over Histograms" paper
--
-- The package that implements the formula for joins over histograms
-- is PL/SQL and SQL, reading directly from the data dictionary views
-- dba_histograms, dba_tab_columns, etc.
--
-- Primarily meant for helping research, but also very useful when diagnosing
-- the reasons for a bad cardinality estimate in real-life.
--
-- Notice that the package prints the four contributors on screen, and other
-- useful informations, when invoked with "set serveroutput on".
--
-- (c) Alberto Dell'Era, March 2007
-- Tested in 10.2.0.3, 9.2.0.8.
--
-- Necessary privileges:
-- create table, create view (and on some systems, analyze any) 
--  granted directly (not through roles)

set echo on
set lines 150
set pages 9999
set define on
set escape off
set serveroutput on size 1000000

spool join_over_histograms.lst

create or replace package join_over_histograms is

  -- computes the paper formula for the join over the table/columns set in the
  -- first 4 formal parameters. If p_install_also = 'Y', the default,
  -- it (re)installs the supporting objects (see method "install" below) transparently
  -- before computing. Leave the default at 'Y' for simple experiments.
  -- Example: select join_over_histograms.get ('t1', 'value', 't2', 'value') from dual;
  function get (
    p_lhs_table_name  varchar2,
    p_lhs_column_name varchar2,
    p_rhs_table_name  varchar2,
    p_rhs_column_name varchar2,
    p_install_also    varchar2 default 'Y'
  )
  return number; 

  -- same as "get", returns warnings also.
  function get_with_warn (
    p_lhs_table_name  varchar2,
    p_lhs_column_name varchar2,
    p_rhs_table_name  varchar2,
    p_rhs_column_name varchar2,
    p_warnings        out varchar2,
    p_install_also    varchar2 default 'Y'
  )
  return number;  
  
  -- installs the supporting objects (adapters for the data dictionary views,
  -- temp tables, join histograms calculators, etc).
  -- It needs to be called directly only if you wish to avoid the overhead
  -- of object creations - it is called implicitly by "get" if p_install_also = 'Y',
  -- the default. Useful only for repeated calls from the automatic formula validator.
  procedure install (
    p_lhs_table_name  varchar2,
    p_lhs_column_name varchar2,
    p_rhs_table_name  varchar2,
    p_rhs_column_name varchar2
  );
  
  -------------------------------------
  -- private interface (called by supporting objects internally)
  -------------------------------------
  function minMV  return number deterministic;
  function maxMV  return number deterministic;
  function minmax return number deterministic;
  function maxmax return number deterministic;
  function maxPV  return number deterministic;
  function min_density                return number deterministic;
  function rhs_num_rows_times_density return number deterministic;
  function lhs_num_rows_times_density return number deterministic;
  
  g_last_cbo_standard_8i    number;
  g_last_cbo_standard_9i10g number;
  
end join_over_histograms;
/
show errors;

create or replace package body join_over_histograms is

type t_simple_stats is record (
  num_rows     number,
  num_distinct number,
  low_value    raw(32),
  high_value   raw(32),
  num_buckets  number
);

g_minMV  number;
g_maxMV  number;
g_minmax number;
g_maxmax number;
g_maxPV  number;
g_min_density number;
g_rhs_num_rows_times_density number;
g_lhs_num_rows_times_density number;

function minMV  return number is begin return g_minMV ; end;
function maxMV  return number is begin return g_maxMV ; end;
function minmax return number is begin return g_minmax; end;
function maxmax return number is begin return g_maxmax; end;
function maxPV  return number is begin return g_maxPV ; end;
function min_density                return number is begin return g_min_density; end;
function rhs_num_rows_times_density return number is begin return g_rhs_num_rows_times_density; end;
function lhs_num_rows_times_density return number is begin return g_lhs_num_rows_times_density; end;

function cbo_standard (
  p_t1_num_rows     number,
  p_t2_num_rows     number,
  p_t1_num_distinct number,
  p_t2_num_distinct number,
  p_t1_min          raw,
  p_t1_max          raw,
  p_t2_min          raw,
  p_t2_max          raw,
  p_version         varchar2)
return number
is
  function overlapping_ranges (
    p_t1_min          raw,
    p_t1_max          raw,
    p_t2_min          raw,
    p_t2_max          raw
  )
  return boolean
  is
  begin
    if p_t1_min = p_t2_min then
      return true;
    end if;
    if p_t1_min > p_t2_min then
      return overlapping_ranges (p_t2_min, p_t2_max, p_t1_min, p_t1_max);
    end if; 
    return p_t1_max >= p_t2_min;
  end;
begin
 
  -- if cardinality of any table is zero => return 1
  if p_t1_num_rows * p_t2_num_rows = 0 then
    return 1;
  end if;
  
  -- 9i/10g version: detects non-overlapping ranges
  if lower (p_version) = '9i/10g' then
    if not overlapping_ranges (p_t1_min, p_t1_max, p_t2_min, p_t2_max) then
      return 1;
    end if;
  elsif lower (p_version) = '8i' then
    null;
  else 
    raise_application_error (-20002, 'cbo_standard(): wrong p_version='||p_version);
  end if;

  return p_t1_num_rows * p_t2_num_rows /
         greatest (p_t1_num_distinct, p_t2_num_distinct);

end cbo_standard;

-----------------------------------------------------------
procedure drop_table_idem (table_in varchar2)
is
  no_such_table exception;
  pragma exception_init (no_such_table, -942);
begin
  execute immediate 'drop table ' || table_in;
exception
  when no_such_table then
    null;
end drop_table_idem;

-----------------------------------------------------------
procedure install_for_table (
  p_table_name  varchar2,
  p_column_name varchar2,
  p_lhr_rhs     varchar2
)
is
  l_hist_table_name         varchar2(30) := 'joh_'||p_lhr_rhs||'_raw_hist';
  l_table_stats_table_name  varchar2(30) := 'joh_'||p_lhr_rhs||'_table_stats';
  l_column_stats_table_name varchar2(30) := 'joh_'||p_lhr_rhs||'_column_stats';
  l_hist_view_name          varchar2(30) := 'joh_'||p_lhr_rhs||'_hist';
begin
  drop_table_idem (l_hist_table_name);
  execute immediate 
    'create table '||l_hist_table_name||' as 
    select endpoint_number ep, endpoint_value value, endpoint_actual_value actual_value
      from user_histograms where 1=0';
      
  drop_table_idem (l_table_stats_table_name);    
  execute immediate 
    'create table '||l_table_stats_table_name||' as
     select num_rows from user_tables where 1=0';
     
  drop_table_idem (l_column_stats_table_name);
  execute immediate 
    'create table '||l_column_stats_table_name||' as
     select 0 num_rows, density, num_distinct, 0 max_ep, num_buckets, low_value, high_value from user_tab_columns where 1=0';   
     
  execute immediate 
    'create or replace view '||l_hist_view_name|| ' as
     with hist_ as (
       select ep, value, actual_value,
              lag (ep) over (order by ep) prev_ep,
              max (ep) over ()            max_ep
         from '||l_hist_table_name||'
     )
     select hist_.*,
              (select num_rows from '||l_table_stats_table_name||') 
            * (ep - nvl (prev_ep, 0)) 
            / max_ep as counts,
            decode (ep - nvl (prev_ep, 0), 0, 0, 1, 0, 1) as popularity
       from hist_'; 
 
  dbms_output.put_line ('supporting objects installed for '||p_lhr_rhs||': '||p_table_name||','||p_column_name);
end install_for_table;

-----------------------------------------------------------
procedure analyze_table (p_table_name varchar2)
is
begin
  return;
  
  dbms_stats.gather_table_stats (
    user, p_table_name,
    cascade          => true,
    method_opt       => 'for all columns size 1',
    estimate_percent => 100,
    no_invalidate    => false
  );
end analyze_table;

-----------------------------------------------------------
procedure dump_table_stats (
  p_table_name  varchar2,
  p_column_name varchar2,
  p_lhr_rhs     varchar2
)
is
  l_hist_table_name         varchar2(30) := 'joh_'||p_lhr_rhs||'_raw_hist';
  l_table_stats_table_name  varchar2(30) := 'joh_'||p_lhr_rhs||'_table_stats';
  l_column_stats_table_name varchar2(30) := 'joh_'||p_lhr_rhs||'_column_stats';
begin
  execute immediate 'delete from '||l_hist_table_name;
  execute immediate 'insert into '||l_hist_table_name||' (ep, value, actual_value)
    select endpoint_number ep, endpoint_value value, endpoint_actual_value actual_value
      from user_histograms where table_name = :1 and column_name = :2'
  using upper(p_table_name), upper(p_column_name);
  analyze_table (l_hist_table_name);
  
  execute immediate 'delete from '||l_table_stats_table_name;
  execute immediate 'insert into '||l_table_stats_table_name||' (num_rows)
  select num_rows from user_tables where table_name = :1'
  using upper(p_table_name);
  analyze_table (l_table_stats_table_name);
  
  execute immediate 'delete from '||l_column_stats_table_name;
  execute immediate 'insert into '||l_column_stats_table_name||' 
    (num_rows, density, num_distinct, max_ep, num_buckets, low_value, high_value)
  select (select num_rows from '||l_table_stats_table_name||'), 
         density, num_distinct, 
         (select max(ep) from '||l_hist_table_name||'), 
         num_buckets, low_value, high_value 
    from user_tab_columns where table_name = :1 and column_name = :2'
  using upper(p_table_name), upper(p_column_name);
  analyze_table (l_column_stats_table_name);
  
end dump_table_stats;

-----------------------------------------------------------
procedure install_for_join
is
begin
  ------------------------- scalars
  execute immediate 
    'create or replace view joh_scalars_xcols as
     select min(density) as min_density
       from (
     select density from joh_lhs_column_stats   
      union all
     select density from joh_rhs_column_stats
            )';

  execute immediate 
    'create or replace view joh_scalars_xMV as 
     select min (joh_lhs_raw_hist.value) minMV, max (joh_lhs_raw_hist.value) maxMV
       from joh_lhs_raw_hist, joh_rhs_raw_hist
      where joh_lhs_raw_hist.value = joh_rhs_raw_hist.value';

  execute immediate 
    'create or replace view joh_scalars_xHV as
     select min (value) as minmax, max (value) as maxmax
       from (
     select max (value) as value from joh_lhs_raw_hist
      union all
     select max (value) as value from joh_rhs_raw_hist
            )';
            
  ------------------------- join histograms
  execute immediate 
    'create or replace view joh_jh as
     with lhs_ as ( -- with subquery necessary for bug workaround
       select * from joh_lhs_hist
     ),   rhs_ as ( -- with subquery necessary for bug workaround
       select * from joh_rhs_hist
     )
     select nvl(lhs.value, rhs.value) as value,
            lhs.value             as lhs_value,
            rhs.value             as rhs_value,
            nvl(lhs.counts, 0)    as lhs_counts, 
            nvl(rhs.counts, 0)    as rhs_counts,
            nvl(lhs.popularity,0) as lhs_popularity,
            nvl(rhs.popularity,0) as rhs_popularity,
            nvl(lhs.popularity,0) + nvl(rhs.popularity,0) as join_popularity
       from lhs_ lhs 
            full outer join 
            rhs_ rhs 
         on lhs.value = rhs.value';
                
  execute immediate 
    'create or replace view joh_cjh /* chopped join histogram */ as 
     select joh_jh.*
       from joh_jh
      where value between join_over_histograms.minMV -- lowest MATCHING value 
                      and join_over_histograms.minmax -- lowest high value
    ';
    
  execute immediate 
    'create or replace view joh_cjh_plus_2 as
     with jh_numbered as (
      select jh.*, rownum jh_bucket_number
        from (
      select * 
        from joh_jh
       order by value
             ) jh
     )
     select *
       from jh_numbered 
      where value >= join_over_histograms.minMV
        and jh_bucket_number <= 2 + (select jh_bucket_number 
                                       from jh_numbered 
                                       where value = join_over_histograms.minmax
                                    )';
    
  execute immediate 
    'create or replace view joh_scalars_maxPV as                               
     select max (value) as maxPV
       from joh_cjh
      where join_popularity >= 1';
                                    
   ------------------------- cardinality components  
   execute immediate 
     'create or replace view joh_card_pop_2 as
      select nvl (sum (lhs_counts * rhs_counts), 0) as v
        from joh_cjh
       where join_popularity = 2';     

   execute immediate 
     'create or replace view joh_card_pop_1 as
      select nvl (
                sum (decode (lhs_popularity, 1, lhs_counts, join_over_histograms.lhs_num_rows_times_density)
                     *
                     decode (rhs_popularity, 1, rhs_counts, join_over_histograms.rhs_num_rows_times_density)
                    )
                 , 0
              ) as v
        from joh_cjh
       where join_popularity = 1';      

       /*
   execute immediate 
     'create or replace view joh_card_other as
      select case when num_rows_unpop_lhs = 0 
                  then num_rows_unpop_rhs / (select num_buckets from joh_lhs_column_stats)
                  when num_rows_unpop_rhs = 0 
                  then num_rows_unpop_lhs / (select num_buckets from joh_rhs_column_stats)
                  else num_rows_unpop_lhs * num_rows_unpop_rhs * join_over_histograms.min_density
             end as v
        from (
      select nvl( sum( decode (lhs_popularity, 1, 0, lhs_counts) ) , 0 ) as num_rows_unpop_lhs,
             nvl( sum( decode (rhs_popularity, 1, 0, rhs_counts) ) , 0 ) as num_rows_unpop_rhs
        from joh_cjh_plus_2
       where join_popularity < 2
         and value != join_over_histograms.minMV -- confirmed
            )';       
        */    
   execute immediate 
     'create or replace view joh_card_other as
      select decode (num_rows_unpop_lhs, 0, (select num_rows / max_ep from joh_lhs_column_stats), num_rows_unpop_lhs)
             *
             decode (num_rows_unpop_rhs, 0, (select num_rows / max_ep from joh_rhs_column_stats), num_rows_unpop_rhs)
             *
             join_over_histograms.min_density
             as v
        from (
      select nvl( sum( decode (lhs_popularity, 1, 0, lhs_counts) ) , 0 ) as num_rows_unpop_lhs,
             nvl( sum( decode (rhs_popularity, 1, 0, rhs_counts) ) , 0 ) as num_rows_unpop_rhs
        from joh_cjh_plus_2
       where join_popularity < 2
         and value != join_over_histograms.minMV -- confirmed
            )';         
            
   execute immediate 
     'create or replace view joh_card_special as 
      select case when join_over_histograms.maxMV  - join_over_histograms.minmax = 0 
                   and join_over_histograms.minmax - join_over_histograms.maxmax < 0
                  then decode ( (select lhs_value from joh_jh where value = join_over_histograms.maxmax),
                                 null,
                                 -- lhs is the "shorter" table
                                 (select case when lhs_popularity = 1 
                                         then lhs_counts * join_over_histograms.rhs_num_rows_times_density
                                         else 0
                                         end
                                    from joh_jh where value = join_over_histograms.minmax),
                                 -- rhs is the "shorter" table
                                 (select case when rhs_popularity = 1 
                                         then rhs_counts * join_over_histograms.lhs_num_rows_times_density
                                         else 0
                                         end
                                    from joh_jh where value = join_over_histograms.minmax)
                              )
                   else 0
             end as v
        from dual';          

  dbms_output.put_line ('supporting objects installed for join');
end install_for_join;

-----------------------------------------------------------
procedure install (
  p_lhs_table_name  varchar2,
  p_lhs_column_name varchar2,
  p_rhs_table_name  varchar2,
  p_rhs_column_name varchar2
)
is
begin
  install_for_table (p_lhs_table_name, p_lhs_column_name, 'lhs');
  install_for_table (p_rhs_table_name, p_rhs_column_name, 'rhs');
  install_for_join;
end install;

-----------------------------------------------------------
procedure set_scalars is
begin
  execute immediate 'select min_density    from joh_scalars_xcols' into g_min_density;
  execute immediate 'select minMV, maxMV   from joh_scalars_xMV'   into g_minMV , g_maxMV;
  execute immediate 'select minmax, maxmax from joh_scalars_xHV'   into g_minmax, g_maxmax;
  execute immediate 'select maxPV          from joh_scalars_maxPV' into g_maxPV;
  execute immediate 'select num_rows * density 
                     from joh_lhs_column_stats' into g_lhs_num_rows_times_density;
  execute immediate 'select num_rows * density 
                     from joh_rhs_column_stats' into g_rhs_num_rows_times_density;
end set_scalars;

-----------------------------------------------------------
procedure set_simple_stats (s out t_simple_stats, p_lhr_rhs varchar2)
is
  l_table_stats_table_name  varchar2(30) := 'joh_'||p_lhr_rhs||'_table_stats';
  l_column_stats_table_name varchar2(30) := 'joh_'||p_lhr_rhs||'_column_stats';
begin
  execute immediate 'select num_rows from '||l_table_stats_table_name into s.num_rows;
  execute immediate 'select num_distinct, low_value, high_value, num_buckets from '||l_column_stats_table_name
    into s.num_distinct, s.low_value, s.high_value, s.num_buckets;
end set_simple_stats;

-----------------------------------------------------------
function get_with_warn (
  p_lhs_table_name  varchar2,
  p_lhs_column_name varchar2,
  p_rhs_table_name  varchar2,
  p_rhs_column_name varchar2,
  p_warnings        out varchar2,
  p_install_also    varchar2 default 'Y'
)
return number
is
  lhs_ss t_simple_stats;
  rhs_ss t_simple_stats;
  l_cbo_standard_8i number;
  l_cbo_standard_9i10g number;
  l_card_pop_2   number;
  l_card_pop_1   number;
  l_card_other   number;
  l_card_special number;
  l_card_total   number;
begin
  dbms_application_info.set_module ('JOH','JOH');
  if upper (p_install_also) = 'Y' then
    install (p_lhs_table_name, p_lhs_column_name, p_rhs_table_name, p_rhs_column_name);
  end if;
  
  dump_table_stats (p_lhs_table_name, p_lhs_column_name, 'lhs');
  dump_table_stats (p_rhs_table_name, p_rhs_column_name, 'rhs');
  commit;
  set_simple_stats (lhs_ss, 'lhs');
  set_simple_stats (rhs_ss, 'rhs');
  set_scalars;
  
  dbms_output.put_line ('minMV='||minMV||' maxMV='||maxMV||' minmax='||minmax||' maxmax='||maxmax||' maxPV='||maxPV);
  
  l_cbo_standard_8i  := cbo_standard (lhs_ss.num_rows, rhs_ss.num_rows, lhs_ss.num_distinct, rhs_ss.num_distinct,
                                      lhs_ss.low_value, lhs_ss.high_value, rhs_ss.low_value, rhs_ss.high_value, '8i');
  g_last_cbo_standard_8i := l_cbo_standard_8i;

  l_cbo_standard_9i10g := cbo_standard (lhs_ss.num_rows, rhs_ss.num_rows, lhs_ss.num_distinct, rhs_ss.num_distinct,
                                        lhs_ss.low_value, lhs_ss.high_value, rhs_ss.low_value, rhs_ss.high_value, '9i/10g');
  g_last_cbo_standard_9i10g := l_cbo_standard_9i10g;
                         
  dbms_output.put_line ('standard formulae would be: 8i=' || round(l_cbo_standard_8i,1) || ' 9i10g=' || round(l_cbo_standard_9i10g,1));
  
  -- if any table has num_rows = num_distinct and no histogram =>
  -- back to standard formula of 9i/10g (with no-overlap detector)
  if    (lhs_ss.num_buckets <= 1 and (lhs_ss.num_rows = lhs_ss.num_distinct))
     or (rhs_ss.num_buckets <= 1 and (rhs_ss.num_rows = rhs_ss.num_distinct))  then
    dbms_output.put_line ('special case num_buckets <= 1 => back to standard formula of 9i/10g');
    return l_cbo_standard_9i10g;
  end if;
  
  -- if any table has num_rows <= 1 => 
  -- back to standard formula of 9i/10g (with no-overlap detector)
  if lhs_ss.num_rows <= 1 or rhs_ss.num_rows <= 1 then
    dbms_output.put_line ('special case num_rows <= 1 => back to standard formula of 9i/10g');
    return l_cbo_standard_9i10g;
  end if;

  -- if not exists a matching value less than a popular value =>
  -- back to standard formula of 8i (without no-overlap detector)
  if minMV is null or maxPV is null or minMV > maxPV then 
    dbms_output.put_line ('back to standard formula of 8i');
    return l_cbo_standard_8i;
  end if;
  
  -- calc formula contributions
  execute immediate 'select v from joh_card_pop_2  ' into l_card_pop_2;
  execute immediate 'select v from joh_card_pop_1  ' into l_card_pop_1;
  execute immediate 'select v from joh_card_other  ' into l_card_other;
  execute immediate 'select v from joh_card_special' into l_card_special;
  l_card_total := l_card_pop_2 + l_card_pop_1 + l_card_other + l_card_special;
  
  dbms_output.put_line ('CARD_POP_2  = '|| to_char (l_card_pop_2  , '99999999.00'));
  dbms_output.put_line ('CARD_POP_1  = '|| to_char (l_card_pop_1  , '99999999.00'));
  dbms_output.put_line ('CARD_OTHER  = '|| to_char (l_card_other  , '99999999.00'));
  dbms_output.put_line ('CARD_SPECIAL= '|| to_char (l_card_special, '99999999.00'));
  dbms_output.put_line ('------------------------');
  dbms_output.put_line ('TOTAL ------->'|| to_char (l_card_total, '99999999.00'));
  
  -- special case: if standard formula predicts zero cardinality =>
  -- back to standard formula of 8i (without no-overlap detector)
  if l_card_total < 0.001 then
    dbms_output.put_line ('predicted card = 0 => back to standard formula of 8i');
    return l_cbo_standard_8i;
  end if;
  
  return l_card_total;
end get_with_warn;  

-----------------------------------------------------------
function get (
  p_lhs_table_name  varchar2,
  p_lhs_column_name varchar2,
  p_rhs_table_name  varchar2,
  p_rhs_column_name varchar2,
  p_install_also    varchar2 default 'Y'
)
return number
is
  pragma autonomous_transaction;
  l_ret number;
  l_warn varchar2 (300 char);
begin
  l_ret := get_with_warn (p_lhs_table_name, p_lhs_column_name, 
                          p_rhs_table_name, p_rhs_column_name, l_warn, p_install_also);
  dbms_output.put_line (l_warn);
  return l_ret;
end get;
  
end join_over_histograms;
/
show errors;


-- installation sanity check
/*

-- workaround for bug 4626732, 5752903 "ORA-07445 [ACCESS_VIOLATION] [_evaopn2+153]"
alter session set "_optimizer_native_full_outer_join"=force;

-- install start

drop table lhs;
drop table rhs;
create table lhs (x number);
create table rhs (x number);
exec join_over_histograms.install ('lhs', 'x', 'rhs', 'x');
drop table lhs_h;
drop table rhs_h; 
create table lhs_h (x number, diff_ep int);
create table rhs_h (x number, diff_ep int);
exec set_histo.install ('lhs', 'lhs_h');
exec set_histo.install ('rhs', 'rhs_h');

-- install end

col actual_value form a20
col  low_value   form a20
col high_value   form a20
col card new_value card
col cbo_card new_value cbo_card
set verify off
set feedback off

delete from lhs_h;
insert into lhs_h (x, diff_ep) values (0  , 2);
insert into lhs_h (x, diff_ep) values (1  , 1);
insert into lhs_h (x, diff_ep) values (2  , 1);
insert into lhs_h (x, diff_ep) values (3  , 1);
insert into lhs_h (x, diff_ep) values (1000, 4);

delete from rhs_h;
insert into rhs_h (x, diff_ep) values (0  , 2);
insert into rhs_h (x, diff_ep) values (1  , 1);
insert into rhs_h (x, diff_ep) values (2  , 1);
insert into rhs_h (x, diff_ep) values (3  , 1);
insert into rhs_h (x, diff_ep) values (10  , 1);
insert into rhs_h (x, diff_ep) values (20 , 1);
insert into rhs_h (x, diff_ep) values (1000, 2);


--exec set_histo.set ('lhs', 'lhs_h', 10, 3.2, 'N');
--exec set_histo.set ('rhs', 'rhs_h', 0, 3.61, 'N');
exec set_histo.set ('lhs', 'lhs_h', 10, 0.99, 'N');
exec set_histo.set ('rhs', 'rhs_h', 10, 1, 'N');

select join_over_histograms.get ('lhs', 'x', 'rhs', 'x', 'N') card, 
       cbo_cardinality.get ('lhs', 'x', 'rhs', 'x') cbo_card,
       (join_over_histograms.get ('lhs', 'x', 'rhs', 'x', 'N') -  cbo_cardinality.get ('lhs', 'x', 'rhs', 'x')) diff from dual;

select * from joh_lhs_column_stats;
select * from joh_rhs_column_stats;
select * from joh_lhs_hist order by value;
select * from joh_rhs_hist order by value;
select * from joh_jh order by value;

*/

spool off
