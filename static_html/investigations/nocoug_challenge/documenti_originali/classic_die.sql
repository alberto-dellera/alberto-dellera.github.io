
-- http://en.wikipedia.org/wiki/Binomial_coefficient
create or replace function binomial (n int, k int)
return int
is
  accum number;
  l_k int := k;
begin
    if l_k > n then 
      return null;
    end if;

    if l_k > n/2 then 
      l_k := n - l_k; 
    end if;

    accum := 1;
    for i in 1 .. l_k loop
      accum := accum * (n - l_k + i) / i;
    end loop;
    
    return round(accum);
end binomial;
/
show errors

-- http://mathworld.wolfram.com/Dice.html
create or replace function p_s_n_classic (s int, N int, max_s_1 int)
return number
is
  max_iter int := floor ( (s-N) / max_s_1  );
  accum number := 0;
begin
  for k in 0..max_iter loop
    accum := accum + power (-1, k) * binomial (N, k) * binomial ( s - max_s_1 * k - 1 , N - 1 );
  end loop;
  
  return accum / power (max_s_1, N); 
end p_s_n_classic;
/
show errors

select p_s_n_classic (7 , 2, 6), 1 / 6  as exact from dual;

select p_s_n_classic (2 , 2, 6), 1 / 36 as exact from dual;

select p_s_n_classic (12, 2, 6), 1 / 36 as exact from dual;

