---
layout: post
title: overlapping ranges with priority
date: 2012-10-01 10:54:57.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- case studies
tags: []
meta:
  _syntaxhighlighter_encoded: '1'
  _sg_subscribe-to-comments: ginger_barron_qra13@hushmail.com
author:
  login: alberto.dellera
  email: alberto.dellera@gmail.com
  display_name: Alberto Dell'Era
  first_name: Alberto
  last_name: Dell'Era
permalink: "/blog/2012/10/01/overlapping-ranges-with-priority/"
---
<p>A customer of ours (a leading Italian consumer goods retailer) has asked us to solve the following  problem, that occurs quite frequently and that is not trivial to solve efficiently - and that is very interesting to design and fun to blog about!<br />
<b>the problem</b><br />
Prices of <a href="http://en.wikipedia.org/wiki/Stock-keeping_unit">sku</a>s (i.e. goods) have validity ranges (time intervals) and can overlap;  on an overlapping range, the strongest priority  (lower number) wins. In pictures:</p>
<pre>
b---(0,$200)---d
          c---(1,$300)---e
</pre>
<p>the expected output is, since priority 0 is stronger then 1:</p>
<pre>
b----($200)----d---($300)---e
</pre>
<p>I'm going to illustrate in detail the pure-SQL algorithm I have designed, and then discuss about its performance and efficiency. As usual, everything I discuss is supported by an <a href="http://34.247.94.223/wp-content/uploads/2012/09/overlapping_ranges_with_priority.zip">actual demo</a>. Please note that the algorithm uses analytics functions very, very heavily.<br />
<b>pure SQL solution</b><br />
The input table:<br />
[sql light="true"]<br />
create table ranges (<br />
  sku   varchar2(10) not null,<br />
  a     int not null,<br />
  b     int not null,<br />
  prio  int not null,<br />
  price int not null<br />
);<br />
alter table ranges add constraint ranges_pk primary key (sku, a, b);<br />
[/sql]<br />
Let's provide the opening example as input:<br />
[sql light="true"]<br />
insert into ranges(sku, a, b, prio, price) values ('sku1', ascii('b'), ascii('d'), 0, 200);<br />
insert into ranges(sku, a, b, prio, price) values ('sku1', ascii('c'), ascii('e'), 1, 300);<br />
[/sql]<br />
The algorith is implemented as a single view; let's comment each step and show its output over the example:<br />
 [sql light="true"]<br />
create or replace view ranges_output_view<br />
as<br />
[/sql]<br />
The instants in time where the ranges start or begin:<br />
 [sql light="true"]<br />
with instants as (<br />
  select sku, a as i from ranges<br />
  union<br />
  select sku, b as i from ranges<br />
),<br />
[/sql]<br />
Output: b,c,d,e.<br />
The base ranges, i.e. the consecutive ranges that connect all the instants:<br />
[sql light="true"]<br />
base_ranges as (<br />
  select *<br />
    from (<br />
  select sku,<br />
         i as ba,<br />
         lead(i) over (partition by sku order by i) as bb<br />
    from instants<br />
         )<br />
   where bb is not null<br />
),<br />
[/sql]</p>
<pre> b------c------d------e </pre>
<p>The original ranges factored over the base ranges; in other words, "cut" by the instants:<br />
[sql light="true"]<br />
factored_ranges as (<br />
  select i.sku, bi.ba, bi.bb, i.a, i.b, i.prio, i.price<br />
    from ranges i, base_ranges bi<br />
   where i.sku = bi.sku<br />
     and (i.a &lt;= bi.ba and bi.ba &lt; i.b)<br />
),<br />
[/sql]</p>
<pre>
b---(0,$200)---c---(0,$200)---d
               c---(1,$300)---d---(1,$300)---e
