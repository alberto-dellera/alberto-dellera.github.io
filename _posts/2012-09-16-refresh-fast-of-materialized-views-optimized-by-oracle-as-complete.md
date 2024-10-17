---
layout: post
title: refresh "fast" of materialized views optimized by Oracle as "complete"
date: 2012-09-16 18:49:14.000000000 +02:00
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
permalink: "/blog/2012/09/16/refresh-fast-of-materialized-views-optimized-by-oracle-as-complete/"
migration_from_wordpress:
  approved_on: working 
---
>In my current "big" project, I am building a network of nested materialized views to transform rows of  one schema into rows of another (very different) schema. The former is used by the old (but still live) version of an application of ours, the latter by the new version; our idea is to incrementally (aka "fast") refresh the network daily in order to have the new schema ready when the new version goes live. We need this nework because we have only a few hours of allowed downtime, and the transformations are very complex: the MV network is going to be composed of at least 200+ MVs, each containing tens of millions of rows.

We have carefully  designed all MVs as fast refreshable, and built a simple PL/SQL engine to refresh them in parallel using Oracle jobs; we are hence sure that we can meet our time constraints. Now I'm looking at optimizing the COMPLETE refresh, both for damage limitation (should some MVs required to be refreshed as complete, due to corruption or recreation mandated by to last-minute functional changes) and to speed up the initial network build. 
One of the optimization I was thinking about was to refresh as complete any MV whose masters have been completely refreshed before, since it is common knowledge that in this case, "complete" is much faster then "fast" (pardon the pun) - mostly because using the MV log to identify  modified rows is far from cheap and it's a huge, useless overhead when ALL rows have been modified. But actually I don't need to worry, since I have discovered that in this case, Oracle <i>silently</i> turns the fast refresh into a complete one, at least in 11.2.0.3. 

The [test case](http://34.247.94.223/wp-content/uploads/2012/09/mv_fast_becomes_complete.zip) (script mv_fast_becomes_complete.sql) builds a chain of three MVs:

```plsql
create table dellera_t ..
create materialized view dellera_mv1 .. as select .. from dellera_t;
create materialized view dellera_mv2 .. as select .. from dellera_mv1;
create materialized view dellera_mv3 .. as select .. from dellera_mv2;
```

Then the test case modifies some rows of the master table and asks for fast refresh:
```plsql
exec dbms_mview.refresh('dellera_mv1', method=>'f', atomic_refresh => true);
exec dbms_mview.refresh('dellera_mv2', method=>'f', atomic_refresh => true);
exec dbms_mview.refresh('dellera_mv3', method=>'f', atomic_refresh => true);
```

It's no surprise that we get:
```
SQL> select mview_name, last_refresh_type from user_mviews
where mview_name like 'DELLERA%' order by mview_name;
MVIEW_NAME           LAST_REFRESH_TYPE
-------------------- ------------------------
DELLERA_MV1          FAST
DELLERA_MV2          FAST
DELLERA_MV3          FAST
```

But, when the test case refreshes the first alone as complete, keeping the next ones as fast:
```plsql
exec dbms_mview.refresh('dellera_mv1', method=>'c', atomic_refresh => true);
exec dbms_mview.refresh('dellera_mv2', method=>'f', atomic_refresh => true);
exec dbms_mview.refresh('dellera_mv3', method=>'f', atomic_refresh => true);
```

We get:
```
MVIEW_NAME           LAST_REFRESH_TYPE
-------------------- ------------------------
DELLERA_MV1 COMPLETE  
DELLERA_MV2 COMPLETE  
DELLERA_MV3 COMPLETE  
``` 

Hence, our request for fast has been silently turned by Oracle into a complete refresh, for all MVs down the chain. By the way, I have verified that this is true also for join-only and aggregates-only Mvs (check the test case if interested): all it takes to trigger this silent optimization is that at least one master has been completely refreshed before.  

Moreover, the trace file shows the following steps, for the fast-turned-complete refresh of dellera\_mv2 (edited for readability):  
```plsql
a) update mlog$_dellera_mv1 set snaptime$$ = :1 where ...;  
b) delete from dellera_mv2;  
c) delete from mlog$_dellera_mv2;  
d) insert into dellera_mv2 (m_row$$, x , y , rid#)  
select rowid,x,y,rowid from dellera_mv1;  
e) delete from mlog$_dellera_mv1 where snaptime$$ <= :1;  
```

This is indeed the signature of a complete refresh: a complete delete (b) of the refreshing MV (dellera\_mv2) followed by a straight insert (d) from the master (dellera\_mv1), with no visit of the MV log of the master besides the usual initial marking (a) and the final purge (e).  
What is also interesting is that the MV log is completely (no reference to snaptime$$) deleted in (c) BEFORE the insert; insertion that does not populate the MV log since the kernel trigger is "disabled" during a complete refresh (otherwise we would find a lot of rows in the log since the delete happens before and not after, but the script verifies that no row is found). No MV log management overhead, as expected. 

It's also interesting to check what changes when the refresh is done with atomic =\> false (NB I have skipped table-locking and index-maintenance operations, and non pertinent hints, for brevity):  
```plsql  
a) same as above  
b) same as above  
c) truncate table dellera\_mv2 purge snapshot log;  
d) insert /*+ append */ into dellera_mv2 (m_row$$, x , y , rid#)  
   select rowid,x,y,rowid from dellera_mv1;  
e) same as above  
```

That is, the delete has turned into a "truncate purge snapshot log" and the insert is now running in append mode, the rest is the same. In passing, (b) looks a tad redundant.  
As always, you can find all scripts in the test case .zip above - including of course spool files and traces, the latter also processed with a tool of mine (now retired) to quickly mine the SQL statements of interest. 
