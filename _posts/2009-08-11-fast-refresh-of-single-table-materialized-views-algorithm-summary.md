---
layout: post
title: fast refresh of single-table materialized views - algorithm summary
date: 2009-08-11 17:57:10.000000000 +02:00
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
permalink: "/blog/2009/08/11/fast-refresh-of-single-table-materialized-views-algorithm-summary/"
migration_from_wordpress:
  approved_on: working
---
Today we are going to investigate how Oracle fast refreshes materialized views (MVs) of a single master table, containing no aggregate but, at most, filter predicates and additional column definitions:  
```plsql 
create materialized view test_mv  
build immediate  
refresh fast on demand  
with rowid  
-- with primary key  
as  
select test_t1.*, x1+x2 as x1x2  
 from test_t1  
 where x1 != 0.42;  
```  
This kind of MVs might be considered a degenerate case of a join-only MV, a topic that we investigated on an earlier [post](/blog/2009/08/04/fast-refresh-of-join-only-materialized-views-algorithm-summary/), and one could expect the same algorithm. But that is not the case: the [test case](/assets/file/2009/08/post_0050_single_table_mv.zip) shows that the algorithm used is very different.  

The two main differences are (as we are going to illustrate in detail) that UPDATEs are actually used in this case (as [noted](/blog/2009/08/04/fast-refresh-of-join-only-materialized-views-algorithm-summary/#comments) by [Cristian Cudizio](http://cristiancudizio.wordpress.com/ )) instead of DELETE+INSERT only, and especially that row-by-row propagation is performed instead of using a couple of single SQL statements.

This kind of MV is frequently used for replication across a db-link (with a clause such as "from test\_t1@db\_link"); in this scenario, the MV used to be named SNAPSHOT in old releases. I have checked this scenario as well (not included in the test case) and the only difference is that, obviously, the master table test\_t1 is referenced via a db-link and a few hints are injected by the refreshing engine.

In the test case, I have checked both the WITH ROWID and WITH PRIMARY KEY options for the MV DDL; the algorithm turns out as being identical, besides (obviously) that in the former the rowid and in the latter the primary key is used to identify rows.

I am going to follow the path of the previous discussion about join-only MVs referenced above, as both the test case format and some of the actual refresh steps are very similar. I have tested on 9.2.0.8, 10.2.0.4 and 11.1.0.7 for the most common DML on the base table (conventional INSERTs, UPDATEs and DELETEs). I have seen no difference in the algorithm for the three kernel versions.

**Materialized view logs configuration**

Even for this test case, I have configured the materialized view logs to "log everything" to check whether Oracle is able to take advantage of more information in the log:  
```plsql 
create materialized view log on test_t1  
with sequence, rowid, primary key (x1, x2)  
including new values;  
```
but even for single-table MVs the algorithm uses only the rowid or primary key information, hence the minimal (and hence optimal) log configuration is, for the WITH ROWID option:  
```plsql 
create materialized view log on test_t1 with rowid;  
```
and for the WITH PRIMARY KEY option:  
```plsql
create materialized view log on test_t1 with primary key;  
```

## Log snapshots

The first step in the refresh algorithm is to take a log snapshot, exactly as in the join-only case, by setting snaptime\$\$  current time. Hencethe marked log rows (the ones and only ones to consider for propagation) will be characterized by snaptime\$\$ <= current time and > last snapshot refresh time. See the previous post about the join-only case for a more in-depth discussion.

Note: actually, for the sake of precision, two (minor) differences with the join-only case are that the snapshot statement is exactly the same in all versions (there's no special version for 11.1.0.7) and that the log is not "inspected to count the number and type of the logged modifications".

## Core algorithm: the DELETE and UPSERT steps

Then, the core replication starts. The propagation from the master table is composed of two simple steps, steps that I've named DELETE and UPSERT (UPDate + insERT).

The first **DELETE step** is a simple select-then-delete row-by-row processing, where each row returned by a select statement is passed to a single-row delete statement.  
For the WITH ROWID option, the select statement of the DELETE step is (editing for readability: removing hints, unnecessary aliases, etc):  
```plsql 
select distinct m_row$$  
 from (  
select m_row$$  
 from mlog$_test_t1  
 where snaptime$$ > :1  
 and dmltype$$ != 'I'  
 ) log  
 where m_row$$ not in  
 (  
select rowid from test_t1 mas  
 where (mas.x1 <> 0.42)  
 and mas.rowid = log.m_row$$  
 );  
```  
and the delete is a trivial  
```plsql
delete from test_mv where m_row$$ = :1;  
```  
The select+delete purpose is to delete all marked rows that are not in the master table anymore, or that are still there but that do not satisfy the MV defining SQL (here, x1 != 0.42) anymore.

In fact, the first in-line view fetches from the log the rowid of a subset (those whose dmltype$$ != 'I') of the marked rows, since :1 is set to the date of the previous refresh of the materialized view. Well actually - the SQL, as it is, would also get the log rows inserted after the snapshot was taken, which is obviously not acceptable since the propagation must operate on a stable set of rows. I'm not sure how the non-marked rows are excluded, but probably the various "select for update" on the log data dictionary tables might play a role by locking the commits on the logs, or maybe the serialization level is set to read-only or serializable (I will investigate this in the future). For now, let's make the conjecture that only the marked rows are selected.

The last correlated subquery simply filters out the rowid of the rows that are still in the master table. The condition dmltype$$ != 'I' ('I' stands for INSERT) is only an optimization, since an inserted row would be filtered out by the subquery anyway - unless it has not been deleted after being inserted, but that would be recorded with another log row with dmltype\$\$ = 'D'.

Why are updates (dmltype$$ = 'U') not optimized away as well? This is to delete rows from the MV that no longer belong to the current image of the MV defining SQL statement, since they used to satisfy the filter condition (here, x1 != 0.42) but no longer do after an update. Thanks to the filter condition (x1 != 0.42) being included in the subquery, any row that does not satisfy it anymore after an update will not be filtered out, and hence will be deleted.

Note that column m\_row$$ of the MV is a hidden (but not virtual) column that records, for each MV row, the rowid of the corresponding master table row. It is automatically created when you define the MV with the WITH ROWID option; an index is automatically created on m\_row\$\$ as well (unless you specify USING NO INDEX, something that does not make sense if you want to fast refresh the MV). Hence you do not need to create any additional index, neither on the master table nor on the MV, to optimize this step of the fast refresh.

Switching to the WITH PRIMARY KEY option, the select statement of the DELETE step is  
```plsql  
select distinct pk1  
 from (  
    select pk1  
      from mlog$_test_t1  
     where snaptime$$ > :1  
       and dmltype$$ != 'I' 
 ) log  
 where pk1 not in  
 (  
  select pk1  
    from test_t1 mas  
   where (mas.x1 <> 0.42)  
     and log.pk1 = mas.pk1  
 );  
``` 

and the delete is simply  
```plsql 
delete from test_mv where pk1 = :1;  
```

That is, the statements are the same as in the WITH ROWID case, with the primary key instead of the rowid in all statements. Since the master table must have a primary key for the MV create to succeed, and since an index on the MV that spans the primary key column(s) is automatically created (unless you specify USING NO INDEX of course), even in the WITH PRIMARY KEY case you do not need to create any additional index for performance. Actually, for best performance, an index on the master table that combines the PK and the column(s) referenced by the MV filter condition - here on (pk1, x1) - might help a bit, since probably the optimal plan is a nested loop having test\_t1 as the inner table. This would avoid a block get on the master tables for marked rows not satisfying the MV filter condition; the effectiveness of this index depends on whether you have a lot of updates on the column referenced in the filter condition.

The **UPSERT step** is a simple select-then-upsert row-by-row processing, where each row returned by a select statement (that calculates the current image of the row that needs to be propagated to the MV) is used to update the corresponding row in the MV; if the update finds no row, the row is inserted.

For the WITH ROWID option, the select statement of the UPSERT step is:  
```plsql
select current.x1, current.x2, current.pk1, current.x1x2,  
        rowidtochar (current.rowid) m_row$$  
  from (  
    select x1, x2, pk1, x1+x2 as x1x2  
     from test_t1  
    where (x1 <> 0.42)  
  ) current,  
  (  
    select distinct m_row$$  
      from mlog$_test_t1  
     where snaptime$$ > :1  
       and dmltype$$ != 'D'  
  ) log  
 where current.rowid = log.m_row$$;  
```  

and the update and insert statements are simply:  
```plsql 
update test_mv set x1=:1, x2=:2, pk1=:3, x1x2 = :4 
 where m_row$$ = :5;  

insert into test_mv (x1,x2,pk1,x1x2,m_row$$) values (:1,:2,:3,:4,:5);  
``` 
The select+upsert purpose is to calculate the new image of all marked rows that satisfy the MV defining SQL filter condition (here, x1 != 0.42) and then overwrite the old image in the MV with the new one. Note that an update on the master table might produce an insert if the old image did not satisfy the filter condition and the new one does.

The structure of the select statement should be obvious after the previous illustration of the DELETE step. Note of course the different optimization in the second inline view (dmltype\$\$ != 'D'). Even in this case, the automatically created index on the m\_row\$\$ MV column optimizes the update statement, and no other index is necessary for performance on neither the base table nor the MV.

Switching to the WITH PRIMARY KEY option, the select statement of the UPSERT step is  
```plsql
select current.x1, current.x2, current.pk1, current.x1x2  
  from (  
    select x1, x2, pk1, x1+x2 x1x2  
      from test_t1  
     where (x1 <> 0.42)  
  ) current,  
  (  
    select distinct pk1  
      from mlog_test_t1  
     where snaptime$$ > :1  
      and dmltype$$ != 'D'  
  ) log  
where current.pk1 = log.pk1;  
```

and the update and insert statements are:  
[sql]  
update test_mv set x1=:1, x2=:2, pk1=:3, x1x2=:4 where pk1=:3;

insert into test_mv (x1, x2, pk1, x1x2) values (:1, :2, :3, :4);  
[/sql]

And the same considerations about the substitution of rowid with the primary key hold. The index on the master table on (pk1, x1) might be of help here as well.

So here it is what the algorithm, essentially, is all about: a row-by-row propagation of all the modified (marked) rows to the MV, with a few optimizations.

## Algorithm optimizations

Whatever the type of modifications, the algorithm is always the same: both the DELETE and UPSERT step are performed in all cases. Of course, in both cases, the select statement might select no row.