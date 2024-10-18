--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Exhaustive check of the "Selection Without Replacement" formula
--    for the join case, single-column.
--    Alberto Dell'Era, August 2007
--    tested in 10.2.0.3, 9.2.0.8

start setenv.sql
start distinctBallsPlSql.sql
set timing off

exec dbms_random.seed(0)

exec execute immediate 'purge recyclebin'; exception when others then null;

spool join_exhaustive_single_column.lst

-- end of initialization section

set echo on

drop table results;
create table results (
  num_rows_t1          int    not null,
  num_rows_t2          int    not null,
  num_distinct_t1_x    int    not null,
  num_distinct_t2_x    int    not null,
  f_num_rows_t1        number not null,
  f_num_rows_t2        number not null,
  f_num_distinct_t1_x  number not null,  
  f_num_distinct_t1_2  number not null,
  cbo_card             number not null, 
  frm_card             number not null,
  sel                  number not null
);

drop table t1;
drop table t2;

purge recyclebin;

-- max 250
define num_rows_t1=100
-- max 250
define num_rows_t2=100

create table t1 as
select 100000 x, rownum filter from dual connect by level <= &num_rows_t1. ;

create table t2 as
select 100000 x, rownum filter from dual connect by level <= &num_rows_t2. ;

-- create index t1_x_filter_idx on t1(x, filter);
-- create index t1_filter_x_idx on t1(filter, x);
  
-- collect baseline stats, build an histogram on the "filter" column
exec dbms_stats.gather_table_stats (user, 't1', cascade=>true, method_opt => 'for columns x size 1, columns filter size 254', estimate_percent=>100);
exec dbms_stats.gather_table_stats (user, 't2', cascade=>true, method_opt => 'for columns x size 1, columns filter size 254', estimate_percent=>100);

drop sequence get_cbo_card_seq;
create sequence get_cbo_card_seq;

alter system flush shared_pool;

-- this procedure parses the statement, and fetches the relevant CBO cardinality
-- estimates from v$sql_plan
create or replace procedure get_cbo_card (
  p_desired_f_num_rows_t1 number, 
  p_desired_f_num_rows_t2 number,
  p_cbo_card              out number,
  p_f_num_rows_t1         out number,
  p_f_num_rows_t2         out number
)
is
  l_stmt long;
  l_cursor sys_refcursor;
  l_seq_val int;
  l_address      v$sql.address%type; 
  l_hash_value   v$sql.hash_value%type;  
  l_child_number v$sql.child_number%type;
  l_filter_pred_t1   varchar2 (1000);
  l_filter_pred_t2   varchar2 (1000);
  
  function calc_filter_pred (p_desired_f_num_rows int)
  return varchar2
  is
  begin
    if p_desired_f_num_rows > 250 then
      raise_application_error (-20001, 'cannot produce desired filtered card for p_desired_f_num_rows='||p_desired_f_num_rows);
    end if;
    
    if p_desired_f_num_rows = 1 then
      return '<= 1';
    else
     return '< '||p_desired_f_num_rows;
    end if;
  end;
begin 
  l_filter_pred_t1 := calc_filter_pred (p_desired_f_num_rows_t1);
  l_filter_pred_t2 := calc_filter_pred (p_desired_f_num_rows_t2);
  
  select get_cbo_card_seq.nextval into l_seq_val from dual;
  l_stmt := 'select /*+ ordered use_hash(t2) no_index (t1) no_index(t2) get_cbo_card_tag '|| l_seq_val || ' */  t1.*, t2.* '
         || ' from t1, t2 '
         || 'where t1.x = t2.x '
         || '  and t1.filter '||l_filter_pred_t1
         || '  and t2.filter '||l_filter_pred_t2;
     
  --dbms_output.put_line (  l_stmt );      
  
  open l_cursor for l_stmt;
  close l_cursor;
  
  select address, hash_value, child_number
    into l_address, l_hash_value, l_child_number
    from v$sql
   where sql_text = l_stmt
     and rownum = 1;
       
  for r in (select operation, object_name, cardinality, options
              from v$sql_plan
             where address      = l_address
               and hash_value   = l_hash_value
               and child_number = l_child_number
               and id > 0)
  loop
    -- dbms_output.put_line ('"'||r.operation||'" - "'||r.options||'"');
    if r.operation like ('%JOIN') then
      p_cbo_card := r.cardinality;
    elsif r.operation in ('TABLE ACCESS') then
      if r.object_name = 'T1' then 
        p_f_num_rows_t1 := r.cardinality;
      elsif r.object_name = 'T2' then 
        p_f_num_rows_t2 := r.cardinality;
      end if;
    end if;
  end loop;
  
  if p_desired_f_num_rows_t1 != p_f_num_rows_t1 or p_f_num_rows_t1 is null then
    raise_application_error (-20002, 'cannot produce desired f_num_rows='||p_desired_f_num_rows_t1||' p_f_num_rows='||p_f_num_rows_t1); 
  end if;
  
  if p_desired_f_num_rows_t2 != p_f_num_rows_t2 or p_f_num_rows_t2 is null then
    raise_application_error (-20003, 'cannot produce desired f_num_rows='||p_desired_f_num_rows_t2||' p_f_num_rows='||p_f_num_rows_t2); 
  end if;
  
