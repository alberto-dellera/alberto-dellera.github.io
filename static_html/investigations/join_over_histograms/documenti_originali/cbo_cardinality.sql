-- Supporting code for the "Join over Histograms" paper
--
-- This package parses the equijoin statement between the two table/columns 
-- given as parameters, then retrieves the CBO estimated join cardinality from v$sql_plan.
-- 
-- Since a bug (discovered by Wolfgang Breitling) makes the CBO
-- (sometimes) change its cardinality if you reverse the order of the join predicate,
-- a stored function is available to repeate the parse with the join predicate reversed, 
-- and get both the CBO cardinality estimations..
--
-- (c) Alberto Dell'Era, March 2007
-- Tested in 10.2.0.3.

set echo on
set lines 150
set pages 9999
set define on
set escape off
set serveroutput on size 1000000

spool cbo_cardinality.lst

create or replace package cbo_cardinality is

  -- get the CBO join cardinality estimation for the statement
  -- select ... from <p_lhs_table_name> lhs, <p_rhs_table_name> rhs 
  --  where lhs.<p_lhs_column_name> = rhs.<p_rhs_column_name>
  function get (
    p_lhs_table_name  varchar2,
    p_lhs_column_name varchar2,
    p_rhs_table_name  varchar2,
    p_rhs_column_name varchar2
  )
  return number;

  -- same as "get", but with warnings as well
  function get_with_warn (
    p_lhs_table_name  varchar2,
    p_lhs_column_name varchar2,
    p_rhs_table_name  varchar2,
    p_rhs_column_name varchar2,
    p_warnings        out varchar2
  )
  return number;  
  
  -- return the output of "get" in p_card, and the output of "get" 
  -- with lhs and rhs swapped in p_card_swapped.
  procedure get_both (
    p_lhs_table_name  varchar2,
    p_lhs_column_name varchar2,
    p_rhs_table_name  varchar2,
    p_rhs_column_name varchar2,
    p_card            out number,
    p_card_swapped    out number
  );
  
end cbo_cardinality;
/
show errors;

create or replace package body cbo_cardinality is

function get_internal (
  p_lhs_table_name  varchar2,
  p_lhs_column_name varchar2,
  p_rhs_table_name  varchar2,
  p_rhs_column_name varchar2
)
return number
is
  -- these uniquely identify a statement
  l_start_scn varchar2(100) := dbms_flashback.get_system_change_number;
  l_tag       varchar2(100);

  -- cursor to probe the CBO and its statement text
  l_c     sys_refcursor;
  l_query varchar2(1000);

  -- type for "cursor unique id" below
  type t_stmt_id_record is record (
    address       v$sql.address%type, 
    hash_value    v$sql.hash_value%type,
    child_number  v$sql.child_number%type
  );
  
  -- contains the cursor unique id
  l_stmt_id t_stmt_id_record;

  l_cbo_est_card number;
begin

  -- build an unique (=tagged with unique tage) stmt text
  l_tag := '/*+ test#' || l_start_scn || '.' || dbms_random.random || ' */';
  l_query := l_tag || ' select /*+ use_hash(a,b) */ * '
                   || '   from '||p_lhs_table_name||' a, '||p_rhs_table_name||' b '
                   || '  where a.'||p_lhs_column_name||' = b.'||p_rhs_column_name;

  -- parse the statement
  open l_c for (l_query);
  close l_c;

  -- -----------------------------
  -- | SELECT STATEMENT   |      |
  -- |  HASH JOIN         |      |
  -- |   TABLE ACCESS FULL| T2   |
  -- |   TABLE ACCESS FULL| T1   |
  -- -----------------------------

  -- read cardinality from v$sql_plan
  select address, hash_value, child_number
    into l_stmt_id.address, l_stmt_id.hash_value, l_stmt_id.child_number
    from v$sql
   where sql_text = l_query
     and rownum = 1; -- this alone cuts the elapsed time by 50%
         
  select cardinality
    into l_cbo_est_card
    from v$sql_plan
   where address      = l_stmt_id.address
     and hash_value   = l_stmt_id.hash_value  
     and child_number = l_stmt_id.child_number
     and operation    = 'HASH JOIN';
     
  return l_cbo_est_card;
end get_internal;

function get_with_warn (
  p_lhs_table_name  varchar2,
  p_lhs_column_name varchar2,
  p_rhs_table_name  varchar2,
  p_rhs_column_name varchar2,
  p_warnings        out varchar2
)
return number
is
  l_cbo_1 number;
  l_cbo_2 number;
  l_cbo_min number;
  l_cbo_max number;
begin
  l_cbo_1 := get_internal (p_lhs_table_name, p_lhs_column_name, p_rhs_table_name, p_rhs_column_name);
  l_cbo_2 := get_internal (p_rhs_table_name, p_rhs_column_name, p_lhs_table_name, p_lhs_column_name);
  
  if l_cbo_1 != l_cbo_2 then
    l_cbo_min := least    (l_cbo_1, l_cbo_2);
    l_cbo_max := greatest (l_cbo_1, l_cbo_2);
    p_warnings := 'WARNING: cbo cardinality changes by swapping LHS and RHS'
               || '(min='||l_cbo_min||' max='||l_cbo_max||' diff='||(l_cbo_max-l_cbo_min)||')';
  end if;
  
  return least (l_cbo_1, l_cbo_2);
end get_with_warn;

procedure get_both (
    p_lhs_table_name  varchar2,
    p_lhs_column_name varchar2,
    p_rhs_table_name  varchar2,
    p_rhs_column_name varchar2,
    p_card            out number,
    p_card_swapped    out number
  )
is
begin
  p_card         := get_internal (p_lhs_table_name, p_lhs_column_name, p_rhs_table_name, p_rhs_column_name);
  p_card_swapped := get_internal (p_rhs_table_name, p_rhs_column_name, p_lhs_table_name, p_lhs_column_name);
end get_both;
  
function get (
  p_lhs_table_name  varchar2,
  p_lhs_column_name varchar2,
  p_rhs_table_name  varchar2,
  p_rhs_column_name varchar2
)
return number
is
  l_warn varchar2(200 char);
  l_ret number;
begin
  l_ret := get_with_warn (p_lhs_table_name, p_lhs_column_name, p_rhs_table_name, p_rhs_column_name, l_warn);
  dbms_output.put_line (l_warn);
  return l_ret;
end get;

end cbo_cardinality;
/
show errors;

-- sanity check installation
drop table t1;
drop table t2;

create table t1 as select rownum x from dual connect by level <= 10;
create table t2 as select rownum y from dual connect by level <= 10;
exec dbms_stats.gather_table_stats (user, 't1', method_opt=>'for all columns size 1');
exec dbms_stats.gather_table_stats (user, 't2', method_opt=>'for all columns size 1');

select cbo_cardinality.get ('t1','x','t2','y') from dual;
variable card number
variable w varchar2(200)
exec :card := cbo_cardinality.get_with_warn ('t1','x','t2','y',:w);
print card
print w

spool off