</pre>
<p>Then, let's filter out the factored ranges with weaker priority (that have a stronger priority range with the same extremes "covering" them):<br />
[sql light="true"]<br />
strongest_factored_ranges as (<br />
  select sku, ba, bb, prio, price<br />
    from (<br />
  select sku, ba, bb, prio, price,<br />
         dense_rank () over (partition by sku, ba, bb order by prio) as rnk<br />
    from factored_ranges<br />
         )<br />
   where rnk = 1<br />
),<br />
[/sql]</p>
<pre>
b---(0,$200)---c---(0,$200)---d---(1,$300)---e
</pre>
<p>The problem could be now considered solved, if you could live with consecutive intervals showing the same price (such as b--c and c--d above). If you can't for whatever reason (I couldn't), we can join them using analytics again in a way similar to this <a href=" http://www.oracle.com/technetwork/issue-archive/o24asktom-095715.html ">asktom technique</a> (look at the bottom for "Analytics to the Rescue (Again)").<br />
First, we calculate "step", a nonnegative number  that will be zero if a range can be joined to the previous one, since:<br />
a) they are consecutive (no gap between them)<br />
 b) they have the same price:<br />
[sql light="true"]<br />
ranges_with_step as (<br />
  select sku, ba, bb, prio, price,<br />
         decode ( price, lag(price) over (partition by sku order by ba),  ba - lag(bb) over (partition by sku order by ba), 1000 ) step<br />
    from strongest_factored_ranges<br />
),<br />
[/sql]</p>
<pre>
RANGE_CODED                    STEP
------------------------ ----------
b---(0,$200)---c               1000
c---(0,$200)---d                  0
d---(1,$300)---e               1000
</pre>
<p>Then we compute the integral of step over the ranges;  joinable ranges will hence have the same value for "interval" since step is zero:<br />
[sql light="true"]<br />
ranges_with_step_integral as (<br />
  select sku, ba, bb, prio, price, step,<br />
         sum(step) over (partition by sku order by ba rows between unbounded preceding and current row) as integral<br />
    from ranges_with_step<br />
),<br />
[/sql]</p>
<pre>
RANGE_CODED                INTEGRAL 
------------------------ ---------- 
b---(0,$200)---c               1000 
c---(0,$200)---d               1000 
d---(1,$300)---e               2000 
</pre>
<p>The joined joinable ranges :<br />
[sql light="true"]<br />
ranges_joined as (<br />
  select *<br />
    from (<br />
  select sku, ba, bb, prio, price, step, integral,<br />
         min(ba) over (partition by sku, integral) as a,<br />
         max(bb) over (partition by sku, integral) as b<br />
    from ranges_with_step_integral<br />
         )<br />
   where step &gt; 0<br />
)<br />
select sku, a, b, price from ranges_joined;<br />
[/sql]</p>
<pre>
b---(0,$200)---c---(1,$300)---e
</pre>
<p><b>predicate-"pushability"</b><br />
The first desirable property of this view is that a predicate (such as an equality predicate, but it works even for the "between" operator, less-than, etc) on sku  can be pushed down the view to the base tables. For:<br />
[sql light="true"]<br />
select * from ranges_output_view where sku = 'k100';<br />
[/sql]<br />
the plan is:<br />
 [sql light="true"]<br />
