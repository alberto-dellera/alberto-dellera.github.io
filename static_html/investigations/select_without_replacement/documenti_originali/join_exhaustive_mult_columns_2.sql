--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Exhaustive check of the "Selection Without Replacement" formula
--    for the join case, multiple-column, 2 columns
--    Alberto Dell'Era, August 2007
--    tested in 10.2.0.3, 9.2.0.8

start setenv.sql
start distinctBallsPlSql.sql
start interval_helpers.sql
set timing off

exec dbms_random.seed(0)

exec execute immediate 'purge recyclebin'; exception when others then null;

spool join_exhaustive_mult_columns_2.lst

-- end of initialization section

set echo on

drop table results;
create table results (
  num_rows_t1          int    not null,
  num_rows_t2          int    not null,
  num_distinct_t1_x    int    not null,
  num_distinct_t2_x    int    not null,
  num_distinct_t1_y    int    not null,
  num_distinct_t2_y    int    not null,
  f_num_rows_t1 number not null,
  f_num_rows_t2 number not null,
  f_num_distinct_t1_x  number,
  f_num_distinct_t2_x  number,
  f_num_distinct_t1_y  number,
  f_num_distinct_t2_y  number,
  on_sel_x             number,  
  on_sel_y             number,
  cbo_card             number not null, 
  frm_card             number not null,
  frm_card_san         number not null,
  frm_card_nosan       number not null,
  cbo_card_san         number not null,
  cbo_card_nosan       number not null,
  irf                  varchar2(4 char), -- insane reason flag
  st1                  number , -- card with the sanity check for t1 applied
  st2                  number   -- card with the sanity check for t2 applied
);

drop table t1;
drop table t2;

purge recyclebin;

-- max 250
define num_rows_t1=50
-- max 250
define num_rows_t2=50

create table t1 as
select 100000 x, 100000 y, rownum filter, rownum-1 id from dual connect by level <= &num_rows_t1. ;

create table t2 as
select 100000 x, 100000 y, rownum filter, rownum-1 id from dual connect by level <= &num_rows_t2. ;

-- following indexes have no influence at all (checked for paper)
--create index t1_x_y_idx on t1 (x, y);
--create index t1_y_x_idx on t1 (y, x);
--create index t2_x_y_idx on t2 (x, y);
--create index t2_y_x_idx on t2 (y, x);
--create index t1_x_filter_idx on t1 (x, filter);
--create index t1_filter_x_idx on t1 (filter, x);
--create index t2_x_filter_idx on t2 (x, filter);
--create index t2_filter_x_idx on t2 (filter, x);
  
-- collect baseline stats, build an histogram on the "filter" column
--exec dbms_stats.gather_table_stats (user, 't1', cascade=>true, method_opt => 'for columns x size 1,y size 1, columns filter size 254', estimate_percent=>100);
--exec dbms_stats.gather_table_stats (user, 't2', cascade=>true, method_opt => 'for columns x size 1,y size 1, columns filter size 254', estimate_percent=>100);

drop sequence get_cbo_card_seq;
create sequence get_cbo_card_seq;

alter system flush shared_pool;

-- this is to prevent the 10g "multi-column join key sanity check" from masking the core algorithm
define opt_join_sel_sanity_check=true;
alter session set "_optimizer_join_sel_sanity_check"=&opt_join_sel_sanity_check.;

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
  l_stmt := 'select /*+ ordered use_hash(t2) get_cbo_card_tag '|| l_seq_val || '  */  t1.*, t2.* '
         || ' from t1, t2 '
         || 'where t1.x = t2.x '
         || '  and t1.y = t2.y '
         || '  and t1.filter '||l_filter_pred_t1
         || '  and t2.filter '||l_filter_pred_t2; 
 
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
  
  if p_desired_f_num_rows_t1 != p_f_num_rows_t1 then
    raise_application_error (-20002, 'cannot produce desired f_num_rows_t1='||p_desired_f_num_rows_t1||' p_f_num_rows_t1='||p_f_num_rows_t1); 
  end if;
   if p_desired_f_num_rows_t2 != p_f_num_rows_t2 then
    raise_application_error (-20003, 'cannot produce desired f_num_rows_t2='||p_desired_f_num_rows_t2||' p_f_num_rows_t2='||p_f_num_rows_t2); 
  end if;
  
