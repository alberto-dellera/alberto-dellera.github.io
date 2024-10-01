---
layout: post
title: Fast refresh of aggregate-only materialized views with MAX - algorithm
date: 2013-08-23 14:03:56.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- materialized views
tags: []
meta:
author: Alberto Dell'Era
permalink: "/blog/2013/08/23/fast-refresh-of-aggregate-only-materialized-views-with-max-algorithm/"
migration_from_potsgres:
  approved_on: false
---
<p>In this post I will illustrate the algorithm used by Oracle (in 11.2.0.3) to fast refresh a materialized view (MV) containing only the MAX aggregate function:</p>
<p>[sql light="true"]<br />
create materialized view test_mv<br />
build immediate<br />
refresh fast on demand<br />
with rowid<br />
as<br />
select gby        as mv_gby,<br />
       count(*)   as mv_cnt_star,<br />
       max  (dat) as mv_max_dat<br />
  from test_master<br />
 --where whe = 0<br />
 group by gby<br />
;<br />
[/sql]</p>
<p>The where clause is commented to enable fast refresh whatever type of DML occurs on the master table, in order to investigate all possible scenarios; the case having the where-clause is anywhere a sub-case of the former and we will illustrate it as well below.    </p>
<p>As usual, the MV log is configured to "log everything":<br />
[sql light="true"]<br />
create materialized view log on test_master<br />
with rowid ( whe, gby, dat ), sequence<br />
including new values;<br />
[/sql]</p>
<p>In the <a href="http://www.adellera.it/blog/2013/08/05/fast-refresh-of-aggregate-only-materialized-views-introduction/">general introduction to aggregate-only MVs</a> we have seen how the refresh engine first marks the log rows, then inspects TMPDLT (loading its rows into the result cache at the same time) to classify its content as insert-only (if it contains only new values), delete-only (if it contains only old values) or general (if it contains a mix of new/old values). In the MAX scenario, a specialized (and much more performant) algorithm exists only for the insert-only case, and every other case falls back to the general algorithm. </p>
<p>Let's illustrate, with the help of the usual supporting <a href="http://34.247.94.223/wp-content/uploads/2013/08/post_0280_gby_mv_max.zip">test case</a>, and building on the shoulders of the already illustrated <a href="http://www.adellera.it/blog/2013/08/19/fast-refresh-of-aggregate-only-materialized-views-with-sum-algorithm/">SUM case</a>.</p>
<p><b>refresh for insert-only TMPDLT</b></p>
<p>The refresh is made using this single merge statement:<br />
[sql light="true"]<br />
/* MV_REFRESH (MRG) */<br />
/* MV_REFRESH (MRG) */<br />
merge into test_mv<br />
using (<br />
  with tmpdlt$_test_master as  (<br />
    -- check introduction post for statement<br />
  )<br />
  select gby,<br />
         sum( 1 )   as cnt_star,<br />
         max( dat ) as max_dat<br />
    from (select rid$, gby, dat, dml$$<br />
            from tmpdlt$_test_master<br />
         ) as of snapshot(:b_scn)<br />
    -- where whe = 0 (if the where clause is specified in the MV)<br />
  group by gby<br />
) deltas<br />
on (sys_op_map_nonnull(test_mv.mv_gby) = sys_op_map_nonnull(deltas.gby))<br />
when matched then<br />
  update set<br />
    test_mv.mv_cnt_star = test_mv.mv_cnt_star + deltas.cnt_star<br />
    test_mv.mv_max_dat =<br />
      decode( test_mv.mv_max_dat,<br />
              null, deltas.max_dat,<br />
              decode( deltas.max_dat,<br />
                      null, test_mv.mv_max_dat,<br />
                      greatest( test_mv.mv_max_dat, deltas.max_dat )<br />
                    )<br />
            )<br />
when not matched then<br />
  insert ( test_mv.mv_gby, test_mv.mv_max_dat, test_mv.mv_cnt_star )<br />
  values ( deltas.gby, deltas.max_dat, deltas.cnt_star )<br />
