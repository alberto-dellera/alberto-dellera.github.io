drop table t;
drop table t_stage;

spool exchange_segment.spool
set echo on

-- table t 
create table t (
  pk   int,
  data varchar2(20)
);

alter table t add constraint t_pk primary key(pk);
create unique index t_uq on t (pk, data);
create index t_data_idx on t (data);

insert into t (pk, data) 
select rownum, 'data-' || rownum 
  from all_objects
 where rownum <= 100;
 
create trigger t_trig
after insert or update or delete on t 
for each row
begin
  dbms_output.put_line (:new.pk);
end;
/

create or replace procedure p
as
begin
  for i in (select * from t) loop
     dbms_output.put_line (i.pk);
  end loop;
end p;
/
show errors;

-- table t_stage
create table t_stage 
partition by range (pk) (
  partition p_all_rows values less than (maxvalue)
)
as
select * from t where 1=0;

alter table t_stage 
add constraint t_stage_pk primary key (pk)
using index local;

create unique index t_stage_uq on t_stage (pk, data) local;
create index t_stage_data_idx on t_stage (data) local;

insert /*+ append */ into t_stage 
select -pk, data 
  from t;
commit;

-- open and fetch a statement on t
set echo off 
prompt "------------------------------------------------------------------------------------"
prompt Now press <enter> a couple of times to fetch some rows from t,
prompt and keep the statement open.
prompt
prompt Then go in another session and issue:
prompt
prompt alter table t_stage
prompt exchange partition p_all_rows
prompt with table t
prompt including indexes
prompt without validation;;
prompt 
prompt Then, get back here, press <enter> until all the rows have been fetched;;
prompt you will see that the old rows are fetched.
prompt "------------------------------------------------------------------------------------"
set echo on
set lines 100
set pages 13
set pause on
select * from t;
set pause off
set pages 9999

-- object defined on/dependent from t are still VALID
select object_name, status from user_objects where object_name in (select name from user_dependencies where referenced_name='T');

spool off