end get_cbo_card;
/
show errors

alter system flush shared_pool;

create or replace procedure test
is
  l_db_version number;
  l_dummy_v varchar2(100 char);
  l_compat  varchar2(100 char);
  l_cbo_card number;
  l_cbo_card_san number;
  l_cbo_card_nosan number;
  l_f_num_rows_t1 number;
  l_f_num_rows_t2 number;
  l_num_distinct_t1_x number;
  l_num_distinct_t1_y number;
  l_num_distinct_t2_x number;
  l_num_distinct_t2_y number;
  l_num_rows_t1 number;
  l_num_rows_t2 number;
  l_frm_card number;
  l_frm_card_san number;
  l_frm_card_nosan number;
  l_f_num_distinct_t1_x    number;
  l_f_num_distinct_t1_y    number;
  l_f_num_distinct_t1_mult number;
  l_f_num_distinct_t2_x    number;
  l_f_num_distinct_t2_y    number;
  l_f_num_distinct_t2_mult number;
  l_num_test int := 0;
  l_desired_num_distinct_t1_x number := null;
  l_desired_num_distinct_t1_y number := null;
  l_desired_num_distinct_t2_x number := null;
  l_desired_num_distinct_t2_y number := null;
  l_desired_f_num_rows_t1 number := null;
  l_desired_f_num_rows_t2 number := null;
  l_desired_nr_t1 number := null; 
  l_desired_nr_t2 number := null;
  l_join_filter_sel_t1_y number;  
  l_join_filter_sel_t2_y number;
  l_interval_ratio number;
  l_min_t1_x number; l_max_t1_x number;
  l_min_t1_y number; l_max_t1_y number;
  l_min_t2_x number; l_max_t2_x number;
  l_min_t2_y number; l_max_t2_y number;
  l_sel_x number;
  l_sel_y number;
  l_sel_xy number;
  l_sel_xy_san number;
  l_multi_join_key_card_t1 number;
  l_multi_join_key_card_t2 number;
  l_f_multi_join_key_card_t1 number;
  l_f_multi_join_key_card_t2 number;
  l_straight_f_num_distinct_t1 number;
  l_straight_f_num_distinct_t2 number;
  l_straight_f_num_distinct_t1_x number;
  l_straight_f_num_distinct_t1_y number;
  l_straight_f_num_distinct_t2_x number;
  l_straight_f_num_distinct_t2_y number;
  l_insane_reason_flag results.irf%type;
  l_t1_is_insane varchar2(1 char);
  l_t2_is_insane varchar2(1 char);
  l_dummy number;
  
  function get_next (p_curr number, p_min number, p_max number, p_step number)
  return number
  is
    l_ret number;
  begin
    if p_step < 1 then
      raise_application_error (-20001, 'illegal p_step='||p_step);
    end if;
    if p_curr is null then return p_min; end if;
    if p_curr = p_max then return null;  end if;
    l_ret := p_curr + p_step;
    if l_ret > p_max then return p_max; else return l_ret; end if;
  end get_next;
  
  function get_distinct (p_table_name varchar2, p_column_name varchar2) 
  return number
  is
    l_ret number;
  begin
    select num_distinct 
      into l_ret
      from user_tab_columns 
     where table_name = p_table_name
       and column_name = p_column_name;
    return l_ret;
  end get_distinct; 
  
  procedure check_intervals (p_max_t1 number, p_min_t1 number, p_max_t2 number, p_min_t2 number)
  is
  begin
    if (p_min_t2 between p_min_t1 and p_max_t1) and (p_max_t2 between p_min_t1 and p_max_t1) then return; end if;
    if (p_min_t1 between p_min_t2 and p_max_t2) and (p_max_t1 between p_min_t2 and p_max_t2) then return; end if;
    raise_application_error (-20088, 'one interval does not include the other '||p_min_t1||' '||p_max_t1||' '||p_min_t2||' '||p_max_t2);
  end check_intervals;
  
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
  
  dbms_utility.db_version (l_dummy_v, l_compat);
  l_db_version := to_number (substr (l_compat, 1, instr (l_compat, '.')-1));
  
  loop
    l_desired_nr_t1 := get_next (l_desired_nr_t1, 11, &num_rows_t1., &num_rows_t1.);
    exit when l_desired_nr_t1 is null;
    delete from t1;
    insert into t1(x,y,filter,id)
    select 100000 x, 100000 y, rownum filter, rownum-1 id from dual connect by level <= l_desired_nr_t1 ;
 
    dbms_stats.gather_table_stats (user, 't1', cascade=>true, method_opt => 'for columns x size 1,y size 1, columns filter size 254', estimate_percent=>100);

    select num_rows
      into l_num_rows_t1
      from user_tables
     where table_name = 'T1';
 
  loop
    l_desired_nr_t2 := get_next (l_desired_nr_t2, 11, &num_rows_t2., &num_rows_t2.);
    exit when l_desired_nr_t2 is null;
    delete from t2;
    insert into t2(x,y,filter, id)
    select 100000 x, 100000 y, rownum filter, rownum-1 id from dual connect by level <= l_desired_nr_t2 ;
 
    dbms_stats.gather_table_stats (user, 't2', cascade=>true, method_opt => 'for columns x size 1,y size 1, columns filter size 254', estimate_percent=>100);
    
    select num_rows
      into l_num_rows_t2
      from user_tables
     where table_name = 'T2';  
    
  loop
    l_desired_num_distinct_t1_x := get_next (l_desired_num_distinct_t1_x, 2, l_num_rows_t1, 8);
    --l_desired_num_distinct_t1_x := get_next (l_desired_num_distinct_t1_x, 20, 20, trunc(l_num_rows_t1/5));
    exit when l_desired_num_distinct_t1_x is null;
  
    set_column_data ('t1', 'x', l_desired_num_distinct_t1_x);
    select min(x), max(x) into l_min_t1_x, l_max_t1_x from t1;
     
    -- refresh statistics of column "t1.x"
    -- using SIZE 254 (checked only by setting SIZE 254 simultaneously on t1.x, t1.y, t2.x, t2.y) does not change
    -- the output if the sanity checks are disabled, does change it when they are enabled (checked for paper)
    dbms_stats.gather_table_stats (user, 't1', cascade => true, method_opt => 'for columns x size 1', estimate_percent => 100);
    l_num_distinct_t1_x := get_distinct ('T1', 'X');
    
    loop 
      l_desired_num_distinct_t1_y := get_next (l_desired_num_distinct_t1_y, 2, l_num_rows_t1, 8);
      --l_desired_num_distinct_t1_y := get_next (l_desired_num_distinct_t1_y, 2, 2, 2);
      exit when l_desired_num_distinct_t1_y is null;
    
      set_column_data ('t1', 'y', l_desired_num_distinct_t1_y); 
      select min(y), max(y) into l_min_t1_y, l_max_t1_y from t1;
      
      -- refresh statistics of column "t1.y"
      -- using SIZE 254 (checked only by setting SIZE 254 simultaneously on t1.x, t1.y, t2.x, t2.y) does not change
      -- the output if the sanity checks are disabled, does change it when they are enabled (checked for paper)
      dbms_stats.gather_table_stats (user, 't1', cascade => true, method_opt => 'for columns y size 1', estimate_percent => 100);
      l_num_distinct_t1_y := get_distinct ('T1', 'Y');
   
      loop 
        l_desired_num_distinct_t2_x := get_next (l_desired_num_distinct_t2_x, 2, l_num_rows_t2, 8);
        --l_desired_num_distinct_t2_x := get_next (l_desired_num_distinct_t2_x, 2, 2, trunc(l_num_rows_t2/5));
        exit when l_desired_num_distinct_t2_x is null;
      
        set_column_data ('t2', 'x', l_desired_num_distinct_t2_x);
        -- update t2 set x = x + 0.5 * (l_desired_num_distinct_t1_x-1); -- note: variable overlap 
        select min(x), max(x) into l_min_t2_x, l_max_t2_x from t2;
        
        -- refresh statistics of column "t2.x"
        -- using SIZE 254 (checked only by setting SIZE 254 simultaneously on t1.x, t1.y, t2.x, t2.y) does not change
        -- the output if the sanity checks are disabled, does change it when they are enabled (checked for paper)
        dbms_stats.gather_table_stats (user, 't2', cascade => true, method_opt => 'for columns x size 1', estimate_percent => 100);
        l_num_distinct_t2_x := get_distinct ('T2', 'X');
        
        loop 
          l_desired_num_distinct_t2_y := get_next (l_desired_num_distinct_t2_y, 2, l_num_rows_t2, 8);
          --l_desired_num_distinct_t2_y := get_next (l_desired_num_distinct_t2_y, 20, 20, 2);
          
          exit when l_desired_num_distinct_t2_y is null;
        
          set_column_data ('t2', 'y', l_desired_num_distinct_t2_y);
          select min(y), max(y) into l_min_t2_y, l_max_t2_y from t2;
          
          -- refresh statistics of column "t2.y"
          -- using SIZE 254 (checked only by setting SIZE 254 simultaneously on t1.x, t1.y, t2.x, t2.y) does not change
          -- the output if the sanity checks are disabled, does change it when they are enabled (checked for paper)
          dbms_stats.gather_table_stats (user, 't2', cascade => true, method_opt => 'for columns y size 1', estimate_percent => 100);
          l_num_distinct_t2_y := get_distinct ('T2', 'Y');
            
          loop
            l_desired_f_num_rows_t1 := get_next (l_desired_f_num_rows_t1, 1, l_num_rows_t1, 8); 
            --l_desired_f_num_rows_t1 := get_next (l_desired_f_num_rows_t1, 1, l_num_rows_t1, 1);
            exit when l_desired_f_num_rows_t1 is null;

            loop
              l_desired_f_num_rows_t2 := get_next (l_desired_f_num_rows_t2, 1, l_num_rows_t2, 8);
              --l_desired_f_num_rows_t2 := get_next (l_desired_f_num_rows_t2, 200, 200, 1);
              exit when l_desired_f_num_rows_t2 is null;
                          
              execute immediate 'alter session set "_optimizer_join_sel_sanity_check"=false';
              get_cbo_card (l_desired_f_num_rows_t1, l_desired_f_num_rows_t2, l_cbo_card_nosan, 
                            l_f_num_rows_t1, l_f_num_rows_t2);
              execute immediate 'alter session set "_optimizer_join_sel_sanity_check"=true';
              get_cbo_card (l_desired_f_num_rows_t1, l_desired_f_num_rows_t2, l_cbo_card_san, 
                            l_dummy, l_dummy);               
                            
              l_f_num_distinct_t1_x    := null; l_f_num_distinct_t2_x    := null;
              l_f_num_distinct_t1_y    := null; l_f_num_distinct_t2_y    := null;
              l_multi_join_key_card_t1 := null; l_multi_join_key_card_t2 := null;  
              l_insane_reason_flag     := null;
    
              if is_disjunct_interval (l_min_t1_x, l_max_t1_x, l_min_t2_x, l_max_t2_x) = 1 or
                 is_disjunct_interval (l_min_t1_y, l_max_t1_y, l_min_t2_y, l_max_t2_y) = 1
              then
                -- disjunct interval => selectivity = 0 (from 10053 trace)
                l_sel_xy := 0;
              else   
                -- join on x first
                l_f_num_distinct_t1_x := yao ( l_num_distinct_t1_x, l_f_num_rows_t1, l_num_rows_t1 );
                l_f_num_distinct_t2_x := yao ( l_num_distinct_t2_x, l_f_num_rows_t2, l_num_rows_t2 );
                l_sel_x := 1 / ceil (greatest (round(l_f_num_distinct_t1_x,2), round(l_f_num_distinct_t2_x,2)));
                
                -- test per "un intervallo deve essere dentro l'altro"
                --check_intervals (l_max_t1_x, l_min_t1_x, l_max_t2_x, l_min_t2_x);
                
                /*if (l_max_t1_x - l_min_t1_x) <= (l_max_t2_x - l_min_t2_x) then
                  l_join_filter_sel_t1_y := 1;
                  l_join_filter_sel_t2_y := (l_max_t1_x - l_min_t1_x) / (l_max_t2_x - l_min_t2_x);
                else
                  l_join_filter_sel_t1_y := (l_max_t2_x - l_min_t2_x) / (l_max_t1_x - l_min_t1_x);
                  l_join_filter_sel_t2_y := 1;
                end if;*/
                
                l_join_filter_sel_t1_y := overlapping_ratio_a ( l_min_t1_x, l_max_t1_x, l_min_t2_x, l_max_t2_x);
                l_join_filter_sel_t2_y := overlapping_ratio_b ( l_min_t1_x, l_max_t1_x, l_min_t2_x, l_max_t2_x);
                
                if l_join_filter_sel_t1_y = 0 or l_join_filter_sel_t2_y= 0 then
                  -- if overlapping_ratio = 0 (intersection of intervals is a single point) =>
                  -- selectivity = 1 (from 10053 trace), probably because we have num_distinct=1
                  -- and so 1/num_distinct = 1 (or because of f_num_distinct -> 1 as the overlapping
                  -- interval decreases)
                  l_sel_y := 1;
                else
                  l_f_num_distinct_t1_y := yao ( l_num_distinct_t1_y, l_join_filter_sel_t1_y * l_f_num_rows_t1, l_num_rows_t1 );
                  l_f_num_distinct_t2_y := yao ( l_num_distinct_t2_y, l_join_filter_sel_t2_y * l_f_num_rows_t2, l_num_rows_t2 );
                
                  l_sel_y := 1 / ceil (greatest (round(l_f_num_distinct_t1_y,2), round(l_f_num_distinct_t2_y,2)));
                end if;
                
                l_sel_xy := l_sel_x * l_sel_y;         
       
                -- join selectivity multicolumn sanity checks
                -- when the selectivity is labeled as "insane" => fallback to lower bound 
                l_insane_reason_flag := null;
                if 1=1  then
                  -- multi join key cards (from 10053 trace)
                  l_multi_join_key_card_t1 := least ( l_num_distinct_t1_x * l_num_distinct_t1_y, l_num_rows_t1);
                  l_multi_join_key_card_t2 := least ( l_num_distinct_t2_x * l_num_distinct_t2_y, l_num_rows_t2);
                  /*
                  -- filtered multi join key cards
                  l_f_multi_join_key_card_t1 := least (l_multi_join_key_card_t1, l_f_num_rows_t1);
                  l_f_multi_join_key_card_t2 := least (l_multi_join_key_card_t2, l_f_num_rows_t2);
                  -- straight (without join filter sel) filtered num distincts
                  l_straight_f_num_distinct_t1_x := yao ( l_num_distinct_t1_x, l_f_num_rows_t1, l_num_rows_t1 );
                  l_straight_f_num_distinct_t2_x := yao ( l_num_distinct_t2_x, l_f_num_rows_t2, l_num_rows_t2 );
                  l_straight_f_num_distinct_t1_y := yao ( l_num_distinct_t1_y, l_f_num_rows_t1, l_num_rows_t1 );
                  l_straight_f_num_distinct_t2_y := yao ( l_num_distinct_t2_y, l_f_num_rows_t2, l_num_rows_t2 );
                  -- straight table distinct values
                  l_straight_f_num_distinct_t1 := ceil (l_straight_f_num_distinct_t1_x) * ceil (l_straight_f_num_distinct_t1_y);
                  l_straight_f_num_distinct_t2 := ceil (l_straight_f_num_distinct_t2_x) * ceil (l_straight_f_num_distinct_t2_y);
                  l_t1_is_insane := 'N'; l_t2_is_insane := 'N';
                  -- NB the = in >= is confirmed by using an unfiltered join on two tables
                  -- with nr >> nd(x)*nd(y), so that swru(nd,..)=nd, fnd=nd, sfnd(..)=mjkc(..),
                  -- eg join_card_04.sql [Lewis, CBO, page 272]. Whatever the combination of
                  -- nd, the sanity checks always trigger for both, and the CBO takes 1/greatest(mjkc(t1),mjkc)t2))
                  if l_straight_f_num_distinct_t1 >= l_f_multi_join_key_card_t1 then
                    l_insane_reason_flag := l_insane_reason_flag || '1';
                    l_t1_is_insane := 'Y';
                    l_sel_xy := 1 / l_multi_join_key_card_t1; -- confirmed by where (cbo_card_nosan != cbo_card_san) and cbo_card_san not in (st1, st2) => 0 rows selected
                  end if;
                  if l_straight_f_num_distinct_t2 >= l_f_multi_join_key_card_t2 then
                    l_insane_reason_flag := l_insane_reason_flag || '2';
                    l_t2_is_insane := 'Y';
                    l_sel_xy := 1 / l_multi_join_key_card_t2; -- confirmed by where (cbo_card_nosan != cbo_card_san) and cbo_card_san not in (st1, st2) => 0 rows selected
                  end if;
                  -- use the most selective if both multicolumn sanity checks apply
                  if l_t1_is_insane = 'Y' and l_t2_is_insane = 'Y' then
                     l_sel_xy := 1 / greatest ( l_multi_join_key_card_t1, l_multi_join_key_card_t2 );
                  end if;
                  */
                  l_sel_xy_san := 1 / greatest ( l_multi_join_key_card_t1, l_multi_join_key_card_t2 );
                end if;
                
              end if; -- if is_disjunt_interval()
              
              l_frm_card_nosan := l_f_num_rows_t1 * l_f_num_rows_t2 * l_sel_xy;
              l_frm_card_san   := l_f_num_rows_t1 * l_f_num_rows_t2 * l_sel_xy_san;
              
              if lower(trim('&opt_join_sel_sanity_check.')) = 'true' then
                l_frm_card := l_frm_card_san;
                l_cbo_card := l_cbo_card_san;
              else
                l_frm_card := l_frm_card_nosan;
                l_cbo_card := l_cbo_card_nosan;
              end if;
              
              -- CBO round()s the final card (from 10053 trace)
              if 1=1 then
                l_frm_card := round (l_frm_card);
                if l_frm_card < 1 then 
                  l_frm_card := 1;
                end if;
              end if;
              
              insert into results (num_rows_t1, num_rows_t2, 
                                   num_distinct_t1_x, num_distinct_t1_y, num_distinct_t2_x, num_distinct_t2_y, 
                                   f_num_distinct_t1_x, f_num_distinct_t1_y, f_num_distinct_t2_x, f_num_distinct_t2_y,
                                   on_sel_x, on_sel_y, f_num_rows_t1, f_num_rows_t2, 
                                   cbo_card, frm_card, frm_card_san, frm_card_nosan, cbo_card_san, cbo_card_nosan, irf, 
                                   st1, st2)
                values (l_num_rows_t1, l_num_rows_t2, 
                        l_num_distinct_t1_x, l_num_distinct_t1_y, l_num_distinct_t2_x, l_num_distinct_t2_y,
                        l_f_num_distinct_t1_x, l_f_num_distinct_t1_y, l_f_num_distinct_t2_x, l_f_num_distinct_t2_y,
                        1/decode(l_sel_x,null,null,l_sel_x), 1/decode(l_sel_y,null,null,l_sel_y), l_f_num_rows_t1, l_f_num_rows_t2, 
                        l_cbo_card, l_frm_card, l_frm_card_san, l_frm_card_nosan, l_cbo_card_san, l_cbo_card_nosan, l_insane_reason_flag, 
                        round(l_f_num_rows_t1 * l_f_num_rows_t2 / l_multi_join_key_card_t1), 
                        round(l_f_num_rows_t1 * l_f_num_rows_t2 / l_multi_join_key_card_t2)
                       );
              commit;
              
              l_num_test := l_num_test + 1;
              if mod (l_num_test, 121) = 0 then
                execute immediate 'alter system flush shared_pool';
              end if;
            
            end loop;
          end loop;
        end loop;
      end loop;
    end loop;
  end loop;
  end loop;
  end loop;
