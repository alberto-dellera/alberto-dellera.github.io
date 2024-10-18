--    Supporting code for the "Select Without Replacement" paper (www.adellera.it).
-- 
--    Some helpers to calculate the additional filtered cardinality for the
--    second join predicate.
--
--    Alberto Dell'Era, August 2007

-- calculates the overlapping ratio for interval a
create or replace function overlapping_ratio_a (a_min number, a_max number, b_min number, b_max number)
return number
is 
  overlap_min     number; overlap_max     number; 
  intersect_a_min number; intersect_a_max number;
begin
  overlap_min := greatest (a_min, b_min);
  overlap_max := least    (a_max, b_max);
  
  if overlap_min > overlap_max then
    raise_application_error (-20001, 'disjunct intervals, a_min='||a_min||' a_max='||a_max||' b_min='||b_min||' b_max='||b_max);
  end if;
  
  intersect_a_min := greatest (a_min, overlap_min);
  intersect_a_max := least    (a_max, overlap_max);
  
  if a_max - a_min = 0 then
    raise_application_error (-20002, 'null interval, a_min='||a_min||' a_max='||a_max||' b_min='||b_min||' b_max='||b_max);
  end if;
  
  return (intersect_a_max - intersect_a_min) / (a_max - a_min);
  
end overlapping_ratio_a;
/
show errors;

-- calculates the overlapping ratio for interval a
create or replace function overlapping_ratio_b (a_min number, a_max number, b_min number, b_max number)
return number
is 
begin
  return overlapping_ratio_a (b_min, b_max, a_min, a_max);
end overlapping_ratio_b;
/
show errors;

-- should be 0.2
select overlapping_ratio_a (0, 100, 98, 142) from dual;
-- should be .045454545
select overlapping_ratio_b (0, 100, 98, 142) from dual;

-- returns 1 if the intervals are disjunct (no overlapping), 0 otherwise
create or replace function is_disjunct_interval (a_min number, a_max number, b_min number, b_max number)
return number
is
  overlap_min     number; overlap_max     number; 
begin
  overlap_min := greatest (a_min, b_min);
  overlap_max := least    (a_max, b_max);
  
  if overlap_min > overlap_max then
    return 1;
  else
    return 0;
  end if;
end is_disjunct_interval;
/
show errors;

select is_disjunct_interval (0, 100, 200, 300) from dual;
select is_disjunct_interval (0, 100, 50, 300) from dual;
