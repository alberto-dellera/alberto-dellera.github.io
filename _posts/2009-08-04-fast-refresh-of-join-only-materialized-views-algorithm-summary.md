---
layout: post
title: fast refresh of join-only materialized views - algorithm summary
date: 2009-08-04 16:34:51.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- materialized views
tags: []
meta: {}
author: Alberto Dell'Era
permalink: "/blog/2009/08/04/fast-refresh-of-join-only-materialized-views-algorithm-summary/"
migration_from_wordpress:
  approved_on: working
---
This post investigates how Oracle fast refreshes materialized views containing only joins of master tables:  
```plsql 
create materialized view test_mv  
build immediate  
refresh fast on demand  
as  
select test_t1.*, test_t1.rowid as test_t1_rowid,  
       test_t2.*, test_t2.rowid as test_t2_rowid,  
       test_t3.*, test_t3.rowid as test_t3_rowid  
  from test_t1, test_t2, test_t3  
 where test_t1.j1_2 = test_t2.j2_1  
   and test_t2.j2_3 = test_t3.j3_2  
;  
```
The fast refresh algorithm is simple and very easy to understand - so trivial in fact that once examined and understood, the possible tuning techniques follow naturally.

The [test case](/assets/files/2009/08/post_0030_join_mv.zip) traces the fast refresh of the above materialized view (MV) using the 10046 event (aka "sql trace"). The test case has been run on 9.2.0.8, 10.2.0.4 and 11.1.0.7 (the latest versions of 9i, 10g and 11g available as of today), and on all of these versions the algorithm used by the refreshing engine (run by invoking dbms\_mview.refresh) appears to be the same, with only a few implementation differences.

The test case explores the most general case: it performs inserts, updates and deletes on all the three master tables (the inserts being conventional; I will explore direct-path inserts another time).

### Materialized view logs configuration

In the test case, I have configured the materialized view logs to "log everything", in order to check whether more information in the logs could trigger some special kernel code designed to take advantage of it:  
```plsql  
create materialized view log on test_t1  
with sequence, rowid, primary key (j1_2, x1)  
including new values;  
```
but the engine uses only the rowid information even in 11.1.0.7, so you are better off logging only the rowid if the master table feeds join-only materialized views exclusively:  
```plsql
create materialized view log on test_t1 with rowid;  
``` 
Minimal logging obviously improves the performance of DML against the master tables, but it also optimizes the fast refresh, since the latter, as we are going to see in a moment, reads each log twice, and of course the less you log, the more compact the logs will be.

### Log snapshots

After some preliminary visits to the data dictionary, the first operation performed by the fast refresh engine is to "mark" the modifications (recorded in the materialized view logs) to be propagated to the MV. Only the marked log rows are then fed by the fast refresh engine as input to the next steps.

The "flag" used to mark the rows is the column snaptime\$\$. When the refresh starts, the engine performs a "snapshot" of the materialized view logs by setting the snaptime\$\$ of all the new rows (those with snaptime\$\$ = '01/01/4000') of each log in turn to the current time (SYSDATE).

In detail, the snapshot is performed by issuing this SQL statement (slightly edited for readability) in 9.2.0.8 and 10.2.0.4:  
```plsql 
update MLOG$_TEST_T1  
   set snaptime$$ = :1  
 where snaptime$$ > to_date('2100-01-01:00:00:00','YYYY-MM-DD:HH24:MI:SS')  
``` 
The bind variable :1 is a DATE whose value is equal to SYSDATE.