end;
/
show errors;

exec test;

col num_rows_t1 head "nr_t1" form 999
col num_rows_t2 head "nr_t2" form 999
col f_num_rows_t1 head "fnr_t1" form 999
col f_num_rows_t2 head "fnr_t2" form 999
col num_distinct_t1_x head "nd_t1_x"  form 999
col num_distinct_t1_y head "nd_t1_y"  form 999
col num_distinct_t2_x head "nd_t2_x"  form 999
col num_distinct_t2_y head "nd_t2_y"  form 999
col f_num_distinct_t1_x head "fnd_t1_x" form 9999.999   
col f_num_distinct_t1_y head "fnd_t1_y" form 9999.999 
col f_num_distinct_t2_x head "fnd_t2_x" form 9999.999 
col f_num_distinct_t2_y head "fnd_t2_y" form 9999.999 
col on_sel_x head "1/selx" form 9999
col on_sel_y head "1/sely" form 9999
col irf form a3
col st1 form 9999
col st2 form 9999
  
prompt formula with sanity checks 
select avg ( cbo_card_san - greatest(1,round(frm_card_san)) ), stddev ( cbo_card_san - greatest(1,round(frm_card_san)) ), 
       avg ( abs( cbo_card_san - greatest(1,round(frm_card_san)) ) ), stddev ( abs ( cbo_card_san - greatest(1,round(frm_card_san)) ) ) from results;
       