[/sql]<br />
Similarly to what it is done for the SUM case, it simply calculates the delta values to be propagated by grouping-and-maximazing the new values contained in TMPDLT (essentially, it executes the MV statement on the filtered mv log), and then looks for matches over the grouped-by expression (using the null-aware function sys_op_map_nonnull, already illustrated in the post about SUM). It then applies the deltas to the MV, or simply inserts them if no match is found. </p>
<p>The delta application algorithm is very simple: since only inserts have been performed, the MV max(dat) value cannot decrease, but only increase if max(dat) calculated by the deltas is greater. Hence it is simply a matter to set the new value to the greatest of the old and the max of the deltas, with a few decodes to handle nulls in the obvious way.</p>
<p>Note that count(dat)  is not used, and even not present in the MV definition. </p>
<p>Note especially, as in the SUM case, that the master table, test_master, is not accessed at all - unfortunately that cannot be done for the general case, as we will see shortly.</p>
<p>This algorithm is used also when the where clause is specified in the MV (adding this clause makes the MV an "insert-only MV", as per Oracle definition, which means that can be fast refreshed only after inserts and not after other DML types); the only difference is the obvious addition of the where clause in the deltas calculation as well (as commented in the statement above).</p>
<p>It's also very interesting to remember that this algorithm can be used when only inserts(new values) are present <i>in TMPDLT</i>, not in the log, and hence it can be used <i>even when deletes or inserts are present in the log</i>, provided they are redundant (as seen in the general introduction post). This is especially useful for where-clause MVs, since it widens the possibility to refresh beyond insert-only, as already demonstrated in script tmpdlt_enables_fast_refresh_of_insert_only_mv.sql of the introduction post. </p>
<p><b>refresh for mixed-DML TMPDLT</b></p>
<p>The refresh is accomplished using two statements, a delete that removes every gby value referenced in the log:<br />
[sql light="true"]<br />
/* MV_REFRESH (DEL) */<br />
delete from test_mv<br />
 where sys_op_map_nonnull(mv_gby) in (<br />
        select sys_op_map_nonnull(gby)<br />
          from (select gby<br />
                  from mlog$_test_master<br />
                 where snaptime$$ &gt; :b_st0<br />
               ) as of snapshot(:b_scn)<br />
       )<br />
[/sql]</p>
<p>and an insert that recalculates them reading from the master table:</p>
<p>[sql light="true"]<br />
/* MV_REFRESH (INS) */<br />
insert into test_mv<br />
select gby, count(*), max(dat)<br />
 from (select gby, dat<br />
         from test_master<br />
        where ( sys_op_map_nonnull(gby) ) in (<br />
                select sys_op_map_nonnull(gby)<br />
                  from (select gby, dat<br />
                          from mlog$_test_master<br />
                         where snaptime$$ &gt; :b_st0<br />
                       ) as of snapshot(:b_scn)<br />
              )<br />
       )<br />
 group by gby<br />
[/sql]</p>
<p>This is necessary since a delete(old value) might remove the max value present in the MV, and to know the new max value we must necessarily visit the master table. This might not happen for all log values, but the refresh engine takes the easiest (and drastic) option of deleting and recreating all anyway.</p>
<p>Note that this might result in massive degradation of performance - this algorithm in not O(modifications)  but O(modifications * V), where V is the average number of rows per distinct value of gby, which is generally O(mv size). For example: if your order table doubles in size, you must expect to double the refresh time, even if the number of orders modified is always the same.   </p>
<p>As in the SUM case, a bit surprisingly, this statement does not use TMPDLT, but reads straight from the log; the same observations made for the SUM case apply here as well.</p>
<p><b>optimizations</b></p>
<p>The insert-only case is very similar to the SUM case, and thus please refer to the high-level discussion presented there if interested (but, obviously, the creation of the index on mv_cnt_star is not needed in the MAX case). As a side note, one might notice that insert-only algorithms for aggregation are a class of their own, vastly simpler and vastly more performant (and that does not come as a surprise).</p>
<p>The mixed-DML case is another story altogether - to optimize it you must (almost always) create a proper index on the master table. At least the expression sys_op_map_nonnull(gby) must be indexed, but I would strongly advise to create this covering index:</p>
<p>create index test_master_covering on test_master ( sys_op_map_nonnull(gby), gby, dat )</p>
<p>this way everything needed for recalculating a given gby value is neatly clustered in some leaf blocks, instead of being spread out across all the table. You might spare thousands of table block visits if,  as it is quite often the case, you have thousands of rows for each gby values and a bad clustering_factor.</p>
<p>Note also that this index is probably highly compressible, thus adding compress 2 (or even 3, depending on the "dat" column statistic distribution) is a great thing to do as well.</p>
<p>Script gby_max_with_covering_index.sql shows the possible index-only resulting plan:</p>
<p>[sql light="true"]<br />
--------------------------------------------------<br />
|Id|Operation               |Name                |<br />
--------------------------------------------------<br />
| 0|INSERT STATEMENT        |                    |<br />
| 1| LOAD TABLE CONVENTIONAL|                    |<br />
| 2|  HASH GROUP BY         |                    |<br />
| 3|   NESTED LOOPS         |                    |<br />
| 4|    SORT UNIQUE         |                    |<br />
| 5|     TABLE ACCESS FULL  |MLOG$_TEST_MASTER   |<br />
| 6|    INDEX RANGE SCAN    |TEST_MASTER_COVERING|<br />
--------------------------------------------------
  
[/sql]

For optimizing the log, and disabling TMPDLT, the same considerations made for the SUM case hold.

