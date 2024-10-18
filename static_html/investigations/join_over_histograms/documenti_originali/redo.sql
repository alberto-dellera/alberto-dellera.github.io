select * from joh_lhs_column_stats;
select * from joh_rhs_column_stats;
select * from joh_lhs_hist;
select * from joh_rhs_hist;
select cbo_cardinality.get ('johet_lhs', 'x', 'johet_rhs', 'x') from dual;
select join_over_histograms.get ('johet_lhs', 'x', 'johet_rhs', 'x', 'N') from dual;