Note: In 11.1.0.7, the statement is slightly different but makes the same thing, probably in a more scalable way concurrency-wise (check the script spools if you're interested).

You might have noticed the where condition on snaptime\$\$; that is necessary since the logs might be used by more than one materialized view. When a refresh ends, in fact, the engine checks whether other MVs might need each log row, and deletes only the log rows that have been processed by all dependant MVs; the other ones are left unchanged (and hence keep the snaptime\$\$ that was set when the fast refresh started). The where condition is needed to avoid overwriting the snaptime\$\$, and mark with the current time only the brand new rows (those with snaptime\$\$ = '01/01/4000').

So, at the end of the snapshot, the log rows that must be examined by the refresh engine will be the ones that are marked by having their snaptime\$\$ between the date of the last refresh (excluded) and :1 (included). All the other log rows must be ignored.

Side note: marking data at a certain point in time and then replicating the marked data is the only replication strategy that can work when you cannot "freeze" the master tables, as this is definitely our case. This is a general topic worth blogging about in the future.

The marked log rows are then inspected to count the number and type of the logged modifications. This is to check whether any of the replication steps (i.e. the DEL and INS steps that we are going to discuss in a moment) could be skipped. Also, the number of modifications is used (in some versions) to inject some hints in the SQL statements of the replication steps, a topic that falls out of the scope of this post.

### Core algorithm: the INS and DEL steps

Then, the core replication starts. The replication considers each master table in turn, and for each table, propagates the modifications to the MV. So we have essentially one single algorithm that propagates from a single master table, just repeated once for each master table.

The propagation for each master table is made of two simple steps, steps that I'm going to name after the comments of the SQL as a DEL (DELETE) step followed by an INS (INSERT) step.

The DEL step is (editing for readability: removing hints, unnecessary aliases, etc):  
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
The subquery simply fetches the rowid of all marked rows, since :1 is the date of the previous refresh of the materialized view, and :2 is the SCN (coded as a RAW variable) of the time when the snapshot was performed. So, this step deletes from the MV all the rows that record the result of the MV-defining join of any of the marked rows (of the current master table) with the other master tables.

This is the step that can benefit from the index on the column that stores the master table rowid (here, test\_t1\_rowid) that the [documentation suggests](http://download.oracle.com/docs/cd/B28359_01/server.111/b28313/refresh.htm#sthref463) to create. Note that in order to optimize this step, you need three separate single-column indexes (here, on test\_t1\_rowid, test\_t2\_rowid, test\_t3\_rowid), not a single composite index spanning the (here, three) columns, as it is sometimes wrongly stated.

The INS step is (again editing for readability):  
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
       ) as of snapshot (:2) jv,  
 test_t2 as of snapshot (:2) mas2,  
 test_t3 as of snapshot (:2) mas3  
where jv.j1_2 = mas2.j2_1  
  and mas2.j2_3 = mas3.j3_2  
``` 
The subquery is the same as the DEL step and serves the very same function. So, this statement replays the SQL statement of the MV definition, but limited to the marked rows only. Note that all tables are read at the same point in time in the past, the time when the snapshot of the log was performed, thanks to the argument of the "as of snapshot" clause being the same.

In order to speed up the INS step, indexes on the joined columns can be created on the master tables (not on the MV!). 
This is because, special cases aside, it is well known that the "fast refresh"  can be actually "fast" only if a small fraction of the master tables is modified; otherwise, a complete refresh is better (in passing: the adjective "fast" itself is quite horrible, many people prefer the adjective "incremental"). 
In this scenario, almost certainly the optimal plan is a series of NESTED LOOPs that has the current table (test\_t1 in this case) as the most outer table, series that can usually benefit a lot by an index on the inner tables join columns. Of course, you must remember that every table, in turn, acts as the most outer table, hence you should index every possible join permutation.

So here what the algorithm is all about: the DEL and INS steps, together, simply ** delete and recreate the "slice" of the MV that is referenced by the marked rows**, whatever the modification type. The algorithm is as simple (and brutal) as it seems.

### Algorithm optimizations

The only optimizations performed are the skipping of some steps when they are obviously unnecessary. For every master table, the DEL step is skipped when only INSERTs are marked in the logs; the INS is skipped when only DELETEs are marked, and of course both are skipped if no row is marked. I have not been able to spot any other optimization.

Note that this means that UPDATEs always turn into a delete+insert of the entire "slice". For example, consider the typical case of a parent table (say, CUSTOMER), with a child (say, ORDER) and a grandchild (say, ORDER\_LINE); if you update a column of a row of the parent (say, ORDERS\_TOTAL\_AMOUNT), the parent row and its whole progeny (the "slice") will be deleted and then recreated. This was a quite surprising discovery for me - a fact that I have now committed to memory as a fact to check first when investigating performance issues.