end get_cbo_card;
/
show errors

alter system flush shared_pool;

create or replace procedure test
is
  l_cbo_card number;
  l_f_num_rows_t1 number;
  l_f_num_rows_t2 number;
  l_cbo_card_lower number;
  l_num_distinct_t1_x number;
  l_num_distinct_t2_x number;
  l_num_rows_t1 number;
  l_num_rows_t2 number;
  l_frm_card number;
  l_f_num_distinct_t1_x number;
  l_f_num_distinct_t1_2 number;
  l_num_test int := 0;
  l_sel number;
  l_desired_num_distinct_t1_x number := null; 
  l_desired_num_distinct_t2_x number := null; 
  l_desired_f_num_rows_t1 number := null; 
  l_desired_f_num_rows_t2 number := null;
  
  function get_next (p_curr number, p_min number, p_max number, p_step number)
  return number
  is
    l_ret number;
  begin
    if p_curr is null then return p_min; end if;
    if p_curr = p_max then return null;  end if;
    l_ret := p_curr + p_step;
    if l_ret > p_max then return p_max; else return l_ret; end if;
  end get_next;
  
  procedure set_column_data (p_table varchar2, p_column varchar2, p_desired_num_distinct varchar2)
  is
    l_distribution_type varchar2(10 char) := 'mod';
    l_perfect_overlap   varchar2(1 char) := 'N';
  begin
    if l_distribution_type = 'random' then 
      execute immediate 'update '||p_table||' set '||p_column||'= trunc(dbms_random.value(0,'||p_desired_num_distinct||'))';
      execute immediate 'update '||p_table||' set '||p_column||'= rownum-1 where rownum <= '|| p_desired_num_distinct;
      if l_perfect_overlap = 'Y' then 
        execute immediate 'update '||p_table||' set '||p_column||'= 1e5 where  '||p_column||'= '|| (p_desired_num_distinct-1); 
      end if;
    elsif l_distribution_type = 'mod' then
      execute immediate 'update '||p_table||' set '||p_column||'= least (rownum-1, '||(p_desired_num_distinct-1)||')';
      if l_perfect_overlap = 'Y' then 
        execute immediate 'update '||p_table||' set '||p_column||'= 1e5 where  '||p_column||'= '|| (p_desired_num_distinct-1); 
      end if;
    end if;
    
  end set_column_data;
