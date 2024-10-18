--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Exhaustive check of the "Selection Without Replacement" formula
--    for the distinct case, multiple-column, 2 columns.
--    Alberto Dell'Era, August 2007
--    tested in 10.2.0.3, 9.2.0.8

start setenv.sql
start distinctBallsPlSql.sql
set timing off

exec dbms_random.seed(0)

exec execute immediate 'purge recyclebin'; exception when others then null;

spool distinct_exhaustive_mult_columns_2.lst

-- end of initialization section

set echo on

drop table results;

create table results (
  num_rows          int    not null,
  num_distinct_x    int    not null,
  num_distinct_y    int    not null,
  f_num_rows        number not null,
  cbo_card          number not null, 
  frm_card          number not null
);

drop table t purge;

-- max 250
define num_rows_t=50

create table t as
select 1000 as x, 1000 as y, rownum filter from dual connect by level <= &num_rows_t. ;
 
-- create index t_x_y_idx on t (x,y); -- no difference (tested for paper)
-- create index t_y_x_idx on t (y,x); -- no difference (tested for paper)
  
-- collect baseline stats, build an histogram on the "filter" column
exec dbms_stats.gather_table_stats (user, 't', cascade=>true, method_opt => 'for columns x size 1, y size 1, filter size 254', estimate_percent=>100);

drop sequence get_cbo_card_seq;
create sequence get_cbo_card_seq;

alter system flush shared_pool;

-- this procedure parses the statement, and fetches the relevant CBO cardinality
-- estimates from v$sql_plan
create or replace procedure get_cbo_card (
  p_desired_f_num_rows number, 
  p_cbo_card           out number,
  p_f_num_rows         out number
)
is
  l_stmt long;
  l_cursor sys_refcursor;
  l_seq_val int;
  l_address      v$sql.address%type; 
  l_hash_value   v$sql.hash_value%type;  
  l_child_number v$sql.child_number%type;
  l_filter_pred_t varchar2 (1000);
  
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
  l_filter_pred_t := calc_filter_pred (p_desired_f_num_rows);
  
  select get_cbo_card_seq.nextval into l_seq_val from dual;
  --l_stmt := 'select /*+ get_cbo_card_m_tag '|| l_seq_val || ' */  x, y,  count(*) from t where filter '||l_filter_pred_t||' group by x, y';
  l_stmt := 'select /*+ get_cbo_card_m_tag '|| l_seq_val || ' */ distinct x, y from t where filter '||l_filter_pred_t;
  
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
    if r.operation in ('SORT','HASH') and (r.options like 'GROUP BY%' or r.options = 'UNIQUE') then
      p_cbo_card := r.cardinality;
    elsif r.operation in ('TABLE ACCESS','INDEX') then
      p_f_num_rows := r.cardinality;
    end if;
  end loop;
  
  if p_desired_f_num_rows != p_f_num_rows then
    raise_application_error (-20002, 'cannot produce desired f_num_rows='||p_desired_f_num_rows||' p_f_num_rows='||p_f_num_rows); 
  end if;
  
end get_cbo_card;
/
show errors

variable c number
variable f number
exec get_cbo_card (4, :c, :f);
print c
print f

create or replace procedure test
is
  l_cbo_card number;
  l_f_num_rows number;
  l_num_distinct_x number;
  l_num_distinct_y number;
  l_num_rows number;
  l_frm_card number;
  l_frm_card_min number;     
  l_frm_card_max number;
  l_f_num_distinct_x number;     
  l_f_num_distinct_y number;
  l_num_test int := 0;
  l_desired_num_distinct_x number := null;
  l_desired_num_distinct_y number := null;
  l_desired_f_num_rows number := null;
  
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
begin

  select num_rows
    into l_num_rows
    from user_tables
   where table_name = 'T';
   
  loop 
    l_desired_num_distinct_x := get_next (l_desired_num_distinct_x, 1, l_num_rows, 1);
    exit when l_desired_num_distinct_x is null;
  
    update t set x = least (rownum, l_desired_num_distinct_x);
   
    -- refresh statistics of column "x"
    dbms_stats.gather_table_stats (user, 't', cascade => true, method_opt => 'for columns x size 1', estimate_percent => 100);
    
    select num_distinct 
      into l_num_distinct_x
      from user_tab_columns 
     where table_name = 'T'
       and column_name = 'X';
    
    update t set y = 0;
    
    loop
      l_desired_num_distinct_y := get_next (l_desired_num_distinct_y, 1, l_num_rows, 1);
      exit when l_desired_num_distinct_y is null;
    
      update t set y = least (rownum, l_desired_num_distinct_y);
       
      -- refresh statistics of column "y"
      dbms_stats.gather_table_stats (user, 't', cascade => true, method_opt => 'for columns y size 1', estimate_percent => 100);
      
      select num_distinct 
        into l_num_distinct_y
        from user_tab_columns 
       where table_name = 'T'
         and column_name = 'Y';   
    
      loop
        l_desired_f_num_rows := get_next (l_desired_f_num_rows, 1, l_num_rows, 1);
        exit when l_desired_f_num_rows is null;
        
        get_cbo_card (l_desired_f_num_rows, l_cbo_card, l_f_num_rows);
        
        l_f_num_distinct_x := swru ( l_num_distinct_x, l_f_num_rows, l_num_rows );
        l_f_num_distinct_y := swru ( l_num_distinct_y, l_f_num_rows, l_num_rows );
        
        l_frm_card_max := l_f_num_distinct_x * l_f_num_distinct_y;
        
        l_frm_card := ( 1/sqrt(2) ) * ( l_frm_card_max );
        
        -- sanity check: f_num_distinct (T.X, T.Y) cannot be above f_num_rows(T)
        if l_frm_card > l_f_num_rows then
          l_frm_card := l_f_num_rows;
        end if;
        
        -- CBO round()s the final card 
        if 1=1 then
          l_frm_card := round (l_frm_card);
          if l_frm_card < 1 then 
            l_frm_card := 1;
          end if;
        end if;
        
        insert into results (num_rows, num_distinct_x, num_distinct_y, f_num_rows, cbo_card, frm_card)
          values (l_num_rows, l_num_distinct_x, l_num_distinct_y, l_f_num_rows, l_cbo_card, l_frm_card);
        commit;
        
        l_num_test := l_num_test + 1;
        --if mod (l_num_test, 121) = 0 then
        --  execute immediate 'alter system flush shared_pool';
        --end if;
      
      end loop;
    end loop;
  end loop;
end;
/
show errors;

exec test;

select avg ( cbo_card - round(frm_card) ), stddev ( cbo_card - round(frm_card) ), 
       avg ( abs( cbo_card - round(frm_card) ) ), stddev ( abs ( cbo_card - round(frm_card) ) ) from results;
       
-- note: percentage of error has cbo_card as denominator
select avg ( 100 * abs (cbo_card - round(frm_card)) / cbo_card ) perc_error,
       stddev ( 100 * abs (cbo_card - round(frm_card)) / cbo_card ) from results;        

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
