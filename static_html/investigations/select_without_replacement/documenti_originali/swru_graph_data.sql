--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Plots the SWRU formula for illustration purposes.

--    Alberto Dell'Era, August 2007
--    tested in: n/a

start distinctBallsPlSql.sql

set serveroutput on size 100000 format wrapped
set lines 200
set echo on;

create or replace procedure test
is
  num_distinct number := 100;
  type num_array_t is table of number index by binary_integer;
  f_num_distinct_perc num_array_t;
  l_line varchar2(200 char);
  num_rows number;
  
  function f (num_distinct number, f_num_rows_perc number, num_rows number)
  return number
  is
  begin
    return 100 * swru (num_distinct, (f_num_rows_perc/100) * num_rows, num_rows) / num_distinct;
  end;
begin
  for f_num_rows_perc in 0..100 loop
  
    num_rows :=  1 * num_distinct;
    f_num_distinct_perc(num_rows) := f (num_distinct, f_num_rows_perc, num_rows);
    
    num_rows :=  2 * num_distinct;
    f_num_distinct_perc(num_rows) := f (num_distinct, f_num_rows_perc, num_rows);
  
    num_rows :=  5 * num_distinct;
    f_num_distinct_perc(num_rows) := f (num_distinct, f_num_rows_perc, num_rows);
    
    num_rows := 30 * num_distinct;
    f_num_distinct_perc(num_rows) := f (num_distinct, f_num_rows_perc, num_rows);
 
    l_line := to_char(round(f_num_rows_perc,2),'9999.99999');
    num_rows := f_num_distinct_perc.first;
    loop
      exit when num_rows is null;
      l_line := l_line || ' '|| to_char(round(f_num_distinct_perc (num_rows),5), '9999.99999');
      num_rows := f_num_distinct_perc.next (num_rows);
    end loop;
    dbms_output.put_line (l_line);
  end loop;
end;
/
show errors;

set echo off
set feedback off
spool data.dat
exec test;
spool off

exit
