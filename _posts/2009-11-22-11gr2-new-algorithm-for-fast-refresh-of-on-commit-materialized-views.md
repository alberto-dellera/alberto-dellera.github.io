---
layout: post
title: '11gR2: new algorithm for fast refresh of on-commit materialized views'
date: 2009-11-22 17:56:28.000000000 +01:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- materialized views
- performance tuning
tags: []
meta: {}
author: Alberto Dell'Era
permalink: "/blog/2009/11/22/11gr2-new-algorithm-for-fast-refresh-of-on-commit-materialized-views/"
migration_from_wordpress:
  approved_on: 20241017
---
This post investigates the improvements that have been made in 11gR2 to the fast refresh engine of materialized views (MVs) that are set to be automatically refreshed at commit time. We speak about join-only materialized views only in this post, as always with the help of a test case.

As noted in the post of mine [11gR2: materialized view logs changes](/blog/2009/11/03/11gr2-materialized-view-logs-changes/), in 11gR2 a new column, xid\$\$, is now part of materialized view logs; this column records the id of the transaction that logged the changes of the base table which the log is defined on. It is important to stress that this column is added regardless of the type of the MV log, that is, to **both** the brand-new "commit SCN-based" logs **and** the old fashioned "timestamp-based" ones. That means that both types of MV logs can take advantage of the new improvements - albeit I haven't tested whether MVs (logs) migrated from a previous version are automatically upgraded by the migration scripts and get the new xid\$\$ column added.

## Algorithm before 11gR2

In versions before 11gR2, the refresh algorithm for on-commit MVs was the same as the one for on-demand ones, with only minor variants. That is, the algorithm was almost completely the same, just triggered by the commit event instead of by the user.

For an in-depth analysis of the algorithm, I will refer the reader to the discussion about the on-demand algorithm in the post [fast refresh of join-only materialized views - algorithm summary](/blog/2009/08/04/fast-refresh-of-join-only-materialized-views-algorithm-summary/); in passing, the [test case](/assets/files/2009/11/11gr2_join_mv_on_commit.zip) for this post is in fact the very same three-table join MV, just redefined as "on commit" instead of "on demand". 

To recap, the "old" algorithm (until 11.1.0.7) was:

1) new log rows are inserted with snaptime\$\$=4000 A.D;  
2) at refresh time (commit time), a snapshot of the new rows is taken, that is, all the new rows are marked with snaptime\$\$= "commit time", using the statement  
```plsql  
update MLOG$_TEST_T1  
   set snaptime$$ = :1  
 where snaptime$$ > to_date('2100-01-01:00:00:00','YYYY-MM-DD:HH24:MI:SS')  
``` 
3) all modifications whose snaptime\$\$ is between the date of the last refresh (excluded) and the commit date(included) are propagated to the MV. The propagation consists of two steps.  

First a DEL step:  
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
    ) -- no "as of snapshot (:2)" clause  
 )  
```  

Then an INS one:  
```plsql
/* MV_REFRESH (INS) */  
insert into test_mv  
select jv.j1_2, jv.x1, jv.pk1, jv.rid$,  
       mas2.j2_1, mas2.j2_3, mas2.x2, mas2.pk2, mas2.rowid,  
       mas3.j3_2, mas3.x3, mas3.pk3, mas3.rowid  
  from (  
    select log.rowid rid$, log.*  
      from test_t1 log  
     where rowid in  
     (  
       select chartorowid(log.m_row$$)  
         from mlog$_test_t1  
        where snaptime$$ > :1  
     )  
 ) jv, -- no "as of snapshot (:2) jv" clause  
   test_t2 as of snapshot (:2) mas2,  
   test_t3 as of snapshot (:2) mas3  
   where jv.j1_2 = mas2.j2_1  
     and mas2.j2_3 = mas3.j3_2  
```

Note that the only small difference from the on-demand case is the absence of the "as of snapshot" clause, but the statements are otherwise identical. Note also that the rows in the MV log are identified in both statements by snaptime, using the subquery  
```plsql 
select chartorowid(log.m_row$$)  
  from mlog$_test_t1  
 where snaptime$$ > :1  
