
drop table model_test;

create table model_test (
  N                 int    not null,
  s                 int    not null,
  probability       number not null,
  probability_exact number,
  constraint model_test_pk primary key (N,s)
);

drop table model_perf;

create table model_perf (N int not null, millis int not null);

create or replace procedure model_test_p (
  p_min_N       int, 
  p_max_N       int, 
  p_step_N_lin  int default 1, 
  p_step_N_geom int default 0)
is
  l_stmt long;
  l_time_start number;
  l_time_end number;
  N number;
begin
  l_stmt 
  := 'insert into model_test (N, s, probability, probability_exact)'
  || ' select :N, s, probability, null'
  || ' from ('
  || q'|  
with number_of_dies as (select count(*) cnt from die)
, all_probabilities as
( select sum_value
   , prob
       , i
    from (select level l from number_of_dies connect by level <= power(cnt,:N))
       , number_of_dies
   model
         reference r on (select face_id, face_value, probability from die)
           dimension by (face_id)
           measures (face_value,probability)  
         main m
           partition by (l rn, cnt)
           dimension by (0 i)
           measures (0 die_face_id, 0 sum_value, 1 prob, l remainder)
         rules iterate (1000) until (iteration_number + 1 = :N)
         ( die_face_id[0] = 1 + mod(remainder[0]-1,cv(cnt))
         , remainder[0]   = ceil((remainder[0] - die_face_id[0] + 1) / cv(cnt))
         , sum_value[0]   = sum_value[0] + face_value[die_face_id[0]]
         , prob[0]        = prob[0] * probability[die_face_id[0]]
         )
)
select sum_value s
     , sum(prob) probability
  from all_probabilities
  group by sum_value
  )
  |';
   
  N := p_min_N;
  while N <= p_max_N loop
    -- exec FFT
    l_time_start := dbms_utility.get_time;
    execute immediate l_stmt using N, N, N;
    l_time_end := dbms_utility.get_time;
    
    -- insert into performance data
    insert into model_perf (N, millis) values (N, (l_time_end - l_time_start) * 10);
    commit;
    
    -- go to next N
    if p_step_N_lin != 0 then
      N := N + p_step_N_lin;
    else 
      N := N * p_step_N_geom;
    end if;
  end loop;
end model_test_p;
/
show errors;



