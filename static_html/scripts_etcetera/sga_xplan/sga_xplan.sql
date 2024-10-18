-- sga_xplan is a package that reads all SQL statements (cursors) 
-- contained in the library cache and that match a like-expression, 
-- and "prints" their plans and statistics.
--
-- The main table infos (columns, indexes, statistics) of all tables
-- referenced in the statements are printed as well, in a compact fashion.
--
-- Peeked bind values and types are printed as well (from v$sql_plan.other_xml)
--
-- An extension of Tom Kyte's "dynamic_plan_table":
-- see "Effective Oracle by Design" by Thomas Kyte, page 91
--
-- install using: @sga_xplan.sql 
-- (see "install notes" below)
--
-- Author: (C) Alberto Dell'Era 2005-2007
--
-- Last tested on 9.2.0.6, 9.2.0.8, 10.2.0.3
--
-- $Id: sga_xplan.sql,v 1.7 2007-08-30 16:08:28 adellera Exp $ (Alberto Dell'Era)
--
--
/* Example of use (work around "explain plan" limitations with bind variables):
   create table sga_xplan_test (x) as select to_char(rownum) from all_objects
   where rownum <= 10000;
   create index sga_xplan_test_idx on sga_xplan_test (x);
   exec dbms_stats.gather_table_stats (user, 'sga_xplan_test', cascade=>true);
   variable x number
   exec :x := 1;
   select x from sga_xplan_test mymarker where x = :x;
   select * from table (sga_xplan.display ('% mymarker %'));
   
======================================================================
module: SQL*Plus, dump_date: 2007/05/04 20:37:40, sql_id: 4xm0td8yybgpn
first_load_time: 2007/05/04 20:37:39, last_load_time: 2007/05/04 20:37:39

select x from sga_xplan_test mymarker where x = :x

peeked binds values: :X = 1
peeked binds types : :X = number(22)
Plan hash value: 2440864970

------------------------------------------------------------------------------------
| Id  | Operation         | Name           | Rows  | Bytes | Cost (%CPU)| Time     | Real Rows(real-estd)
------------------------------------------------------------------------------------
|   0 | SELECT STATEMENT  |                |       |       |     6 (100)|          |
|*  1 |  TABLE ACCESS FULL| SGA_XPLAN_TEST |     1 |     4 |     6   (0)| 00:00:01 |          (      )
------------------------------------------------------------------------------------

Predicate Information (identified by operation id):
---------------------------------------------------

   1 - filter(TO_NUMBER("X")=:X)

sga_xplan warning: plan statistics not available.
--------------------------------- ------------------------------- ----------------------------------------
|v$sql statname  |total |/exec  | |v$sql statname |total |/exec | |v$sql statname          |total |/exec |
--------------------------------- ------------------------------- ----------------------------------------
|executions      |    1 |       | |sorts          |    0 |   .0 | |users_executing         |    0 |   .0 |
|rows_processed  |    1 |   1.0 | |fetches        |    2 |  2.0 | |application wait (usec) |    0 |   .0 |
|buffer_gets     |   20 |  20.0 | |end_of_fetch_c |    1 |  1.0 | |concurrency wait (usec) |    0 |   .0 |
|disk_reads      |    0 |    .0 | |parse_calls    |    1 |  1.0 | |cluster     wait (usec) |    0 |   .0 |
|direct_writes   |    0 |    .0 | |sharable_mem   | 8554 |      | |user io     wait (usec) |    0 |   .0 |
|elapsed (usec)  | 5865 |5865.0 | |persistent_mem | 2352 |      | |plsql exec  wait (usec) |    0 |   .0 |
|cpu_time (usec) | 5865 |5865.0 | |runtime_mem    | 1788 |      | |java  exec  wait (usec) |    0 |   .0 |
--------------------------------- ------------------------------- ----------------------------------------
** table               num_rows blocks empty_blocks avg_row_len sample_size       last_analyzed
dellera.SGA_XPLAN_TEST    10000     20            0           4       10000 2007/05/04 20:37:39
column 1                  ndv density nulls bkts avg_col_len       last_analyzed
X      a  VARCHAR2 (40) 10000   .0001     0    1           5 2007/05/04 20:37:39
- index              distinct_keys num_rows blevel leaf_blocks cluf sample_size       last_analyzed
1 SGA_XPLAN_TEST_IDX         10000    10000      1          23 1849       10000 2007/05/04 20:37:39
======================================================================   

Explain plan "lies":

   explain plan for select x from sga_xplan_test mymarker where x = :x;
   select * from table (dbms_xplan.display ('plan_table',null,'all'));
   
---------------------------------------------------------------------------------------
| Id  | Operation        | Name               | Rows  | Bytes | Cost (%CPU)| Time     |
---------------------------------------------------------------------------------------
|   0 | SELECT STATEMENT |                    |     1 |     4 |     1   (0)| 00:00:01 |
|*  1 |  INDEX RANGE SCAN| SGA_XPLAN_TEST_IDX |     1 |     4 |     1   (0)| 00:00:01 |
---------------------------------------------------------------------------------------

Predicate Information (identified by operation id):
---------------------------------------------------

   1 - access("X"=:X)

Note: cpu costing is off

*/

------ install notes ---------
-- 1) special privileges required for the owner of the install schema to be granted by SYS:
doc
  define sga_xplan_user=dellera
  grant select on sys.v_$sql                     to &sga_xplan_user.;
  grant select on sys.v_$sqltext_with_newlines   to &sga_xplan_user.;
  grant select on sys.v_$sql_plan                to &sga_xplan_user.;
  grant select on sys.v_$sql_plan_statistics     to &sga_xplan_user.;
  grant select on sys.v_$sql_plan_statistics_all to &sga_xplan_user.;
  grant select on sys.dba_tables                 to &sga_xplan_user.;
  grant select on sys.dba_tab_cols               to &sga_xplan_user.;
  grant select on sys.dba_ind_columns            to &sga_xplan_user.;
  grant select on sys.dba_cons_columns           to &sga_xplan_user.;
  grant select on sys.dba_indexes                to &sga_xplan_user.;
  grant select on sys.dba_constraints            to &sga_xplan_user.;
  grant select on sys.dba_objects                to &sga_xplan_user.;
  grant create table                             to &sga_xplan_user.;
  grant create view                              to &sga_xplan_user.;
#
-- 2) install using: @sga_xplan.sql 
--    You will be prompted for the install parameters "public" and "persistent".
--    a) public=y means that the script will create a public synonym for 
--       the package sga_xplan, and grant execute privileges on it to public.
--       This is very convenient but a potential security threat in production,
--       since it may expose some sensitive informations contained
--       in the library cache; so beware.
--    b) persistent=y means that the tables that contains the infos about the
--       plans will be regular tables; persistent=n that they will be 
--       global temporary tables. The former is useful only if you are a very advanced
--       user and want to maintain the history of the plans by dumping them (through the
--       sp dump_plans) and then accessing the history later (through the
--       sp display_dumped_plans), and you don't mind to have to purge the
--       tables sometimes with purge_tables. 
--       In both cases, using the SP display (or print) is safe, since the
--       infos are dumped, the plans displayed, and then purged immediately
--       (without purging other infos dumped by dump_plans, if present).
--       Invoking display (or print) concurrently is always safe, too, whether
--       you're using persistent=y or persistent=n.
-- 3) see the comments in the sga_xplan package header for API documentation.
-- 4) Uninstall: just drop all the objects whose name begins with "SGA_XPLAN"
--    call sga_xplan.generate_uninstall to generate dropping sql statements
------ end of "install notes" --------

spool sga_xplan_install_spool.txt
set serveroutput on size 1000000
set define on
set escape off
set pages 9999
set lines 150
set echo on

set echo off
prompt ======================== install options ==============================
prompt Do you want to grant execute on the sga_xplan package to public ?
prompt This is very convenient, but it may expose some sensitive informations contained
prompt in the library cache to everyone. So beware in production.
prompt You usually want this on a test machine, with some caution on a production machine.
accept input_public char default y prompt "public[y|n, default=y]="
prompt
prompt Do you want persistent tables ? See "install notes" on the head of the script for explanation.
prompt You usually don't want persistent tables unless you're an advanced user.
accept input_persistent char default n prompt "persistent[y|n, default=n]="  
prompt =================== end of install options ============================
set echo on

---- process and check input parameters
whenever sqlerror exit

set verify off
variable public_package  varchar2(1)
variable tables_type     varchar2(100)
variable on_commit       varchar2(100)
declare
  l_public_answer     varchar2(40) := lower (replace ('&input_public.',' ',''));
  l_persistent_answer varchar2(40) := lower (replace ('&input_persistent.',' ',''));
begin
  if    l_public_answer     is null
     or l_public_answer     not in ('y','n','s')  
  then
    raise_application_error (-20001, '"public" should be either y or n');
  end if;
  
  if    l_persistent_answer is null
     or l_persistent_answer not in ('y','n','s')    
  then
    raise_application_error (-20002, '"persistent" should be either y or n');
  end if;
  
  if l_public_answer in ('y','s') then
    :public_package := 'y';
  else
    :public_package := 'n';
  end if;
  
  if l_persistent_answer in ('y','s') then
    :tables_type := ' ';
    :on_commit   := '--';
  else
    :tables_type := 'global temporary';
    :on_commit   := 'on commit preserve rows';
  end if;
  
end;
/
set verify on

print public_package
print tables_type

column tables_type new_value tables_type
column on_commit   new_value on_commit
select :tables_type as tables_type, :on_commit as on_commit from dual;

create or replace package sga_xplan_install as

procedure drop_table_idem (p_table_name varchar2);

procedure create_v_templates;

procedure create_v_adapters;

end sga_xplan_install;
/
show errors;

create or replace package body sga_xplan_install as

procedure drop_table_idem (p_table_name varchar2)
is
  ignore_exc exception;
  pragma exception_init (ignore_exc, -00942);
begin
  execute immediate 'drop table '||p_table_name;
exception 
  when ignore_exc then
    null;
end drop_table_idem;

procedure create_v_template (p_view_name varchar2, p_view_short_name varchar2)
is
  l_template_name varchar2(30) := 'sga_xplan_tpl_' || p_view_short_name;
  l_ddl      long;
  l_col_list long;
