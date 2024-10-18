--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Exhaustive check of the "Selection Without Replacement" formula
--    for the distinct case, single-column.
--    Alberto Dell'Era, August 2007
--    tested in 10.2.0.3, 9.2.0.8

start setenv.sql
start distinctBallsPlSql.sql
set timing off

exec dbms_random.seed(0)

exec execute immediate 'purge recyclebin'; exception when others then null;

spool distinct_exhaustive_single_column.lst

-- end of initialization section

drop table results;

create table results (
  num_rows          int    not null,
  num_distinct_x    int    not null,
  f_num_rows        number not null,
  f_num_distinct    number not null,
  cbo_card          number not null, 
  frm_card          number not null
);

drop table t;

-- max 250
define num_rows_t=250
 
create table t as
select 1000 x, rownum filter from dual connect by level <= &num_rows_t. ;

-- create index t_filter_x_idx on t (filter, x); no difference (tested for paper)
-- create index t_x_filter_idx on t (x, filter); no difference (tested for paper)

-- collect baseline stats, build an histogram on the "filter" column
exec dbms_stats.gather_table_stats (user, 't', cascade=>true, method_opt => 'for columns x size 1, columns filter size 254', estimate_percent=>100);

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
  l_remainder int;
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
  -- l_stmt := 'select /*+ get_cbo_card_tag '|| l_seq_val || ' */  x, count(*) from t where filter '||l_filter_pred_t||' group by x';
  l_stmt := 'select /*+ get_cbo_card_tag '|| l_seq_val || ' */  distinct x from t where filter '||l_filter_pred_t; 
 
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
    raise_application_error (-20002, 'cannot produce desired f_num_rows='||p_desired_f_num_rows||': p_f_num_rows='||p_f_num_rows); 
  end if;
  
end get_cbo_card;
/
show errors

create or replace procedure test
is
  l_cbo_card       number;
  l_frm_card       number;
  l_f_num_rows     number;
  l_num_distinct_x number;
  l_f_num_distinct number;
  l_num_rows       number;
begin

  select num_rows
    into l_num_rows
    from user_tables
   where table_name = 'T';
   
  update t set x = 0;

  for l_i in 0 .. l_num_rows-1 loop
  
    -- increase num_distinct (x) by one at every iteration
    if l_i > 0 then
      update t set x = l_i where x = 0 and rownum = 1;
    end if;
    
    -- refresh statistics of column "x"
    --dbms_stats.gather_table_stats (user, 't', cascade => true, method_opt => 'for columns x size 254', estimate_percent => 100); -- no difference (tested for paper)
    -- dbms_stats.gather_table_stats (user, 't', cascade => true, method_opt => 'for columns x size 4', estimate_percent => 100); -- no difference (tested for paper)
    dbms_stats.gather_table_stats (user, 't', cascade => true, method_opt => 'for columns x size 1', estimate_percent => 100);
    
    select num_distinct 
      into l_num_distinct_x
      from user_tab_columns 
     where table_name = 'T'
       and column_name = 'X';
  
    for desired_f_num_rows in 1 .. l_num_rows loop
    
      -- increase the filtered cardinality at every iteration
      get_cbo_card (desired_f_num_rows, l_cbo_card, l_f_num_rows);
      
      l_f_num_distinct := swru (l_num_distinct_x, l_f_num_rows, l_num_rows );
      l_frm_card := l_f_num_distinct;
      
      -- CBO round()s the final card 
      if 1=1 then
        l_frm_card := round (l_frm_card);
        if l_frm_card < 1 then 
          l_frm_card := 1;
        end if;
      end if;
      
      insert into results (num_rows, num_distinct_x, f_num_rows, f_num_distinct, cbo_card, frm_card)
        values (l_num_rows, l_num_distinct_x,  l_f_num_rows, l_f_num_distinct, l_cbo_card, l_frm_card);
      commit;
    
    end loop;
    
  end loop;
end;
/
show errors;

exec test;

-- select * from results where abs (cbo_card - frm_card) > 1 order by 1,2,3;
  
select avg ( cbo_card - round(frm_card) ), stddev ( cbo_card - round(frm_card) ), 
       avg ( abs( cbo_card - round(frm_card) ) ), stddev ( abs ( cbo_card - round(frm_card) ) ) from results;
       
