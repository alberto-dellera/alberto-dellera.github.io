-- Supporting code for the "Join over Histograms" paper
--
-- Experiments made by Jonathan Lewis in "Cost Based Oracle", pages 280-283,
-- differently organized. Shows the CBO estimate and the advantages of some
-- improvements to the Join Cardinality estimation formula proposed in the paper.
--
-- (c) Alberto Dell'Era, March 2007
-- Tested in 10.2.0.3, 9.2.0.8.

@join_over_histograms_improved.sql

set echo on
set lines 150
set pages 9999
set define on
set escape off
set serveroutput on size 1000000

purge recyclebin;

spool overlaps.lst

-- workaround for bug 4626732, 5752903 "ORA-07445 [ACCESS_VIOLATION] [_evaopn2+153]"
alter session set "_optimizer_native_full_outer_join"=force;

drop table lhs;
drop table rhs;
drop table overlaps_results;

create table lhs (x number) pctfree 0 nologging;
create table rhs (x number) pctfree 0 nologging;
create table overlaps_results (
  offset      number not null, 
  lhs_buckets int    not null, 
  rhs_buckets int    not null,
  card_real   number,
  card_impr   number,
  card_cbo    number
);

col actual_value form a20
col  low_value   form a20
col high_value   form a20
col card new_value card
col cbo_card new_value cbo_card
set verify off
set feedback off

define buckets = 75
define t1off = 50

define t1j1 = 100
define t2j1 = 100

set timing on

exec join_over_histograms_improved.install ('lhs', 'x', 'rhs', 'x'); 

set serveroutput off

declare
  card_real number;
  card_cbo  number;
  card_impr number;
  offset    int;
begin
  
  dbms_random.seed(0);
  
  --for repeat in 1..50 loop
  
  execute immediate 'truncate table lhs reuse storage';
  
  insert /* append */ into lhs (x)
  select trunc(dbms_random.value(0, &t1j1 ))
    from dual connect by level <= 10000;
  
  for offset_i in 0..4 loop
  
    offset := 50 + 10 * offset_i;
   
    execute immediate 'truncate table rhs reuse storage';
    
    insert /* append */ into rhs (x)
    select offset + trunc(dbms_random.value(0, &t2j1 ))
      from dual connect by level <= 10000;
    commit;
    
    select count(*) into card_real
      from lhs, rhs
     where lhs.x = rhs.x;  
      
    for lhs_buckets in 75..90 loop
    --for lhs_buckets in 254..254 loop
    
      dbms_stats.gather_table_stats (user, 'lhs', method_opt =>'for all columns size '||lhs_buckets, estimate_percent => 100);
      
      for rhs_buckets in 75..90 loop
      --for rhs_buckets in 254..254 loop
        
        dbms_stats.gather_table_stats (user, 'rhs', method_opt =>'for all columns size '||rhs_buckets, estimate_percent => 100);
        
        card_cbo  := cbo_cardinality.get ('lhs', 'x', 'rhs', 'x');
        card_impr := join_over_histograms_improved.get ('lhs', 'x', 'rhs', 'x', 'N', p_correct_notpop => 'Y'); 
        
        insert into overlaps_results (offset, lhs_buckets, rhs_buckets, card_real, card_impr, card_cbo)
                              values (offset, lhs_buckets, rhs_buckets, card_real, card_impr, card_cbo);
      end loop;
    end loop;
  end loop;
  
  --end loop;
  
  commit;
end;
/

set timing off
set serveroutput on size 1000000

with r as (
  select 100 * (card_impr - card_real) / card_real as diff_perc
    from overlaps_results
)
select avg (abs (diff_perc)), stddev (abs (diff_perc)), max (abs (diff_perc)), count(*), avg (diff_perc)
  from r;
  
with r as (
  select 100 * (card_cbo - card_real) / card_real as diff_perc
    from overlaps_results
)
select avg (abs (diff_perc)), stddev (abs (diff_perc)), max (abs (diff_perc)), count(*), avg (diff_perc)
  from r;

spool off