-- note: percentage of error has frm_card_san as denominator
select avg ( 100 * abs (cbo_card_san - greatest(1,round(frm_card_san))) / greatest(1,round(frm_card_san)) ) perc_error,
       stddev ( 100 * abs (cbo_card_san - greatest(1,round(frm_card_san))) / greatest(1,round(frm_card_san)) ) from results;  
 
-- test exact formula 
col perc form 99.99
col perc_cum form 999.99
select r2.*, trunc (100 * cnt_ratio, 2) as perc,
             trunc (100 * sum(cnt_ratio) over (order by abs_error), 2) as perc_cum
  from (
select r.*, ratio_to_report (cnt) over() cnt_ratio
  from (
select round (abs (cbo_card_san - greatest(1,round(frm_card_san))), 1) as abs_error, count(*) cnt
  from results
 group by round (abs (cbo_card_san - greatest(1,round(frm_card_san))), 1)
       ) r
       ) r2
 order by 1;
 
prompt formula without sanity checks 
select avg ( cbo_card_nosan - greatest(1,round(frm_card_nosan)) ), stddev ( cbo_card_nosan - greatest(1,round(frm_card_nosan)) ), 
       avg ( abs( cbo_card_nosan - greatest(1,round(frm_card_nosan)) ) ), stddev ( abs ( cbo_card_nosan - greatest(1,round(frm_card_nosan)) ) ) from results;
       
