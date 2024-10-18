@create_die.sql

@fft_test_generator.sql

@ft_test_generator.sql

spool check_performance.lst

alter session set workarea_size_policy=manual;
alter session set sort_area_size=100000000;
alter session set hash_area_size=100000000;

--------------------------
-- check performance 
--------------------------
exec fft_test_p (512, 32768, 0, 2);

-- check asymptotic O(N log N) claim
select N, millis, N * log(2, N), millis / (N * log(2, N)) ratio from fft_perf order by N;

select min(ratio), avg(ratio), max (ratio) 
  from (
select millis / (N * log(2, N)) ratio from fft_perf  
       )
;

spool off