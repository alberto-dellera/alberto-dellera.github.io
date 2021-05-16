---
layout: post
title: '"alter session force parallel query", and indexes'
date: 2013-05-17 14:15:05.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- CBO
tags: []
meta:
  _syntaxhighlighter_encoded: '1'
  _sg_subscribe-to-comments: shivahindwan@gmail.com
author:
  login: alberto.dellera
  email: alberto.dellera@gmail.com
  display_name: Alberto Dell'Era
  first_name: Alberto
  last_name: Dell'Era
permalink: "/blog/2013/05/17/alter-session-force-parallel-query-and-indexes/"
---
<p>This post is a brief discussion about the advantages of activating parallelism by altering the session environment instead of using the alternative ways (hints, DDL). The latter ways are the most popular in my experience, but I have noticed that their popularity is actually due, quite frequently, more to imperfect understanding rather than informed decision - and that's a pity since "alter session force parallel query" can really save everyone a lot of tedious work and improve maintainability a great deal. </p>
<p>We will also check that issuing<br />
[sql light="true"]<br />
alter session force parallel query parallel N;<br />
[/sql]<br />
is the same as specifying the hints<br />
[sql light="true"]<br />
/*+ parallel (t,N)  */<br />
/*+ parallel_index (t, t_idx, N) */<br />
[/sql]<br />
for all tables referenced in the query, and <b>for all indexes defined on them</b> (the former is quite obvious, the latter not that much).</p>
<p>Side note: it is worth remembering that hinting the table for parallelism does not cascade automatically to its indexes as well - you must explicitly specify the indexes that you want to be accessed in parallel by using the separate parallel_index hint (maybe specifying "all indexes" by using the two-parameter variant "parallel_index(t,N)"). The same holds for "alter table parallel N" and "alter <b>index</b> parallel N", of course.</p>
<p><b>the power of "force parallel query"</b></p>
<p>I've rarely found any reason for avoiding index parallel operations nowadays - usually both the tables and their indexes are stored on disks with the same performance figures (if not the same set of disks altogether), and the cost of the initial segment checkpoint is not generally different. At the opposite, using an index can offer terrific opportunities for speeding up queries, especially when a full table scan can be substituted by a fast full scan on a (perhaps much) smaller index.</p>
<p>Thus, I almost always let the CBO consider index parallelism as well. Three methods can be used:<br />
- statement hints (the most popular option)<br />
- alter table/index parallel N<br />
- "force parallel query". </p>
<p>I rather hate injecting parallel hints everywhere in my statements since it is very risky. It is far too easy to forget to specify a table or index (or simply misspell them), not to mention to forget new potentially good indexes added after the statement had been finalized. Also, you must change the statement as well even if you simply want to change the degree of parallelism, perhaps just because you are moving from an underequipped, humble and cheap test environment to a mighty production server. At the opposite, "force parallel query" is simple and elegant - just a quick command and you're done, and with a single place to touch in order to change the parallel degree.</p>
<p>"alter table/index parallel N" is another weak technique as well in my opinion, mainly for two reasons. The first one is that it is a permanent modification to the database objects, and  after the query has finished, it is far too easy to fail to revert the objects back to their original degree setting (because of failure or coding bug). The second one is the risk of  two concurrent sessions colliding on the same object that they both want to read, but with different degrees of parallelism.<br />
Both the two problems above do not hold only when you always want to run with a fixed degree for all statements; but even in this case, I would consider issuing "force parallel query" (maybe inside a logon trigger) instead of having to set/change the degree for all tables/indexes accessed by the application.</p>
<p>I have noticed that many people are afraid of "force parallel query" because of the word "force", believing that it switches every statement into parallel mode. But <b>this is not the case</b>: as <a href="http://blog.tanelpoder.com/2013/03/20/alter-session-force-parallel-query-doesnt-really-force-anything/">Tanel Poder recently illustrated</a>, the phrase "force parallel query" is misleading; a better one would be something like "<i>consider</i> parallel query", since it is perfectly equivalent to hinting the statement for parallelism as far as I can tell (see below). And hinting itself tells the CBO to <i>consider</i> parallelism <i>in addition</i> to serial execution; the CBO is perfectly free to choose a serial execution plan if it estimates that it will cost less - as <a href=" http://jonathanlewis.wordpress.com/2007/06/17/hints-again/ ">demonstrated by Jonathan Lewis</a> years ago.<br />
Hence there's no reason to be afraid, for example, that a nice Index Range Scan that selects just one row might turn into a massively inefficient Full Table Scan (or index Fast Full Scan) of a one million row table/index. That is true besides bugs and CBO limitations, obviously; but in these hopefully rare circumstances, one can always use the no_parallel and no_parallel_index to fix the issue.</p>
<p><b>"force parallel query" and hinting: test case</b></p>
<p>Let's show that altering the session is equivalent to hinting. I will illustrate the simplest case only - a single-table statement that can be resolved either by a full table scan or an index fast full scan (check script force_parallel_main.sql in the <a href="http://34.247.94.223/wp-content/uploads/2013/05/force_parallel_query.zip">test case</a>), but in the test case zip two other scenarios (a join and a subquery) are tested as well. Note: I have only checked 9.2.0.8 and 11.2.0.3 (but I would be surprised if the test case could not reproduce in 10g as well).</p>
<p>Table "t" has an index t_idx on column x, and hence the statement<br />
[sql light="true"]<br />
select sum(x) from t;<br />
[/sql]<br />
can be calculated by either scanning the table or the index. In serial, the CBO chooses to scan the smaller index (costs are from 11.2.0.3):<br />
[sql light="true"]<br />
select /* serial */ sum(x) from t;<br />
--------------------------------------<br />
|Id|Operation             |Name |Cost|<br />
--------------------------------------<br />
| 0|SELECT STATEMENT      |     | 502|<br />
| 1| SORT AGGREGATE       |     |    |<br />
| 2|  INDEX FAST FULL SCAN|T_IDX| 502|<br />
--------------------------------------<br />
 [/sql]<br />