-- note: percentage of error has frm_card_nosan as denominator
select avg ( 100 * abs (cbo_card_nosan - greatest(1,round(frm_card_nosan))) / greatest(1,round(frm_card_nosan)) ) perc_error,
       stddev ( 100 * abs (cbo_card_nosan - greatest(1,round(frm_card_nosan))) / greatest(1,round(frm_card_nosan)) ) from results;  
 
-- test exact formula 
col perc form 99.99
col perc_cum form 999.99
select r2.*, trunc (100 * cnt_ratio, 2) as perc,
             trunc (100 * sum(cnt_ratio) over (order by abs_error), 2) as perc_cum
  from (
select r.*, ratio_to_report (cnt) over() cnt_ratio
  from (
select round (abs (cbo_card_nosan - greatest(1,round(frm_card_nosan))), 1) as abs_error, count(*) cnt
  from results
 group by round (abs (cbo_card_nosan - greatest(1,round(frm_card_nosan))), 1)
       ) r
       ) r2
 order by 1; 
 
doc
exactly the same in both 9.2.0.8 and 10.2.0.3

formula with sanity checks 
SQL> select avg ( cbo_card_san - greatest(1,round(frm_card_san)) ), stddev ( cbo_card_san - greatest(1,round(frm_card_san)) ),
  2         avg ( abs( cbo_card_san - greatest(1,round(frm_card_san)) ) ), stddev ( abs ( cbo_card_san - greatest(1,round(frm_card_san)) ) ) from results;

