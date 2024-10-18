-- PL/SQL implementation of the modified Jonathan Lewis' standard formula
-- fringe cases of "range completely inside one of the bands" not implemented
-- tested against the CBO estimates - perfect fit +- 1 due to CBO rounding policy (formula doesn't round)
-- tested on 10.2.0.2 only 

set echo on

create or replace function range_sel_formula (
  low#         varchar2,
  low_x        number,
  high#        varchar2,
  high_x       number,
  min_x        number,
  max_x        number,
  num_rows     number,
  num_distinct number
)
return number
is
  B                            number  := (max_x - min_x) / num_distinct;
  low_x_effective              number  := low_x;
  high_x_effective             number  := high_x;
  low_x_inside_left_band       boolean :=  low_x < min_x + B;
  high_x_inside_right_band     boolean := high_x > max_x - B;
  correction_for_or_equal_oper number  := 0;
  correction_for_special_case  number  := 0;
  height_ramp                  number  := num_rows / num_distinct;
  l_cardinality                number;
begin
  -- input parameters sanity checks
  if    low# in ('>=', '>') and high# in ('<=', '<')
    and low_x  >= min_x and low_x  <= max_x
    and high_x >= min_x and high_x <= max_x
    and low_x < high_x
    and min_x < max_x
    and num_rows >= 0
    and num_distinct >= 1
  then 
    null;
  else
    raise_application_error (-20001, 'range_sel_formula() : illegal parameters');
  end if;

  -- completely in left band
  if low_x < min_x + B and high_x < min_x + B then
    -- not implemented
    return -10;
  end if;

  -- completely in right band
  if low_x > max_x - B and high_x > max_x - B then
    -- not implemented
    return -11;
  end if;

  -- low_x_effective and high_x_effective
  if low# = '>=' and low_x_inside_left_band then
    low_x_effective := min_x + B;
  end if;

  if high# = '<=' and high_x_inside_right_band then
    high_x_effective := max_x - B;
  end if;
  
  -- correction_for_or_equal_oper
  correction_for_or_equal_oper := (1 / num_distinct) 
    * ( (case when low#  = '>=' then 1 else 0 end) 
      + (case when high# = '<=' then 1 else 0 end)
      );

  -- correction_for_special_case
  if low_x  = min_x and low#  = '>' then
    correction_for_special_case := correction_for_special_case + (1 / num_distinct);
  end if;

  if high_x = max_x and high# = '<' then
    correction_for_special_case := correction_for_special_case + (1 / num_distinct);
  end if;

  l_cardinality := num_rows * (high_x_effective - low_x_effective) / (max_x - min_x)
                 + num_rows * correction_for_or_equal_oper
                 - num_rows * correction_for_special_case;
  
  -- round only to compensate for numerical errors
  return round (l_cardinality, 9);
end range_sel_formula;
/
show errors;

select range_sel_formula ('>', 0.1, '<', 7, 0, 10, 4000000, 4) from dual;