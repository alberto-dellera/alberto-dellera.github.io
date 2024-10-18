--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Shows that the "Selection Without Replacement" formula
--    makes for a significant increase in accuracy in the cardinality estimation.
--    Alberto Dell'Era, August 2007
--    tested in 10.2.0.3, 9.2.0.8

start setenv.sql
start distinctBallsPlSql.sql
set timing off

exec dbms_random.seed(0)

exec execute immediate 'purge recyclebin'; exception when others then null;

spool distinct_swru_relevancy_example.lst

-- end of initialization section

drop table t;

create table t 
as
select trunc(dbms_random.value(0,6000)) as x, 40 + trunc(dbms_random.value(0,20)) as filter
  from dual connect by level <= 100000;
 
exec dbms_stats.gather_table_stats (user, 't', cascade=>true, method_opt => 'for columns x size 1, columns filter size 254', estimate_percent=>100);

select count(*) 
  from (
select distinct x
  from t
 where filter = 42
       );
 
set autotrace traceonly explain
alter session set events '10053 trace name context forever, level 1';

select distinct x
  from t
 where filter = 42;
  
alter session set events '10053 trace name context off';
set autotrace off

select t.table_name, c.column_name, c.num_distinct, c.num_buckets, 
       swru ( c.num_distinct, 5066, t.num_rows ) f_num_distinct
 from user_tab_columns c, user_tables t 
 where t.table_name in ('T')
   and t.table_name = c.table_name
   and c.column_name in ('X')
 order by table_name, column_name;
 
doc
SQL> select count(*)
  2    from (
  3  select distinct x
  4    from t
  5   where filter = 42
  6         );

  COUNT(*)
----------
      3428
      
---------------------------------------------------------------------------
| Id  | Operation          | Name | Rows  | Bytes | Cost (%CPU)| Time     |
---------------------------------------------------------------------------
|   0 | SELECT STATEMENT   |      |  3477 | 20862 |    48  (15)| 00:00:01 |
|   1 |  HASH UNIQUE       |      |  3477 | 20862 |    48  (15)| 00:00:01 |
|*  2 |   TABLE ACCESS FULL| T    |  5066 | 30396 |    46  (11)| 00:00:01 |
---------------------------------------------------------------------------

  swru ( 6000, 5066, 100000) = 3476.81841
  
  % of error = (3477 - 3428) /  3428 = 1.42%
  
#

spool off