-- note: percentage of error has frm_card as denominator
select avg ( 100 * abs (cbo_card - round(frm_card)) / round(frm_card) ) perc_error,
       stddev ( 100 * abs (cbo_card - round(frm_card)) / round(frm_card) ) from results;  

-- test Yao's formula
col perc form 99.99
col perc_cum form 999.99 
select r2.*, trunc (100 * cnt_ratio, 2) as yao_perc,
             trunc (100 * sum(cnt_ratio) over (order by abs_error), 2) as yao_perc_cum
  from (
select r.*, ratio_to_report (cnt) over() cnt_ratio
  from (
select abs (greatest(1,round(yao (num_distinct_x,f_num_rows,num_rows)))-cbo_card)  as abs_error, count(*) cnt
  from results
 group by abs (greatest(1,round(yao (num_distinct_x,f_num_rows,num_rows)))-cbo_card) 
       ) r
       ) r2
 order by 1;
 
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
 
doc

Results (identical in 9.2.0.8 and 10.2.0.3):

SQL> -- select * from results where abs (cbo_card - frm_card) > 1 order by 1,2,3;
SQL>
SQL> select avg ( cbo_card - round(frm_card) ), stddev ( cbo_card - round(frm_card) ),
  2         avg ( abs( cbo_card - round(frm_card) ) ), stddev ( abs ( cbo_card - round(frm_card) ) ) from results;

AVG(CBO_CARD-ROUND(FRM_CARD)) STDDEV(CBO_CARD-ROUND(FRM_CARD)) AVG(ABS(CBO_CARD-ROUND(FRM_CARD))) STDDEV(ABS(CBO_CARD-ROUND(FRM_CARD)))
----------------------------- -------------------------------- ---------------------------------- -------------------------------------
                     1.030832                       1.55549095                           1.048368                            1.54372623

SQL> -- note: percentage of error has frm_card as denominator
SQL> select avg ( 100 * abs (cbo_card - round(frm_card)) / round(frm_card) ) perc_error,
  2         stddev ( 100 * abs (cbo_card - round(frm_card)) / round(frm_card) ) from results;

PERC_ERROR STDDEV(100*ABS(CBO_CARD-ROUND(FRM_CARD))/ROUND(FRM_CARD))
---------- ---------------------------------------------------------
.944848617                                                1.30721593

SQL> -- test Yao's formula
SQL> col perc form 99.99
SQL> col perc_cum form 999.99
SQL> select r2.*, trunc (100 * cnt_ratio, 2) as yao_perc,
  2               trunc (100 * sum(cnt_ratio) over (order by abs_error), 2) as yao_perc_cum
  3    from (
  4  select r.*, ratio_to_report (cnt) over() cnt_ratio
  5    from (
  6  select abs (greatest(1,round(yao (num_distinct_x,f_num_rows,num_rows)))-cbo_card)  as abs_error, count(*) cnt
  7    from results
  8   group by abs (greatest(1,round(yao (num_distinct_x,f_num_rows,num_rows)))-cbo_card)
  9         ) r
 10         ) r2
 11   order by 1;

 ABS_ERROR        CNT  CNT_RATIO   YAO_PERC YAO_PERC_CUM
---------- ---------- ---------- ---------- ------------
         0      58968    .943488      94.34        94.34
         1       3532    .056512       5.65          100

SQL> -- test exact formula
SQL> col perc form 99.99
SQL> col perc_cum form 999.99
SQL> select r2.*, trunc (100 * cnt_ratio, 2) as perc,
  2               trunc (100 * sum(cnt_ratio) over (order by abs_error), 2) as perc_cum
  3    from (
  4  select r.*, ratio_to_report (cnt) over() cnt_ratio
  5    from (
  6  select round (abs (cbo_card - round(frm_card)), 1) as abs_error, count(*) cnt
  7    from results
  8   group by round (abs (cbo_card - round(frm_card)), 1)
  9         ) r
 10         ) r2
 11   order by 1;

 ABS_ERROR        CNT  CNT_RATIO   PERC PERC_CUM
---------- ---------- ---------- ------ --------
         0      35043    .560688  56.06    56.06
         1      11587    .185392  18.53    74.60
         2       4813    .077008   7.70    82.30
         3       4007    .064112   6.41    88.72
         4       3526    .056416   5.64    94.36
         5       2959    .047344   4.73    99.09
         6        565     .00904    .90   100.00

SQL> select count(*) from results;

  COUNT(*)
----------
     62500
#
 
spool off 

