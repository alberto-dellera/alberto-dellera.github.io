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
In this post I will illustrate the algorithm used by Oracle (in 11.2.0.3) to fast refresh a materialized view (MV) containing only the MAX aggregate function:

```plsql
create materialized view test_mv
build immediate
refresh fast on demand
with rowid
as
select gby        as mv_gby,
       count(*)   as mv_cnt_star,
       max  (dat) as mv_max_dat
  from test_master
 --where whe = 0
 group by gby
;
```

The where clause is commented to enable fast refresh whatever type of DML occurs on the master table, in order to investigate all possible scenarios; the case having the where-clause is anywhere a sub-case of the former and we will illustrate it as well below.

As usual, the MV log is configured to "log everything":

```plsql
create materialized view log on test_master
with rowid ( whe, gby, dat ), sequence
including new values;
```

In the <a href="http://www.adellera.it/blog/2013/08/05/fast-refresh-of-aggregate-only-materialized-views-introduction/">general introduction to aggregate-only MVs</a> we have seen how the refresh engine first marks the log rows, then inspects TMPDLT (loading its rows into the result cache at the same time) to classify its content as insert-only (if it contains only new values), delete-only (if it contains only old values) or general (if it contains a mix of new/old values). In the MAX scenario, a specialized (and much more performant) algorithm exists only for the insert-only case, and every other case falls back to the general algorithm. 

Let's illustrate, with the help of the usual supporting <a href="{{ site.baseurl }}/assets/files/2013/08/post_0280_gby_mv_max.zip">test case</a>, and building on the shoulders of the already illustrated <a href="http://www.adellera.it/blog/2013/08/19/fast-refresh-of-aggregate-only-materialized-views-with-sum-algorithm/">SUM case</a>.

## refresh for insert-only TMPDLT

The refresh is made using this single merge statement:

```plsql
/* MV_REFRESH (MRG) */
/* MV_REFRESH (MRG) */
merge into test_mv
using (
  with tmpdlt$_test_master as  (
    -- check introduction post for statement
  )
  select gby,
         sum( 1 )   as cnt_star,
         max( dat ) as max_dat
    from (select rid$, gby, dat, dml$$
            from tmpdlt$_test_master
         ) as of snapshot(:b_scn)
    -- where whe = 0 (if the where clause is specified in the MV)
  group by gby
) deltas
on (sys_op_map_nonnull(test_mv.mv_gby) = sys_op_map_nonnull(deltas.gby))
when matched then
  update set
    test_mv.mv_cnt_star = test_mv.mv_cnt_star + deltas.cnt_star
    test_mv.mv_max_dat =
      decode( test_mv.mv_max_dat,
              null, deltas.max_dat,
              decode( deltas.max_dat,
                      null, test_mv.mv_max_dat,
                      greatest( test_mv.mv_max_dat, deltas.max_dat )
                    )
            )
when not matched then
  insert ( test_mv.mv_gby, test_mv.mv_max_dat, test_mv.mv_cnt_star )
  values ( deltas.gby, deltas.max_dat, deltas.cnt_star )
```

Similarly to what it is done for the SUM case, it simply calculates the delta values to be propagated by grouping-and-maximazing the new values contained in TMPDLT (essentially, it executes the MV statement on the filtered mv log), and then looks for matches over the grouped-by expression (using the null-aware function sys_op_map_nonnull, already illustrated in the post about SUM). It then applies the deltas to the MV, or simply inserts them if no match is found.

The delta application algorithm is very simple: since only inserts have been performed, the MV max(dat) value cannot decrease, but only increase if max(dat) calculated by the deltas is greater. Hence it is simply a matter to set the new value to the greatest of the old and the max of the deltas, with a few decodes to handle nulls in the obvious way.

Note that count(dat)  is not used, and even not present in the MV definition.

Note especially, as in the SUM case, that the master table, test_master, is not accessed at all - unfortunately that cannot be done for the general case, as we will see shortly.

