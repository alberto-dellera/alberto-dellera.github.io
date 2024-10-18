-- fitness test for pl/sql implementation of "ranges formula"


@range_sel_formula.sql

set echo on
set serverouput on size 1000000 format wrapped


create or replace procedure range_sel_formula_check (
  p_table_name  varchar2,
  p_column_name varchar2)
as
  l_table_name  varchar2(30) := upper (p_table_name);
  l_column_name varchar2(30) := upper (p_column_name);
  l_num_rows         number;
  l_num_distinct     number;
  l_endpoint_num     number;
  l_min_x            number;
  l_max_x            number;
  l_B                number;

  type range_sel_number_list is table of number      index by binary_integer;
 
  l_x_points range_sel_number_list;
  l_#low_idx    int;
  l_#high_idx   int;
  l_low_x_idx   int;
  l_high_x_idx  int;
  l_#low        varchar2(2);
  l_#high       varchar2(2);
  l_low_x       number;
  l_high_x      number;
  l_stmt        varchar2(200);
  l_card_f      number;
  l_cardinality number;
  l_num_checked number := 0;
begin
  select num_rows
    into l_num_rows
    from user_tables
   where table_name = l_table_name;
   
  select min (endpoint_value), max (endpoint_value), count(*)
    into l_min_x, l_max_x, l_endpoint_num
    from user_tab_histograms
   where table_name = l_table_name
     and column_name = l_column_name;

  if l_endpoint_num != 2 then
    raise_application_error (-20001, 'wrong number of endpoints: '||l_endpoint_num);
  end if;

  select num_distinct
    into l_num_distinct
    from user_tab_columns
   where table_name = l_table_name
     and column_name = l_column_name;

  l_B := (l_max_x - l_min_x) / l_num_distinct;

  l_x_points( 0) := l_min_x;
  l_x_points( 1) := l_min_x + 1e-3;
  l_x_points( 2) := l_min_x + l_B / 2;
  l_x_points( 3) := l_min_x + l_B - 1e-3;
  l_x_points( 4) := l_min_x + l_B;
  l_x_points( 5) := l_min_x + l_B + 1e-3;
  l_x_points( 6) := l_min_x + l_B + 0.21 * (l_max_x - l_min_x - 2*l_B);
  l_x_points( 7) := l_min_x + l_B + 0.81 * (l_max_x - l_min_x - 2*l_B);
  l_x_points( 8) := l_max_x - l_B - 1e-3;
  l_x_points( 9) := l_max_x - l_B;
  l_x_points(10) := l_max_x - l_B + 1e-3;
  l_x_points(11) := l_max_x - l_B + l_B / 2;
  l_x_points(12) := l_max_x - 1e-3;
  l_x_points(13) := l_max_x;

  for l_#low_idx in 0..1 loop
    l_#low := case when l_#low_idx = 0 then '>' else '>=' end;
    for l_#high_idx in 0..1 loop
      l_#high := case when l_#high_idx = 0 then '<' else '<=' end;
      for l_low_x_idx in l_x_points.first .. l_x_points.last loop
        l_low_x := l_x_points (l_low_x_idx);
        for l_high_x_idx in l_x_points.first .. l_x_points.last loop
        l_high_x := l_x_points (l_high_x_idx);
        if l_low_x < l_high_x then 
          delete from plan_table;
          l_stmt := 'explain plan for '
            || 'select x from t'
            || ' where x ' || l_#low  || ' ' || l_low_x
            || '   and x ' || l_#high || ' ' || l_high_x;
          dbms_output.put_line (l_stmt);
          execute immediate l_stmt;
    
          select cardinality
            into l_cardinality
            from plan_table
           where operation = 'SELECT STATEMENT';
          
          commit;

          l_card_f := range_sel_formula (l_#low, l_low_x, l_#high, l_high_x, 
                                         l_min_x, l_max_x, l_num_rows, l_num_distinct);          
         
          if l_card_f not in (-10,-11) -- -10 or -11 signals "not implemented" for ranges completely in bands
             and abs (l_card_f - l_cardinality) > 1
          then
            raise_application_error (-20010, 'failed '||l_stmt||'; formula='||l_card_f||' actual='||l_cardinality);
          end if;

          l_num_checked := l_num_checked + 1;
        end if;
        end loop;
      end loop;
    end loop;
  end loop;  

  dbms_output.put_line ('checked combinations: '||l_num_checked);
end range_sel_formula_check;
/
show errors;

-- check with not-whole numbers
drop table t;

create table t as select decode (mod (rownum-1, 3), 0, -1.937, 1, 0.122, 2, +12.1853) x from dual connect by level <= 1000000;

exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);

exec range_sel_formula_check ('t', 'x');

-- check discussion cases

drop table t;

create table t as select 10 * mod (rownum-1, 2) x from dual connect by level <= 2000000;

exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);

exec range_sel_formula_check ('t', 'x');

-- add a third distinct value
insert /*+ append */ into t(x) select 6.1 from dual connect by level <= 1000000;
commit;

exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);

exec range_sel_formula_check ('t', 'x');

-- add a fourth distinct value
insert /*+ append */ into t(x) select 7.42 from dual connect by level <= 1000000;
commit;
exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);

exec range_sel_formula_check ('t', 'x');








