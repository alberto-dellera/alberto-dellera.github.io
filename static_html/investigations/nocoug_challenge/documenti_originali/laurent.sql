select sum, sum(prob) probability
  from (
select level l,
       xmlquery(substr(sys_connect_by_path(face_value,'+'),2) returning content).getnumberval() sum,
       xmlquery(substr(sys_connect_by_path(probability,'*'),2) returning content).getnumberval() prob
  from die
  connect by level <= :N
       )
 where l = :N
 group by sum
 order by sum;