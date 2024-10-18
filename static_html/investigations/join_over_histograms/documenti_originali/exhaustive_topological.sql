-- Supporting code for the "Join over Histograms" paper
--
-- The exhaustive test of the formula.
--
-- This script checks the output of the formula (implemented in the
-- package join_over_histograms) against the output of the actual CBO
-- formula (by parsing the join statement and reading the CBO
-- estimated cardinality from v$sql_plan - this step is implemented
-- in the package cbo_cardinality).
--
-- A whole set of scenarios are checked; for each scenario, histograms
-- (and other table and column statistics) are set using dbms_stats
-- (the set_histo package provides the necessary routines), the
-- formula and CBO output are collected and then stored in the johet_results
-- table.
--
-- To reduce the number of scenarios, only "topologically different" scenarios are checked,
-- since the CBO output doesn't depend on the actual values of the columns, but only
-- on their order and on their matching on the other table or not. 

-- The symmetry of the formula is taken into account to further reduce the number
-- of scenarios - but since a bug (discovered by Wolfgang Breitling) makes the CBO
-- (sometimes) change its cardinality if you reverse the order of the join predicate,
-- the parse is repeated with the join predicate reversed, and a match if recorded
-- if the formula output matches at least one output from the CBO.
--
-- (c) Alberto Dell'Era, March 2007
-- Tested in 10.2.0.3.

doc

Scenario parameters: n and k

Each scenario is defined by a set of values in the lhs and rhs table
(contained in the johet_lhs_values, johet_rhs_values) and their cardinality
(number of buckets filled) in the histogram (contained in the column
cards_string in johet_lhs_configuration, johet_rhs_configuration).
A value can occur 0 (ignored),1(unpopular),2(popular) times.

The set of values is defined by the parameter n and k.
N is the number of values in the lhs table; the rhs table contains
the same values plus k values between them (see following diagram).

n=2 k=3
<-- lhs -------   ----- rhs --->

  cards   val       val   cards
      0   000       000   0
                    001   2   ^
                    002   1   |<--- k = 3
                    003   1   v
                                  
      2   100       100   2
                    101   1
                    102   2
                    103   0
                                    
      1   200       200   0
                    201   1
                    202   1
                    203   2
   
cards_string(lhs) = '021'   
cards_string(rhs) = '021121200112'    

card of val=000 is always zero (ghost value)

lhs contains only always-present values (card=1 or 2)

rhs can have no-there values (card=0), but must obey
the following rule to avoid rechecking topological-equivalent scenarios:     
inside k-plets, zero cards are allowed only at the end. ie:
110, 100, 000 are allowed
010, 020, 022 are not allowed

#

set echo on
set lines 150
set pages 9999
set define on
set escape off
set serveroutput on size 1000000

purge recyclebin;
drop table johet_lhs_values;
drop table johet_lhs_configuration;
drop table johet_rhs_values;
drop table johet_rhs_configuration;
drop table johet_results;

spool exhaustive_topological.lst

create table johet_lhs_values (
  string_position int    not null,
  value           number not null,
  constraint johet_lhs_values_pk primary key (string_position)
)
organization index;

create table johet_lhs_configuration (
  cards_string  varchar2(100 char) not null,
  constraint johet_lhs_configuration_pk primary key (cards_string)
)
organization index;

create table johet_rhs_values (
  string_position int    not null,
  value           number not null,
  constraint johet_rhs_values_pk primary key (string_position)
)
organization index;

create table johet_rhs_configuration (
  cards_string  varchar2(100 char) not null,
  constraint johet_rhs_configuration_pk primary key (cards_string)
)
organization index;

create table johet_results (
  lhs_cards_string varchar2(100 char) not null,
  rhs_cards_string varchar2(100 char) not null,
  cbo_card_min  number,
  cbo_card_max  number,
  joh_card      number,
  best_diff     number,
  cbo_std_8i    number,
  cbo_std_9i10g number,
  cbo_std_best_diff number,
  redo          varchar2(100),
  constraint johet_results_pk primary key (lhs_cards_string, rhs_cards_string)
);