begin
  dbms_random.seed (0);

  select num_rows
    into l_num_rows_t1
    from user_tables
   where table_name = 'T1';
   
   select num_rows
    into l_num_rows_t2
    from user_tables
   where table_name = 'T2';  
   
  loop 
    l_desired_num_distinct_t1_x := get_next (l_desired_num_distinct_t1_x, 2, l_num_rows_t1, trunc(l_num_rows_t1/10));
    exit when l_desired_num_distinct_t1_x is null;
  
    set_column_data ('t1', 'x', l_desired_num_distinct_t1_x);
       
    -- refresh statistics of column "t1.x"
    dbms_stats.gather_table_stats (user, 't1', cascade => true, method_opt => 'for columns x size 1', estimate_percent => 100);
    
    select num_distinct 
      into l_num_distinct_t1_x
      from user_tab_columns 
     where table_name = 'T1'
       and column_name = 'X';
       
    loop 
      l_desired_num_distinct_t2_x := get_next (l_desired_num_distinct_t2_x, 2, l_num_rows_t2, trunc(l_num_rows_t2/10));
      exit when l_desired_num_distinct_t2_x is null;
    
      set_column_data ('t2', 'x', l_desired_num_distinct_t2_x);
      -- partial overlaps of range intervals for t1.x and t2.1
      -- this makes no difference (tested for paper)
      -- update t2 set x = x + l_desired_num_distinct_t1_x - 1; 
      
      -- refresh statistics of column "t2.x"
      dbms_stats.gather_table_stats (user, 't2', cascade => true, method_opt => 'for columns x size 1', estimate_percent => 100);
      
      select num_distinct 
        into l_num_distinct_t2_x
        from user_tab_columns 
       where table_name = 'T2'
         and column_name = 'X';  
         
      loop 
        l_desired_f_num_rows_t1 := get_next (l_desired_f_num_rows_t1, 1, l_num_rows_t1, trunc(l_num_rows_t1/5));
        exit when l_desired_f_num_rows_t1 is null;   
         
        loop 
          l_desired_f_num_rows_t2 := get_next (l_desired_f_num_rows_t2, 1, l_num_rows_t2, 1);
          exit when l_desired_f_num_rows_t2 is null;  
            
          get_cbo_card (l_desired_f_num_rows_t1, l_desired_f_num_rows_t2, l_cbo_card, 
                        l_f_num_rows_t1, l_f_num_rows_t2);
          
          l_f_num_distinct_t1_x := yao ( l_num_distinct_t1_x, l_f_num_rows_t1, l_num_rows_t1 );
          l_f_num_distinct_t1_2 := yao ( l_num_distinct_t2_x, l_f_num_rows_t2, l_num_rows_t2 );
                        
          l_sel := 1 / ceil ( greatest ( l_f_num_distinct_t1_x, l_f_num_distinct_t1_2 ) );
             
          -- special case: both num_distinct = 1 => sel = 1
          if l_num_distinct_t1_x = 1 or l_num_distinct_t2_x = 1 then            
            if l_num_distinct_t1_x = 1 and l_num_distinct_t2_x = 1 then
              l_sel := 1;
            end if;
          end if;
          
          l_frm_card := l_f_num_rows_t1 * l_f_num_rows_t2 * l_sel;
          
          -- CBO round()s the final card 
          if 1=1 then
            l_frm_card := round (l_frm_card);
            if l_frm_card < 1 then 
              l_frm_card := 1;
            end if;
          end if;
          
          -- lower bound: least of filtered cardinalities
          -- it doesn't seem to make any difference with the latest refinements
          /*
          l_cbo_card_lower := least (l_f_num_rows_t1, l_f_num_rows_t2);
         
          if l_frm_card < l_cbo_card_lower then
            l_frm_card := l_cbo_card_lower;
          end if;
          */
         
          insert into results (num_rows_t1, num_rows_t2, num_distinct_t1_x, num_distinct_t2_x, 
                               f_num_distinct_t1_x, f_num_distinct_t1_2, f_num_rows_t1, f_num_rows_t2, 
                               cbo_card, frm_card, sel)
            values (l_num_rows_t1, l_num_rows_t2, l_num_distinct_t1_x, l_num_distinct_t2_x,  
                    l_f_num_distinct_t1_x, l_f_num_distinct_t1_2, l_f_num_rows_t1, l_f_num_rows_t2, 
                    l_cbo_card, l_frm_card, l_sel );
          commit;
         
          l_num_test := l_num_test + 1;
          if mod (l_num_test, 121) = 0 then
            execute immediate 'alter system flush shared_pool';
          end if;
        
        end loop;
        
      end loop;
    end loop;
  end loop;
end;
/
show errors;

exec test;

--alter session set events '10053 trace name context forever, level 1';

--alter session set events '10053 trace name context off';

col num_rows_t1 head "nr_t1" form 999
col num_rows_t2 head "nr_t2" form 999
col f_num_rows_t1 head "fnr_t1" form 999
col f_num_rows_t2 head "fnr_t2" form 999
col num_distinct_t1_x head "nd_t1_x" form 9999
col num_distinct_t2_x head "nd_t2_x" form 9999
col f_num_distinct_t1_x head "fnd_t1_x" form 99.9999999999
col f_num_distinct_t1_2 head "fnd_t2_x" form 99.9999999999
col sel form 99.99999
--select r.*, cbo_card / frm_card from results r where abs (cbo_card - frm_card) > 1 order by 1,2,3,4,7,8;
  
select avg ( cbo_card - round(frm_card) ), stddev ( cbo_card - round(frm_card) ), 
       avg ( abs( cbo_card - round(frm_card) ) ), stddev ( abs ( cbo_card - round(frm_card) ) ) from results;
       
-- note: percentage of error has frm_card as denominator
select avg ( 100 * abs (cbo_card - round(frm_card)) / round(frm_card) ) perc_error,
       stddev ( 100 * abs (cbo_card - round(frm_card)) / round(frm_card) ) from results;  
 
-- test exact formula 
col perc form 99.99
col perc_cum form 999.99
select r2.*, trunc (100 * cnt_ratio, 2) as perc,
             trunc (100 * sum(cnt_ratio) over (order by abs_error), 2) as perc_cum
  from (
select r.*, ratio_to_report (cnt) over() cnt_ratio
  from (
select round (abs (cbo_card - round(frm_card)), 1) as abs_error, count(*) cnt
  from results
 group by round (abs (cbo_card - round(frm_card)), 1)
       ) r
       ) r2
 order by 1;
 
spool off