----------------------------------------------------------<br />
| Id  | Operation                            | Name      |<br />
----------------------------------------------------------<br />
...<br />
|  10 |           TABLE ACCESS BY INDEX ROWID| RANGES    |<br />
|* 11 |            INDEX RANGE SCAN          | RANGES_PK |<br />
...<br />
|* 17 |                INDEX RANGE SCAN      | RANGES_PK |<br />
|* 18 |                INDEX RANGE SCAN      | RANGES_PK |<br />
----------------------------------------------<br />
---<br />
11 - access(&quot;I&quot;.&quot;SKU&quot;='k100')<br />
---<br />
17 - access(&quot;SKU&quot;='k100')<br />
18 - access(&quot;SKU&quot;='k100')<br />
[/sql]<br />
That means that only the required SKU(s) are fed to the view, and proper indexes (such as RANGES_PK in this case) can be used. So, if you need to refresh only a few skus the response time is going to be almost istantaneous - provided that you have only sane (a few) ranges per sku. Hence you can use the same view for both calculating prices of all skus (say, in a nightly batch) and calculating a small subset of skus (say, online), and that is a great help for maintenance and testing.<br />
<b>running in parallel</b><br />
Another desirable property is that the view can operate efficiently in parallel, at least in 11.2.0.3 (I have not tested other versions):<br />
[sql light="true"]<br />
-------------------------------------------------------------------<br />
| Operation                                   |IN-OUT| PQ Distrib |<br />
-------------------------------------------------------------------<br />
| SELECT STATEMENT                            |      |            |<br />
|  PX COORDINATOR                             |      |            |<br />
|   PX SEND QC (RANDOM)                       | P-&gt;S | QC (RAND)  |<br />
|    VIEW                                     | PCWP |            |<br />
|     WINDOW SORT                             | PCWP |            |<br />
|      VIEW                                   | PCWP |            |<br />
|       WINDOW SORT                           | PCWP |            |<br />
|        VIEW                                 | PCWP |            |<br />
|         WINDOW BUFFER                       | PCWP |            |<br />
|          VIEW                               | PCWP |            |<br />
|           WINDOW SORT PUSHED RANK           | PCWP |            |<br />
|            HASH JOIN                        | PCWP |            |<br />
|             PX RECEIVE                      | PCWP |            |<br />
|              PX SEND HASH                   | P-&gt;P | HASH       |<br />
|               PX BLOCK ITERATOR             | PCWC |            |<br />
|                TABLE ACCESS FULL            | PCWP |            |<br />
|             PX RECEIVE                      | PCWP |            |<br />
|              PX SEND HASH                   | P-&gt;P | HASH       |<br />
|               VIEW                          | PCWP |            |<br />
|                WINDOW SORT                  | PCWP |            |<br />
|                 PX RECEIVE                  | PCWP |            |<br />
|                  PX SEND HASH               | P-&gt;P | HASH       |<br />
|                   VIEW                      | PCWP |            |<br />
|                    SORT UNIQUE              | PCWP |            |<br />
|                     PX RECEIVE              | PCWP |            |<br />
|                      PX SEND HASH           | P-&gt;P | HASH       |<br />
|                       UNION-ALL             | PCWP |            |<br />
|                        PX BLOCK ITERATOR    | PCWC |            |<br />
|                         INDEX FAST FULL SCAN| PCWP |            |<br />
|                        PX BLOCK ITERATOR    | PCWC |            |<br />
|                         INDEX FAST FULL SCAN| PCWP |            |<br />
-------------------------------------------------------------------
  
[/sql]  
There's no point of serialization (all servers communicate parallel-to-parallel), the rows are distributed evenly using an hash distribution function (probably over the sku) and all operations are parallel.  
**sku subsetting and partitioning**  
It is well known that analytics functions use sort operations heavily, and that means (whether or not you are running in parallel) that the temporary tablespace may be used a lot, possibly too much - as it actually happened to me , leading to (in my case) unacceptable performance.  
_Side note: as I'm writing this, I realize now that I had probably been hit by the bug illustrated by Jonathan Lewis in [Analytic Agony](http://jonathanlewis.wordpress.com/2009/09/07/analytic-agony/), but of course, overuse of temp could happen, for large datasets, without the bug kicking in._  
A possible solution is to process only a sub-batch of the skus at a time, to keep the sorts running in memory (or with one-pass to temp), leveraging the predicate-pushability of the view. In my case, I have made one step further: I have partitioned the table "ranges" by "sku\_group", replaced in the view every occurrence of "sku" with the pair "sku\_group, sku", and then run something like:  
[sql light="true"]  
 for s in (select sku\_group from "list of sku\_group") loop  
 select .. from ranges\_output\_view where sku\_group = s.sku\_group;  
end loop;  
[/sql]  
The predicate gets pushed down to the table, hence partition elimination kicks in and I can visit the input table one time only, one partition at a time, using a fraction of the resources at a time, and hence vastly improving performance.  
And that naturally leads to "do-it-yourself parallelism": running a job for every partition in parallel. I'm going to implement it since the customer is salivating about it ... even if it is probably over-engineering :D .