AVG(CBO_CARD_SAN-GREATEST(1,ROUND(FRM_CARD_SAN))) STDDEV(CBO_CARD_SAN-GREATEST(1,ROUND(FRM_CARD_SAN))) AVG(ABS(CBO_CARD_SAN-GREATEST(1,ROUND(FRM_CARD_SAN))))
------------------------------------------------- ---------------------------------------------------- ------------------------------------------------------
STDDEV(ABS(CBO_CARD_SAN-GREATEST(1,ROUND(FRM_CARD_SAN))))
---------------------------------------------------------
                                       -.00135565                                           .036794348                                             .001355654
                                               .036794348


SQL> -- note: percentage of error has frm_card_san as denominator
SQL> select avg ( 100 * abs (cbo_card_san - greatest(1,round(frm_card_san))) / greatest(1,round(frm_card_san)) ) perc_error,
  2         stddev ( 100 * abs (cbo_card_san - greatest(1,round(frm_card_san))) / greatest(1,round(frm_card_san)) ) from results;

PERC_ERROR STDDEV(100*ABS(CBO_CARD_SAN-GREATEST(1,ROUND(FRM_CARD_SAN)))/GREATEST(1,ROUND(FRM_CARD_SAN)))
---------- ---------------------------------------------------------------------------------------------
.005457878                                                                                    .148359172

