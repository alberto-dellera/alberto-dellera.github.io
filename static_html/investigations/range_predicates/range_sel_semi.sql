drop table t;

create table t as select 10 * mod (rownum-1, 2) x from dual connect by level <= 2000000;

-- add a third distinct value
insert /*+ append */ into t(x) select 6.1 from dual connect by level <= 1000000;
commit;

-- add a fourth distinct value
insert /*+ append */ into t(x) select 7.42 from dual connect by level <= 1000000;
commit;

exec dbms_stats.gather_table_stats (user, 't', method_opt=>'for all columns size 1', estimate_percent=>100);

set echo on

set autotrace traceonly explain
-- left band, >, <=
select x from t where x >  0.1 and x <= 2.4;
select x from t where x >  0.1 and x <  1.0;
select x from t where x >= 1.0 and x <= 2.4;

-- left band, >=, <
select x from t where x >= 0.1 and x <  2.4;
select x from t where x >= 0.1 and x <= 1.0;
select x from t where x >  1.0 and x <  2.4;

-- left band + central, >, <=
select x from t where x >  0.1 and x <= 6.4;
select x from t where x >  0.1 and x <  2.5;
select x from t where x >= 2.5 and x <= 6.4;

-- left band + central, <=, <
select x from t where x >= 0.1 and x <  6.4;
select x from t where x >= 0.1 and x <= 2.5;
select x from t where x >  2.5 and x <  6.4;

-- left band + central + right band, >, <=
select x from t where x >  0.1 and x <= 9.8;
select x from t where x >  0.1 and x <  2.5;
select x from t where x >  2.5 and x <  7.5;
select x from t where x >= 7.5 and x <= 9.8;

-- left band + central + right band, >=, <
select x from t where x >= 0.1 and x <  9.8;
select x from t where x >= 0.1 and x <= 2.5;
select x from t where x >  2.5 and x <  7.5;
select x from t where x >  7.5 and x <  9.8;

-- special case: x > low_x = min_x
select x from t where x > 0         and x <= 1;
select x from t where x > 0 + 1e-12 and x <= 1;
select x from t where x > 0         and x <= 3;
select x from t where x > 0 + 1e-12 and x <= 3;
select x from t where x > 0         and x <= 9;
select x from t where x > 0 + 1e-12 and x <= 9;
select x from t where x > 0         and x < 10;
select x from t where x > 0 + 1e-12 and x < 10-1e-12;

-- NO special case for x > low_x = min_x
select x from t where x >= 0         and x <= 1;
select x from t where x >= 0 + 1e-12 and x <= 1;
set autotrace off