
@create_die.sql

@fft_test_generator.sql

@model_test_generator.sql

spool compare_results.lst
set echo on

alter session set workarea_size_policy=manual;
alter session set sort_area_size=100000000;
alter session set hash_area_size=100000000;

--------------------------
-- check correctnes of FFT implementation against Rob van Wijk's Model solution
--------------------------

-- build a random P(s,1)
exec dbms_random.seed (1);
delete from die;
insert into die (face_id, face_value, probability)
select rownum, rownum*2, dbms_random.value (0, 1)
  from dual connect by level <= 10;
update die set probability = probability / (select sum(probability) from die);
commit;

delete from fft_test;
delete from model_test;
commit;

exec fft_test_p    (1, 6, 1);
exec model_test_p  (1, 6, 1);

select * 
  from fft_test, model_test
 where fft_test.N = model_test.N
   and fft_test.s = model_test.s
   and abs (fft_test.probability-model_test.probability) > 1e6
 order by fft_test.N, fft_test.s;
 
spool off 