drop table johet_lhs;
drop table johet_rhs;
create table johet_lhs (x number);
create table johet_rhs (x number);
exec join_over_histograms.install ('johet_lhs', 'x', 'johet_rhs', 'x');
drop table johet_lhs_h;
drop table johet_rhs_h; 
create table johet_lhs_h (x number, diff_ep int not null);
create table johet_rhs_h (x number, diff_ep int not null);
exec set_histo.install ('johet_lhs', 'johet_lhs_h');
exec set_histo.install ('johet_rhs', 'johet_rhs_h');

create or replace package johet is

  -- generate the scenarios with parameter N and K and store
  -- them in the johet_*_values, johet_*_configuration tables. 
  -- See the script header for the definition of N and K
  procedure generate (n int, k int);
  
  -- run the scenarios.
  -- See set_histo for the meaning of p_*_num_rows_per_bkt
  -- and p_*_density.
  procedure run (
    p_lhs_num_rows_per_bkt  number,
    p_lhs_density           number,
    p_rhs_num_rows_per_bkt  number,
    p_rhs_density           number
  );
  
  -- continue an interrupted run
  procedure restart (
    p_lhs_num_rows_per_bkt  number,
    p_lhs_density           number,
    p_rhs_num_rows_per_bkt  number,
    p_rhs_density           number
  );
  
  procedure perform_test_ext (
    p_lhs_cards_string      varchar2,
    p_rhs_cards_string      varchar2, 
    p_lhs_num_rows_per_bkt  number,
    p_lhs_density           number,
    p_rhs_num_rows_per_bkt  number,
    p_rhs_density           number
  );

end johet;
/
show errors;

create or replace package body johet is

-----------------------------------------------------------
-- http://asktom.oracle.com/tkyte/hexdec/hexdec.sql
-- slightly modified
function to_base( p_dec in number, p_base in number, p_num_digits int) 
return varchar2
is
	l_str	varchar2(255) default NULL;
	l_num	number	default p_dec;
	l_hex	varchar2(16) default '0123456789ABCDEF';
begin
	if ( p_dec is null or p_base is null ) 
	then
		return null;
	end if;
	if ( trunc(p_dec) <> p_dec OR p_dec < 0 ) then
		raise PROGRAM_ERROR;
	end if;
	loop
		l_str := substr( l_hex, mod(l_num,p_base)+1, 1 ) || l_str;
		l_num := trunc( l_num/p_base );
		exit when ( l_num = 0 );
	end loop;
	return lpad (l_str, p_num_digits, '0');
end to_base;

-----------------------------------------------------------
-- http://asktom.oracle.com/tkyte/hexdec/hexdec.sql
function to_dec
( p_str in varchar2, 
  p_from_base in number default 16 ) return number
is
	l_num   number default 0;
	l_hex   varchar2(16) default '0123456789ABCDEF';
begin
	if ( p_str is null or p_from_base is null )
	then
		return null;
	end if;
	for i in 1 .. length(p_str) loop
		l_num := l_num * p_from_base + instr(l_hex,upper(substr(p_str,i,1)))-1;
	end loop;
	return l_num;
end to_dec;

-----------------------------------------------------------
procedure generate_lhs (n int) 
is
  v     number;
  cards varchar2(100 char);
begin
   delete from johet_lhs_configuration;
   delete from johet_lhs_values;
   
   for i in 0..n loop
     v := 100 * i;
     insert into johet_lhs_values (string_position, value) values (i, v);
   end loop;
   
   for i in 0.. power (2, n)-1 loop
     cards := '0'|| translate (to_base (i, 2, n), '01','12') ;
     -- change popular card to 3 (temp 1/2)
     cards := replace (cards, '2', '3');
     dbms_output.put_line (cards);
     insert into johet_lhs_configuration (cards_string) values (cards);
   end loop;
   
end generate_lhs;