SQL> select r2.*, trunc (100 * cnt_ratio, 2) as perc,
  2               trunc (100 * sum(cnt_ratio) over (order by abs_error), 2) as perc_cum
  3    from (
  4  select r.*, ratio_to_report (cnt) over() cnt_ratio
  5    from (
  6  select round (abs (cbo_card_san - greatest(1,round(frm_card_san))), 1) as abs_error, count(*) cnt
  7    from results
  8   group by round (abs (cbo_card_san - greatest(1,round(frm_card_san))), 1)
  9         ) r
 10         ) r2
 11   order by 1;

 ABS_ERROR        CNT  CNT_RATIO   PERC PERC_CUM
---------- ---------- ---------- ------ --------
         0     175323 .998644346  99.86    99.86
         1        238 .001355654    .13   100.00

formula without sanity checks 
SQL> select avg ( cbo_card_nosan - greatest(1,round(frm_card_nosan)) ), stddev ( cbo_card_nosan - greatest(1,round(frm_card_nosan)) ),
  2         avg ( abs( cbo_card_nosan - greatest(1,round(frm_card_nosan)) ) ), stddev ( abs ( cbo_card_nosan - greatest(1,round(frm_card_nosan)) ) ) from resu
lts;

AVG(CBO_CARD_NOSAN-GREATEST(1,ROUND(FRM_CARD_NOSAN))) STDDEV(CBO_CARD_NOSAN-GREATEST(1,ROUND(FRM_CARD_NOSAN))) AVG(ABS(CBO_CARD_NOSAN-GREATEST(1,ROUND(FRM_CAR
D_NOSAN))))
----------------------------------------------------- -------------------------------------------------------- -----------------------------------------------
-----------
STDDEV(ABS(CBO_CARD_NOSAN-GREATEST(1,ROUND(FRM_CARD_NOSAN))))
-------------------------------------------------------------
                                           -.01560711                                               .364314702
 .020482909
                                                   .364073116

