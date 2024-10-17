---
layout: post
title: 'fast refresh of join-only MVs: _mv_refresh_use_stats and locking log stats'
date: 2010-03-11 22:46:16.000000000 +01:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- materialized views
- performance tuning
tags: []
meta:
author: Alberto Dell'Era
permalink: "/blog/2010/03/11/fast-refresh-of-join-only-mvs-_mv_refresh_use_stats-and-locking-log-stats/"
migration_from_wordpress:
  approved_on: 20241017
---
A devastating performance degradation of materialized view fast refreshes can happen in versions after 9i - and can be healed rather easily by simply setting the hidden parameter _mv_refresh_use_stats or, a bit surprisingly, by locking statistics on the logs. The problem can manifest at least in the currently-latest patchsets of 10g, 11gR1 and 11gR2 (10.2.0.4, 11.1.0.7 and 11.2.0.1), seems to hit a lot of people, and its root cause are the utilization of wrong hints by the Oracle refresh engine.

We will investigate the join-only MV case only, since this is the case I have investigated after a question by [Christo Kutrovsky](http://www.pythian.com/news/author/kutrovsky/), factoring in some observations by Taral Desai and some Support notes; I have some clues that something similar may happen for other types of MVs.

The [test case](/assets/files/2010/03/join_mv_use_stats_lock.zip) sets up this very common scenario for fast refreshes:
1 - two big base tables joined together by the MV;
2 - only a small fraction of rows modified (actually one deleted, two updated, one inserted);
3 - all tables and indexes with fresh statistics collected;
4 - MV logs with no statistic collected AND with not-locked statistics;
5 - indexes present on the joined columns;
6 - indexes present on the rowid columns of the MV.

Points 1 and 2 make for the ideal scenario for incremental ("fast") refreshes to be effective; 3 is very common as well, since you normally have many other statements issued on the tables; the relevance of 4 will be clear later, but it happens very often in real life, since people might perhaps consider collecting stats on the log, but locking their statistics is usually not made, at least in my experience.

To understand the importance of points 5 and 6, please check [this post of mine](/blog/2009/08/04/fast-refresh-of-join-only-materialized-views-algorithm-summary/); note how those indexes are a necessary prerequisite for the sanity of the DEL and INS steps of the MV process. Without them, the refresh cannot be incremental since it has no physical way to read and propagate only the modified rows and those related to them, but it must scan (uselessly) most of the base tables and MV. But in other for the refresh to be incremental ("fast"), those indexes have to be actually used...

## the issue

Let's illustrate the issue focusing on the DEL step (the easier to discuss about). In the above mentioned post, we have seen that the DEL step uses a single SQL statement whose text, leaving out minor technical details *and hints*, is:

```plsql
/* MV_REFRESH (DEL) */
delete from test_mv
 where test_t1_rowid in
       (
select * from
       (
select chartorowid (m_row$$)
  from mlog$_test_t1
 where snaptime$$ > :1
       ) as of snapshot (:2)
       )
```

In 9.2.0.8, we get this very healthy plan:
```
-------------------------------------------------
|Id|Operation             |Name                 |
-------------------------------------------------
| 0|DELETE STATEMENT      |                     |
| 1| DELETE               |                     |
| 2|  NESTED LOOPS        |                     |
| 3|   VIEW               |                     |
| 4|    SORT UNIQUE       |                     |
| 5|     TABLE ACCESS FULL|MLOG$_TEST_T1        |
| 6|   INDEX RANGE SCAN   |TEST_MV_TEST_T1_ROWID|
-------------------------------------------------
```

That is: get the rowid of all modified rows from the log, and use the rowid-based index to delete the "old image" of them from the MV (inserting their "new image" is the job of the INS step). This is truly incremental, since the resource usage and elapsed time are proportional to the number of rows logged in the MV log, not to the dimension of the tables.

In 10.2.0.4, 11.1.0.7 and 11.2.0.1 the plan becomes:
```
------------------------------------------
|Id|Operation              |Name         |
------------------------------------------
| 0|DELETE STATEMENT       |             |
| 1| DELETE                |TEST_MV      |
| 2|  HASH JOIN RIGHT SEMI |             |
| 3|   TABLE ACCESS FULL   |MLOG$_TEST_T1|
| 4|   MAT_VIEW ACCESS FULL|TEST_MV      |
------------------------------------------
```

Oops, the indexes are not used ... hence the DEL step overhead is proportional to the size of the MV, and that can be definitely unacceptable.

That is due to the engine injecting an HASH_SJ hint in the outermost nested subquery:
```plsql
... WHERE "TEST_T1_ROWID" IN (SELECT /*+ NO_MERGE  HASH_SJ  */ ...
```

This is recognized as a bug in many scenarios (start from Oracle Support note 578720.1 and follow the references to explore some of them) even if I have not found a clear and exhaustive note that documents the behaviour.

## remedy one: set "_mv_refresh_use_stats"

To get back to the healthy plan, simply set "_mv_refresh_use_stats" to "true" (ask Oracle Support first of course for permission); this makes for a set of hint much more adequate for a fast refresh:
```plsql
... WHERE "TEST_T1_ROWID" IN (SELECT /*+ NO_MERGE  NO_SEMIJOIN  */ ...
```

Note: The root cause for this bug is probably due to a change hinted in note 875532.1 - in 10.2.0.3 the meaning of _mv_refresh_use_stats was reversed, but not the default, hence (by mistake?) activating a different piece of the engine code.

The very same problem happens for the INS step; I won't go into much details here (please check the test case spools provided above if interested), but in 9.2.0.8 the base table modified rows are directly fetched using the rowid contained in the log:
```
-----------------------------------------------------
|Id|Operation                      |Name            |
-----------------------------------------------------
| 0|INSERT STATEMENT               |                |
| 1| TABLE ACCESS BY INDEX ROWID   |TEST_T2         |
| 2|  NESTED LOOPS                 |                |
| 3|   VIEW                        |                |
| 4|    NESTED LOOPS               |                |
| 5|     VIEW                      |                |
| 6|      SORT UNIQUE              |                |
| 7|       TABLE ACCESS FULL       |MLOG$_TEST_T1   |
| 8|     TABLE ACCESS BY USER ROWID|TEST_T1         |
| 9|   INDEX RANGE SCAN            |TEST_T2_J2_1_IDX|
-----------------------------------------------------
```

Instead, in 10.2.0.4, 11.1.0.7 and 11.2.0.1 we get the following plan:
```
--------------------------------------------------
|Id|Operation                   |Name            |
--------------------------------------------------
| 0|INSERT STATEMENT            |                |
| 1| TABLE ACCESS BY INDEX ROWID|TEST_T2         |
| 2|  NESTED LOOPS              |                |
| 3|   VIEW                     |                |
| 4|    HASH JOIN RIGHT SEMI    |                |
| 5|     TABLE ACCESS FULL      |MLOG$_TEST_T1   |
| 6|     TABLE ACCESS FULL      |TEST_T1         |
| 7|   INDEX RANGE SCAN         |TEST_T2_J2_1_IDX|
--------------------------------------------------
```  
Whose resource consumption is, of course, proportional to the size of the base table.

Even in this case, this is due to the nasty HASH\_SJ hint:  
```plsql 
... FROM "TEST_T1" "MAS$" WHERE ROWID IN (SELECT /*+ HASH_SJ \*/ ...  
```

If you set \_mv\_refresh\_use\_stats, you get back the 9.2.0.8 plan - and thus you are back to incremental for both the DEL and INS steps. As a side note, a cardinality hint is used, where the cardinality is set to the correct value (6 in my test case):  
```plsql 
... FROM "TEST_T1" "MAS$" WHERE ROWID IN (SELECT /*+ CARDINALITY(MAS$ 6) NO_SEMIJOIN ...  
```  

## remedy two: collect and lock statistics on the logs

Very interestingly, instead of setting the hidden parameter, you have another way to get back to the healthy plan: gather statistics on the MV logs when they are empty AND lock them (as suggested in note 578720.1, albeit not in this scenario and even if setting the parameter is not necessary; thanks to Taral Desai for pointing me to the note). In this case, no hint at all is injected beside a NO\_MERGE for the DEL step:

```plsql
... WHERE "TEST_T1_ROWID" IN (SELECT /*+ NO_MERGE */ ...  
...  FROM "TEST_T1" "MAS$" WHERE ROWID IN (SELECT ...  
```

So, the engine is confident that the CBO will come out with a good plan, and it does not inject any "intelligent" hint. Possibly, and intriguing, this is because by locking the statistics, I am assuring the engine that these statistics are representative of the data anytime. So, locking the statistics is not meant only as a way to prevent dbms\_stats from changing them ... it is deeper than that. At least in this case, you are taking responsibility for them, and Oracle will take that in consideration.
