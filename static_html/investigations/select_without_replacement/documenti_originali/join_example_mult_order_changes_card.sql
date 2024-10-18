--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Changing the order of two join predicates in a multi-column join statement
--    changes the estimated cardinality.
--
--    Script template from join_card_10.sql by Jonathan Lewis, adapted to the paper terminology
--    and with table data changed.
--
--    Alberto Dell'Era, August 2007
--    tested in 10.2.0.3
--    
--    Alberto Dell'Era, August 2007
--    
--    tested in 10.2.0.3, 9.2.0.8

start setenv
set timing off

execute dbms_random.seed(0)

drop table t2;
drop table t1;

begin
	execute immediate 'purge recyclebin';
exception
	when others then null;
end;
/


begin
	execute immediate 'execute dbms_stats.delete_system_stats';
exception
	when others then null;
end;
/

create table t1 
as
with generator as (
	select	--+ materialize
		rownum 	id
	from	all_objects 
	where	rownum <= 3000
)
select
	/*+ ordered use_nl(v2) */
	trunc(dbms_random.value(0,  100 ))		filter,
	trunc(dbms_random.value(0,   20 ))		x, -- orig:20
	trunc(dbms_random.value(0,   20 ))		y, -- orig:20
	lpad(rownum,10)					v1,
	rpad('x',100)					padding
from
	generator	v1,
	generator	v2
where
	rownum <= 10000
;

create table t2
as
with generator as (
	select	--+ materialize
		rownum 	id
	from	all_objects 
	where	rownum <= 3000
)
select
	/*+ ordered use_nl(v2) */
	trunc(dbms_random.value(0,  100 ))		filter,
	trunc(dbms_random.value(0,  100 ))		x, -- orig:100
	trunc(dbms_random.value(0,  390 ))		y, -- orig:390
	lpad(rownum,10)					v1,
	rpad('x',100)					padding
from
	generator	v1,
	generator	v2
where
	rownum <= 10000
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


spool join_example_mult_order_changes_card.lst

-- this is to prevent the 10g "multi-column join key sanity check" from masking the bug
alter session set "_optimizer_join_sel_sanity_check"=false;

--alter session set events '10053 trace name context forever, level 1';
set autotrace traceonly explain

prompt x first; card = 781 = 100 * 10000 / 64 / 20 [considers F_NUM_DISTINCT (t2.x) = 64 (rounded) ]

select
	t1.v1, t2.v1
from
	t1, t2
where   t2.x = t1.x 
and	t2.y = t1.y
-- and	t1.filter = 10
and	t2.filter = 10
;


doc
---------------------------------------------------------------------------
| Id  | Operation          | Name | Rows  | Bytes | Cost (%CPU)| Time     |
---------------------------------------------------------------------------
|   0 | SELECT STATEMENT   |      |   781 | 29678 |    88   (3)| 00:00:02 |
|*  1 |  HASH JOIN         |      |   781 | 29678 |    88   (3)| 00:00:02 |
|*  2 |   TABLE ACCESS FULL| T2   |   100 |  2100 |    44   (3)| 00:00:01 |
|   3 |   TABLE ACCESS FULL| T1   | 10000 |   166K|    44   (3)| 00:00:01 |
---------------------------------------------------------------------------
#

prompt y first; card = 562 = 100 * 10000 / 89 / 20 [considers F_NUM_DISTINCT (t2.y) = 89 (rounded) ]

select
	t1.v1, t2.v1
from
	t1, t2
where   t2.y = t1.y --swap
and	t2.x = t1.x --swap
-- and	t1.filter = 10
and	t2.filter = 10
;

doc
---------------------------------------------------------------------------
| Id  | Operation          | Name | Rows  | Bytes | Cost (%CPU)| Time     |
---------------------------------------------------------------------------
|   0 | SELECT STATEMENT   |      |   562 | 21356 |    88   (3)| 00:00:02 |
|*  1 |  HASH JOIN         |      |   562 | 21356 |    88   (3)| 00:00:02 |
|*  2 |   TABLE ACCESS FULL| T2   |   100 |  2100 |    44   (3)| 00:00:01 |
|   3 |   TABLE ACCESS FULL| T1   | 10000 |   166K|    44   (3)| 00:00:01 |
---------------------------------------------------------------------------
#

set autotrace off
alter session set events '10053 trace name context off';

select t.table_name, c.column_name, c.num_distinct, 
       swru ( c.num_distinct, decode (c.table_name, 'T2', 100, t.num_rows), t.num_rows ) f_num_distinct
 from user_tab_columns c, user_tables t 
 where t.table_name in ('T1','T2')
   and t.table_name = c.table_name
   and c.column_name in ('X', 'Y')
 order by table_name, column_name;
 
select 'T1' table_name, min(x), max (x), min (y), max (y) from t1;
select 'T2' table_name, min(x), max (x), min (y), max (y) from t2;

doc 
TABLE_NAME           COLUMN_NAME          NUM_DISTINCT F_NUM_DISTINCT
-------------------- -------------------- ------------ --------------
T1                   X                          20             20
T1                   Y                          20             20
T2                   X                         100     63.5805485
T2                   Y                         390     88.6905667

TABLE_NAME           MIN(X)     MAX(X)     MIN(Y)     MAX(Y)
-------------------- ---------- ---------- ---------- ----------
T1                            0         19          0         19
T2                            0         99          0        389

== first join order (t2.x = t1.x, then t2.y = t1.y)

   -- join on first join predicate [ t2.x = t1.x ]
     f_num_distinct (t1.x) = swru (   20, 10000, 10000) = 20
     f_num_distinct (t2.x) = swru (  100,   100, 10000) = 63.5805485
     join_sel_x = 1 / ceil (greatest (20, 63.5805485) = 1 / 64
   -- join on second join predicate [ t2.y = t1.y ]
   -- join pred selectivity (coming from first join predicate) 
     interval [ 0, 19 ] is contained in [ 0, 99 ]
     first_pred_sel ( t1.y ) = 1
     first_pred_sel ( t2.y ) = (19-0)/(99-0) = 19 / 99
     f_num_distinct (t1.y) = swru (  20, 10000 * 1      , 10000) =  20
     f_num_distinct (t2.y) = swru ( 390,   100 * 19 / 99, 10000) =  18.7673466
     join_sel_y = 1 / ceil (greatest (20, 18.7673466) = 1 / 20
   
     join card = round ( 100*10000 * (1 / 64) * (1 / 20) ) =  round ( 781.25 ) = 781 (as required)

== second join order (t2.y = t1.y, then t2.x = t1.x)
   -- join on first join predicate [ t2.y = t1.y ]
     f_num_distinct (t1.y) = swru (   20, 10000, 10000) = 20
     f_num_distinct (t2.y) = swru (  390,   100, 10000) = 88.6905667
     join_sel_y = 1 / ceil (greatest (20, 88.6905667) = 1 / 89
   -- join on second join predicate [ t2.x = t1.x ]
   -- join pred selectivity (coming from first join predicate) 
     interval [ 0, 19 ] is contained in [ 0, 389 ]
     first_pred_sel ( t1.x ) = 1
     first_pred_sel ( t2.x ) = (19-0)/(389-0) = 19 / 389
     f_num_distinct (t1.x) = swru (  20, 10000 * 1       , 10000) =  20
     f_num_distinct (t2.x) = swru ( 100,   100 * 19 / 389, 10000) =   4.79127781
     join_sel_x = 1 / ceil (greatest (20, 4.79127781) = 1 / 20
   
     join card = round ( 100*10000 * (1 / 89) * (1 / 20) ) =  round (  561.797753 ) = 562 (as required)
#

spool off


