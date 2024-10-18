-- Supporting code for the "New Density calculation in 11g" paper (www.adellera.it).
-- 
-- This test case suggests that using the HB NewDensity formula for 
-- Frequency Histograms too can significantly improve the cardinality estimation
-- in the important scenario of joins over a (logical) FK relation and
-- be resilient to small (logical) constraint violations.
--
-- (c) Alberto Dell'Era, November 2007
-- Tested in 11.1.0.6.

set echo on
set lines 150
set pages 9999
set serveroutput on size 1000000

col table_name form a11
col column_name form a11
col histogram form a15

drop table child;
drop table parent;

spool 11g_NewDensity_frequency_HBformula_is_better.lst

-- parent table with 100 unique values 
create table parent as select rownum-1 value from dual connect by level <= 100;
-- child table with the same 100 distinct values 
create table child  as select mod(rownum-1,100) value from dual connect by level <= 1000;

-- stats
exec dbms_stats.gather_table_stats (user, 'parent', method_opt=>'for all columns size 254', estimate_percent=>null);
exec dbms_stats.gather_table_stats (user, 'child' , method_opt=>'for all columns size 254', estimate_percent=>null);

select table_name, column_name, histogram from user_tab_columns where table_name in ('PARENT','CHILD') order by 1,2;
doc
  TABLE_NAME  COLUMN_NAME HISTOGRAM
  ----------- ----------- ---------------
  CHILD       VALUE       FREQUENCY
  PARENT      VALUE       HEIGHT BALANCED
  
  An histogram on unique values is considered an Height-Balanced one
#

-- join on parent, child. 
set autotrace on
select count(*) from parent, child where parent.value = child.value; 
set autotrace off

doc

    COUNT(*)
  ----------
        1000
      
  ----------------------------------------------
  | Id  | Operation           | Name   | Rows  |
  ----------------------------------------------
  |   0 | SELECT STATEMENT    |        |     1 |
  |   1 |  SORT AGGREGATE     |        |     1 |
  |*  2 |   HASH JOIN         |        |  1001 |
  |   3 |    TABLE ACCESS FULL| PARENT |   100 |
  |   4 |    TABLE ACCESS FULL| CHILD  |  1000 |
  ----------------------------------------------

  Note: fantastic cardinality estimation.  
#

-- let's introduce a single violation of the parent uniqueness
insert into parent (value) values (1000);
insert into parent (value) values (1000);
exec dbms_stats.gather_table_stats (user, 'parent', method_opt=>'for all columns size 254', estimate_percent=>null);

select table_name, column_name, histogram from user_tab_columns where table_name in ('PARENT','CHILD') order by 1,2;
doc
  TABLE_NAME  COLUMN_NAME HISTOGRAM
  ----------- ----------- ---------------
  CHILD       VALUE       FREQUENCY
  PARENT      VALUE       FREQUENCY
#

set autotrace on
select count(*) from parent, child where parent.value = child.value; 
set autotrace off

doc

    COUNT(*)
  ----------
        1000

  ----------------------------------------------
  | Id  | Operation           | Name   | Rows  |
  ----------------------------------------------
  |   0 | SELECT STATEMENT    |        |     1 |
  |   1 |  SORT AGGREGATE     |        |     1 |
  |*  2 |   HASH JOIN         |        |   506 |
  |   3 |    TABLE ACCESS FULL| PARENT |   102 |
  |   4 |    TABLE ACCESS FULL| CHILD  |  1000 |
  ----------------------------------------------
  
  Note: poor estimation (half the real cardinality)
#

-- a utility procedure to change density, preserving the histogram
create or replace procedure set_density (
  p_table_name  varchar2,
  p_column_name varchar2,
  p_new_density number
)
is
  l_distcnt number;
  l_density number;
  l_nullcnt number;
  l_srec    dbms_stats.statrec;
  l_avgclen number;
begin
  -- get the current column statistics
  dbms_stats.get_column_stats (
    ownname => user,
    tabname => p_table_name,
    colname => p_column_name,
    distcnt => l_distcnt,
    density => l_density,
    nullcnt => l_nullcnt,
    srec    => l_srec,
    avgclen => l_avgclen
  );

  -- reset them, overwriting "density"
  dbms_stats.set_column_stats (
    ownname => user,
    tabname => p_table_name,
    colname => p_column_name,
    distcnt => l_distcnt,
    density => p_new_density,
    nullcnt => l_nullcnt,
    srec    => l_srec,
    avgclen => l_avgclen,
    no_invalidate => false
  );

  dbms_output.put_line ('density of '||p_table_name||'.'||p_column_name||' changed from '||l_density||' to '|| p_new_density);

end set_density;
/
show errors;

-- let's simulate setting NewDensity to 1.0 / num_rows instead of 0.5 / num_rows
-- Note: this is equivalent to ignoring the histogram type and using always the
-- formula used for Height-Balanced histogram, since the output of the latter
-- is always 1.0 / num_rows when applied to Frequency Histograms.
col num_rows new_value num_rows
select num_rows from user_tables where table_name = 'PARENT';
exec set_density ('PARENT', 'VALUE', 1.0 / &num_rows. );

select table_name, column_name, histogram from user_tab_columns where table_name in ('PARENT','CHILD') order by 1,2;
doc
  TABLE_NAME  COLUMN_NAME HISTOGRAM
  ----------- ----------- ---------------
  CHILD       VALUE       FREQUENCY
  PARENT      VALUE       FREQUENCY
#

alter session set "_optimizer_enable_density_improvements"=false;

set autotrace on
select count(*) from parent, child where parent.value = child.value; 
set autotrace off

alter session set "_optimizer_enable_density_improvements"=true;

doc

       COUNT(*)
  ----------
        1000

  ----------------------------------------------
  | Id  | Operation           | Name   | Rows  |
  ----------------------------------------------
  |   0 | SELECT STATEMENT    |        |     1 |
  |   1 |  SORT AGGREGATE     |        |     1 |
  |*  2 |   HASH JOIN         |        |  1011 |
  |   3 |    TABLE ACCESS FULL| PARENT |   102 |
  |   4 |    TABLE ACCESS FULL| CHILD  |  1000 |
  ----------------------------------------------
  
  Note: back to excellent estimation.
#

spool off