If we now activate parallelism for the table, but not for the index, the CBO chooses to scan the table:<br />
[sql light="true"]<br />
select /*+ parallel(t,20) */ sum(x) from t<br />
------------------------------------------<br />
|Id|Operation              |Name    |Cost|<br />
------------------------------------------<br />
| 0|SELECT STATEMENT       |        | 229|<br />
| 1| SORT AGGREGATE        |        |    |<br />
| 2|  PX COORDINATOR       |        |    |<br />
| 3|   PX SEND QC (RANDOM) |:TQ10000|    |<br />
| 4|    SORT AGGREGATE     |        |    |<br />
| 5|     PX BLOCK ITERATOR |        | 229|<br />
| 6|      TABLE ACCESS FULL|T       | 229|<br />
------------------------------------------<br />
[/sql]<br />
since the cost for the parallel table access is now down from the serial cost of 4135 (check the test case logs) to the parallel cost 4135 / (0.9 * 20) = 229, thus less than the cost (502) of the serial index access.</p>
<p>Hinting the index as well makes the CBO apply the same scaling factor (0.9*20) to the index as well, and hence we are back to index access:<br />
[sql light="true"]<br />
select /*+ parallel_index(t, t_idx, 20) parallel(t,20) */ sum(x) from t<br />
---------------------------------------------<br />
|Id|Operation                 |Name    |Cost|<br />
---------------------------------------------<br />
| 0|SELECT STATEMENT          |        |  28|<br />
| 1| SORT AGGREGATE           |        |    |<br />
| 2|  PX COORDINATOR          |        |    |<br />
| 3|   PX SEND QC (RANDOM)    |:TQ10000|    |<br />
| 4|    SORT AGGREGATE        |        |    |<br />
| 5|     PX BLOCK ITERATOR    |        |  28|<br />
| 6|      INDEX FAST FULL SCAN|T_IDX   |  28|<br />
---------------------------------------------<br />
[/sql]<br />
Note that the cost computation is 28 = 502 / (0.9 * 20), less than the previous one (229).</p>
<p>"Forcing" parallel query:</p>
<p>[sql light="true"]<br />
alter session force parallel query parallel 20;</p>
<p>select /* force parallel query  */ sum(x) as from t<br />
---------------------------------------------<br />
|Id|Operation                 |Name    |Cost|<br />
---------------------------------------------<br />
| 0|SELECT STATEMENT          |        |  28|<br />
| 1| SORT AGGREGATE           |        |    |<br />
| 2|  PX COORDINATOR          |        |    |<br />
| 3|   PX SEND QC (RANDOM)    |:TQ10000|    |<br />
| 4|    SORT AGGREGATE        |        |    |<br />
| 5|     PX BLOCK ITERATOR    |        |  28|<br />
| 6|      INDEX FAST FULL SCAN|T_IDX   |  28|<br />
---------------------------------------------<br />
[/sql]<br />
Note that the plan is the same (including costs), as predicted.</p>
<p>Side note: let's verify, just for fun, that the statement can run serially even if the session is "forced" as parallel (note that I have changed the statement since the original always benefits from parallelism):</p>
<p>[sql light="true"]<br />
alter session force parallel query parallel 20;</p>
<p>select /* force parallel query (with no parallel execution) */ sum(x) from t<br />
WHERE X &lt; 0<br />
----------------------------------<br />
|Id|Operation         |Name |Cost|<br />
----------------------------------<br />
| 0|SELECT STATEMENT  |     |   3|<br />
| 1| SORT AGGREGATE   |     |    |<br />
| 2|  INDEX RANGE SCAN|T_IDX|   3|<br />
----------------------------------<br />
[/sql]</p>
<p>Side note 2: activation of parallelism for all referenced objects  can be obtained, in 11.2.0.3, using the new statement-level parallel hint (check <a href="http://oracle-randolf.blogspot.it/2011/03/things-worth-to-mention-and-remember-ii.html">this note by Randolf Geist</a> for details):<br />
[sql light="true"]<br />
select /*+ parallel(20) */ sum(x) from t<br />
---------------------------------------------------<br />
|Id|Operation                 |Name    |Table|Cost|<br />
---------------------------------------------------<br />
| 0|SELECT STATEMENT          |        |     |  28|<br />
| 1| SORT AGGREGATE           |        |     |    |<br />
| 2|  PX COORDINATOR          |        |     |    |<br />
| 3|   PX SEND QC (RANDOM)    |:TQ10000|     |    |<br />
| 4|    SORT AGGREGATE        |        |     |    |<br />
| 5|     PX BLOCK ITERATOR    |        |     |  28|<br />
| 6|      INDEX FAST FULL SCAN|T_IDX   |T    |  28|<br />
---------------------------------------------------
  
[/sql]  
This greatly simplifies hinting, but of course you must still edit the statement if you need to change the parallel degree.