This algorithm is used also when the where clause is specified in the MV (adding this clause makes the MV an "insert-only MV", as per Oracle definition, which means that can be fast refreshed only after inserts and not after other DML types); the only difference is the obvious addition of the where clause in the deltas calculation as well (as commented in the statement above).

It's also very interesting to remember that this algorithm can be used when only inserts(new values) are present *in TMPDLT*, not in the log, and hence it can be used *even when deletes or inserts are present in the log*, provided they are redundant (as seen in the general introduction post). This is especially useful for where-clause MVs, since it widens the possibility to refresh beyond insert-only, as already demonstrated in script tmpdlt_enables_fast_refresh_of_insert_only_mv.sql of the introduction post.

## refresh for mixed-DML TMPDLT

The refresh is accomplished using two statements, a delete that removes every gby value referenced in the log:

```plsql
/* MV_REFRESH (DEL) */
delete from test_mv
 where sys_op_map_nonnull(mv_gby) in (
        select sys_op_map_nonnull(gby)
          from (select gby
                  from mlog$_test_master
                 where snaptime$$ &gt; :b_st0
               ) as of snapshot(:b_scn)
       )
```

and an insert that recalculates them reading from the master table:

```plsql
/* MV_REFRESH (INS) */
insert into test_mv
select gby, count(*), max(dat)
 from (select gby, dat
         from test_master
        where ( sys_op_map_nonnull(gby) ) in (
                select sys_op_map_nonnull(gby)
                  from (select gby, dat
                          from mlog$_test_master
                         where snaptime$$ &gt; :b_st0
                       ) as of snapshot(:b_scn)
              )
       )
 group by gby
```

This is necessary since a delete(old value) might remove the max value present in the MV, and to know the new max value we must necessarily visit the master table. This might not happen for all log values, but the refresh engine takes the easiest (and drastic) option of deleting and recreating all anyway.

Note that this might result in massive degradation of performance - this algorithm in not O(modifications)  but O(modifications * V), where V is the average number of rows per distinct value of gby, which is generally O(mv size). For example: if your order table doubles in size, you must expect to double the refresh time, even if the number of orders modified is always the same. 

As in the SUM case, a bit surprisingly, this statement does not use TMPDLT, but reads straight from the log; the same observations made for the SUM case apply here as well.

## optimizations

The insert-only case is very similar to the SUM case, and thus please refer to the high-level discussion presented there if interested (but, obviously, the creation of the index on mv_cnt_star is not needed in the MAX case). As a side note, one might notice that insert-only algorithms for aggregation are a class of their own, vastly simpler and vastly more performant (and that does not come as a surprise).

The mixed-DML case is another story altogether - to optimize it you must (almost always) create a proper index on the master table. At least the expression sys_op_map_nonnull(gby) must be indexed, but I would strongly advise to create this covering index:

```plsql
create index test_master_covering on test_master ( sys_op_map_nonnull(gby), gby, dat )
```

this way everything needed for recalculating a given gby value is neatly clustered in some leaf blocks, instead of being spread out across all the table. You might spare thousands of table block visits if,  as it is quite often the case, you have thousands of rows for each gby values and a bad clustering_factor.

Note also that this index is probably highly compressible, thus adding compress 2 (or even 3, depending on the "dat" column statistic distribution) is a great thing to do as well.

Script gby_max_with_covering_index.sql shows the possible index-only resulting plan:

```
--------------------------------------------------
|Id|Operation               |Name                |
--------------------------------------------------
| 0|INSERT STATEMENT        |                    |
| 1| LOAD TABLE CONVENTIONAL|                    |
| 2|  HASH GROUP BY         |                    |
| 3|   NESTED LOOPS         |                    |
| 4|    SORT UNIQUE         |                    |
| 5|     TABLE ACCESS FULL  |MLOG$_TEST_MASTER   |
| 6|    INDEX RANGE SCAN    |TEST_MASTER_COVERING|
--------------------------------------------------
```

For optimizing the log, and disabling TMPDLT, the same considerations made for the SUM case hold.

