drop table die;

create table die(
  face_id      int not null,
  face_value   int not null,
  probability real not null,
  constraint pk_die primary key (face_id)
);

insert into die (face_id, face_value, probability) values (1, 1, 1/6 + 1/12);
insert into die (face_id, face_value, probability) values (2, 3, 1/6 + 1/12);
insert into die (face_id, face_value, probability) values (3, 4, 1/6 + 1/12);
insert into die (face_id, face_value, probability) values (4, 5, 1/6 - 1/12);
insert into die (face_id, face_value, probability) values (5, 6, 1/6 - 1/12);
insert into die (face_id, face_value, probability) values (6, 8, 1/6 - 1/12);
commit;

exec dbms_stats.gather_table_stats (user, 'die', cascade => true, method_opt=>'for all columns size 254', estimate_percent=>null);