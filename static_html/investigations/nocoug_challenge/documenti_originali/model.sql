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
select sum_value "Sum"
     , sum(prob) "Probability"
  from all_probabilities
 group by rollup(sum_value)
 order by sum_value
/