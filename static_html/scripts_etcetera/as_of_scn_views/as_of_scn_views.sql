drop table t1_local;
drop table t2_local;

set verify on
set echo on
spool as_of_scn_views.spool

-- place you db-link name here
define db_link=loopback

-- create local tables as a mirror of the remote ones
create table t1_local as select * from t1@&db_link. where 1=0;
create table t2_local as select * from t2@&db_link. where 1=0;

-- fill remote tables with test data
delete from t1@&db_link.;
delete from t2@&db_link.;
insert into t1@&db_link. (x) values (1);
insert into t2@&db_link. (x) values (2);
commit;

-- get current remote scn
variable scn number
exec :scn := as_of_scn_views_pkg.get_remote_scn@&db_link.;

-- create as-of-scn views
begin
  as_of_scn_views_pkg.create_as_of_scn_view@&db_link. ('t1', 't1_scn_view', :scn);
  as_of_scn_views_pkg.create_as_of_scn_view@&db_link. ('t2', 't2_scn_view', :scn);
end;
/
show errors;

-- delete from remote tables
delete from t1@&db_link.;
delete from t2@&db_link.;
commit;

-- copy data from the consistent image
insert /*+ append */ into t1_local select * from t1_scn_view@&db_link.;
commit;
insert /*+ append */ into t2_local select * from t2_scn_view@&db_link.;
commit;

-- show local data
select * from t1_local;
select * from t2_local;

spool off