-----------------------------------------------------------
function rhs_filter (cards varchar2, n int, k int) 
return varchar2
is
  s varchar2(100 char);
begin
  -- cards = 022211112202 for n=2, k = 3
  for i in 0..n loop
    s := substr (cards, 1 + i*(k+1) + 1, k);
    s := rtrim (s, '0');
    if instr (s, '0') > 0 then
      return 'N';
    end if;
  end loop;
  return 'Y';
end rhs_filter;

-----------------------------------------------------------
procedure generate_rhs (n int, k int)
is
  v     number;
  cards varchar2(100 char);
  cards_num_digits int;
  l_filter_passed varchar2 (1 char);
  l_num_potential int := 0;
  l_num_inserted  int := 0;
begin
  delete from johet_rhs_configuration;
  delete from johet_rhs_values;
  
  for i in 0..n loop
    for j in 0..k loop
      v := 100 * i + j;
      insert into johet_rhs_values (string_position, value) values (i*(k+1)+j, v);
    end loop;
  end loop;
  
  cards_num_digits := (n+1)*(k+1);
  dbms_output.put_line ('cards_num_digits='||cards_num_digits);
  for i in 1..power (3, cards_num_digits-1)-1 loop
    cards := '0'|| to_base (i, 3, cards_num_digits-1);
    l_filter_passed := rhs_filter (cards, n, k);
    --dbms_output.put_line (cards||' '||l_filter_passed);
    l_num_potential := l_num_potential + 1;
    if l_filter_passed = 'Y' then
      -- change popular card to 3 (temp 2/2)
      cards := replace (cards, '2', '3');
      insert into johet_rhs_configuration (cards_string) values (cards);
      l_num_inserted := l_num_inserted + 1;
    end if;
  end loop;
   
  dbms_output.put_line ('inserted='||l_num_inserted||' potential='||l_num_potential
    ||' ratio='||trunc(100*l_num_inserted/l_num_potential,2)||'%'); 
end generate_rhs;

-----------------------------------------------------------
procedure generate (n int, k int) 
is
begin
  generate_lhs (n);
  generate_rhs (n,k);
  commit;
end generate;

-----------------------------------------------------------
procedure perform_test (
  p_lhs_cards_string      varchar2,
  p_rhs_cards_string      varchar2, 
  p_lhs_num_rows_per_bkt  number,
  p_lhs_density           number,
  p_rhs_num_rows_per_bkt  number,
  p_rhs_density           number,
  p_cbo_card_min          out number,
  p_cbo_card_max          out number,
  p_joh_card              out number,
  p_cbo_standard_8i       out number,
  p_cbo_standard_9i10g    out number,
  p_prev_lhs_cards_string in out varchar2, -- speed optim only
  p_prev_rhs_cards_string in out varchar2, -- speed optim only
  p_redo                  out varchar2
)
is
  l_diff_ep number;
  l_card         number;
  l_card_swapped number;
