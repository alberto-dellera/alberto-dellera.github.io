---
layout: post
title: '11gR2: materialized view logs changes'
date: 2009-11-03 19:20:51.000000000 +01:00
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
permalink: "/blog/2009/11/03/11gr2-materialized-view-logs-changes/"
migration_from_wordpress:
  approved_on: working
---
In this post we are going to discuss some 11gR2 changes to materialized view logs that are aimed at increasing the performance of the fast-refresh engine of materialized views (MVs), especially the on-commit variant.

The MV logs, in 10gr2, now comes in [two flavours](http://download.oracle.com/docs/cd/E11882_01/server.112/e10592/statements_6003.htm#i2064649"): the traditional (and still the default) **timestamp**-based one and the brand new **commit SCN**-based one; you choose the latter type by specifing the "WITH COMMIT SCN" clause at MV log creation time. Interestingly, the "old" timestamp-based implementation has been changed as well. Let's examine both with the help, as usual, of a [test case](/assets/files/2009/11/11gr2_mv_logs.zip).

## Timestamp-based MV logs (the "old" type)

The test case configures an MV log as "log everything", that is, it activates all the logging options:
```plsql  
create materialized view log on test_t1
with sequence, rowid, primary key (x1)
including new values;
```

In pre-11gR2 (e.g. in 11.1.0.7, 10.2.0.4), the MV log columns were:
```
pk1             number(22)
x1              number(22)
m_row$$         varchar2(255)
sequence$$      number(22)
snaptime$$      date(7)
dmltype$$       varchar2(1)
old_new$$       varchar2(1)
change_vector$$ raw(255)
```

now in 11gR2 (11.2.0.1):
```
pk1             number(22)
x1              number(22)
m_row$$         varchar2(255)
sequence$$      number(22)
snaptime$$      date(7)
dmltype$$       varchar2(1)
old_new$$       varchar2(1)
change_vector$$ raw(255)
xid$$           number(22)
```  

the only difference is the new column xid\$\$ (transaction id) that uniquely identifies the transaction that made the changes to the row. For the curious, the number is a combination of the elements of the triplet (undo segment number, undo slot, undo sequence); it is simply the binary concatenation of the three numbers shifted by (48, 32, 0) bits respectively (as checked in the script).

The xid\$\$ column is used by the 11gR2 on-commit fast refresh engine, which can now easily retrieve the changes made by the just-committed transaction by its xid; at the opposite, the on-demand fast refresh one keeps using snaptime$$ as it did in previous versions. I will speak about this in more detail in an upcoming post.

## Commit SCN-based MV logs (the "new" type in 11gR2)

Let's recreate the same MV log, this time adding the commit SCN clause (new in 11GR2):
```plsql  
create materialized view log on test_t1
with sequence, rowid, primary key (x1), COMMIT SCN
including new values;
```

The columns of the MV log are:
```
pk1             number(22)
x1              number(22)
m_row$$         varchar2(255)
sequence$$      number(22)
dmltype$$       varchar2(1)
old_new$$       varchar2(1)
change_vector$$ raw(255)
xid$$           number(22)
```

so, the only difference from the 11gR2 timestamp-based case is that  snaptime\$\$ is no longer a column of the MV log; the only difference from the pre-11gR2 is that snaptime\$\$ has been replaced with xid\$\$.

For this log flavour only, the mapping between the xid that modified the table and its commit-time SCN is now tracked in a new view, all_summap (probably named after "SUMmary MAP", "summary" being yet another synonym for "MV"), which is (as of 11.2.0.1) a straight "select *" of  the dictionary table sys.snap_xcmt\$. To illustrate, the script makes one insert, one update and one delete on the base table, which translates into 4 rows inside the MV log with the same xid:

```plsql  
SQL> select distinct xid$$ from mlog$_test_t1;
```
```
                XID$$
---------------------
     1126024460895690
```
after the commit, we get
```plsql  
SQL> select * from all_summap where xid in (select xid$$ from mlog$_test_t1);
```
```
                  XID COMMIT_SCN
--------------------- ----------
  
 1126024460895690 2885433  
```  
hence, it is now possible to know the infinite-precision time (the SCN) when every modification became visible to an external observer (the commit SCN) by simply joining the MV log and all\_summap (or sys.snap\_xcmt\$). Note that the commit SCN is not propagated to the MV log at all.

## Commit SCN-based MV logs for on-demand fast refresh

This new xid\$\$ column and commit-SCN mapping table are leveraged by the fast refresh of on-demand MVs as follows (on-commit ones do not need the SCN as they know exactly the xid of the committed transaction; again we will see that in an upcoming post).

With "old style" timestamp-based MV logs, the refresh is performed by using a "mark-and-propagate" algorithm, which is essentially (check [this post](/blog/2009/08/04/fast-refresh-of-join-only-materialized-views-algorithm-summary/) for some additional details):  
1) new log rows are inserted with snaptime\$\$=4000 A.D;  
2) at refresh time, a snapshot of the new rows is taken, that is, all new rows are marked with snaptime\$\$=sysdate;  
3) all modifications whose snaptime\$\$ is between the date of the last refresh (excluded) and sysdate(included) are propagated to the MV;  
4) all obsolete log rows are deleted, that is, all rows whose snaptime\$\$ is less than or equal the lowest of all refresh times are removed from the log.

With "new style" SCN-based MV logs, the algorithm is, instead:  
1) new log rows are inserted with xid\$\$=transaction id of modifing transaction;  
2) at refresh time, the current SCN is retrieved (no snapshot is performed);  
3) all modifications whose xid maps to a row in all\_summap whose commit\_scn is between the SCN of the last refresh (excluded) and the retrieved current SCN(included) are propagated to the MV;  
4) obsolete rows are removed from the log as before, this time using the SCN instead of snaptime\$\$.

The main advantage is that the snapshot is not performed, thus removing the redo and undo generated by the update, and obviously the log visit (usually a full table scan) as well - at the cost of an additional join with all\_summap (or sys.snap\_xcmt$) later; if the join is calculated efficiently, that is very likely advantageous "in general" (but as always, it depends on your scenario).

It might be (rarely) beneficial to index xid\$\$, as it is (rarely) beneficial to index snaptime\$\$. In that case, having no snapshot performed reduces both the undo and redo generated for the index maintenance.

As a side and "philosophical" note, it is also worth noting that the new logging mechanism records more information - now we know which transactions modified the table and the infinite-precision time (the SCN) of modifications, and this is much more informative about the history of the logged table than the mostly meaningless refresh time contained in snaptime\$\$. This is definitely a better utilization of storage.

I plan to blog about how the new MV log impact fast refreshes in 11gR2 in the near future, focusing on join-only MVs; so stay tuned if you're interested.
