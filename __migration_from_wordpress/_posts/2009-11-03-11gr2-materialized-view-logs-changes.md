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
  _syntaxhighlighter_encoded: '1'
author:
  login: alberto.dellera
  email: alberto.dellera@gmail.com
  display_name: Alberto Dell'Era
  first_name: Alberto
  last_name: Dell'Era
permalink: "/blog/2009/11/03/11gr2-materialized-view-logs-changes/"
---
<p>In this post we are going to discuss some 11gR2 changes to materialized view logs that are aimed at increasing the performance of the fast-refresh engine of materialized views (MVs), especially the on-commit variant. </p>
<p>The MV logs, in 10gr2, now comes in <a href="http://download.oracle.com/docs/cd/E11882_01/server.112/e10592/statements_6003.htm#i2064649">two flavours</a>: the traditional (and still the default) <b>timestamp</b>-based one and the brand new <b>commit SCN</b>-based one; you choose the latter type by specifing the "WITH COMMIT SCN" clause at MV log creation time. Interestingly, the "old" timestamp-based implementation has been changed as well. Let's examine both with the help, as usual, of a <a href="http://34.247.94.223/wp-content/uploads/2009/11/11gr2_mv_logs.zip">test case</a>.</p>
<p><b>Timestamp-based MV logs (the "old" type)</b></p>
<p>The test case configures an MV log as "log everything", that is, it activates all the logging options:<br />
[text]<br />
create materialized view log on test_t1<br />
with sequence, rowid, primary key (x1)<br />
including new values;<br />
[/text]</p>
<p>In pre-11gR2 (e.g. in 11.1.0.7, 10.2.0.4), the MV log columns were:<br />
[text]<br />
pk1             number(22)<br />
x1              number(22)<br />
m_row$$         varchar2(255)<br />
sequence$$      number(22)<br />
snaptime$$      date(7)<br />
dmltype$$       varchar2(1)<br />
old_new$$       varchar2(1)<br />
change_vector$$ raw(255)<br />
[/text]<br />
now in 11gR2 (11.2.0.1):<br />
[text]<br />
pk1             number(22)<br />
x1              number(22)<br />
m_row$$         varchar2(255)<br />
sequence$$      number(22)<br />
snaptime$$      date(7)<br />
dmltype$$       varchar2(1)<br />
old_new$$       varchar2(1)<br />
change_vector$$ raw(255)<br />
xid$$           number(22)<br />
[/text]<br />
the only difference is the new column xid$$ (transaction id) that uniquely identifies the transaction that made the changes to the row. For the curious, the number is a combination of the elements of the triplet (undo segment number, undo slot, undo sequence); it is simply the binary concatenation of the three numbers shifted by (48, 32, 0) bits respectively (as checked in the script).</p>
<p>The xid$$ column is used by the 11gR2 on-commit fast refresh engine, which can now easily retrieve the changes made by the just-committed transaction by its xid; at the opposite, the on-demand fast refresh one keeps using snaptime$$ as it did in previous versions. I will speak about this in more detail in an upcoming post.</p>
<p><b>Commit SCN-based MV logs (the "new" type in 11gR2)</b></p>
<p>Let's recreate the same MV log, this time adding the commit SCN clause (new in 11GR2):<br />
[text]<br />
create materialized view log on test_t1<br />
with sequence, rowid, primary key (x1), COMMIT SCN<br />
including new values;<br />
[/text]<br />
The columns of the MV log are:<br />
[text]<br />
pk1             number(22)<br />
x1              number(22)<br />
m_row$$         varchar2(255)<br />
sequence$$      number(22)<br />
dmltype$$       varchar2(1)<br />
old_new$$       varchar2(1)<br />
change_vector$$ raw(255)<br />
xid$$           number(22)<br />
[/text]<br />
so, the only difference from the 11gR2 timestamp-based case is that  snaptime$$ is no longer a column of the MV log; the only difference from the pre-11gR2 is that snaptime$$ has been replaced with xid$$.</p>
<p>For this log flavour only, the mapping between the xid that modified the table and its commit-time SCN is now tracked in a new view, all_summap (probably named after "SUMmary MAP", "summary" being yet another synonym for "MV"), which is (as of 11.2.0.1) a straight "select *" of  the dictionary table sys.snap_xcmt$. To illustrate, the script makes one insert, one update and one delete on the base table, which translates into 4 rows inside the MV log with the same xid:<br />
[sql]<br />
SQL&gt; select distinct xid$$ from mlog$_test_t1;</p>
<p>                XID$$<br />
---------------------<br />
     1126024460895690<br />
[/sql]<br />
after the commit, we get<br />
[sql]<br />
SQL&gt; select * from all_summap where xid in (select xid$$ from mlog$_test_t1);</p>
<p>                  XID COMMIT_SCN<br />
--------------------- ----------
  
 1126024460895690 2885433  
[/sql]  
hence, it is now possible to know the infinite-precision time (the SCN) when every modification became visible to an external observer (the commit SCN) by simply joining the MV log and all\_summap (or sys.snap\_xcmt$). Note that the commit SCN is not propagated to the MV log at all.

**commit SCN-based MV logs for on-demand fast refresh**

This new xid$$ column and commit-SCN mapping table are leveraged by the fast refresh of on-demand MVs as follows (on-commit ones do not need the SCN as they know exactly the xid of the committed transaction; again we will see that in an upcoming post).

With "old style" timestamp-based MV logs, the refresh is performed by using a "mark-and-propagate" algorithm, which is essentially (check [this post](http://www.adellera.it/blog/2009/08/04/fast-refresh-of-join-only-materialized-views-algorithm-summary/) for some additional details):  
1) new log rows are inserted with snaptime$$=4000 A.D;  
2) at refresh time, a snapshot of the new rows is taken, that is, all new rows are marked with snaptime$$=sysdate;  
3) all modifications whose snaptime$$ is between the date of the last refresh (excluded) and sysdate(included) are propagated to the MV;  
4) all obsolete log rows are deleted, that is, all rows whose snaptime$$ is less than or equal the lowest of all refresh times are removed from the log.

With "new style" SCN-based MV logs, the algorithm is, instead:  
1) new log rows are inserted with xid$$=transaction id of modifing transaction;  
2) at refresh time, the current SCN is retrieved (no snapshot is performed);  
3) all modifications whose xid maps to a row in all\_summap whose commit\_scn is between the SCN of the last refresh (excluded) and the retrieved current SCN(included) are propagated to the MV;  
4) obsolete rows are removed from the log as before, this time using the SCN instead of snaptime$$.

The main advantage is that the snapshot is not performed, thus removing the redo and undo generated by the update, and obviously the log visit (usually a full table scan) as well - at the cost of an additional join with all\_summap (or sys.snap\_xcmt$) later; if the join is calculated efficiently, that is very likely advantageous "in general" (but as always, it depends on your scenario).

It might be (rarely) beneficial to index xid$$, as it is (rarely) beneficial to index snaptime$$. In that case, having no snapshot performed reduces both the undo and redo generated for the index maintenance.

As a side and "philosophical" note, it is also worth noting that the new logging mechanism records more information - now we know which transactions modified the table and the infinite-precision time (the SCN) of modifications, and this is much more informative about the history of the logged table than the mostly meaningless refresh time contained in snaptime$$. This is definitely a better utilization of storage.

I plan to blog about how the new MV log impact fast refreshes in 11gR2 in the near future, focusing on join-only MVs; so stay tuned if you're interested.