begin
 
  for c in (select column_name 
              from dba_tab_cols 
             where table_name = replace (upper(p_view_name), 'V$', 'V_$')
               and data_type not in ('LONG')
             order by column_id)
  loop
    l_col_list := l_col_list || '"' || c.column_name || '",';
  end loop;
  l_col_list := rtrim (l_col_list, ',');
 
  drop_table_idem (l_template_name);
  execute immediate 'create table '||l_template_name||' as select '||l_col_list||' from '||p_view_name;
  
  dbms_output.put_line ('exec sga_xplan_install.drop_table_idem ('''||l_template_name||''');');
  
  dbms_metadata.set_transform_param ( DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', false );
  dbms_metadata.set_transform_param ( DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', false );
  dbms_metadata.set_transform_param ( DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR', true );
  dbms_metadata.set_transform_param ( DBMS_METADATA.SESSION_TRANSFORM, 'PRETTY', false );
  
  select dbms_metadata.get_ddl ('TABLE', upper(l_template_name))
    into l_ddl from dual;
  l_ddl := replace (l_ddl, '"'||user||'".', '');
  l_ddl := replace (l_ddl, chr(10), ' ');
  l_ddl := trim (l_ddl);

  dbms_output.put_line (l_ddl);
end create_v_template;

procedure create_v_templates 
is
begin
  create_v_template ('v$sql'                    , 'v$sql'          );
  create_v_template ('v$sqltext_with_newlines'  , 'v$sqltext_nl'   );
  create_v_template ('v$sql_plan'               , 'v$sql_plan'     );
  --create_v_template ('v$sql_plan_statistics'    , 'v$sql_plan_stat');
  create_v_template ('v$sql_plan_statistics_all', 'v$sql_plan_sall');
  
  create_v_template ('dba_tables'      , 'dba_tables');
  create_v_template ('dba_tab_cols'    , 'dba_tab_cols');
  create_v_template ('dba_ind_columns' , 'dba_ind_columns');
  create_v_template ('dba_cons_columns', 'dba_cons_columns');
  create_v_template ('dba_indexes'     , 'dba_indexes');
  create_v_template ('dba_constraints' , 'dba_constraints');
end create_v_templates;

procedure create_v_adapter (p_view_name varchar2, p_view_short_name varchar2)
is
  l_template_name varchar2(30)     := 'sga_xplan_tpl_' || p_view_short_name;
  l_view_adapter_name varchar2(30) := 'sga_xplan_va_'  || p_view_short_name;
  l_stmt long;
  l_num_cols_found int := 0;
begin
  l_stmt := 'create or replace view '||l_view_adapter_name||' as select ';
  for c in (select tpl.column_name, 
                   decode (v.column_name, null, 'cast (null as varchar2(1))', v.column_name) as v_colname,
                   decode (v.column_name, null, 0, 1) as col_found
              from (select column_name, column_id from all_tab_columns 
                     where owner = 'SYS' and table_name = replace (upper (p_view_name), 'V$', 'V_$')
                   ) v,
                   (select column_name, column_id from user_tab_columns 
                     where table_name = upper (l_template_name)
                   ) tpl
             where tpl.column_name = v.column_name(+)
             order by tpl.column_id
            )
   loop
     if lower (p_view_name) in ('v$sql_plan', 'v$sql_plan_statistics_all') and c.column_name = 'TIMESTAMP' then
       l_stmt := l_stmt || 'sysdate'   || ' "' || c.column_name || '",';
     else
       l_stmt := l_stmt || c.v_colname || ' "' || c.column_name || '",';
     end if;
     l_num_cols_found := l_num_cols_found + c.col_found;
   end loop;
   
   if l_num_cols_found = 0 then
     raise_application_error (-20001, 'no matching columns for '||p_view_short_name||' ('||p_view_name||' not accessible?)');
   end if;
   
   l_stmt := rtrim (l_stmt, ',');
   l_stmt := l_stmt || ' from sys.'|| replace (upper(p_view_name), 'V$', 'V_$');
   
   --dbms_output.put_line (l_stmt || chr(10));
   dbms_output.put_line ('creating '||l_view_adapter_name||' for '||p_view_name);
   execute immediate (l_stmt);
end create_v_adapter;

procedure create_v_adapters 
is
begin
  create_v_adapter ('v$sql'                    , 'v$sql'          );
  create_v_adapter ('v$sqltext_with_newlines'  , 'v$sqltext_nl'   );
  create_v_adapter ('v$sql_plan'               , 'v$sql_plan'     );
  --create_v_adapter ('v$sql_plan_statistics'    , 'v$sql_plan_stat');
  create_v_adapter ('v$sql_plan_statistics_all', 'v$sql_plan_sall');
  
  create_v_adapter ('dba_tables'      , 'dba_tables');
  create_v_adapter ('dba_tab_cols'    , 'dba_tab_cols');
  create_v_adapter ('dba_ind_columns' , 'dba_ind_columns');
  create_v_adapter ('dba_cons_columns', 'dba_cons_columns');
  create_v_adapter ('dba_indexes'     , 'dba_indexes');
  create_v_adapter ('dba_constraints' , 'dba_constraints');
end create_v_adapters;

end sga_xplan_install;
/
show errors;

-- templates for dump tables
-- version of v$sql, v$sql_plan etc for the most current version (currently 10.2.0.3)
-- generated by:
doc
  set serveroutput on size 1000000 
  set head off
  set pages 9999
  set lines 100
  exec sga_xplan_install.create_v_templates;
#

exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_v$sql');
CREATE TABLE "SGA_XPLAN_TPL_V$SQL" ("SQL_TEXT" VARCHAR2(1000), "SQL_FULLTEXT" CLOB, "SQL_ID"
VARCHAR2(13), "SHARABLE_MEM" NUMBER, "PERSISTENT_MEM" NUMBER, "RUNTIME_MEM" NUMBER, "SORTS" NUMBER,
"LOADED_VERSIONS" NUMBER, "OPEN_VERSIONS" NUMBER, "USERS_OPENING" NUMBER, "FETCHES" NUMBER,
"EXECUTIONS" NUMBER, "PX_SERVERS_EXECUTIONS" NUMBER, "END_OF_FETCH_COUNT" NUMBER, "USERS_EXECUTING"
NUMBER, "LOADS" NUMBER, "FIRST_LOAD_TIME" VARCHAR2(76), "INVALIDATIONS" NUMBER, "PARSE_CALLS"
NUMBER, "DISK_READS" NUMBER, "DIRECT_WRITES" NUMBER, "BUFFER_GETS" NUMBER, "APPLICATION_WAIT_TIME"
NUMBER, "CONCURRENCY_WAIT_TIME" NUMBER, "CLUSTER_WAIT_TIME" NUMBER, "USER_IO_WAIT_TIME" NUMBER,
"PLSQL_EXEC_TIME" NUMBER, "JAVA_EXEC_TIME" NUMBER, "ROWS_PROCESSED" NUMBER, "COMMAND_TYPE" NUMBER,
"OPTIMIZER_MODE" VARCHAR2(10), "OPTIMIZER_COST" NUMBER, "OPTIMIZER_ENV" RAW(839),
"OPTIMIZER_ENV_HASH_VALUE" NUMBER, "PARSING_USER_ID" NUMBER, "PARSING_SCHEMA_ID" NUMBER,
"PARSING_SCHEMA_NAME" VARCHAR2(30), "KEPT_VERSIONS" NUMBER, "ADDRESS" RAW(4), "TYPE_CHK_HEAP"
RAW(4), "HASH_VALUE" NUMBER, "OLD_HASH_VALUE" NUMBER, "PLAN_HASH_VALUE" NUMBER, "CHILD_NUMBER"
NUMBER, "SERVICE" VARCHAR2(64), "SERVICE_HASH" NUMBER, "MODULE" VARCHAR2(64), "MODULE_HASH" NUMBER,
"ACTION" VARCHAR2(64), "ACTION_HASH" NUMBER, "SERIALIZABLE_ABORTS" NUMBER, "OUTLINE_CATEGORY"
VARCHAR2(64), "CPU_TIME" NUMBER, "ELAPSED_TIME" NUMBER, "OUTLINE_SID" NUMBER, "CHILD_ADDRESS"
RAW(4), "SQLTYPE" NUMBER, "REMOTE" VARCHAR2(1), "OBJECT_STATUS" VARCHAR2(19), "LITERAL_HASH_VALUE"
NUMBER, "LAST_LOAD_TIME" VARCHAR2(76), "IS_OBSOLETE" VARCHAR2(1), "CHILD_LATCH" NUMBER,
"SQL_PROFILE" VARCHAR2(64), "PROGRAM_ID" NUMBER, "PROGRAM_LINE#" NUMBER, "EXACT_MATCHING_SIGNATURE"
NUMBER, "FORCE_MATCHING_SIGNATURE" NUMBER, "LAST_ACTIVE_TIME" DATE, "BIND_DATA" RAW(2000)) ;

exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_v$sqltext_nl');
CREATE TABLE "SGA_XPLAN_TPL_V$SQLTEXT_NL" ("ADDRESS" RAW(4), "HASH_VALUE" NUMBER, "SQL_ID"
VARCHAR2(13), "COMMAND_TYPE" NUMBER, "PIECE" NUMBER, "SQL_TEXT" VARCHAR2(64)) ;

exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_v$sql_plan');
CREATE TABLE "SGA_XPLAN_TPL_V$SQL_PLAN" ("ADDRESS" RAW(4), "HASH_VALUE" NUMBER, "SQL_ID"
VARCHAR2(13), "PLAN_HASH_VALUE" NUMBER, "CHILD_ADDRESS" RAW(4), "CHILD_NUMBER" NUMBER, "TIMESTAMP"
DATE, "OPERATION" VARCHAR2(120), "OPTIONS" VARCHAR2(120), "OBJECT_NODE" VARCHAR2(160), "OBJECT#"
NUMBER, "OBJECT_OWNER" VARCHAR2(30), "OBJECT_NAME" VARCHAR2(30), "OBJECT_ALIAS" VARCHAR2(65),
"OBJECT_TYPE" VARCHAR2(80), "OPTIMIZER" VARCHAR2(80), "ID" NUMBER, "PARENT_ID" NUMBER, "DEPTH"
NUMBER, "POSITION" NUMBER, "SEARCH_COLUMNS" NUMBER, "COST" NUMBER, "CARDINALITY" NUMBER, "BYTES"
NUMBER, "OTHER_TAG" VARCHAR2(140), "PARTITION_START" VARCHAR2(20), "PARTITION_STOP" VARCHAR2(20),
"PARTITION_ID" NUMBER, "OTHER" VARCHAR2(4000), "DISTRIBUTION" VARCHAR2(80), "CPU_COST" NUMBER,
"IO_COST" NUMBER, "TEMP_SPACE" NUMBER, "ACCESS_PREDICATES" VARCHAR2(4000), "FILTER_PREDICATES"
VARCHAR2(4000), "PROJECTION" VARCHAR2(4000), "TIME" NUMBER, "QBLOCK_NAME" VARCHAR2(30), "REMARKS"
VARCHAR2(4000), "OTHER_XML" CLOB) ;

/*
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_v$sql_plan_stat');
CREATE TABLE "SGA_XPLAN_TPL_V$SQL_PLAN_STAT" ("ADDRESS" RAW(4), "HASH_VALUE" NUMBER, "SQL_ID"
VARCHAR2(13), "PLAN_HASH_VALUE" NUMBER, "CHILD_ADDRESS" RAW(4), "CHILD_NUMBER" NUMBER,
"OPERATION_ID" NUMBER, "EXECUTIONS" NUMBER, "LAST_STARTS" NUMBER, "STARTS" NUMBER,
"LAST_OUTPUT_ROWS" NUMBER, "OUTPUT_ROWS" NUMBER, "LAST_CR_BUFFER_GETS" NUMBER, "CR_BUFFER_GETS"
NUMBER, "LAST_CU_BUFFER_GETS" NUMBER, "CU_BUFFER_GETS" NUMBER, "LAST_DISK_READS" NUMBER,
"DISK_READS" NUMBER, "LAST_DISK_WRITES" NUMBER, "DISK_WRITES" NUMBER, "LAST_ELAPSED_TIME" NUMBER,
"ELAPSED_TIME" NUMBER) ;
*/

exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_v$sql_plan_sall');
CREATE TABLE "SGA_XPLAN_TPL_V$SQL_PLAN_SALL" ("ADDRESS" RAW(4), "HASH_VALUE" NUMBER, "SQL_ID"
VARCHAR2(13), "PLAN_HASH_VALUE" NUMBER, "CHILD_ADDRESS" RAW(4), "CHILD_NUMBER" NUMBER, "TIMESTAMP"
DATE, "OPERATION" VARCHAR2(120), "OPTIONS" VARCHAR2(120), "OBJECT_NODE" VARCHAR2(160), "OBJECT#"
NUMBER, "OBJECT_OWNER" VARCHAR2(30), "OBJECT_NAME" VARCHAR2(30), "OBJECT_ALIAS" VARCHAR2(65),
"OBJECT_TYPE" VARCHAR2(80), "OPTIMIZER" VARCHAR2(80), "ID" NUMBER, "PARENT_ID" NUMBER, "DEPTH"
NUMBER, "POSITION" NUMBER, "SEARCH_COLUMNS" NUMBER, "COST" NUMBER, "CARDINALITY" NUMBER, "BYTES"
NUMBER, "OTHER_TAG" VARCHAR2(140), "PARTITION_START" VARCHAR2(20), "PARTITION_STOP" VARCHAR2(20),
"PARTITION_ID" NUMBER, "OTHER" VARCHAR2(4000), "DISTRIBUTION" VARCHAR2(80), "CPU_COST" NUMBER,
"IO_COST" NUMBER, "TEMP_SPACE" NUMBER, "ACCESS_PREDICATES" VARCHAR2(4000), "FILTER_PREDICATES"
VARCHAR2(4000), "PROJECTION" VARCHAR2(4000), "TIME" NUMBER, "QBLOCK_NAME" VARCHAR2(30), "REMARKS"
VARCHAR2(4000), "OTHER_XML" CLOB, "EXECUTIONS" NUMBER, "LAST_STARTS" NUMBER, "STARTS" NUMBER,
"LAST_OUTPUT_ROWS" NUMBER, "OUTPUT_ROWS" NUMBER, "LAST_CR_BUFFER_GETS" NUMBER, "CR_BUFFER_GETS"
NUMBER, "LAST_CU_BUFFER_GETS" NUMBER, "CU_BUFFER_GETS" NUMBER, "LAST_DISK_READS" NUMBER,
"DISK_READS" NUMBER, "LAST_DISK_WRITES" NUMBER, "DISK_WRITES" NUMBER, "LAST_ELAPSED_TIME" NUMBER,
"ELAPSED_TIME" NUMBER, "POLICY" VARCHAR2(40), "ESTIMATED_OPTIMAL_SIZE" NUMBER,
"ESTIMATED_ONEPASS_SIZE" NUMBER, "LAST_MEMORY_USED" NUMBER, "LAST_EXECUTION" VARCHAR2(40),
"LAST_DEGREE" NUMBER, "TOTAL_EXECUTIONS" NUMBER, "OPTIMAL_EXECUTIONS" NUMBER, "ONEPASS_EXECUTIONS"
NUMBER, "MULTIPASSES_EXECUTIONS" NUMBER, "ACTIVE_TIME" NUMBER, "MAX_TEMPSEG_SIZE" NUMBER,
"LAST_TEMPSEG_SIZE" NUMBER) ;

exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_tables');
CREATE TABLE "SGA_XPLAN_TPL_DBA_TABLES" ("OWNER" VARCHAR2(30) NOT NULL ENABLE, "TABLE_NAME"
VARCHAR2(30) NOT NULL ENABLE, "TABLESPACE_NAME" VARCHAR2(30), "CLUSTER_NAME" VARCHAR2(30),
"IOT_NAME" VARCHAR2(30), "STATUS" VARCHAR2(8), "PCT_FREE" NUMBER, "PCT_USED" NUMBER, "INI_TRANS"
NUMBER, "MAX_TRANS" NUMBER, "INITIAL_EXTENT" NUMBER, "NEXT_EXTENT" NUMBER, "MIN_EXTENTS" NUMBER,
"MAX_EXTENTS" NUMBER, "PCT_INCREASE" NUMBER, "FREELISTS" NUMBER, "FREELIST_GROUPS" NUMBER, "LOGGING"
VARCHAR2(3), "BACKED_UP" VARCHAR2(1), "NUM_ROWS" NUMBER, "BLOCKS" NUMBER, "EMPTY_BLOCKS" NUMBER,
"AVG_SPACE" NUMBER, "CHAIN_CNT" NUMBER, "AVG_ROW_LEN" NUMBER, "AVG_SPACE_FREELIST_BLOCKS" NUMBER,
"NUM_FREELIST_BLOCKS" NUMBER, "DEGREE" VARCHAR2(40), "INSTANCES" VARCHAR2(40), "CACHE" VARCHAR2(20),
"TABLE_LOCK" VARCHAR2(8), "SAMPLE_SIZE" NUMBER, "LAST_ANALYZED" DATE, "PARTITIONED" VARCHAR2(3),
"IOT_TYPE" VARCHAR2(12), "TEMPORARY" VARCHAR2(1), "SECONDARY" VARCHAR2(1), "NESTED" VARCHAR2(3),
"BUFFER_POOL" VARCHAR2(7), "ROW_MOVEMENT" VARCHAR2(8), "GLOBAL_STATS" VARCHAR2(3), "USER_STATS"
VARCHAR2(3), "DURATION" VARCHAR2(15), "SKIP_CORRUPT" VARCHAR2(8), "MONITORING" VARCHAR2(3),
"CLUSTER_OWNER" VARCHAR2(30), "DEPENDENCIES" VARCHAR2(8), "COMPRESSION" VARCHAR2(8), "DROPPED"
VARCHAR2(3)) ;

exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_tab_cols');
CREATE TABLE "SGA_XPLAN_TPL_DBA_TAB_COLS" ("OWNER" VARCHAR2(30) NOT NULL ENABLE, "TABLE_NAME"
VARCHAR2(30) NOT NULL ENABLE, "COLUMN_NAME" VARCHAR2(30) NOT NULL ENABLE, "DATA_TYPE" VARCHAR2(106),
"DATA_TYPE_MOD" VARCHAR2(3), "DATA_TYPE_OWNER" VARCHAR2(30), "DATA_LENGTH" NUMBER NOT NULL ENABLE,
"DATA_PRECISION" NUMBER, "DATA_SCALE" NUMBER, "NULLABLE" VARCHAR2(1), "COLUMN_ID" NUMBER,
"DEFAULT_LENGTH" NUMBER, "NUM_DISTINCT" NUMBER, "LOW_VALUE" RAW(32), "HIGH_VALUE" RAW(32), "DENSITY"
NUMBER, "NUM_NULLS" NUMBER, "NUM_BUCKETS" NUMBER, "LAST_ANALYZED" DATE, "SAMPLE_SIZE" NUMBER,
"CHARACTER_SET_NAME" VARCHAR2(44), "CHAR_COL_DECL_LENGTH" NUMBER, "GLOBAL_STATS" VARCHAR2(3),
"USER_STATS" VARCHAR2(3), "AVG_COL_LEN" NUMBER, "CHAR_LENGTH" NUMBER, "CHAR_USED" VARCHAR2(1),
"V80_FMT_IMAGE" VARCHAR2(3), "DATA_UPGRADED" VARCHAR2(3), "HIDDEN_COLUMN" VARCHAR2(3),
"VIRTUAL_COLUMN" VARCHAR2(3), "SEGMENT_COLUMN_ID" NUMBER, "INTERNAL_COLUMN_ID" NUMBER NOT NULL
ENABLE, "HISTOGRAM" VARCHAR2(15), "QUALIFIED_COL_NAME" VARCHAR2(4000)) ;

exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_ind_columns');
CREATE TABLE "SGA_XPLAN_TPL_DBA_IND_COLUMNS" ("INDEX_OWNER" VARCHAR2(30) NOT NULL ENABLE,
"INDEX_NAME" VARCHAR2(30) NOT NULL ENABLE, "TABLE_OWNER" VARCHAR2(30) NOT NULL ENABLE, "TABLE_NAME"
VARCHAR2(30) NOT NULL ENABLE, "COLUMN_NAME" VARCHAR2(4000), "COLUMN_POSITION" NUMBER NOT NULL
ENABLE, "COLUMN_LENGTH" NUMBER NOT NULL ENABLE, "CHAR_LENGTH" NUMBER, "DESCEND" VARCHAR2(4)) ;
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_cons_columns');
CREATE TABLE "SGA_XPLAN_TPL_DBA_CONS_COLUMNS" ("OWNER" VARCHAR2(30) NOT NULL ENABLE,
"CONSTRAINT_NAME" VARCHAR2(30) NOT NULL ENABLE, "TABLE_NAME" VARCHAR2(30) NOT NULL ENABLE,
"COLUMN_NAME" VARCHAR2(4000), "POSITION" NUMBER) ;

exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_indexes');
CREATE TABLE "SGA_XPLAN_TPL_DBA_INDEXES" ("OWNER" VARCHAR2(30) NOT NULL ENABLE, "INDEX_NAME"
VARCHAR2(30) NOT NULL ENABLE, "INDEX_TYPE" VARCHAR2(27), "TABLE_OWNER" VARCHAR2(30) NOT NULL ENABLE,
"TABLE_NAME" VARCHAR2(30) NOT NULL ENABLE, "TABLE_TYPE" VARCHAR2(11), "UNIQUENESS" VARCHAR2(9),
"COMPRESSION" VARCHAR2(8), "PREFIX_LENGTH" NUMBER, "TABLESPACE_NAME" VARCHAR2(30), "INI_TRANS"
NUMBER, "MAX_TRANS" NUMBER, "INITIAL_EXTENT" NUMBER, "NEXT_EXTENT" NUMBER, "MIN_EXTENTS" NUMBER,
"MAX_EXTENTS" NUMBER, "PCT_INCREASE" NUMBER, "PCT_THRESHOLD" NUMBER, "INCLUDE_COLUMN" NUMBER,
"FREELISTS" NUMBER, "FREELIST_GROUPS" NUMBER, "PCT_FREE" NUMBER, "LOGGING" VARCHAR2(3), "BLEVEL"
NUMBER, "LEAF_BLOCKS" NUMBER, "DISTINCT_KEYS" NUMBER, "AVG_LEAF_BLOCKS_PER_KEY" NUMBER,
"AVG_DATA_BLOCKS_PER_KEY" NUMBER, "CLUSTERING_FACTOR" NUMBER, "STATUS" VARCHAR2(8), "NUM_ROWS"
NUMBER, "SAMPLE_SIZE" NUMBER, "LAST_ANALYZED" DATE, "DEGREE" VARCHAR2(40), "INSTANCES" VARCHAR2(40),
"PARTITIONED" VARCHAR2(3), "TEMPORARY" VARCHAR2(1), "GENERATED" VARCHAR2(1), "SECONDARY"
VARCHAR2(1), "BUFFER_POOL" VARCHAR2(7), "USER_STATS" VARCHAR2(3), "DURATION" VARCHAR2(15),
"PCT_DIRECT_ACCESS" NUMBER, "ITYP_OWNER" VARCHAR2(30), "ITYP_NAME" VARCHAR2(30), "PARAMETERS"
VARCHAR2(1000), "GLOBAL_STATS" VARCHAR2(3), "DOMIDX_STATUS" VARCHAR2(12), "DOMIDX_OPSTATUS"
VARCHAR2(6), "FUNCIDX_STATUS" VARCHAR2(8), "JOIN_INDEX" VARCHAR2(3), "IOT_REDUNDANT_PKEY_ELIM"
VARCHAR2(3), "DROPPED" VARCHAR2(3)) ;

exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_constraints');
CREATE TABLE "SGA_XPLAN_TPL_DBA_CONSTRAINTS" ("OWNER" VARCHAR2(30) NOT NULL ENABLE,
"CONSTRAINT_NAME" VARCHAR2(30) NOT NULL ENABLE, "CONSTRAINT_TYPE" VARCHAR2(1), "TABLE_NAME"
VARCHAR2(30) NOT NULL ENABLE, "R_OWNER" VARCHAR2(30), "R_CONSTRAINT_NAME" VARCHAR2(30),
"DELETE_RULE" VARCHAR2(9), "STATUS" VARCHAR2(8), "DEFERRABLE" VARCHAR2(14), "DEFERRED" VARCHAR2(9),
"VALIDATED" VARCHAR2(13), "GENERATED" VARCHAR2(14), "BAD" VARCHAR2(3), "RELY" VARCHAR2(4),
"LAST_CHANGE" DATE, "INDEX_OWNER" VARCHAR2(30), "INDEX_NAME" VARCHAR2(30), "INVALID" VARCHAR2(7),
"VIEW_RELATED" VARCHAR2(14)) ;
 
-- create view adapters 
exec sga_xplan_install.create_v_adapters;

-- drop templates
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_v$sql');
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_v$sqltext_nl');
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_v$sql_plan');
--exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_v$sql_plan_stat');
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_v$sql_plan_sall');

exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_tables'      );
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_tab_cols'    );
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_ind_columns' );
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_cons_columns');
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_indexes'     );
exec sga_xplan_install.drop_table_idem ('sga_xplan_tpl_dba_constraints' );

---- drop old versions of objects
whenever sqlerror continue
drop sequence sga_xplan_v$sql_plan_seq;
whenever sqlerror exit

exec sga_xplan_install.drop_table_idem ('sga_xplan_v$sql');
exec sga_xplan_install.drop_table_idem ('sga_xplan_v$sqltext_nl');
exec sga_xplan_install.drop_table_idem ('sga_xplan_v$sql_plan');
--exec sga_xplan_install.drop_table_idem ('sga_xplan_v$sql_plan_stat');
exec sga_xplan_install.drop_table_idem ('sga_xplan_v$sql_plan_sall');

exec sga_xplan_install.drop_table_idem ('sga_xplan_dba_tables'        );
exec sga_xplan_install.drop_table_idem ('sga_xplan_dba_tab_cols'      );
exec sga_xplan_install.drop_table_idem ('sga_xplan_dba_ind_columns'   );
exec sga_xplan_install.drop_table_idem ('sga_xplan_dba_cons_columns'  );
exec sga_xplan_install.drop_table_idem ('sga_xplan_dba_indexes'       );
exec sga_xplan_install.drop_table_idem ('sga_xplan_dba_constraints'   );
exec sga_xplan_install.drop_table_idem ('sga_xplan_ti_cache_tables'   );
exec sga_xplan_install.drop_table_idem ('sga_xplan_ti_cache_tab_infos');

---- create objects

-- sequence that feeds statement_id and plan_id (in 10g)
create sequence sga_xplan_v$sql_plan_seq increment by 1 start with 100000 cache 100;

-- contains v$sql dumps
create &tables_type. table sga_xplan_v$sql 
&on_commit.
as select rpad ('x',30,'x') as statement_id, 
          sysdate sga_xplan_dump_date,
          0       sga_xplan_dump_id,
          t.*
     from sga_xplan_va_v$sql t where 1=0;
     
alter table sga_xplan_v$sql modify (statement_id not null);  
create index sga_xplan_v$sql_sid_idx on  sga_xplan_v$sql (statement_id);

-- contains v$sqltext_with_newlines dumps
create &tables_type. table sga_xplan_v$sqltext_nl 
&on_commit.
as select rpad ('x',30,'x') as statement_id, 
          t.*
     from sga_xplan_va_v$sqltext_nl t where 1=0;
     
alter table sga_xplan_v$sqltext_nl modify (statement_id not null);  
create index sga_xplan_v$sqltext_nl_st_idx on sga_xplan_v$sqltext_nl (statement_id);

-- contains v$sql_plan dumps     
create &tables_type. table sga_xplan_v$sql_plan
&on_commit.
as select rpad ('x',30,'x') statement_id,
          t.*,
          object# object_instance,
          0       plan_id 
     from sga_xplan_va_v$sql_plan t where 1=0;
alter table sga_xplan_v$sql_plan modify (statement_id not null);  
create index sga_xplan_v$sql_plan_sid_idx on sga_xplan_v$sql_plan (statement_id, id);
create index sga_xplan_v$sql_plan_pid_idx on sga_xplan_v$sql_plan (plan_id);  
     
/*     
-- contains v$sql_plan_statistics dumps       
create &tables_type. table sga_xplan_v$sql_plan_stat
&on_commit.
as select rpad ('x',30,'x') as statement_id, 
          t.*
     from sga_xplan_va_v$sql_plan_stat t where 1=0;
alter table sga_xplan_v$sql_plan_stat modify (statement_id not null);  
create index sga_xplan_v$sql_pl_st_oid_idx on sga_xplan_v$sql_plan_stat (statement_id, operation_id); 
*/

-- contains v$sql_plan_statistics_all dumps       
create &tables_type. table sga_xplan_v$sql_plan_sall
&on_commit.
as select rpad ('x',30,'x') as statement_id, 
          t.*,
          object# object_instance,
          0       plan_id
     from sga_xplan_va_v$sql_plan_sall t where 1=0;
alter table sga_xplan_v$sql_plan_sall modify (statement_id not null);  
create index sga_xplan_v$sql_pa_st_oid_idx on sga_xplan_v$sql_plan_sall (statement_id, id); 

create global temporary table sga_xplan_dba_tables
on commit preserve rows
as select *
     from sga_xplan_va_dba_tables where 1=0;
     
create global temporary table sga_xplan_dba_tab_cols
on commit preserve rows
as select *
     from sga_xplan_va_dba_tab_cols where 1=0;

create global temporary table sga_xplan_dba_ind_columns
on commit preserve rows
as select *
     from sga_xplan_va_dba_ind_columns where 1=0;

create global temporary table sga_xplan_dba_cons_columns
on commit preserve rows
as select *
     from sga_xplan_va_dba_cons_columns where 1=0;

create global temporary table sga_xplan_dba_indexes
on commit preserve rows
as select *
     from sga_xplan_va_dba_indexes where 1=0;     
     
create global temporary table sga_xplan_dba_constraints
on commit preserve rows
as select *
     from sga_xplan_va_dba_constraints where 1=0; 
     
create global temporary table sga_xplan_ti_cache_tables (
  owner varchar2(30) not null, table_name varchar2(30) not null,
  constraint sga_xplan_ti_cache_tables_pk primary key (owner, table_name)
)
on commit preserve rows;

create global temporary table sga_xplan_ti_cache_tab_infos (
  owner varchar2(30) not null, table_name varchar2(30) not null,
  info_row_num int not null, info_row varchar2(300 char)
)
on commit preserve rows;
create index sga_xplan_ti_cache_tab_inf_idx on sga_xplan_ti_cache_tab_infos (
  owner, table_name, info_row_num, info_row
 );
alter table sga_xplan_ti_cache_tab_infos add constraint 
sga_xplan_ti_cache_tab_inf_pk primary key (owner, table_name, info_row_num);
 
-- types for sga_xplan.display return  
whenever sqlerror continue  
drop type sga_xplan_plan_row_array;
whenever sqlerror exit

create or replace type sga_xplan_plan_row as object (plan_table_output varchar2(300));
/
create or replace type sga_xplan_plan_row_array as table of sga_xplan_plan_row;
/

-- Multi Column Formatter
-- A utility package to print nice multi-column reports
create or replace package sga_xplan_mcf is

  -- API 1: name, stat, stat / execs 
  procedure reset (p_default_execs number, p_stat_default_decimals int, p_stex_default_decimals int);
  procedure add_line_char (p_name varchar2, p_stat varchar2, p_stex varchar2);
  procedure add_line (p_name varchar2, p_stat number, p_execs number default -1);
  procedure prepare_output (p_num_columns int);
  function  next_output_line return varchar2;
  
  procedure test;
  
  -- API 2: col1, col2 .. colN
  procedure n_reset;
  procedure n_add_line (c1  varchar2 default null, c2  varchar2 default null, c3  varchar2 default null,
                        c4  varchar2 default null, c5  varchar2 default null, c6  varchar2 default null,
                        c7  varchar2 default null, c8  varchar2 default null, c9  varchar2 default null,
                        c10 varchar2 default null, c11 varchar2 default null, c12 varchar2 default null);
  procedure n_prepare_output (c1_align  varchar2 default 'right', c2_align  varchar2 default 'right', c3_align  varchar2 default 'right',
                              c4_align  varchar2 default 'right', c5_align  varchar2 default 'right', c6_align  varchar2 default 'right',
                              c7_align  varchar2 default 'right', c8_align  varchar2 default 'right', c9_align  varchar2 default 'right',
                              c10_align varchar2 default 'right', c11_align varchar2 default 'right', c12_align varchar2 default 'right',
                              p_separator varchar2 default ' ');
   function n_next_output_line return varchar2;
  procedure n_test;
end sga_xplan_mcf;
/
show errors;

create or replace package body sga_xplan_mcf is
  
type t_line         is record (m_name varchar2(30), m_stat varchar2(30), m_stex varchar2(30));
type t_line_arr     is table of t_line index by binary_integer;
type t_output_array is table of varchar2(150) index by binary_integer;

type t_n_line         is table of varchar2(150) index by binary_integer;
type t_n_line_arr     is table of t_n_line index by binary_integer;
type t_n_output_array is table of varchar2(300) index by binary_integer;

m_default_execs         number;
m_stat_default_decimals int;
m_stex_default_decimals int;

m_lines         t_line_arr;
m_lines_out     t_output_array;
m_output_height int;

m_n_lines     t_n_line_arr;
m_n_lines_out t_n_output_array;

-----------------------------------------------------------
procedure reset (p_default_execs number, p_stat_default_decimals int, p_stex_default_decimals int)
is
begin
  m_default_execs         := p_default_execs;
  m_stat_default_decimals := p_stat_default_decimals;
  m_stex_default_decimals := p_stex_default_decimals;
  m_lines.delete;
  m_lines_out.delete;
end reset;
 
-----------------------------------------------------------
procedure add_line_char (p_name varchar2, p_stat varchar2, p_stex varchar2) 
is
  l_line t_line;
begin
  l_line.m_name      := p_name;
  l_line.m_stat      := p_stat;
  l_line.m_stex := nvl (p_stex, ' ');
  m_lines(m_lines.count) := l_line;
end add_line_char;

-----------------------------------------------------------
procedure add_line (p_name varchar2, p_stat number, p_execs number default -1)
is
  l_execs number;
  l_stat_fmt varchar2(29);
  l_stat_left_digits int := 29 - m_stat_default_decimals - 1;
  l_stat_rite_digits int :=      m_stat_default_decimals;
  l_stex_fmt varchar2(29);
  l_stex_left_digits int := 29 - m_stex_default_decimals - 1;
  l_stex_rite_digits int :=      m_stex_default_decimals;
begin
  -- ignore if p_stat is null
  if p_stat is null then
    return;
  end if;
  
  -- use defaults if p_execs = -1
  if p_execs = -1 then
    l_execs := m_default_execs;
  else
    l_execs := p_execs;
  end if;
  -- handle execs = 0 by suppressing output
  if l_execs = 0 then
    l_execs := null;
  end if;
  -- build formats
  l_stat_fmt := rpad ('9', l_stat_left_digits, '9') || rtrim (rpad ('.', l_stat_rite_digits+1, '9'), '.');
  l_stex_fmt := rpad ('9', l_stex_left_digits, '9') || rtrim (rpad ('.', l_stex_rite_digits+1, '9'), '.');
  -- format and add
  add_line_char (p_name, trim(to_char (p_stat, l_stat_fmt)), trim(to_char (p_stat / l_execs, l_stex_fmt))); 
end add_line;

-----------------------------------------------------------
procedure prepare_output (p_num_columns int) 
is
  l_height number;
  l_max_name      int;
  l_max_stat      int;
  l_max_stex int;
  l_i_start int;
  l_i_stop  int;
  l_separ_line varchar2(200 char);
begin
  m_lines_out.delete;
  
  l_height := ceil ( (m_lines.count-1) / p_num_columns); 
  
  for c in 0..p_num_columns-1 loop
    l_max_name := length (m_lines(0).m_name);
    l_max_stat := length (m_lines(0).m_stat);
    l_max_stex := length (m_lines(0).m_stex);
    l_i_start := c*l_height+1;
    l_i_stop  := least ( (c+1)*l_height, m_lines.count-1 );
    
    for i in l_i_start .. l_i_stop loop
      if length (m_lines(i).m_name) > l_max_name then l_max_name := length (m_lines(i).m_name); end if;
      if length (m_lines(i).m_stat) > l_max_stat then l_max_stat := length (m_lines(i).m_stat); end if;
      if length (m_lines(i).m_stex) > l_max_stex then l_max_stex := length (m_lines(i).m_stex); end if;
    end loop;
    l_separ_line := '-' || rpad ('-', l_max_name+2, '-')
                        || rpad ('-', l_max_stat+2, '-')
                        || rpad ('-', l_max_stex+2, '-');
    m_lines_out(m_lines_out.count) := l_separ_line;
    m_lines_out(m_lines_out.count) := '|' || rpad (m_lines(0).m_name, l_max_name, ' ') || ' |'
                                          || rpad (m_lines(0).m_stat, l_max_stat, ' ') || ' |'
                                          || rpad (m_lines(0).m_stex, l_max_stex, ' ') || ' |'; 
    m_lines_out(m_lines_out.count) := l_separ_line;
    for i in l_i_start .. l_i_stop loop
      m_lines_out(m_lines_out.count) := '|' || rpad (m_lines(i).m_name, l_max_name, ' ') || ' |'
                                            || lpad (m_lines(i).m_stat, l_max_stat, ' ') || ' |'
                                            || lpad (m_lines(i).m_stex, l_max_stex, ' ') || ' |'; 
    end loop;
    m_lines_out(m_lines_out.count) := l_separ_line;
  end loop;
  
  --for i in 0..m_lines_out.count-1 loop
  --  dbms_output.put_line (m_lines_out(i)|| ' | ');
  --end loop;
 
  m_output_height := l_height + 4;
end prepare_output;

-----------------------------------------------------------
function next_output_line
return varchar2
is
  l_out varchar2(200 char);
  i int;
begin
  if m_lines_out.count = 0 then
    return null;
  end if;
  i := m_lines_out.first;
  loop
     l_out := l_out || m_lines_out(i);
     m_lines_out.delete (i);
     i := i + m_output_height;
     exit when not m_lines_out.exists(i);
     l_out := l_out || ' ';
  end loop;
  return l_out;
end next_output_line;
  
-----------------------------------------------------------
procedure test 
is
  l_out varchar2(200 char);
begin
  reset (p_default_execs => 10, p_stat_default_decimals => 0, p_stex_default_decimals => 1);
  add_line_char ('v$sql statname', 'total', 'total/exec');
  add_line ('s0', 0, null);
  add_line ('s1____________________', 1);
  add_line ('s2', 2, 10);
  add_line ('s3______________', 3, 10);
  add_line ('s4', 4, 10);
  prepare_output (p_num_columns => 2);
  loop
    l_out := next_output_line;
    exit when l_out is null;
    dbms_output.put_line (l_out);
  end loop;
end test;

-----------------------------------------------------------
procedure n_reset 
is
begin
  m_n_lines.delete;
  m_n_lines_out.delete;
end n_reset;

-----------------------------------------------------------
procedure n_add_line (c1  varchar2 default null, c2  varchar2 default null, c3  varchar2 default null,
                      c4  varchar2 default null, c5  varchar2 default null, c6  varchar2 default null,
                      c7  varchar2 default null, c8  varchar2 default null, c9  varchar2 default null,
                      c10 varchar2 default null, c11 varchar2 default null, c12 varchar2 default null)
is
  l_line t_n_line;
begin
  l_line(1)  := c1;  l_line(2)  := c2;  l_line(3) := c3;
  l_line(4)  := c4;  l_line(5)  := c5;  l_line(6) := c6;
  l_line(7)  := c7;  l_line(8)  := c8;  l_line(9) := c9;
  l_line(10) := c10; l_line(11) := c11; l_line(12) := c12;
  m_n_lines (m_n_lines.count) := l_line;
end n_add_line;

-----------------------------------------------------------
procedure n_prepare_output (c1_align  varchar2 default 'right', c2_align  varchar2 default 'right', c3_align  varchar2 default 'right',
                            c4_align  varchar2 default 'right', c5_align  varchar2 default 'right', c6_align  varchar2 default 'right',
                            c7_align  varchar2 default 'right', c8_align  varchar2 default 'right', c9_align  varchar2 default 'right',
                            c10_align varchar2 default 'right', c11_align varchar2 default 'right', c12_align varchar2 default 'right',
                            p_separator varchar2 default ' ')
is
  type t_lengths is table of int index by binary_integer;
  type t_aligns  is table of varchar2(5) index by binary_integer;
  l_lengths t_lengths;
  l_aligns  t_aligns;
  l_line    varchar2(300 char);
begin
  m_n_lines_out.delete;
  
  if m_n_lines.count = 0 then
    return;
  end if;
  
  -- get max columns lengths
  for i in m_n_lines.first .. m_n_lines.last loop
    for j in m_n_lines(i).first .. m_n_lines(i).last loop
      if not l_lengths.exists(j) then
        l_lengths(j) := 0;
      end if;
      l_lengths(j) := greatest (l_lengths(j), nvl( length (m_n_lines(i)(j)) , 0)  );
    end loop;
  end loop;
  
  l_aligns(1)  := lower ( c1_align); l_aligns(2)  := lower ( c2_align); l_aligns(3)  := lower ( c3_align);
  l_aligns(4)  := lower ( c4_align); l_aligns(5)  := lower ( c5_align); l_aligns(6)  := lower ( c6_align);
  l_aligns(7)  := lower ( c7_align); l_aligns(8)  := lower ( c8_align); l_aligns(9)  := lower ( c9_align);
  l_aligns(10) := lower (c10_align); l_aligns(11) := lower (c11_align); l_aligns(12) := lower (c12_align);
  
  for i in m_n_lines.first .. m_n_lines.last loop
    l_line := '';
    for j in m_n_lines(i).first .. m_n_lines(i).last loop
      if l_lengths(j) > 0 then 
        l_line := l_line || case when l_aligns(j) = 'right' 
                                 then lpad ( nvl(m_n_lines(i)(j), ' '), l_lengths(j) )
                                 else rpad ( nvl(m_n_lines(i)(j), ' '), l_lengths(j) )
                            end
                         || p_separator;
      end if;
    end loop;
    m_n_lines_out (m_n_lines_out.count) := substr (l_line, 1, length (l_line) - length (p_separator));
  end loop;
end n_prepare_output;

-----------------------------------------------------------
function n_next_output_line 
return varchar2
is
  l_out varchar2 (300 char);
begin
  if m_n_lines_out.count = 0 then
    return null;
  end if;
  l_out := m_n_lines_out (m_n_lines_out.first);
  m_n_lines_out.delete   (m_n_lines_out.first);
  return l_out;
end n_next_output_line;

-----------------------------------------------------------
procedure n_test
is
  l_out varchar2 (300 char);
begin
  n_reset;
  n_add_line ('uno', 'due', null, 'quattro');
  n_add_line ('1', '2', null, 4);
  n_prepare_output (c2_align => 'left', p_separator => '|');
  loop
    l_out := n_next_output_line;
    exit when l_out is null;
    dbms_output.put_line ('"'||l_out||'"');
  end loop;
end n_test;
  
end sga_xplan_mcf;
/
show errors;

-------------------------------------------------------------------------------------------
-- tabinfo (Table Infos) section
-- allows sga_xplan.display to print table layout and statistics 
-------------------------------------------------------------------------------------------

-- attach a number (index_num) to every index, to make it cross-referenceable by ind_block 
create or replace view sga_xplan_ti_num_indexes as
select row_number() over (order by index_name, owner) index_num, owner, index_name, uniqueness,
       blevel, leaf_blocks, distinct_keys, clustering_factor, num_rows, partitioned, sample_size, last_analyzed
  from sga_xplan_dba_indexes;

-- attach to dba_ind_columns a letter to represent column_position
-- 1->a, 2->b, etc - uppercase if the index is unique
-- also attach a P (U) if the index supports a PK (UNIQUE) constraint
create or replace view sga_xplan_ti_ind_cols as
select i.column_name, ni.index_num, 
       case when ni.uniqueness = 'UNIQUE' 
            then upper(substr ('abcdefghijklmnopqrstuvwxyz', i.column_position, 1))
            else       substr ('abcdefghijklmnopqrstuvwxyz', i.column_position, 1)
       end || c.constraint_type as pos,
       i.column_position, ni.uniqueness, c.constraint_type 
  from sga_xplan_dba_ind_columns i, 
       sga_xplan_ti_num_indexes  ni,
       (select * from sga_xplan_dba_constraints where constraint_type in ('P', 'U')) c 
 where i.index_owner = ni.owner
   and i.index_name  = ni.index_name
   and i.index_owner = c.index_owner(+)
   and i.index_name  = c.index_name(+);

-- the indexed_columns display block
create or replace view sga_xplan_ti_ind_block as
with sga_xplan_ti_j1 as (
 select ni.index_num, c.column_name 
   from sga_xplan_ti_num_indexes ni, sga_xplan_dba_tab_cols c
), sga_xplan_ti_j2 as (
 select j1.index_num, j1.column_name, rpad (nvl(ic.pos,' '), 2) as pos
   from sga_xplan_ti_j1 j1,  sga_xplan_ti_ind_cols ic
  where j1.column_name = ic.column_name(+)
    and j1.index_num  = ic.index_num(+)
), sga_xplan_ti_j3 as (
select j2.column_name, sys_connect_by_path (j2.pos,'/') line
  from sga_xplan_ti_j2 j2
 start with index_num = 1
 connect by column_name = prior column_name
        and index_num = 1 + prior index_num
), sga_xplan_ti_j4 as (
  select '#header' as column_name, sys_connect_by_path ( rpad (index_num, 2) , '/') line 
    from sga_xplan_ti_num_indexes 
   start with index_num = 1
  connect by index_num = 1 + prior index_num
), sga_xplan_ti_j5 as (  
  select column_name, line from sga_xplan_ti_j3
  union all 
  select column_name, line from sga_xplan_ti_j4
) 
select column_name, replace ( ltrim (max (line), '/'), '/', ' ') as indexed
  from sga_xplan_ti_j5
 group by column_name;

-- the columns block
create or replace view sga_xplan_ti_columns as
with sga_xplan_ti_j1 as (
  select column_name, column_id, data_type, data_length, data_precision, data_scale, nullable,
         num_distinct, density, num_nulls, num_buckets, avg_col_len, last_analyzed 
    from sga_xplan_dba_tab_cols
  union all
  select '#header', 0, null, null, null, null, null, null, null, null, null, null, null from dual
)
select c.*, i.indexed
  from sga_xplan_ti_j1 c, sga_xplan_ti_ind_block i
 where c.column_name = i.column_name(+)
 order by c.column_id;

-- the tabinfo package 
create or replace package sga_xplan_tabinfo as

-- displays table layout and statistics for p_owner.p_table_name
function display (p_owner varchar2, p_table_name varchar2)
  return sga_xplan_plan_row_array
pipelined;

-- same as display(), but also caches the table infos in the "table cache"
-- and fetches for the cache if the table infos are already there
-- returns a ref cursor instead of am array for performance
function get_infos_and_cache (p_owner varchar2, p_table_name varchar2)
  return sys_refcursor;
  
-- resets the "table cache"
procedure reset_table_cache;

procedure dump (p_owner varchar2, p_table_name varchar2);

end sga_xplan_tabinfo;
/
show errors;

create or replace package body sga_xplan_tabinfo as

-----------------------------------------------------------
procedure dump (p_owner varchar2, p_table_name varchar2)
is
  pragma autonomous_transaction;
begin
  delete /*+ sga_xplan_exec */ from sga_xplan_dba_tables;
  insert /*+ sga_xplan_exec */ into sga_xplan_dba_tables select * from sga_xplan_va_dba_tables
    where owner = upper (p_owner) and table_name = upper (p_table_name);
    
  delete /*+ sga_xplan_exec */ from sga_xplan_dba_tab_cols;
  insert /*+ sga_xplan_exec */ into sga_xplan_dba_tab_cols select * from sga_xplan_va_dba_tab_cols 
   where owner = upper (p_owner) and table_name = upper (p_table_name);

  delete /*+ sga_xplan_exec */ from sga_xplan_dba_ind_columns;
  insert /*+ sga_xplan_exec */ into sga_xplan_dba_ind_columns select * from sga_xplan_va_dba_ind_columns 
   where table_owner = upper (p_owner) and table_name = upper (p_table_name);
  
  delete /*+ sga_xplan_exec */ from sga_xplan_dba_cons_columns;
  insert /*+ sga_xplan_exec */ into sga_xplan_dba_cons_columns select * from sga_xplan_va_dba_cons_columns 
   where owner = upper (p_owner) and table_name = upper (p_table_name);
  
  delete /*+ sga_xplan_exec */ from sga_xplan_dba_indexes;
  insert /*+ sga_xplan_exec */ into sga_xplan_dba_indexes select * from sga_xplan_va_dba_indexes 
    where table_owner = upper (p_owner) and table_name = upper (p_table_name);

  delete /*+ sga_xplan_exec */ from sga_xplan_dba_constraints;
  insert /*+ sga_xplan_exec */ into sga_xplan_dba_constraints select * from sga_xplan_va_dba_constraints
   where owner = upper (p_owner) and table_name = upper (p_table_name);    
    
  commit;  
end dump;

-----------------------------------------------------------
function d2s (p_date date) return varchar2 
is
begin
  return to_char (p_date, 'yyyy/mm/dd hh24:mi:ss');
end d2s;

-----------------------------------------------------------
function display (p_owner varchar2, p_table_name varchar2)
  return sga_xplan_plan_row_array
pipelined
is
  l_out varchar2 (500);
  l_data_mod  varchar2(50);
  l_part_mod  varchar2(50);
  l_uniq_mod  varchar2(10);
  l_table_found   boolean := false;
  l_indexes_found boolean := false;
begin
  dump (p_owner, p_table_name);
  
  -- table
  sga_xplan_mcf.n_reset;
  for t in (select /*+ sga_xplan_exec */ iot_type, num_rows, blocks, empty_blocks, avg_row_len, partitioned, sample_size, last_analyzed
              from sga_xplan_dba_tables)
  loop
    if t.partitioned = 'YES' then l_part_mod := 'PARTITIONED'; else l_part_mod := ''; end if;
    sga_xplan_mcf.n_add_line ('** table', '', '', 'num_rows', 'blocks', 'empty_blocks', 'avg_row_len', 'sample_size', 'last_analyzed');
    sga_xplan_mcf.n_add_line (lower(p_owner)||'.'||p_table_name, t.iot_type, l_part_mod, t.num_rows, t.blocks, t.empty_blocks, t.avg_row_len, t.sample_size, d2s(t.last_analyzed));
    l_table_found := true;
  end loop;
  if not l_table_found then
    return;
  end if;
  sga_xplan_mcf.n_prepare_output (c1_align=>'left');
  loop
    l_out := sga_xplan_mcf.n_next_output_line;
    exit when l_out is null;
    pipe row ( sga_xplan_plan_row( l_out ) );
  end loop;
  
  -- columns
  sga_xplan_mcf.n_reset;
  for c in (select /*+ sga_xplan_exec */ * from sga_xplan_ti_columns order by column_id)
  loop
    if c.column_id = 0 then
      sga_xplan_mcf.n_add_line ('column', c.indexed,' ','ndv','density','nulls','bkts','avg_col_len','last_analyzed');
    else
      l_data_mod := '';
      if c.data_type in ('NUMBER') then
        if c.data_precision is not null or c.data_scale is not null then 
          l_data_mod := ' ('||nvl(c.data_precision,38)||','||c.data_scale||')';
        end if;
      elsif c.data_type in ('FLOAT') then
        l_data_mod := ' ('||c.data_precision||')';
      elsif c.data_type in ('VARCHAR2', 'VARCHAR', 'NVARCHAR2', 'NVARCHAR', 'CHAR', 'NCHAR') then
        l_data_mod := ' ('||c.data_length||')';
      end if;
      if c.nullable = 'N' then
        l_data_mod := l_data_mod || ' NN';
      end if;
      sga_xplan_mcf.n_add_line (c.column_name, c.indexed, 
         c.data_type||l_data_mod, c.num_distinct, c.density, c.num_nulls, c.num_buckets, c.avg_col_len, d2s(c.last_analyzed));
      end if;
  end loop;
  sga_xplan_mcf.n_prepare_output (c1_align=>'left', c3_align => 'left');
  loop
    l_out := sga_xplan_mcf.n_next_output_line;
    exit when l_out is null;
    pipe row ( sga_xplan_plan_row( l_out ) );
  end loop;
  
  -- indexes
  sga_xplan_mcf.n_reset;
  
  for i in (select /*+ sga_xplan_exec */ * from sga_xplan_ti_num_indexes order by index_num) 
  loop
    if not l_indexes_found then
      sga_xplan_mcf.n_add_line ('-', 'index', '', '', 'distinct_keys', 'num_rows', 
        'blevel', 'leaf_blocks', 'cluf', 'sample_size', 'last_analyzed');
      l_indexes_found := true;
    end if;
    if i.partitioned = 'YES'   then l_part_mod := 'PARTITIONED'; else l_part_mod := ''; end if;
    if i.uniqueness = 'UNIQUE' then l_uniq_mod := 'UQ';          else l_uniq_mod := ''; end if;
    sga_xplan_mcf.n_add_line (i.index_num, i.index_name, l_uniq_mod, l_part_mod, i.distinct_keys, i.num_rows, 
      i.blevel, i.leaf_blocks, i.clustering_factor, i.sample_size, d2s(i.last_analyzed));  
  end loop;
  sga_xplan_mcf.n_prepare_output (c1_align=>'left', c2_align=>'left');
  loop
    l_out := sga_xplan_mcf.n_next_output_line;
    exit when l_out is null;
    pipe row ( sga_xplan_plan_row( l_out ) );
  end loop;
  if not l_indexes_found then
    pipe row ( sga_xplan_plan_row( 'no index found' ) );
  end if;
  
  return;
end display;

-----------------------------------------------------------
procedure reset_table_cache 
is
  pragma autonomous_transaction;
begin
  delete /*+ sga_xplan_exec */ from sga_xplan_ti_cache_tab_infos;
  commit;
  delete /*+ sga_xplan_exec */ from sga_xplan_ti_cache_tables;
  commit;
end reset_table_cache;

-----------------------------------------------------------
function get_infos_and_cache (p_owner varchar2, p_table_name varchar2)
  return sys_refcursor
is
  pragma autonomous_transaction;
  l_table_in_cache int;
  l_cur_out sys_refcursor;
begin
  select /*+ index (t, sga_xplan_ti_cache_tables_pk) sga_xplan_exec */ count(*) into l_table_in_cache 
    from sga_xplan_ti_cache_tables t
   where owner = p_owner and table_name = p_table_name and rownum = 1;
   
  if l_table_in_cache = 0 then
    --dbms_output.put_line ('inserting in cache');
    insert /*+ sga_xplan_exec */ into sga_xplan_ti_cache_tables (owner, table_name) values (p_owner, p_table_name);
    -- casting everything to avoid "ORA-22905: cannot access rows from a non-nested table item" in 9i
    -- http://asktom.oracle.com/pls/asktom/f?p=100:11:0::::P11_QUESTION_ID:4447489221109#67490376723105
    insert /*+ sga_xplan_exec */ into sga_xplan_ti_cache_tab_infos (owner, table_name, info_row_num, info_row)
    select /*+ sga_xplan_exec */ p_owner, p_table_name, rownum, cast (plan_table_output as varchar2(300 char))
      from table (sga_xplan_tabinfo.display ( cast (p_owner as varchar2(30)), cast (p_table_name as varchar2(100)) ) );
    commit;
  end if;
   
  open l_cur_out for
  select /*+ index (t, sga_xplan_ti_cache_tab_inf_pk) sga_xplan_exec */ info_row
    from sga_xplan_ti_cache_tab_infos t
   where owner = p_owner and table_name = p_table_name
   order by info_row_num;
   
  return l_cur_out;
end get_infos_and_cache;

end sga_xplan_tabinfo;
/
show errors;

-------------------------------------------------------------------------------------------
-- end of tabinfo (Table Infos) section
-------------------------------------------------------------------------------------------

-----------------------------------------------------------
--------------------- PACKAGE HEADER ----------------------
-----------------------------------------------------------
create or replace package sga_xplan as

-------------------------------------------------------------------------------
------ quick API
------ Use this api if you just want to see the plan
------ currently in the SGA (library cache)
-------------------------------------------------------------------------------

-- function similar to dbms_xplan.display
-- Use as "select * from table (sga_xplan.display ('...'))"
-- Parameters:
-- p_sql_like   : dump only plans for statements whose v$sql.sql_text matches the like-expression (case-insensitive)
--                Eg '%' for all plans, '%from dual%' for stmts selecting from dual, ...
--                If null, it's the same as '%'
-- p_module_like: same as above, for v$sql.module
-- p_action_like: same as above, for v$sql.action
-- p_format     : same as dbms_xplan.display.format (but defaulted to 'all')
function display (
  p_sql_like    varchar2 default null, 
  p_module_like varchar2 default null,
  p_action_like varchar2 default null,
  p_format      varchar2 default 'all')
return sga_xplan_plan_row_array
pipelined;

-- utility function - it just invokes display () and 
-- sends results to dbms_output.put_line
procedure print (
  p_sql_like    varchar2 default null, 
  p_module_like varchar2 default null,
  p_action_like varchar2 default null,
  p_format      varchar2 default 'all'
);

-------------------------------------------------------------------------------
------ advanced API
------ Use this api if you want to dump the plans currently in the SGA 
------ for later analysis (say, every day after a data load).
------ You need to install with persistent=y for this interface to be useful.
-------------------------------------------------------------------------------

-- dumps the plans from the SGA into the tables
-- see "display" for the meaning of parameters
procedure dump_plans (
  p_sql_like       varchar2 default null, 
  p_module_like    varchar2 default null,
  p_action_like    varchar2 default null
);

-- display the plans contained in the tables.
-- p_sql_like    : see "display"
-- p_module_like : see "display"
-- p_action_like : see "display"
-- p_dump_id     : display only plans with this sga_xplan_dump_id,
--                 thus belonging to the same dump_plans invokation.
--                 If null, means "don't filter "
-- p_format      : see "display"
function display_stored_plans (
  p_sql_like    varchar2 default null, 
  p_module_like varchar2 default null,
  p_action_like varchar2 default null,
  p_dump_id     int      default null,
  p_format      varchar2 default 'all'
)
return sga_xplan_plan_row_array
pipelined;

-- purge the tables containing the plans.
-- p_deadline_date: remove plans older then p_deadline_date;
--                  null means remove all
-- p_truncate     : if true, truncate all tables (ignores other parameters)
-- p_dump_id      : remove only plans with the provided sga_xplan_dump_id;
--                  null means remove all
procedure purge_tables (
  p_deadline_date date    default null,
  p_truncate      boolean default false,
  p_dump_id       int     default null
);

-- if you get "ORA-03113: end-of-file on communication channel",
-- you're probably hitting bug 2525630 or one of its variants; it's a 
-- memory corruption of the memory structures pointed by 
-- v$sql_plan.filter_predicates and v$sql_plan.access_predicates
-- on some plans stored in the library cache.
-- This seems to be solved in 10g (SR 4081391.996).
-- You can simply "alter system flush shared_pool" to make 
-- the corrupted plans go away, which is only feasible,
-- of course, on your test machine.
-- When not feasible, call this procedure once in your session
-- to activate "bugged instance mode" - you will not
-- get the filter and access predicates in the output but at least
-- you will have the most of the plan.
procedure set_bugged (p_is_bugged varchar2 default 'Y');

-- set the use of the *_LAST columns of v$sql_plan_statistics
-- instead of the cumulative ones (eg LAST_OUTPUT_ROWS 
-- instead of OUTPUT_ROWS)
procedure set_use_last (p_use_last varchar2 default 'Y');

-- set/unset the printing of the original (not decoded) peeked bind xml string
procedure set_print_orig_peeked (p_print_orig_peeked varchar2 default 'Y');

-- set/unset the display of the "Query Block Name / Object Alias" section of dbms_xplan.display 
procedure set_query_block_name (p_query_block_name varchar2 default 'Y');

-- set/unset the display of the "Column Projection Information" section of dbms_xplan.display 
procedure set_column_projection (p_column_projection varchar2 default 'Y');

-- set/unset the display of informations of tables referenced in the statement
procedure set_tabinfos (p_tabinfos varchar2 default 'N');

-- gets the version (CVS Id string)
function get_version return varchar2;

-- generate (using dbms_output) uninstall statements
procedure generate_uninstall;

end sga_xplan;
/
show errors;

-----------------------------------------------------------
---------------------- PACKAGE BODY -----------------------
-----------------------------------------------------------
create or replace package body sga_xplan as

type t_owner_table_name is record (owner varchar2(30), table_name varchar2(30));
 
type t_tab_list is table of t_owner_table_name index by binary_integer;

-- owner of this package
g_owner varchar2(30);
-- major version of db
g_db_version number;
-- bugged/not bugged flag
g_bugged varchar2(1) default 'N';
-- (cached) bugged column list
g_bugged_cols     long default null;
g_bugged_cols_all long default null;
-- use *_LAST columns of v$sql_plan_statistics
g_use_last varchar2(1) default 'N';
-- print original (not decoded) peeked bind xml string
g_print_orig_peeked varchar2(1) default 'N';
-- display "Query Block Name / Object Alias" section of dbms_xplan.display
g_query_block_name varchar2(1) default ('N');
-- display "Column Projection Information" section of dbms_xplan.display
g_column_projection varchar2(1) default ('N');
-- display table infos
g_tabinfos varchar2(1) default ('Y');

-----------------------------------------------------------
-- set/unset bugged flag
procedure set_bugged (p_is_bugged varchar2 default 'Y')
is
begin
  if upper(p_is_bugged) = 'Y' then
    g_bugged := 'Y';
  else
    g_bugged := 'N';
  end if;
end set_bugged;

-----------------------------------------------------------
-- set/unset use_last flag
procedure set_use_last (p_use_last varchar2 default 'Y')
is
begin
  if upper(p_use_last) = 'Y' then
    g_use_last := 'Y';
  else
    g_use_last := 'N';
  end if;
end set_use_last;

-----------------------------------------------------------
-- set/unset print original (not decoded) peeked bind xml string flag
procedure set_print_orig_peeked (p_print_orig_peeked varchar2 default 'Y')
is
begin
  if upper(p_print_orig_peeked) = 'Y' then
    g_print_orig_peeked := 'Y';
  else
    g_print_orig_peeked := 'N';
  end if;
end set_print_orig_peeked;

-----------------------------------------------------------
-- set/unset query_block_name flag
procedure set_query_block_name (p_query_block_name varchar2 default 'Y')
is
begin
  if upper (p_query_block_name) = 'Y' then
    g_query_block_name := 'Y';
  else
    g_query_block_name := 'N';
  end if;
end set_query_block_name;

-----------------------------------------------------------
-- set/unset column_projection  flag
procedure set_column_projection (p_column_projection varchar2 default 'Y')
is
begin
  if upper (p_column_projection) = 'Y' then
    g_column_projection := 'Y';
  else
    g_column_projection := 'N';
  end if;
end set_column_projection;

-----------------------------------------------------------
-- set/unset tabinfos flag
procedure set_tabinfos (p_tabinfos varchar2 default 'N')
is
begin
  if upper (p_tabinfos) = 'N' then
    g_tabinfos := 'N';
  else
    g_tabinfos := 'Y';
  end if;
end set_tabinfos;

-----------------------------------------------------------
function get_version 
return varchar2 is
begin
	return '$Id: sga_xplan.sql,v 1.7 2007-08-30 16:08:28 adellera Exp $ (Alberto Dell''Era)';
end get_version;

-----------------------------------------------------------
procedure print (
  p_sql_like    varchar2 default null, 
  p_module_like varchar2 default null,
  p_action_like varchar2 default null,
  p_format      varchar2 default 'all'
)
is
begin
  for l in (select plan_table_output
              from table (sga_xplan.display (
                           p_sql_like, 
                           p_module_like,
                           p_action_like,
                           p_format))
           )
  loop
    dbms_output.put_line (l.plan_table_output);
  end loop;
end print;

-----------------------------------------------------------
function bugged_columns
return varchar2
is
begin
  if g_bugged_cols is null then
    
    for x in (select /*+ cursor_sharing_exact sga_xplan_exec */ 
                     decode (column_name, 'ACCESS_PREDICATES', '''bug 2525630''',
                                          'FILTER_PREDICATES', '''bug 2525630''',
                             '"'||column_name||'"') as column_name
                from all_tab_columns
               where owner = g_owner
                 and table_name = upper('sga_xplan_va_v$sql_plan')
               order by column_id)
    loop
      g_bugged_cols := g_bugged_cols || x.column_name || ',';
    end loop;
    
  end if;
  
  return g_bugged_cols;
end bugged_columns;

-----------------------------------------------------------
function bugged_columns_all
return varchar2
is
begin
  if g_bugged_cols_all is null then
    
    for x in (select /*+ cursor_sharing_exact sga_xplan_exec */ 
                     decode (column_name, 'ACCESS_PREDICATES', '''bug 2525630''',
                                          'FILTER_PREDICATES', '''bug 2525630''',
                             '"'||column_name||'"') as column_name
                from all_tab_columns
               where owner = g_owner
                 and table_name = upper('sga_xplan_va_v$sql_plan_sall')
               order by column_id)
    loop
      g_bugged_cols_all := g_bugged_cols_all || x.column_name || ',';
    end loop;
    
  end if;
  
  return g_bugged_cols_all;
end bugged_columns_all;

-----------------------------------------------------------
procedure purge_tables (
  p_deadline_date date    default null,
  p_truncate      boolean default false,
  p_dump_id       int     default null
)
is
  pragma autonomous_transaction;
begin
  if p_truncate then 
    execute immediate ('truncate /*+ sga_xplan_exec */ table sga_xplan_v$sql');
    execute immediate ('truncate /*+ sga_xplan_exec */ table sga_xplan_v$sqltext_nl');
    execute immediate ('truncate /*+ sga_xplan_exec */ table sga_xplan_v$sql_plan');
    execute immediate ('truncate /*+ sga_xplan_exec */ table sga_xplan_v$sql_plan_stat');
    execute immediate ('truncate /*+ sga_xplan_exec */ table sga_xplan_v$sql_plan_sall');
  else 
    delete /*+ sga_xplan_exec */ 
      from sga_xplan_v$sql 
     where (p_deadline_date is null or sga_xplan_dump_date < p_deadline_date)
       and (p_dump_id       is null or sga_xplan_dump_id = p_dump_id);
       
    delete /*+ sga_xplan_exec */ 
      from sga_xplan_v$sqltext_nl
     where p_deadline_date is null 
        or statement_id not in (select statement_id from sga_xplan_v$sql);
    delete /*+ sga_xplan_exec */ 
      from sga_xplan_v$sql_plan
     where p_deadline_date is null 
        or statement_id not in (select statement_id from sga_xplan_v$sql);
    --delete /*+ sga_xplan_exec */ from sga_xplan_v$sql_plan_stat
    -- where p_deadline_date is null 
    --    or statement_id not in (select statement_id from sga_xplan_v$sql); 
    delete /*+ sga_xplan_exec */ from sga_xplan_v$sql_plan_sall
     where p_deadline_date is null 
        or statement_id not in (select statement_id from sga_xplan_v$sql); 
  end if;
  commit;
end purge_tables;

-----------------------------------------------------------
function dump_plans_internal (
  p_sql_like       varchar2 default null, 
  p_module_like    varchar2 default null,
  p_action_like    varchar2 default null,
  p_transient_pool boolean  default false
)
return int
is
  pragma autonomous_transaction;
  l_sga_xplan_dump_id sga_xplan_v$sql.sga_xplan_dump_id%type;
  l_sga_xplan_skip_pattern varchar2 (20 char);
begin
  -- calc sga_xplan_dump_id (negative if transient pool)
  select sga_xplan_v$sql_plan_seq.nextval into l_sga_xplan_dump_id from dual;
  if p_transient_pool then
    l_sga_xplan_dump_id := - l_sga_xplan_dump_id;
  end if;
  
  -- dump the matching sql statements (all stmts will have the same sga_xplan_dump_id)
  -- ignore statements generated by sga_xplan unless the user is after them
  if not lower(p_sql_like) like '%sga_xplan_exec%' then
    l_sga_xplan_skip_pattern := '%sga_xplan_exec%';
  else
    l_sga_xplan_skip_pattern := ' ';
  end if;
  insert /*+ append sga_xplan_exec */ into sga_xplan_v$sql
  select sga_xplan_v$sql_plan_seq.nextval, sysdate, l_sga_xplan_dump_id, t.*
    from sga_xplan_va_v$sql t
         -- NB keep the where clause aligned with display_stored_plans
   where (p_sql_like    is null or lower(sql_text) like lower(p_sql_like   ))
     and (p_action_like is null or lower(action  ) like lower(p_action_like))
     and (p_module_like is null or lower(module  ) like lower(p_module_like))
     and not lower (sql_text) like ('%sga\_xplan.print%'        ) escape '\'
     and not lower (sql_text) like ('%sga\_xplan.display%'      ) escape '\'
     and not lower (sql_text) like ('%sga\_xplan.dump\_plans%'  ) escape '\'
     and not lower (sql_text) like ('%dbms\_application\_info.%') escape '\'
     and not lower (sql_text) like (l_sga_xplan_skip_pattern    )
     and (parse_calls > 0 or executions > 0);
  commit;
  
  -- dump the full sql text 
  insert /*+ append sga_xplan_exec */ into sga_xplan_v$sqltext_nl
  select s.statement_id, t.*
    from sga_xplan_v$sql s, sga_xplan_va_v$sqltext_nl t
   where s.address    = t.address 
     and s.hash_value = t.hash_value
     and s.sga_xplan_dump_id = l_sga_xplan_dump_id;
  commit;

  -- dump v$sql_plan and v$sql_plan_statistics following
  -- internal fixed-table fixed-indexes instead of full-scanning.
  -- This is to minimize the probability of hitting bug 2525630,
  -- since we scan filter_predicates and access_predicates only
  -- when needed, and to improve performance in the most common
  -- case of being interested in only a subset of the statements 
  -- contained in the library cache.
  
  for x in (select /*+ sga_xplan_exec */ statement_id, address, hash_value, child_number 
              from sga_xplan_v$sql
             where sga_xplan_dump_id = l_sga_xplan_dump_id)
  loop
    if g_bugged = 'N' then
      -- NB keep aligned with statement below
      insert /*+ sga_xplan_exec */ into sga_xplan_v$sql_plan
      select x.statement_id statement_id,
             t.*,
             0 object_instance,
             case when g_db_version < 10 then null else x.statement_id end plan_id -- optimization for 9i
        from sga_xplan_va_v$sql_plan t
       where address      = x.address 
         and hash_value   = x.hash_value 
         and child_number = x.child_number;
    else
      -- NB keep aligned with statement above
      -- same as above, but without fetching filter_predicates and access_predicates
      -- to avoid ORA-03113 due to bug 2525630.
      -- (this stmt soft parses for each plan, but hopefully we don't see the bug often)
      execute immediate 'insert /*+ sga_xplan_exec */ into sga_xplan_v$sql_plan
        select :statement_id statement_id,
               '||bugged_columns||'
               0 object_instance,
               case when :g_db_version < 10 then null else :statement_id end plan_id
          from sga_xplan_va_v$sql_plan t
         where address      = :address 
           and hash_value   = :hash_value 
           and child_number = :child_number'
      using x.statement_id, g_db_version, x.statement_id, x.address, x.hash_value, x.child_number;
    end if;
     
    /* 
    insert /*+ sga_xplan_exec * into sga_xplan_v$sql_plan_stat
    select x.statement_id statement_id, 
           t.*
      from sga_xplan_va_v$sql_plan_stat t
     where address      = x.address 
       and hash_value   = x.hash_value 
       and child_number = x.child_number;
    */
    
    if g_bugged = 'N' then
        -- NB keep aligned with statement below
      insert /*+ sga_xplan_exec */ into sga_xplan_v$sql_plan_sall
      select x.statement_id statement_id, 
             t.*,
             0 object_instance,
             case when g_db_version < 10 then null else x.statement_id end plan_id -- optimization for 9i
        from sga_xplan_va_v$sql_plan_sall t
       where address      = x.address 
         and hash_value   = x.hash_value 
         and child_number = x.child_number; 
    else
      -- NB keep aligned with statement above
      -- same as above, but without fetching filter_predicates and access_predicates
      -- to avoid ORA-03113 due to bug 2525630.
      -- (this stmt soft parses for each plan, but hopefully we don't see the bug often)
      execute immediate 'insert /*+ sga_xplan_exec */ into sga_xplan_v$sql_plan_sall
        select :statement_id statement_id,
               '||bugged_columns_all||'
               0 object_instance,
               case when :g_db_version < 10 then null else :statement_id end plan_id
          from sga_xplan_va_v$sql_plan_sall t
         where address      = :address 
           and hash_value   = :hash_value 
           and child_number = :child_number'
      using x.statement_id, g_db_version, x.statement_id, x.address, x.hash_value, x.child_number;
    end if;
  end loop;
   
  commit; 
  
  return l_sga_xplan_dump_id;
end dump_plans_internal;

-----------------------------------------------------------
procedure dump_plans (
  p_sql_like       varchar2 default null, 
  p_module_like    varchar2 default null,
  p_action_like    varchar2 default null
)
is
  l_ignore int;
begin
  l_ignore := dump_plans_internal (
    p_sql_like,
    p_module_like,
    p_action_like,
    p_transient_pool => false
  );
end dump_plans;

-----------------------------------------------------------
-- transforms a statement into lines (with maxsize)
-- It's a pretty-printer as well. 
function str2lines (p_text varchar2)
return sga_xplan_plan_row_array
--create or replace procedure str2lines (p_text varchar2)
is
  l_text        long   default trim(p_text)||' ';
  l_text_length number default length(l_text);
  l_pos         int    default 1;
  l_chunk_size  int    default 124;
  l_lines       sga_xplan_plan_row_array := sga_xplan_plan_row_array();
  l_curr        varchar2(400);
  l_curr_lower  varchar2(400);
  l_last        int;
begin
  loop
    l_curr := substr (l_text, l_pos, l_chunk_size);
    -- chop at the FIRST newline, if any
    l_last := instr (l_curr, chr(10));
    -- if not, chop at the LAST blank, if any
    if l_last <= 0 then 
      l_last := instr (l_curr, ' ', -1);
    end if;
    -- if not, chop BEFORE an operator or separator
    if l_last <= 0 then 
      l_curr_lower := lower (l_curr);
      l_last := -1 + greatest (instr (l_curr      , '<=', -1), 
                               instr (l_curr      , '>=', -1),
                               instr (l_curr      , '<>', -1),
                               instr (l_curr      , '!=', -1),
                               instr (l_curr      , '=' , -1), 
                               instr (l_curr      , '<' , -1),
                               instr (l_curr      , '>' , -1),
                               instr (l_curr      , ',' , -1),
                               instr (l_curr      , ';' , -1),
                               instr (l_curr      , '+' , -1),
                               instr (l_curr      , '-' , -1),
                               instr (l_curr      , '*' , -1),
                               instr (l_curr      , '/' , -1),
                               instr (l_curr      , '(' , -1));
      -- handle clash of '=' and '<=', '>=' or '!='
      if l_last > 2 and substr (l_curr, l_last, 2) in ('<=','>=','<>','!=') then
        l_last := l_last-1;
      end if;                         
    end if;
    -- last resort: don't chop
    if l_last <= 0 then
       l_last := l_chunk_size;
    end if;
    -- return line
    l_lines.extend;
    l_lines (l_lines.count) := sga_xplan_plan_row ( 
      --replace ( replace (   
        rtrim (substr (l_curr, 1, l_last), chr(10) )  
      --, chr(10), '!') , ' ', '?') 
    );
    -- advance current position
    l_pos := l_pos + l_last;
    exit when l_pos > l_text_length;
  end loop;
  return l_lines;
end str2lines;

-----------------------------------------------------------
-- formats the number with the provided number of digits
-- to the left and the right of the decimal point.
function f (p_num number, 
            p_left_digits int default 10,
            p_rite_digits int default 0
)
return varchar2
is
  l_fmt varchar2(30) := rpad ('9', p_left_digits, '9')
   || rtrim (rpad ('.', p_rite_digits+1, '9'), '.');
  l_string varchar2(50);
begin
  l_string := to_char (p_num, l_fmt);
  -- return blank string on null
  if l_string is null then
    return rpad (' ', 1+length (l_fmt));
  end if;
  -- return larger string on overflow
  if instr (l_string, '#') > 0 then
    return ltrim (to_char (p_num, lpad (l_fmt, 50, '9')));
  end if;
  return l_string;
end f;

-----------------------------------------------------------
-- aggregates the full statement reading from 
-- sga_xplan_v$sqltext_nl
procedure aggregate_stmt_pieces (
  p_stmt         out nocopy varchar2,
  p_statement_id sga_xplan_v$sql.statement_id%type)
is
begin
  p_stmt := '';
  for x in (select sql_text 
              from sga_xplan_v$sqltext_nl
             where statement_id = p_statement_id
               and piece <= (64000 / 64)
             order by piece)
  loop
    p_stmt := p_stmt || x.sql_text;
  end loop;
end aggregate_stmt_pieces;

-----------------------------------------------------------
procedure get_peeked_binds (
  p_statement_id        int, 
  p_peeked_binds_values out varchar2, 
  p_peeked_binds_types  out varchar2
)
is
  l_other_xml clob;
  l_start int;
  l_start_next int;
  l_end   int;
  l_end_null int;
  l_start_peeked_marker varchar2(30) := '<peeked_binds>';
  l_end_peeked_marker   varchar2(30) := '</peeked_binds>';
  l_peeked_str long;
  l_bind_str  long;
  l_bind_num  int;
  l_nam  varchar2(30 char);
  l_dty  int;
  l_frm int;
  l_mxl int;
  l_value_hex long;
  l_value_raw long raw;
  l_value long;
  l_type varchar2(100);
  l_value_varchar2   varchar2(32700);
  l_value_nvarchar2 nvarchar2(32700);
  l_value_number   number;
  l_value_date     date;
  /*
  l_value_binary_float binary_float;
  l_value_binary_double binary_double;
  */
  l_value_rowid rowid;
  
  function get_prop (p_str varchar2, p_name varchar2)
  return varchar2
  is
    l_pos int; l_start int; l_end int;
  begin
    l_pos := instr (p_str, p_name||'="');
    if l_pos = 0 then return null; end if;
    l_start := instr (p_str, '"', l_pos);
    if l_start = 0 then return '??'; end if;
    l_start := l_start + 1;
    l_end   := instr (p_str, '"', l_start);
    if l_end = 0 then return '???'; end if;
    return substr (p_str, l_start, l_end - l_start);
  end get_prop;
begin
 
  begin
    select /*+ sga_xplan_exec */ other_xml
      into l_other_xml
      from sga_xplan_v$sql_plan
     where statement_id = p_statement_id
       and id = 1
       and other_xml is not null;
  exception
    when no_data_found then
      return;
  end;
  
  l_start := dbms_lob.instr (l_other_xml, l_start_peeked_marker, 1);
  if l_start = 0 or l_start is null then
    return;
  end if;
  l_start := l_start + length(l_start_peeked_marker);
   
  l_end := dbms_lob.instr (l_other_xml, l_end_peeked_marker, l_start);
  if l_end = 0 or l_end is null then
    p_peeked_binds_types  := 'peeked binds types: end not found ';
    return;
  end if;
  
  if l_end - l_start > 32000 then
    p_peeked_binds_types  := 'peeked binds types: peeked binds too long ';
    return;
  end if;
  
  l_peeked_str := dbms_lob.substr (l_other_xml, l_end - l_start, l_start);
    
  if g_print_orig_peeked = 'Y' then
    p_peeked_binds_values := 'original peeked bind xml:';
    p_peeked_binds_types  := substr (l_peeked_str, 1, 200);
    return;
  end if;
  
  -- format: <bind nam=":X" pos="1" dty="1" csi="873" frm="1" mxl="32">58</bind>
  --      or <bind nam=":X" pos="1" dty="1" csi="873" frm="1" mxl="32"/> (for nulls)
  l_bind_num := 1;
  p_peeked_binds_values := 'peeked binds values:';
  p_peeked_binds_types  := 'peeked binds types :';
  loop
    l_start       := instr (l_peeked_str, '<bind ', 1, l_bind_num);
    exit when l_start = 0 or l_start is null;
    l_start_next  := instr (l_peeked_str, '<bind ', l_start + length ('<bind '));
    if l_start_next = 0 then
      l_bind_str := substr (l_peeked_str, l_start);
    else
      l_bind_str := substr (l_peeked_str, l_start, l_start_next - l_start);
    end if;
      
    l_end      := instr (l_bind_str, '</bind>');
    l_end_null := instr (l_bind_str, '/>'     );
    if (l_end = 0 or l_end is null) and (l_end_null = 0 or l_end_null is null) then
      p_peeked_binds_types  := 'peeked binds types: xml error end='||l_end||' end_null='||l_end_null||' '||l_bind_str;
      return;
    end if;
    
    if l_end > 0 then
      l_value_hex := substr (l_bind_str, instr (l_bind_str, '>')+1, l_end - instr (l_bind_str, '>')-1);
      begin
        l_value_raw  := hextoraw (l_value_hex);
      exception
        when others then
          raise_application_error (-20002, 'l_value_hex="'||l_value_hex||'" '||sqlerrm);
      end;
    elsif l_end_null > 0 then
      l_value_hex := null;
      l_value_raw := null;
    else 
      p_peeked_binds_types  := 'peeked binds types: xml misformat';
      return;
    end if;

    l_nam := get_prop  (l_bind_str, 'nam');
    l_mxl := to_number (get_prop (l_bind_str, 'mxl'));
    l_dty := to_number (get_prop (l_bind_str, 'dty'));
    l_frm := trim(get_prop (l_bind_str, 'frm'));
    -- For dty codes, see "Call Interface Programmer's Guide", "Datatypes"
    -- Also, "select text from dba_views where view_name = 'USER_TAB_COLS'" gives
    -- a decode function to interpret them. charsetform is the "frm" in the xml string.
    -- Generally frm=2 means NLS charset.
    if l_dty = 1 and l_frm = '1' then -- varchar2 
      dbms_stats.convert_raw_value (l_value_raw, l_value_varchar2);
      l_value := ''''||l_value_varchar2||'''';
      l_type  := 'varchar2('||l_mxl||')';
    elsif l_dty = 1 and l_frm = '2' then -- nvarchar2 
      dbms_stats.convert_raw_value_nvarchar (l_value_raw, l_value_nvarchar2);
      l_value := ''''||l_value_nvarchar2||'''';
      l_type  := 'nvarchar2('||l_mxl||')';
    elsif l_dty = 2 then -- number
      dbms_stats.convert_raw_value (l_value_raw, l_value_number);
      l_value := nvl (to_char(l_value_number), 'null');
      l_type  := 'number('||l_mxl||')';
    elsif l_dty = 12 then -- date
      dbms_stats.convert_raw_value (l_value_raw, l_value_date);
      l_value := nvl (to_char (l_value_date, 'yyyy/mm/dd hh24:mi:ss'), 'null');
      l_type  := 'date';
    elsif l_dty = 23 then -- raw
      l_value := nvl (to_char(l_value_hex), 'null');
      l_type  := 'raw('||l_mxl||')';  
    elsif l_dty = 69  then -- rowid (not fully tested)
      dbms_stats.convert_raw_value_rowid (l_value_raw, l_value_rowid);
      l_value := nvl (rowidtochar (l_value_rowid), 'null');
      l_type  := 'rowid';
    elsif l_dty = 96 and l_frm = '1' then -- char 
      dbms_stats.convert_raw_value (l_value_raw, l_value_varchar2);
      l_value := ''''||l_value_varchar2||'''';
      l_type  := 'char('||l_mxl||')';
    elsif l_dty = 96 and l_frm = '2' then -- nchar 
      dbms_stats.convert_raw_value_nvarchar (l_value_raw, l_value_nvarchar2);
      l_value := ''''||l_value_nvarchar2||'''';
      l_type  := 'nchar('||l_mxl||')';  
    /*
    elsif l_dty = 100  then -- binary_float
      dbms_stats.convert_raw_value (l_value_raw, l_value_binary_float);
      l_value := to_char (l_value_binary_float);
      l_type  := 'binary_float';
    elsif l_dty = 101  then -- binary_double
      dbms_stats.convert_raw_value (l_value_raw, l_value_binary_double);
      l_value := to_char (l_value_binary_double);
      l_type  := 'binary_double';
    */
    else
      l_value := '(hex)'||l_value_hex;
      l_type  := '[dty='||l_dty||'frm='||l_frm||' mxl='||l_mxl||']';
    end if;
    p_peeked_binds_values := p_peeked_binds_values || ' ' || l_nam || ' = ' || l_value|| ',';
    p_peeked_binds_types  := p_peeked_binds_types  || ' ' || l_nam || ' = ' || l_type || ',';
    l_bind_num := l_bind_num + 1;
  end loop;
  
  p_peeked_binds_values := rtrim (p_peeked_binds_values, ',');
  p_peeked_binds_types  := rtrim (p_peeked_binds_types , ',');
  
  if length(p_peeked_binds_values) > 190 then
    p_peeked_binds_values := substr (p_peeked_binds_values, 1, 180) || '(trunc)';
  end if;
  
  if length(p_peeked_binds_types) > 190 then
    p_peeked_binds_types := substr (p_peeked_binds_types, 1, 180) || '(trunc)';
  end if;
end get_peeked_binds;

-----------------------------------------------------------
function get_referenced_tables (p_statement_id number)
return t_tab_list
is
  type t_tables is table of varchar2(30) index by varchar2(60);
  l_tables t_tables;
  l_tab_list t_tab_list;
  l_tab t_owner_table_name;
  l_owner varchar2(30);
  l_table varchar2(30);
  l_idx varchar2(60);
  l_object_type varchar2 (100);
begin
  for r in (select /*+ sga_xplan_exec */ distinct object_owner, object_name, object_type, object#
              from sga_xplan_v$sql_plan
             where statement_id = p_statement_id
               and object_owner is not null)
  loop
    l_owner := null;
    --dbms_output.put_line ('===> "'||r.object_owner||'","'||r.object_name||'","'||r.object_type||'","'||r.object#);
    -- if object_type is null (probably we are on 9i - v$sql_plan.object_type does not exist on 9i), 
    -- get it from dba_objects
    l_object_type := r.object_type;
    if r.object_owner = 'SYS' and upper(substr (r.object_name, 1, 2)) in ('X$') then
      l_object_type := 'sga_xplan: fixed table';
    end if;
    if l_object_type is null then
      select /*+ sga_xplan_exec */ object_type
        into l_object_type
        from sys.dba_objects
       where object_id = r.object#;
    end if;
    
    if l_object_type = 'sga_xplan: fixed table' then
      null; -- ignore fixed tables 
    elsif l_object_type in ('TABLE', 'TABLE (TEMP)') then
      l_owner := r.object_owner;
      l_table := r.object_name;
    elsif l_object_type in ('INDEX', 'INDEX (UNIQUE)') then
      begin
        select /*+ sga_xplan_exec */ table_owner, table_name
          into l_owner, l_table
          from sys.dba_indexes
         where owner = r.object_owner
           and index_name = r.object_name;
      exception
        when no_data_found then
          l_owner := null;
      end;
    elsif l_object_type in ('TABLE (FIXED)', 'SEQUENCE', 'VIEW') then
      null; -- ignore these objects
    end if;
    if l_owner is not null then
      l_tables (rpad (l_table, 30)||l_owner) := l_table;
    end if;
  end loop;
  
  if l_tables.count > 0 then
    l_idx := l_tables.first;
    while (l_idx is not null) loop
      l_tab.owner      := substr (l_idx, 31);
      l_tab.table_name := l_tables (l_idx);
      l_tab_list(l_tab_list.count) := l_tab;
      l_idx := l_tables.next(l_idx);
    end loop;
  end if;
   
  return l_tab_list;
end get_referenced_tables;

-----------------------------------------------------------
function display_stored_plans (
  p_sql_like    varchar2 default null, 
  p_module_like varchar2 default null,
  p_action_like varchar2 default null,
  p_dump_id     int      default null,
  p_format      varchar2 default 'all'
)
return sga_xplan_plan_row_array
pipelined
is
  l_plan_found boolean default false;
  l_lines sga_xplan_plan_row_array;
  l_first_line_printed boolean;
  l_first_row_source_line number;
  l_more_line varchar2(50);
  l_id int;
  l_e number;
  l_plan_statistics_available boolean;
  l_stmt_text long;
  l_mod_cat_infos   varchar2(200);
  l_load_times_infos varchar2(200);
  l_ignore_block boolean default false;
  l_block_name varchar2(30);
  l_peeked_binds_values long;
  l_peeked_binds_types  long; 
  l_out varchar2(300);
  l_allstats varchar2(30);
  l_filter_preds varchar2(30);
  l_cursor sys_refcursor;
  l_line_temp long;
  l_tab_list t_tab_list;
begin
  -- for each statement
  for stmt in (select /*+ sga_xplan_exec */
                      t.*,
                      decode (executions, 0, to_number(null), executions) execs
                 from sga_xplan_v$sql t
                      -- NB keep the where clause aligned with dump_plans
                where (p_sql_like    is null or lower(sql_text) like lower(p_sql_like   ))
                  and (p_action_like is null or lower(action  ) like lower(p_action_like))
                  and (p_module_like is null or lower(module  ) like lower(p_module_like))
                  and (p_dump_id     is null or sga_xplan_dump_id = p_dump_id)
                order by sql_text, child_number, sga_xplan_dump_date)
  loop
    pipe row ( sga_xplan_plan_row('======================================================================') );
    l_plan_found := true;
    l_plan_statistics_available := false;
    
    -- print module and action info (if available), and dump date
    l_mod_cat_infos := null;
    if stmt.module is not null then
      l_mod_cat_infos := l_mod_cat_infos || 'module: ' || stmt.module || ', ';
    end if;
    if stmt.action is not null then
      l_mod_cat_infos := l_mod_cat_infos || 'action: ' || stmt.action || ', ';
    end if;
    if stmt.sga_xplan_dump_date is not null then
      l_mod_cat_infos := l_mod_cat_infos || 'dump_date: ' ||
                         to_char (stmt.sga_xplan_dump_date, 'yyyy/mm/dd hh24:mi:ss');
    end if;
    if stmt.sql_id is not null then
      l_mod_cat_infos := l_mod_cat_infos || ', sql_id: ' || stmt.sql_id;
    end if;
    if l_mod_cat_infos is not null then
      pipe row ( sga_xplan_plan_row ( rtrim (l_mod_cat_infos, ', ') ) );
    end if;
    
    -- print load times
    l_load_times_infos :=  'first_load_time: ' || to_char ( to_date (stmt.first_load_time, 'yyyy-mm-dd/hh24:mi:ss'),'yyyy/mm/dd hh24:mi:ss')
                       || ', last_load_time: ' || to_char ( to_date (stmt. last_load_time, 'yyyy-mm-dd/hh24:mi:ss'),'yyyy/mm/dd hh24:mi:ss');
    pipe row ( sga_xplan_plan_row ( l_load_times_infos ) );
    
    -- print statement text
    l_e := case when g_use_last = 'N' then stmt.execs else 1 end;
    pipe row ( sga_xplan_plan_row (' ') );
    aggregate_stmt_pieces (l_stmt_text, stmt.statement_id);
    l_lines := str2lines (l_stmt_text);
    for i in l_lines.first .. l_lines.last loop
      pipe row (l_lines (i));
    end loop;
    
    -- print plan   
    pipe row ( sga_xplan_plan_row(' ') );         
    l_first_line_printed := false;    
    l_first_row_source_line := null;   
    l_block_name := 'sql text';      
    for line in (select /*+ sga_xplan_exec */ plan_table_output, rownum line_num
                  from table 
                       (
                       dbms_xplan.display 
                       (
                         'sga_xplan_v$sql_plan',
                         stmt.statement_id,
                         p_format
                       )
                       )
                )
    loop
      -- print all but the first blank lines
      if l_first_line_printed or trim (line.plan_table_output) is not null then
        l_first_line_printed := true;
        l_more_line := '';
        
        -- print peeked binds 
        if l_block_name = 'sql text' and 
           (substr (line.plan_table_output, 1, 8) = '--------' or line.plan_table_output like 'Plan hash value%')
        then
          get_peeked_binds (stmt.statement_id, l_peeked_binds_values, l_peeked_binds_types);
          if l_peeked_binds_values is not null then
            pipe row ( sga_xplan_plan_row (l_peeked_binds_values) );
          end if;
          if l_peeked_binds_types is not null then
            pipe row ( sga_xplan_plan_row (l_peeked_binds_types) );
          end if;
          l_block_name := 'after sql text';
        end if;
           
        -- add v$sql_plan_statistics.output_rows avg value after each row source op
        if upper(line.plan_table_output) like '|%ID%|%OPERATION%|%' then
          l_first_row_source_line := line.line_num + 2;
          l_more_line := ' Real Rows(real-estd)';
          l_block_name := 'row source';
        end if;
        
        l_id := line.line_num - l_first_row_source_line;
        if l_id >= 0 then          
          if substr (line.plan_table_output, 1, 5) = '-----' then
            l_first_row_source_line := null; -- out of row-source block
            l_block_name := 'after row source';
          else
            -- add real cardinality to the right
            for i in (select /*+ sga_xplan_exec */
                             case when g_use_last = 'N' then
                               s.output_rows/decode (s.starts, 0, to_number(null), s.starts)/l_e
                             else 
                               s.last_output_rows/decode (s.last_starts, 0, to_number(null), s.last_starts)
                             end as card,
                             case when g_use_last = 'N' then
                               s.output_rows/decode (s.starts, 0, to_number(null), s.starts)/l_e - p.cardinality 
                             else
                               s.last_output_rows/decode (s.last_starts, 0, to_number(null), s.last_starts) - p.cardinality
                             end as card_diff
                        from sga_xplan_v$sql_plan p, sga_xplan_v$sql_plan_sall s 
                       where s.statement_id = stmt.statement_id
                         and s.id = l_id
                         and s.statement_id = p.statement_id
                         and s.id = p.id
                         )
            loop
              l_more_line := f ( i.card, 8) ||' ('|| f (i.card_diff, 8) ||')';
              if i.card is not null then 
                l_plan_statistics_available := true;
              end if;
            end loop;
          end if;
        end if;
        
        -- ignore "Query Block Name" and "Column Projection Information"
        if l_block_name not in ('sql text', 'row source') then 
          if upper(line.plan_table_output) like 'QUERY BLOCK NAME%' then
            l_ignore_block := g_query_block_name = 'N';
          elsif upper(line.plan_table_output) like 'PREDICATE INFORMATION%' then
            l_ignore_block := false;
          elsif upper(line.plan_table_output) like 'COLUMN PROJECTION INFORMATION%' then
            l_ignore_block := g_column_projection = 'N';
          elsif upper(line.plan_table_output) like 'NOTE%' then
            l_ignore_block := false;
          elsif nvl (substr (line.plan_table_output, 1, 1), ' ') not in (' ','-') then
            l_ignore_block := false;
          end if;  
        end if;
        
        if not l_ignore_block then
          pipe row ( sga_xplan_plan_row (line.plan_table_output || l_more_line) );
        else
          null; -- pipe row ( sga_xplan_plan_row ('========>'|| line.plan_table_output || l_more_line) );
        end if;      
      end if;
    end loop;   
    
    -- print ALLSTATS statististics (10g only)
    if g_db_version >= 10 and l_plan_statistics_available then 
      if g_use_last = 'N' then
        l_allstats := 'allstats';
      else
        l_allstats := 'allstats last';
      end if;
      l_filter_preds := 'statement_id = '||stmt.statement_id;
      open l_cursor for  
       'select /*+ sga_xplan_exec */ plan_table_output
          from table (dbms_xplan.display (
                        ''sga_xplan_v$sql_plan_sall'',
                        null,
                        :allstats,
                        :filter_preds
                      ))'
        using l_allstats, l_filter_preds;            
      loop
        fetch l_cursor into l_line_temp;
        if l_cursor%notfound then
          close l_cursor;
          exit;
        end if;
        pipe row ( sga_xplan_plan_row (l_line_temp) );
      end loop;
    end if;
    
    -- print row-source execution statistics (from v$sql_plan_statistics), averaged by starts
    if l_plan_statistics_available then
      if g_use_last = 'N' then
        pipe row ( sga_xplan_plan_row ('v$sql_plan_statistics.stat / v$sql_plan_statistics.starts / v$sql.executions'));
      else
        pipe row ( sga_xplan_plan_row ('v$sql_plan_statistics.LAST_stat / v$sql_plan_statistics.LAST_starts'));
      end if;
      pipe row ( sga_xplan_plan_row ('-------------------------------------------------------------------------------------------------------------'));
      pipe row ( sga_xplan_plan_row ('| id  | output_rows    | cr_buffer_gets | cu_buffer_gets | disk_reads     | disk_writes    | elapsed (usec) |'));
      pipe row ( sga_xplan_plan_row ('-------------------------------------------------------------------------------------------------------------'));
    
      for s in (select /*+ sga_xplan_exec */
                       id as id, 
                       case when g_use_last = 'N' 
                            then decode (starts, 0, to_number(null), starts) 
                            else decode (last_starts, 0, to_number(null), last_starts) 
                       end as starts,
                       case when g_use_last = 'N' then output_rows    else last_output_rows    end as output_rows, 
                       case when g_use_last = 'N' then cr_buffer_gets else last_cr_buffer_gets end as cr_buffer_gets,
                       case when g_use_last = 'N' then cu_buffer_gets else last_cu_buffer_gets end as cu_buffer_gets, 
                       case when g_use_last = 'N' then disk_reads     else last_disk_reads     end as disk_reads, 
                       case when g_use_last = 'N' then disk_writes    else last_disk_writes    end as disk_writes, 
                       case when g_use_last = 'N' then elapsed_time   else last_elapsed_time   end as elapsed_time 
                  from sga_xplan_v$sql_plan_sall
                 where statement_id = stmt.statement_id
                 order by id)
      loop
        pipe row ( sga_xplan_plan_row ('|'||to_char (s.id,'999')||' |'
          || f(s.output_rows   / s.starts / l_e, 12,1) ||' |'
          || f(s.cr_buffer_gets/ s.starts /l_e, 12,1) ||' |'
          || f(s.cu_buffer_gets/ s.starts /l_e, 12,1) ||' |'
          || f(s.disk_reads    / s.starts /l_e, 12,1) ||' |'
          || f(s.disk_writes   / s.starts /l_e, 12,1) ||' |'
          || f(s.elapsed_time  / s.starts /l_e, 12,1) ||' |'
        ));
      end loop;
      if l_plan_statistics_available then
        pipe row ( sga_xplan_plan_row ('-------------------------------------------------------------------------------------------------------------'));
      end if;
    end if;
    
    -- print row-source execution statistics (from v$sql_plan_statistics)
    if l_plan_statistics_available then
      if g_use_last = 'N' then
        pipe row ( sga_xplan_plan_row ('v$sql_plan_statistics.stat / v$sql.executions'));
      else
        pipe row ( sga_xplan_plan_row ('v$sql_plan_statistics.LAST_stat'));
      end if;
      pipe row ( sga_xplan_plan_row ('------------------------------------------------------------------------------------------------------------------------------'));
      pipe row ( sga_xplan_plan_row ('| id  | output_rows    | cr_buffer_gets | cu_buffer_gets | disk_reads     | disk_writes    | elapsed (usec) | starts         |'));
      pipe row ( sga_xplan_plan_row ('------------------------------------------------------------------------------------------------------------------------------'));
    
      for s in (select /*+ sga_xplan_exec */
                       id as id,
                       case when g_use_last = 'N' then starts         else last_starts         end as starts,
                       case when g_use_last = 'N' then output_rows    else last_output_rows    end as output_rows, 
                       case when g_use_last = 'N' then cr_buffer_gets else last_cr_buffer_gets end as cr_buffer_gets,
                       case when g_use_last = 'N' then cu_buffer_gets else last_cu_buffer_gets end as cu_buffer_gets, 
                       case when g_use_last = 'N' then disk_reads     else last_disk_reads     end as disk_reads, 
                       case when g_use_last = 'N' then disk_writes    else last_disk_writes    end as disk_writes, 
                       case when g_use_last = 'N' then elapsed_time   else last_elapsed_time   end as elapsed_time
                  from sga_xplan_v$sql_plan_sall
                 where statement_id = stmt.statement_id
                 order by id)
      loop
        pipe row ( sga_xplan_plan_row ('|'||to_char (s.id,'999')||' |'
          || f(s.output_rows   /l_e, 12,1) ||' |'
          || f(s.cr_buffer_gets/l_e, 12,1) ||' |'
          || f(s.cu_buffer_gets/l_e, 12,1) ||' |'
          || f(s.disk_reads    /l_e, 12,1) ||' |'
          || f(s.disk_writes   /l_e, 12,1) ||' |'
          || f(s.elapsed_time  /l_e, 12,1) ||' |'
          || f(s.starts        /l_e, 12,1) ||' |'
        ));
      end loop;
    end if;
    if l_plan_statistics_available then
      pipe row ( sga_xplan_plan_row ('------------------------------------------------------------------------------------------------------------------------------'));
    end if;
    if not l_plan_statistics_available then
      pipe row ( sga_xplan_plan_row ('sga_xplan warning: plan statistics not available.') );
    end if;
    
    -- print execution statistics (from v$sql)
    /*
    pipe row ( sga_xplan_plan_row ('---------------------------------------------'));
    pipe row ( sga_xplan_plan_row ('v$sql statname | total       | total / execs|'));
    pipe row ( sga_xplan_plan_row ('---------------------------------------------'));
    pipe row ( sga_xplan_plan_row ('executions     | ' || f (stmt.executions        ) ||' |'|| f (null                           , 10,1)||' |' ));
    pipe row ( sga_xplan_plan_row ('buffer_gets    | ' || f (stmt.buffer_gets       ) ||' |'|| f (stmt.buffer_gets   / stmt.execs, 10,1)||' |' ));
    pipe row ( sga_xplan_plan_row ('disk_reads     | ' || f (stmt.disk_reads        ) ||' |'|| f (stmt.disk_reads    / stmt.execs, 10,1)||' |' ));  
    pipe row ( sga_xplan_plan_row ('rows_processed | ' || f (stmt.rows_processed    ) ||' |'|| f (stmt.rows_processed/ stmt.execs, 10,1)||' |' ));
    pipe row ( sga_xplan_plan_row ('elapsed (usec) | ' || f (stmt.elapsed_time      ) ||' |'|| f (stmt.elapsed_time  / stmt.execs, 10,1)||' |' )); 
    pipe row ( sga_xplan_plan_row ('cpu_time (usec)| ' || f (stmt.cpu_time          ) ||' |'|| f (stmt.cpu_time      / stmt.execs, 10,1)||' |' ));  
    pipe row ( sga_xplan_plan_row ('sorts          | ' || f (stmt.sorts             ) ||' |'|| f (stmt.sorts         / stmt.execs, 10,1)||' |' ));
    pipe row ( sga_xplan_plan_row ('fetches        | ' || f (stmt.fetches           ) ||' |'|| f (stmt.fetches       / stmt.execs, 10,1)||' |' ));
    pipe row ( sga_xplan_plan_row ('parse_calls    | ' || f (stmt.parse_calls       ) ||' |'|| f (stmt.parse_calls   / stmt.execs, 10,1)||' |' ));
    if stmt.direct_writes is not null then
    pipe row ( sga_xplan_plan_row ('direct_writes  | ' || f (stmt.direct_writes     ) ||' |'|| f (stmt.direct_writes / stmt.execs, 10,1)||' |' ));
    end if;
    pipe row ( sga_xplan_plan_row ('sharable_mem   | ' || f (stmt.sharable_mem      ) ||' |'|| f (null                           ,10,1)||' |' ));
    pipe row ( sga_xplan_plan_row ('persistent_mem | ' || f (stmt.persistent_mem    ) ||' |'|| f (null                           , 10,1)||' |' ));
    pipe row ( sga_xplan_plan_row ('runtime_mem    | ' || f (stmt.runtime_mem       ) ||' |'|| f (null                           , 10,1)||' |' ));
    if stmt.end_of_fetch_count is not null then  
    pipe row ( sga_xplan_plan_row ('end_of_fetch_c | ' || f (stmt.end_of_fetch_count) ||' |'|| f (stmt.end_of_fetch_count / stmt.execs, 10,1)||' |' ));
    end if;      
    pipe row ( sga_xplan_plan_row ('---------------------------------------------'));
    */
    
    -- print execution statistics (from v$sql)
    sga_xplan_mcf.reset (p_default_execs => stmt.executions, p_stat_default_decimals => 0, p_stex_default_decimals => 1);
    sga_xplan_mcf.add_line_char ('v$sql statname', 'total', '/exec');
    sga_xplan_mcf.add_line ('executions'     , stmt.executions    , to_number(null));
    sga_xplan_mcf.add_line ('rows_processed' , stmt.rows_processed);
    sga_xplan_mcf.add_line ('buffer_gets'    , stmt.buffer_gets   );
    sga_xplan_mcf.add_line ('disk_reads'     , stmt.disk_reads    );
    sga_xplan_mcf.add_line ('direct_writes'  , stmt.direct_writes );
    sga_xplan_mcf.add_line ('elapsed (usec)' , stmt.elapsed_time  );
    sga_xplan_mcf.add_line ('cpu_time (usec)', stmt.cpu_time      );
    sga_xplan_mcf.add_line ('sorts'          , stmt.sorts         );
    sga_xplan_mcf.add_line ('fetches'        , stmt.fetches       );
    sga_xplan_mcf.add_line ('end_of_fetch_c' , stmt.end_of_fetch_count);
    sga_xplan_mcf.add_line ('parse_calls'    , stmt.parse_calls   );
    sga_xplan_mcf.add_line ('sharable_mem'   , stmt.sharable_mem  , to_number(null));
    sga_xplan_mcf.add_line ('persistent_mem' , stmt.persistent_mem, to_number(null));
    sga_xplan_mcf.add_line ('runtime_mem'    , stmt.runtime_mem   , to_number(null));
    sga_xplan_mcf.add_line ('users_executing', stmt.users_executing);
    
    sga_xplan_mcf.add_line ('application wait (usec)', stmt.application_wait_time);
    sga_xplan_mcf.add_line ('concurrency wait (usec)', stmt.concurrency_wait_time);
    sga_xplan_mcf.add_line ('cluster     wait (usec)', stmt.cluster_wait_time    );
    sga_xplan_mcf.add_line ('user io     wait (usec)', stmt.user_io_wait_time    );
    sga_xplan_mcf.add_line ('plsql exec  wait (usec)', stmt.plsql_exec_time      );
    sga_xplan_mcf.add_line ('java  exec  wait (usec)', stmt.java_exec_time       );
    
    sga_xplan_mcf.prepare_output (p_num_columns => 3);
    loop
      l_out := sga_xplan_mcf.next_output_line;
      exit when l_out is null;
      pipe row ( sga_xplan_plan_row (l_out) );
    end loop;
    
    -- display tabinfos
    if g_tabinfos = 'Y' then
      l_tab_list := get_referenced_tables (stmt.statement_id);
      if l_tab_list.count > 0 then
        for t in l_tab_list.first .. l_tab_list.last loop
          l_cursor := sga_xplan_tabinfo.get_infos_and_cache (l_tab_list(t).owner, l_tab_list(t).table_name);
          loop
            fetch l_cursor into l_out;
            if l_cursor%notfound then
              close l_cursor;
              exit;
            end if;
            pipe row ( sga_xplan_plan_row ( l_out) );
          end loop;
        end loop;
      end if;
    end if;
  end loop;
  
  -- print "no plans" feedback
  if l_plan_found = false then
     pipe row ( sga_xplan_plan_row ('no plan(s) found.') );
  end if;

  return;
/*exception
  -- when others is a necessary evil here with pipelined functions
  when others then
    pipe row ( sga_xplan_plan_row ( 'ERROR '|| sqlerrm ) );
    dbms_output.put_line ( sqlerrm );
    --dbms_output.put_line ( dbms_utility.format_error_backtrace );
    raise_application_error (-20001, 'ERROR - see dbms_output: '||sqlcode);
    return;*/
end display_stored_plans;

-----------------------------------------------------------
function display (
  p_sql_like    varchar2 default null, 
  p_module_like varchar2 default null,
  p_action_like varchar2 default null,
  p_format      varchar2 default 'all'
)
return sga_xplan_plan_row_array
pipelined
is
  l_sga_xplan_dump_id sga_xplan_v$sql.sga_xplan_dump_id%type;
begin 
  -- reset tabinfo cache
  sga_xplan_tabinfo.reset_table_cache;
 
  -- dump plans
  l_sga_xplan_dump_id := 
  dump_plans_internal (
    p_sql_like, 
    p_module_like, 
    p_action_like, 
    p_transient_pool => true
  );
  
  -- call display_stored_plans
  for line in (select /*+ sga_xplan_exec */ plan_table_output 
                from table 
                       (
                       sga_xplan.display_stored_plans 
                       (
                         null,                -- p_sql_like
                         null,                -- p_module_like
                         null,                -- p_action_like
                         l_sga_xplan_dump_id, -- p_dump_id
                         p_format             -- p_format 
                       )
                       )
                )
  loop
    pipe row ( sga_xplan_plan_row (line.plan_table_output) );   
  end loop;

  -- remove dumped plans
  purge_tables (p_deadline_date => null, p_truncate => false, p_dump_id => l_sga_xplan_dump_id);
  
  -- reset tabinfo cache
  sga_xplan_tabinfo.reset_table_cache;
  
  return;
end display;

-----------------------------------------------------------
procedure generate_uninstall
is
begin

  for o in (select /*+ sga_xplan_exec */ o.owner, o.object_type, o.object_name
              from all_objects o
             where o.owner = g_owner
               and o.object_name like 'SGA\_XPLAN%' escape '\'
               and o.object_type not in ('PACKAGE BODY', 'INDEX')
             order by o.object_type, o.object_name desc 
           )
  loop
    dbms_output.put_line ('drop '||o.object_type||' '||o.owner||'.'||o.object_name||';');
  end loop;

end generate_uninstall;

-----------------------------------------------------------
begin
  -- cache some low-level infos in global variables
  select sys_context ('userenv', 'current_user') into g_owner from dual;
  declare 
    l_version varchar2(255);
    l_compat  varchar2(255);
  begin
    dbms_utility.db_version (l_version, l_compat);
    g_db_version := to_number (substr (l_version, 1, instr (l_version, '.') - 1));
  end;
end sga_xplan;
/
show errors;

---- (if requested) grant execute on the package to public, and create a public synonym
set echo on
declare
  l_stmt long;
begin
  if :public_package = 'y' then 
    dbms_output.put_line ('creating public synonym for sga_xplan package');
    l_stmt := 'create or replace public synonym sga_xplan for sga_xplan';
    dbms_output.put_line ('executing: ' || l_stmt);
    execute immediate l_stmt;
    dbms_output.put_line ('granting execute on ga_xplan package to public');
    l_stmt := 'grant execute on sga_xplan to public';
    dbms_output.put_line ('executing: ' || l_stmt);
    execute immediate l_stmt;
  end if;
end;
/

drop package sga_xplan_install;

whenever sqlerror continue

---- sanity check installation

exec sga_xplan.generate_uninstall;

variable x  varchar2(6)
variable y  varchar2(10)
variable z  varchar2(100)
exec :x := null; :y := '678'; :z := null;
select /*+ sga_xplan_marker */ * from (select * from dual d where d.dummy = :x or d.dummy = :y or d.dummy = :z);
exec sga_xplan.set_use_last ('N');
exec sga_xplan.print ('%/* sga_xplan_marker */%');

exec sga_xplan.dump_plans ('%/*+ sga_xplan_marker */%');
select * from table (sga_xplan.display_stored_plans ('%/*+ sga_xplan_marker */%'));
exec sga_xplan.purge_tables;

exec sga_xplan.set_use_last ('Y');
select /*+ sga_xplan_marker */ * from (select * from dual d where d.dummy = :x or d.dummy = :y or d.dummy = :z);
exec sga_xplan.print ('%/*+ sga_xplan_marker */%');

spool off