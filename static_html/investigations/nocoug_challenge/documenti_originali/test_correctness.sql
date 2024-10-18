
@create_die.sql

@classic_die.sql

@fft_test_generator.sql

@ft_test_generator.sql

alter session set workarea_size_policy=manual;
alter session set sort_area_size=100000000;
alter session set hash_area_size=100000000;

spool test_correctness.lst
set echo on

--------------------------
-- check correctnes against uniform die
--------------------------

-- switch to uniform P(s,1) die
delete from die;
insert into die (face_id, face_value, probability) values (1, 1, 1/6);
insert into die (face_id, face_value, probability) values (2, 2, 1/6);
insert into die (face_id, face_value, probability) values (3, 3, 1/6);
insert into die (face_id, face_value, probability) values (4, 4, 1/6);
insert into die (face_id, face_value, probability) values (5, 5, 1/6);
insert into die (face_id, face_value, probability) values (6, 6, 1/6);
commit;

-- fill fft_test with outputs
exec fft_test_p (1, 20, 1);

-- set probability_exact to exact probability from formula
update fft_test set probability_exact = p_s_n_classic (s, N, 6);
commit;

-- return errors (allowing for small rounding errors)
select * from fft_test where abs (probability-probability_exact) > 1e6 order by N, s;

--------------------------
-- check correctnes of FFT implementation against FT definition 
--------------------------

-- build a random P(s,1)
exec dbms_random.seed (0);
delete from die;
insert into die (face_id, face_value, probability)
select rownum, rownum*2, dbms_random.value (0, 1)
  from dual connect by level <= 10;
update die set probability = probability / (select sum(probability) from die);
commit;

delete from fft_test;
delete from ft_test;
commit;

exec fft_test_p (1, 9, 1);
exec ft_test_p  (1, 9, 1);

exec fft_test_p (10, 20, 10);
exec ft_test_p  (10, 20, 10);

select * 
  from fft_test, ft_test
 where fft_test.N = ft_test.N
   and fft_test.s = ft_test.s
   and abs (fft_test.probability-ft_test.probability) > 1e6
 order by fft_test.N, fft_test.s;

spool off

