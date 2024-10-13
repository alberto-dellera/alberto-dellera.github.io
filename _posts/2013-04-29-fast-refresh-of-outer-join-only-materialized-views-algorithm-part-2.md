---
layout: post
title: fast refresh of outer-join-only materialized views - algorithm, part 2
date: 2013-04-29 10:57:14.000000000 +02:00
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
permalink: "/blog/2013/04/29/fast-refresh-of-outer-join-only-materialized-views-algorithm-part-2/"
migration_from_wordpress:
  approved_on: working
---
In this post, we are going to complete [part 1](/blog/2013/04/22/fast-refresh-of-outer-join-only-materialized-views-algorithm-part-1/) illustrating the (considerably more complex) general case of a fast refresh from a master inner table without a unique constraint on the joined column(s).

To recap, now the outer slice can be composed of more than one row, for example:
```
ooo inn1
ooo inn2
```

and hence, both the DEL and INS step must consider (and read) the whole outer slice even if only a subset of the inner rows have been modified. This requires both more resources and a considerably more complex algorithm. Let's illustrate it (the mandatory test case is [here](/assets/files/2013/04/join_mv_outer_part2.zip)).


## The DEL macro step

This sub step (named DEL.del by me) is performed first:

```plsql
/* MV_REFRESH (DEL) */
delete from test_mv where rowid in (
select rid
  from (
select test_mv.rowid rid,
       row_number() over (partition by test_outer_rowid order by rid$ nulls last) r,
       count(*)     over (partition by test_outer_rowid ) t_cnt,
       count(rid$)  over (partition by test_outer_rowid ) in_mvlog_cnt
  from test_mv, (select distinct rid$ from mlog$_test_inner) mvlog
 where /* read touched outer slices start */
       test_mv.test_outer_rowid in
          (
          select test_outer_rowid
            from test_mv
           where test_inner_rowid in (select rid$ from mlog$_test_inner)
          )
       /* read touched outer slices end */
   and test_mv.test_inner_rowid = mvlog.rid$(+)
       )
 /* victim selection start */
 where t_cnt > 1
   and ( (in_mvlog_cnt = t_cnt and r > 1)
          or
         (in_mvlog_cnt < t_cnt and r <= in_mvlog_cnt)
       )
 /* victim selection end */
)
```

followed by the DEL.upd one:

```plsql
/* MV_REFRESH (UPD) */
update test_mv
   set jinner = null, xinner = null, pkinner = null, test_inner_rowid = null
 where test_inner_rowid in (select rid$ from mlog$_test_inner)
```

This two steps combined do change all the rows of the MV marked in the log (and only them, other rows are not modified at all); the first step deletes some of them, leaving all the others to the second one, that sets to null their columns coming from the inner table.

DEL.upd is straighforward. Let's illustrate the DEL.del algorithm:
a) the section "read touched outer slices" fetches all the MV outer slices that have at least one of their rows marked in the log;
b) the slices are outer joined with the "mvlog" in-line view, so that rid$ will be nonnull for all rows marked in the log;
c) the analytic functions, for each outer slice separately, compute the number of rows (column t_cnt), the number of rows marked (column in_mvlog_cnt), and then attach a label (column r) that orders the row (order is not important at all besides non-marked rows being ordered last)
d) the where-predicate "victim selection" dictates which rows to delete.

The victim selection predicate has three sub-components, each implementing a different case (again, considering each slice separately):

**"t_cnt > 1"**: do not delete anything if the slice contains only one row (since it is for sure marked and hence will be nulled by DEL.upd)
```
             rid$ t_cnt in_mvlog_cnt r  action 
ooo inn1 not-null     1            1 1  updated by DEL.upd   
```

**"in_mvlog_cnt = t_cnt and r > 1"**: all rows are marked, delete all but one (that will be nulled by DEL.upd)
```
             rid$ t_cnt in_mvlog_cnt r  action 
ooo inn1 not-null     3            3 1  updated by DEL.upd    
ooo inn2 not-null     3            3 2  deleted by DEL.del    
ooo inn3 not-null     3            3 3  deleted by DEL.del    
```

**"in_mvlog_cnt < t_cnt and r <= in_mvlog_cnt"**: only some rows are marked; delete all marked rows, keep all the others.
```
             rid$ t_cnt in_mvlog_cnt r  action 
ooo inn1 not-null     3            2 1  deleted by DEL.del    
ooo inn2 not-null     3            2 2  deleted by DEL.del    
ooo inn3     null     3            2 3  nothing    
```

## The INS macro step

The first sub-step is INS.ins:
```plsql
/* MV_REFRESH (INS) */
insert into test_mv
select  o.jouter,  o.xouter,  o.pkouter, o.rowid,
       jv.jinner, jv.xinner, jv.pkinner, jv.rid
  from ( select test_inner.rowid rid,
                test_inner.*
           from test_inner
          where rowid in (select rid$ from mlog_test_inner)
       ) jv, test_outer o
 where jv.jinner = o.jouter
```

this sub-step simply find matches in the outer table for the marked inner table rows (note that it is an inner join, not an outer join), and inserts them in the MV.