SQL> -- note: percentage of error has frm_card_nosan as denominator
SQL> select avg ( 100 * abs (cbo_card_nosan - greatest(1,round(frm_card_nosan))) / greatest(1,round(frm_card_nosan)) ) perc_error,
  2         stddev ( 100 * abs (cbo_card_nosan - greatest(1,round(frm_card_nosan))) / greatest(1,round(frm_card_nosan)) ) from results;

PERC_ERROR STDDEV(100*ABS(CBO_CARD_NOSAN-GREATEST(1,ROUND(FRM_CARD_NOSAN)))/GREATEST(1,ROUND(FRM_CARD_NOSAN)))
---------- ---------------------------------------------------------------------------------------------------
.286217162                                                                                          3.41503088

SQL> select r2.*, trunc (100 * cnt_ratio, 2) as perc,
  2               trunc (100 * sum(cnt_ratio) over (order by abs_error), 2) as perc_cum
  3    from (
  4  select r.*, ratio_to_report (cnt) over() cnt_ratio
  5    from (
  6  select round (abs (cbo_card_nosan - greatest(1,round(frm_card_nosan))), 1) as abs_error, count(*) cnt
  7    from results
  8   group by round (abs (cbo_card_nosan - greatest(1,round(frm_card_nosan))), 1)
  9         ) r
 10         ) r2
 11   order by 1;

 ABS_ERROR        CNT  CNT_RATIO   PERC PERC_CUM
---------- ---------- ---------- ------ --------
         0     173961 .990886359  99.08    99.08
         1       1118 .006368157    .63    99.72
         2        166  .00094554    .09    99.82
         3         90 .000512642    .05    99.87
         4         44 .000250625    .02    99.89
         5         42 .000239233    .02    99.92
         6         24 .000136705    .01    99.93
         7         22 .000125313    .01    99.94
         8         30 .000170881    .01    99.96
         9         12 .000068352    .00    99.97
        10          4 .000022784    .00    99.97
        13         12 .000068352    .00    99.97
        16         12 .000068352    .00    99.98
        19         24 .000136705    .01   100.00
#
 
spool off
