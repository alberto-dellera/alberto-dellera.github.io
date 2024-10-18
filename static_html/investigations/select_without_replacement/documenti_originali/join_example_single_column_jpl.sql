--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Example of the "Selection Without Replacement" formula
--    for the join case, single-column. 
--
--    Original script from Jonathan Lewis, adapted to the paper terminology.
--
--    Alberto Dell'Era, August 2007
--    tested in 10.2.0.3, 9.2.0.8

start distinctBallsPlSql.sql

rem
rem	Script:		join_card_01a.sql
rem	Author:		Jonathan Lewis
rem	Dated:		Sep 2004
rem	Purpose:	Example for "Cost Based Oracle"
rem
rem	Last tested:
rem		10.1.0.4
rem		 9.2.0.6
rem		 8.1.7.4
rem
rem	First special case of breaking the rules
rem	What if we have a filter predicate on just
rem	one side of the join ?
rem

start setenv
set timing off

define t1f0 = 100
define t1j1 = 30

define t2f0 = 100
define t2j1 = 40

execute dbms_random.seed(0)

drop table t2;
drop table t1;

begin
	begin		execute immediate 'purge recyclebin';
	exception	when others then null;
	end;

	begin		execute immediate 'begin dbms_stats.delete_system_stats; end;';
	exception 	when others then null;
	end;

	begin		execute immediate 'alter session set "_optimizer_cost_model"=io';
	exception	when others then null;
	end;

end;
/


create table t1 
as
select
	trunc(dbms_random.value(0, &t1f0 ))	filter,
	trunc(dbms_random.value(0, &t1j1 ))	x,
	lpad(rownum,10)				v1,
	rpad('x',100)				padding
from
	all_objects
where 
	rownum <= 1000
;


create table t2
as
select
	trunc(dbms_random.value(0, &t2f0 ))	filter,
	trunc(dbms_random.value(0, &t2j1 ))	x,
	lpad(rownum,10)				v1,
	rpad('x',100)				padding
from
	all_objects
where
	rownum <= 1000
;


begin
	dbms_stats.gather_table_stats(
		user,
		't1',
		cascade => true,
		estimate_percent => null,
		method_opt => 'for all columns size 1'
	);
end;
/

begin
	dbms_stats.gather_table_stats(
		user,
		't2',
		cascade => true,
		estimate_percent => null,
		method_opt => 'for all columns size 1'
	);
end;
/


spool join_example_single_column_jpl.lst

set autotrace traceonly explain

rem	alter session set events '10053 trace name context forever';
/*
prompt	Join condition: t2.x = t1.x
prompt	Filter on just T1

select	t1.v1, t2.v1
from
	t1,
	t2
where
	t2.x = t1.x
and	t1.filter = 1
;
*/

prompt	Join condition: t2.x = t1.x
prompt	Filter on just T2

select	t1.v1, t2.v1
from
	t1,
	t2
where
	t2.x = t1.x
and	t2.filter = 1
;

alter session set events '10053 trace name context off';

set autotrace off

select t.table_name, c.column_name, c.num_distinct, c.num_buckets, 
       swru ( c.num_distinct, decode (c.table_name, 'T1', t.num_rows, 'T2', 10), t.num_rows ) f_num_distinct
 from user_tab_columns c, user_tables t 
 where t.table_name in ('T1','T2')
   and t.table_name = c.table_name
   and c.column_name in ('X')
 order by table_name, column_name;
 
doc
-----------------------------------------------------------
| Id  | Operation          | Name | Rows  | Bytes | Cost  |
-----------------------------------------------------------
|   0 | SELECT STATEMENT   |      |   333 | 10323 |     9 |
|*  1 |  HASH JOIN         |      |   333 | 10323 |     9 |
|*  2 |   TABLE ACCESS FULL| T2   |    10 |   170 |     4 |
|   3 |   TABLE ACCESS FULL| T1   |  1000 | 14000 |     4 |
-----------------------------------------------------------

TABLE_NAME           COLUMN_NAME          NUM_DISTINCT NUM_BUCKETS F_NUM_DISTINCT
-------------------- -------------------- ------------ ----------- --------------
T1                   X                              30           1             30
T2                   X                              40           1     8.98285634
 
 f_num_rows (T1) := 1000
 f_num_rows (T2) := 10;

 f_num_distinct (T1.X) = SWRU (num_distinct (T1.X), f_num_rows (T1), num_rows (T1)) = 
                         SWRU ( 30, 1000, 1000 ) = 30;
 f_num_distinct (T2.X) = SWRU (num_distinct (T2.X), f_num_rows (T2), num_rows (T2)) =
                         SWRU ( 40,   10, 1000 ) = 8.98285634;
 join_selectivity = 1 / ceil ( max (f_num_distinct (T1.X), f_num_distinct (T2.X) ) =
                  = 1 / ceil ( max ( 30, 8.98285634 ) ) = 1 / 30;
 join_cardinality = round (f_num_rows (T1) * f_num_rows (T2) * join_selectivity ) =
                  = round ( 1000*10 * 1/30 ) = round ( 333.333333 ) = 333 (as required)


#

spool off