Then, INS.del:
```plsql
/* MV_REFRESH (DEL) */
delete from test_mv sna$ where rowid in (
select rid
 from (
select test_mv.rowid rid,
       row_number()            over (partition by test_outer_rowid order by test_inner_rowid nulls first) r,
       count(*)                over (partition by test_outer_rowid ) t_cnt,
       count(test_inner_rowid) over (partition by test_outer_rowid ) nonnull_cnt
  from test_mv
 where /* read touched outer slices start */
       test_mv.test_outer_rowid in
          (
          select o.rowid
            from ( select test_inner.rowid rid$,
                          test_inner.*
                     from test_inner
                    where rowid in (select rid$ from mlog$_test_inner)
                 ) jv, test_outer o
           where jv.jinner = o.jouter
          )
      /* read touched outer slices end */
      )
 /* victim selection start */
 where t_cnt > 1
   and ( (nonnull_cnt = 0 and r > 1)
          or
         (nonnull_cnt > 0 and r <= t_cnt - nonnull_cnt)
       )
 /* victim selection end */
)
```

this substep has a SQL structure very similar to DEL.upd, hence I will simply outline the algorith: first, the statement identifies (in the "read touched outer slices" section) all the outer slices that had at least one rows inserted by INS.ins, by replaying its join; then, for each slice, it deletes any row, if it exists,  that has column "test_inner_rowid" set to null (check the "victim selection predicate"). 

Side note: I cannot understand how nonnull_cnt could be = 0 - possibly that is for robustness only or because it can handle variants of the DEL step I haven't observed. 

## speeding up

These are the indexes that the CBO might enjoy using to optimize the steps of the propagation from the inner table:
- DEL.del: test_mv(test_inner_rowid, test_outer_rowid)
- DEL.upd: test_mv(test_inner_rowid)
- INS.ins: test_outer(jouter)
- INS.del: test_outer(jouter) and test_mv(test_outer_rowid , test_inner_rowid)

And hence, to optimize all steps:
- test_outer(jouter)
- test_mv(test_inner_rowid, test_outer_rowid)
- test_mv(test_outer_rowid , test_inner_rowid)

And of course we need the usual index on test_inner(jinner) to optimize the propagation from the outer table (not shown in this post), unless we positively know that the outer table is never modified.

Note that the two indexes test_mv(test_inner_rowid, test_outer_rowid) and test_mv(test_outer_rowid , test_inner_rowid) allow to skip visiting the MV altogether (except for deleting rows, obviously) and hence might reduce the number of consistent gets dramatically (the indexes are both "covering" indexes for the SQL statements we observed in the DEL.del and INS.del) . 

For example, in my test case (check ojoin_mv_test_case_indexed.sql), the plan for the DEL.del step is:
```plsql
--------------------------------------------------------------
| 0|DELETE STATEMENT                |                        |
| 1| DELETE                         |TEST_MV                 |
| 2|  NESTED LOOPS                  |                        |
| 3|   VIEW                         |VW_NSO_1                |
| 4|    SORT UNIQUE                 |                        |
| 5|     VIEW                       |                        |
| 6|      WINDOW SORT               |                        |
| 7|       HASH JOIN OUTER          |                        |
| 8|        HASH JOIN SEMI          |                        |
| 9|         INDEX FULL SCAN        |TEST_MV_TEST_INNER_ROWID|
|10|         VIEW                   |VW_NSO_2                |
|11|          NESTED LOOPS          |                        |
|12|           TABLE ACCESS FULL    |MLOG$_TEST_INNER        |
|13|           INDEX RANGE SCAN     |TEST_MV_TEST_INNER_ROWID|
|14|        VIEW                    |                        |
|15|         SORT UNIQUE            |                        |
|16|          TABLE ACCESS FULL     |MLOG$_TEST_INNER        |
|17|   MAT_VIEW ACCESS BY USER ROWID|TEST_MV                 |
--------------------------------------------------------------
5 - filter[ (T_CNT>1 AND ((IN_MVLOG_CNT=T_CNT AND R>1)
OR (IN_MVLOG_CNT<T_CNT AND R<=IN_MVLOG_CNT))) ]
...
```

Note the absence of any access to the MV to identify the rows to be deleted (row source operation 5 and its progeny; note the filter operation, which is the final "victim selection predicate"); the MV is only accessed to physically delete the rows. 

Ditto for the INS.del step:

```plsql
-------------------------------------------------------------------
| 0|DELETE STATEMENT                     |                        |
| 1| DELETE                              |TEST_MV                 |
| 2|  NESTED LOOPS                       |                        |
| 3|   VIEW                              |VW_NSO_1                |
| 4|    SORT UNIQUE                      |                        |
| 5|     VIEW                            |                        |
| 6|      WINDOW SORT                    |                        |
| 7|       HASH JOIN SEMI                |                        |
| 8|        INDEX FULL SCAN              |TEST_MV_TEST_INNER_ROWID|
| 9|        VIEW                         |VW_NSO_2                |
|10|         NESTED LOOPS                |                        |
|11|          NESTED LOOPS               |                        |
|12|           TABLE ACCESS FULL         |MLOG$_TEST_INNER        |
|13|           TABLE ACCESS BY USER ROWID|TEST_INNER              |
|14|          INDEX RANGE SCAN           |TEST_OUTER_JOUTER_IDX   |
|15|   MAT_VIEW ACCESS BY USER ROWID     |TEST_MV                 |
-------------------------------------------------------------------
  
5 - filter[ (T\_CNT\>1 AND ((NONNULL\_CNT=0 AND R\>1)  
OR (NONNULL\_CNT\>0 AND R\<=T\_CNT-NONNULL\_CNT))) ]  
...  
``` 
  
You might anyway create just the two "standard" single-column indexes on test\_mv(test\_inner\_rowid) and test\_mv(test\_outer\_rowid) and be happy with the resulting performance, even if you now will access the MV to get the "other" rowid - it all depends, of course, on your data (how many rows you have in each slice, and how many slices are touched by the marked rows) and how you modify the master tables. 
