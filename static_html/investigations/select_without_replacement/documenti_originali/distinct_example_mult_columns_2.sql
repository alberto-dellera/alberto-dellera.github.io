--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Example of the use of the "Selection Without Replacement" formula
--    for the distinct case, multiple-columns, 2 columns.
--    Alberto Dell'Era, August 2007
--    tested in 10.2.0.3, 9.2.0.8

start setenv.sql
start distinctBallsPlSql.sql
set timing off

exec dbms_random.seed(0)

exec execute immediate 'purge recyclebin'; exception when others then null;

spool distinct_example_mult_columns_2.lst

-- end of initialization section

drop table t;

create table t 
as
select mod(rownum-1, 8) as x, mod(rownum-1,6) as y, 40 + mod (rownum-1, 90) as filter
  from dual connect by level <= 10000;
 
exec dbms_stats.gather_table_stats (user, 't', cascade=>true, method_opt => 'for columns x size 1, columns y size 1, columns filter size 254', estimate_percent=>100);

alter session set events '10053 trace name context forever, level 1';
set autotrace traceonly explain
select distinct x, y
  from t
 where filter in (42);
set autotrace off
alter session set events '10053 trace name context off';

select t.table_name, c.column_name, c.num_distinct, c.num_buckets, 
       swru ( c.num_distinct, 112, t.num_rows ) f_num_distinct
 from user_tab_columns c, user_tables t 
 where t.table_name in ('T')
   and t.table_name = c.table_name
   and c.column_name in ('X', 'Y')
 order by table_name, column_name;
 
doc
---------------------------------------------------------------------------
| Id  | Operation          | Name | Rows  | Bytes | Cost (%CPU)| Time     |
---------------------------------------------------------------------------
|   0 | SELECT STATEMENT   |      |    34 |   306 |     8  (13)| 00:00:01 |
|   1 |  HASH UNIQUE       |      |    34 |   306 |     8  (13)| 00:00:01 |
|*  2 |   TABLE ACCESS FULL| T    |   112 |  1008 |     7   (0)| 00:00:01 |
---------------------------------------------------------------------------

TABLE_NAME           COLUMN_NAME          NUM_DISTINCT NUM_BUCKETS F_NUM_DISTINCT
-------------------- -------------------- ------------ ----------- --------------
T                    X                               8           1     7.99999766
T                    Y                               6           1     5.99999999

  f_num_distinct (t.x) = swru ( 8, 112, 10000) = 7.99999766
  f_num_distinct (t.y) = swru ( 6, 112, 10000) = 5.99999999
  (1/sqrt(2)) * f_num_distinct (t.x) * f_num_distinct (t.y) = 
  (1/sqrt(2)) * 7.99999766 * 5.99999999 = 33.9411155 (rounded to 34, as required)
  
  note that it is less than num_distinct (t.x) * num_distinct (t.y) = 48
#

spool off





