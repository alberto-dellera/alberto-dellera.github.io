set echo on

create or replace
function exp_dist_balls_uniform (nd number, s number, nr number)
return number
-- Calculates the expected number of distinct values when
-- selecting from a bag without replacement.
-- Case of a "weakly uniform" distribution (and of course
-- of a "uniform" distribution as well).
-- nd = number of distinct values (="color of balls") in bag 
--  s = number of samples (without replacement) from bag
-- nr = num rows (=number of balls)
-- author: Alberto Dell'Era, December 2005
-- $Id: DistinctBallsPlSql.sql,v 1.1 2007-08-30 16:05:22 adellera Exp $
is
  -- bb = "Big   Buckets"
  -- sb = "Small Buckets"
  nd_bb int := mod (nr, nd);
  nd_sb int := nd - nd_bb;
  nb_sb int := floor (nr / nd);
  nb_bb int := ceil  (nr / nd);
 
  card_bb number := 0;
  card_sb number;  
   
  function pnib (nb int, s number, nr int)
  return number
  is
    pnib number := 1;
  begin 
  
    for i in 0 .. nb-1 loop
      pnib := pnib * ( 1 - s / ( nr-i ) );
    end loop;
    
    return pnib;
    
  end pnib;  
begin
       
  if nd_bb > 0 then
    card_bb := nd_bb * (1 - Pnib (nb_bb, s, nr));
  end if;
  
  card_sb := nd_sb * (1 - Pnib (nb_sb, s, nr));
     
  return card_bb + card_sb;
  
end exp_dist_balls_uniform;
/
show errors

-- sanity checks
-- should give 0
select exp_dist_balls_uniform  (4,  0, 10) from dual;
-- should give 1
select exp_dist_balls_uniform  (4,  1, 10) from dual;
-- should give 4
select exp_dist_balls_uniform  (4, 10, 10) from dual;
-- should give approx 2.483333333333333
select exp_dist_balls_uniform  (4,  3, 10) from dual;
-- should give approx 3.047619047619048
select exp_dist_balls_uniform  (4,  4,  9) from dual;
-- should give approx 3.142857142857143
select exp_dist_balls_uniform  (4,  4,  8) from dual;

create or replace synonym swru for exp_dist_balls_uniform;

create or replace type exp_dist_balls_num_array is table of number;
/

create or replace synonym swr_num_array for exp_dist_balls_num_array;  

create or replace
function exp_dist_balls_skewed (nb exp_dist_balls_num_array, s number)
return number
-- Calculates the expected number of distinct values when
-- selecting from a bag without replacement.
-- Case of a "skewed" (general) distribution.
-- nb() = distribution of distinct values (="color of balls") in bag 
--  s   = number of samples (without replacement) from bag
-- author: Alberto Dell'Era, January 2006
-- $Id: DistinctBallsPlSql.sql,v 1.1 2007-08-30 16:05:22 adellera Exp $
is
  l_card number := 0;
  l_nr int := 0;
  
  function pnib (nb int, s number, nr int)
  return number
  is
    pnib number := 1;
  begin 
  
    for i in 0 .. nb-1 loop
      pnib := pnib * ( 1 - s / ( nr-i ) );
    end loop;
    
    return pnib;
    
  end pnib;  
begin
  -- calc total number of balls
  for i in nb.first .. nb.last loop
    l_nr := l_nr + nb(i);
  end loop;
  
  -- calc expected number of distinct values
  for i in nb.first .. nb.last loop
    l_card := l_card + (1 - pnib (nb(i), s, l_nr));
  end loop;
  
  return l_card;
end exp_dist_balls_skewed;
/
show errors

-- sanity checks
-- should give 0
select exp_dist_balls_skewed (exp_dist_balls_num_array(5,2,3,2), 0) from dual;
-- should give 1
select exp_dist_balls_skewed (exp_dist_balls_num_array(5,2,3,2), 1) from dual;
-- should give approx 1.772727272727273
select exp_dist_balls_skewed (exp_dist_balls_num_array(5,2,3,2), 2) from dual;
-- should give approx 3.1780303030303028
select exp_dist_balls_skewed (exp_dist_balls_num_array(5,2,3,2), 5) from dual;
-- should give 4
select exp_dist_balls_skewed (exp_dist_balls_num_array(5,2,3,2), 11) from dual;
-- should give 4
select exp_dist_balls_skewed (exp_dist_balls_num_array(5,2,3,2), 12) from dual;
-- should give approx 2.22619048
select exp_dist_balls_skewed (exp_dist_balls_num_array(3,2,4), 3) from dual;

create or replace synonym swr for exp_dist_balls_skewed;                                                          
                                                          