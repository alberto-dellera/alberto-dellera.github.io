set echo on

create or replace
function yao (nd number, s number, nr number)
return number
-- nd = number of distinct values (="color of balls") in bag 
--  s = number of samples (without replacement) from bag
-- nr = num rows (=number of balls)
-- author: Alberto Dell'Era, August 2007
-- $Id: yao.sql,v 1.1 2007-08-30 16:05:22 adellera Exp $
is
  d    number := 1 - 1 / nd;
  acc number := 1;
begin
  if nd = 1 or s > nr - nr / nd then
    return nd;
  end if;

  for i in 1..s loop
    acc := acc * (nr*d - i + 1) / (nr - i + 1); 
  end loop;
  return nd * (1 - acc);
end yao;
/
show errors




                                                          
                                                          