``` 
4) all obsolete log rows are deleted, that is, all rows whose snaptime\$\$ is less than or equal the lowest of all refresh times are removed from the log, using the the statement  
```plsql 
delete from mlog$_test_t1  
 where snaptime$$ <= :1  
```

## Algorithm starting from 11gR2

In 11gR2, the on-commit algorithm is still almost the same as the on-demand one; the "only" change is how modified rows to be propagated are identified, and in general, how logs are managed. Not surprisingly, log rows are now directly identified by the transaction id, which is logged in xid\$\$. 
In detail:

1) new log rows are inserted with xid\$\$ = transaction id;  
2) at refresh time (commit time), **no snapshot is taken** , that is, the MV log is not updated at all;  
3) all modifications made by the committing transaction are propagated to the MV, still using the same two steps.

The DEL step is now:  
```plsql 
/* MV_REFRESH (DEL) */  
delete from test_mv  
 where test_t1_rowid in  
 (  
   select * from  
   (  
     select chartorowid (m_row$$)  
       from mlog$_test_t1  
      where xid$$ = :1  
   )  
 )  
```

The INS one is:  
```plsql  
/* MV_REFRESH (INS) */  
insert into test_mv  
select jv.j1_2, jv.x1, jv.pk1, jv.rid$,  
       mas2.j2_1, mas2.j2_3, mas2.x2, mas2.pk2, mas2.rowid,  
       mas3.j3_2, mas3.x3, mas3.pk3, mas3.rowid  
  from (  
    select log.rowid rid$, log.*  
      from test_t1 log  
     where rowid in  
     (  
       select chartorowid(log.m_row$$)  
         from mlog$_test_t1  
        where xid$$ = :1  
     )  
 ) jv, -- no "as of snapshot (:2) jv" clause  
   test_t2 as of snapshot (:2) mas2,  
   test_t3 as of snapshot (:2) mas3  
   where jv.j1_2 = mas2.j2_1  
     and mas2.j2_3 = mas3.j3_2  
```

Hence, the big difference from the previous versions case is that rows in the MV log are identified very simply by the transaction that logged them (the committing transaction, of course), by the subquery  
```plsql
select chartorowid(log.m_row$$)  
  from mlog$_test_t1  
 where xid$$ = :1  
```  
4) all obsolete log rows are deleted, that is, the rows logged by the committing transaction are removed, using the the statement  
```plsql
delete from mlog$_test_t1  
 where where xid$$ = :1  
```

The new algorithm is for sure much simpler and more elegant. Performance is improved since the snapshot step has been removed, and the other steps are more or less as expensive as before.

## Practical implications: an example

I strongly believe that studying the internals is the best way to learn how to make the best use of any feature. Let's see an example of how the few bits of "internal knowledge" I shared here can be used in practice - that is, how a little investment in investigation makes for huge savings in effort afterwards, and huge gains in effectiveness of your work as well.

It is well-known that it can be sometimes beneficial, in pre-11gR2, to place an index on the log (indexing the log is even suggested by support note "258252 MATERIALIZED VIEW REFRESH: Locking, Performance, Monitoring"). The scenario that benefits the most from such an index is when the log is composed of mostly-empty blocks, and hence an index access is preferable over a full table(log) scan; you get mostly-empty blocks, for example, when there are peeks in activity on the master tables that keep the log High Water Mark very high.

From the above discussion, it is obvious that in pre-11gR2, the best index for join-only MVs was on (snaptime\$\$, m\_row\$\$) - not on snaptime\$\$ alone as it is sometimes suggested - to make the refresh operation an index-only one.

Starting from 11gR2, the best index is now on (xid\$\$, m\_row\$\$). Not only that, but having no snapshot step, and hence no update on the index, makes the indexing option even more attractive.

Could you see these implications so easily, without knowing the internals? I cannot.
