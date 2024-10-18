-- as_of_scn_views demo - setup.
-- Run this at the remote database, as a user that
-- (a) has the "create view" privilege granted directly to it,
-- (b) has the "execute" privilege on sys.dbms_flashback granted directly to it,
-- (c) is the user that the db-link connection connects to.
-- Note: (c) is for easy of demonstration only, you can of course
-- use anothe user for connecting, and grant the necessary privileges
-- in order to make the db-link "see" the as-of-scn views.  

drop table t1;
drop table t2;

set verify on
set echo on
spool as_of_scn_views_setup.spool

create table t1 (x int);
create table t2 (x int);

create or replace package as_of_scn_views_pkg is

-- get the current SCN 
function get_remote_scn return number;

-- create an as-of-scn view reading at the point in time
-- defined by the parameter p_as_of_scn 
procedure create_as_of_scn_view (
  p_table_name varchar2, 
  p_view_name  varchar2, 
  p_as_of_scn  number
);

end as_of_scn_views_pkg;
/
show errors;

create or replace package body as_of_scn_views_pkg is

function get_remote_scn return number is
begin
  return sys.dbms_flashback.get_system_change_number;
end get_remote_scn;

procedure create_as_of_scn_view (
  p_table_name varchar2, 
  p_view_name  varchar2, 
  p_as_of_scn  number)
is
  l_stmt long;
begin 
  l_stmt := 'create or replace view ' || p_view_name ||
             ' as select * from ' || p_table_name || ' as of scn ' || p_as_of_scn;
  dbms_output.put_line ('executing: '||l_stmt);
  execute immediate l_stmt;
exception
  when others then
    raise_application_error (-20001, sqlerrm||' while creating '|| p_view_name);   
end create_as_of_scn_view;

end as_of_scn_views_pkg;
/
show errors;

spool off