begin
  p_redo := replace ('exec johet.perform_test_ext (!'
    ||p_lhs_cards_string    ||'!,!'||p_rhs_cards_string||'!,'
    ||p_lhs_num_rows_per_bkt||','||nvl(to_char(p_lhs_density),'null')||','
    ||p_rhs_num_rows_per_bkt||','||nvl(to_char(p_rhs_density),'null')||');', '!', '''');
  
  -- set lhs histogram
  if p_prev_lhs_cards_string is null or p_prev_lhs_cards_string != p_lhs_cards_string then
    delete from johet_lhs_h;
    for i in 1..length(p_lhs_cards_string) loop
      l_diff_ep := to_number (substr (p_lhs_cards_string, i, 1));
      if l_diff_ep > 0 then
        insert into johet_lhs_h (x, diff_ep)
        select value, l_diff_ep from johet_lhs_values where string_position = i-1; 
      end if;
    end loop;
    
    set_histo.set ('johet_lhs', 'johet_lhs_h', p_lhs_num_rows_per_bkt, p_lhs_density, 'N');
    p_prev_lhs_cards_string := p_lhs_cards_string;
  end if;
  
  -- set rhs histogram
  if p_prev_rhs_cards_string is null or p_prev_rhs_cards_string != p_rhs_cards_string then
    delete from johet_rhs_h;
    for i in 1..length(p_rhs_cards_string) loop
      l_diff_ep := to_number (substr (p_rhs_cards_string, i, 1));
      if l_diff_ep > 0 then
        insert into johet_rhs_h (x, diff_ep)
        select value, l_diff_ep from johet_rhs_values where string_position = i-1; 
      end if;
    end loop;
    
    set_histo.set ('johet_rhs', 'johet_rhs_h', p_rhs_num_rows_per_bkt, p_rhs_density, 'N');
    p_prev_rhs_cards_string := p_rhs_cards_string;
  end if;
  
  cbo_cardinality.get_both ('johet_lhs', 'x', 'johet_rhs', 'x', l_card, l_card_swapped);

  p_cbo_card_min  := least    (l_card, l_card_swapped);
  p_cbo_card_max  := greatest (l_card, l_card_swapped);
  p_joh_card      := join_over_histograms.get ('johet_lhs', 'x', 'johet_rhs', 'x', 'N');
  
  -- this lines have to be AFTER the call to join_over_histograms.get()!
  p_cbo_standard_8i    := join_over_histograms.g_last_cbo_standard_8i;
  p_cbo_standard_9i10g := join_over_histograms.g_last_cbo_standard_9i10g;
  
--exception
--  when others then 
--    raise_application_error (-20001, p_lhs_cards_string||' '||p_rhs_cards_string||' '||sqlerrm);
end perform_test;

-----------------------------------------------------------
procedure perform_test_ext (
  p_lhs_cards_string      varchar2,
  p_rhs_cards_string      varchar2, 
  p_lhs_num_rows_per_bkt  number,
  p_lhs_density           number,
  p_rhs_num_rows_per_bkt  number,
  p_rhs_density           number
)
is
  l_cbo_card_min   number;
  l_cbo_card_max   number;
  l_joh_card       number;
  l_cbo_standard_8i    number;
  l_cbo_standard_9i10g number;
  l_prev_lhs_cards_string johet_results.lhs_cards_string%type;
  l_prev_rhs_cards_string johet_results.rhs_cards_string%type;
  l_redo johet_results.redo%type;
begin
  perform_test (
    p_lhs_cards_string      ,
    p_rhs_cards_string      , 
    p_lhs_num_rows_per_bkt  ,
    p_lhs_density           ,
    p_rhs_num_rows_per_bkt  ,
    p_rhs_density           ,
    l_cbo_card_min          ,
    l_cbo_card_max          ,
    l_joh_card              ,
    l_cbo_standard_8i       ,
    l_cbo_standard_9i10g    ,
    l_prev_lhs_cards_string,
    l_prev_rhs_cards_string,
    l_redo
  );
end perform_test_ext;

-----------------------------------------------------------
procedure restart (
  p_lhs_num_rows_per_bkt  number,
  p_lhs_density           number,
  p_rhs_num_rows_per_bkt  number,
  p_rhs_density           number
)
is
  l_cbo_card_min number;
  l_cbo_card_max number;
  l_joh_card     number;
  l_best_diff    number;
  l_start_time number;
  l_end_time   number;
  l_num_performed int := 0;
  l_cbo_standard_8i    number;
  l_cbo_standard_9i10g number;
  l_cbo_std_best_diff  number;
  l_redo johet_results.redo%type;
  l_prev_lhs_cards_string johet_results.lhs_cards_string%type;
  l_prev_rhs_cards_string johet_results.rhs_cards_string%type;
begin
  l_start_time := dbms_utility.get_time;
  dbms_random.seed (0);
  for test in (select lhs_cards_string, rhs_cards_string 
                 from johet_results
                where cbo_card_min is null
                order by dbms_random.random, lhs_cards_string, rhs_cards_string)
  loop
    perform_test (test.lhs_cards_string, test.rhs_cards_string,
                  p_lhs_num_rows_per_bkt, p_lhs_density, p_rhs_num_rows_per_bkt , p_rhs_density,
                  l_cbo_card_min, l_cbo_card_max, l_joh_card, l_cbo_standard_8i, l_cbo_standard_9i10g, 
                  l_prev_lhs_cards_string, l_prev_rhs_cards_string, l_redo);
                  
    if abs (l_cbo_card_min-l_joh_card) < abs (l_cbo_card_max-l_joh_card) then
      l_best_diff := l_cbo_card_min - l_joh_card;
    else
      l_best_diff := l_cbo_card_max - l_joh_card;
    end if;
    
    l_cbo_std_best_diff := least ( abs (l_cbo_standard_8i    - l_cbo_card_min),
                                   abs (l_cbo_standard_8i    - l_cbo_card_max),
                                   abs (l_cbo_standard_9i10g - l_cbo_card_min),
                                   abs (l_cbo_standard_9i10g - l_cbo_card_max)
                                 );
                    
    update johet_results
       set cbo_card_min      = l_cbo_card_min,
           cbo_card_max      = l_cbo_card_max, 
           joh_card          = l_joh_card,
           best_diff         = l_best_diff,
           cbo_std_8i        = l_cbo_standard_8i,
           cbo_std_9i10g     = l_cbo_standard_9i10g,
           cbo_std_best_diff = l_cbo_std_best_diff,
           redo              = l_redo
     where lhs_cards_string = test.lhs_cards_string
       and rhs_cards_string = test.rhs_cards_string;
    commit;
    l_num_performed := l_num_performed + 1;
  end loop;
  l_end_time := dbms_utility.get_time;
  
  dbms_output.put_line ('tests/sec='||round (l_num_performed / ((l_end_time-l_start_time)/100.0), 2));
end restart;

-----------------------------------------------------------
procedure run (
  p_lhs_num_rows_per_bkt  number,
  p_lhs_density           number,
  p_rhs_num_rows_per_bkt  number,
  p_rhs_density           number
)
is
begin
  delete from johet_results;
  commit;
  
  insert /*+ append */ into johet_results (lhs_cards_string, rhs_cards_string)
  select lhs.cards_string, rhs.cards_string
    from johet_lhs_configuration lhs, johet_rhs_configuration rhs;
  dbms_output.put_line (sql%rowcount||' tests ready to run.');
  commit;
  
  restart (p_lhs_num_rows_per_bkt, p_lhs_density, p_rhs_num_rows_per_bkt , p_rhs_density); 
end run;

end johet;
/
show errors;

-- workaround for bug 4626732, 5752903 "ORA-07445 [ACCESS_VIOLATION] [_evaopn2+153]"
alter session set "_optimizer_native_full_outer_join"=force;

--exec johet.generate (1,0);
exec johet.generate (2,1);
--exec johet.generate (2,2);
--exec johet.generate (2,3);

select * from johet_lhs_values;
select * from johet_lhs_configuration; 

select * from johet_rhs_values;
select * from johet_rhs_configuration; 

set serveroutput off
exec johet.run (0, null, 10, null);
set serveroutput on size 1000000

col lhs_cards_string form a10
col rhs_cards_string form a10
col redo form a64
col actual_value form a20
col  low_value   form a20
col high_value   form a20
col percent      form 99.9
--select * from johet_results order by 1,2;

select * from johet_results where abs(best_diff) > 1.5 order by abs(best_diff);

-- absolute error
select 0.5* round (abs(best_diff)/0.5) as diff, count(*), round(100*ratio_to_report (count(*)) over(),1) as percent
 from johet_results group by 0.5* round (abs(best_diff)/0.5) order by 1;

--select * from johet_results where abs(best_diff) > 1.5 
--  and abs (cbo_std_best_diff) <= 1 order by abs(best_diff);

spool off

doc
@redo
#
