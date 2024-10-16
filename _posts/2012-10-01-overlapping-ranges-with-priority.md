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
author: Alberto Dell'Era
permalink: "/blog/2012/10/01/overlapping-ranges-with-priority/"
migration_from_wordpress:
  approved_on: working
---
A customer of ours (a leading Italian consumer goods retailer) has asked us to solve the following  problem, that occurs quite frequently and that is not trivial to solve efficiently - and that is very interesting to design and fun to blog about!

## The problem

Prices of [sku](http://en.wikipedia.org/wiki/Stock-keeping_unit)s (i.e. goods) have validity ranges (time intervals) and can overlap; on an overlapping range, the strongest priority  (lower number) wins. In pictures:

```
b---(0,$200)---d
          c---(1,$300)---e
```
the expected output is, since priority 0 is stronger then 1:
```
b----($200)----d---($300)---e
```

I'm going to illustrate in detail the pure-SQL algorithm I have designed, and then discuss about its performance and efficiency. As usual, everything I discuss is supported by an [actual demo](/assets/files/2012/09/overlapping_ranges_with_priority.zip). Please note that the algorithm uses analytics functions very, very heavily.

### Pure SQL solution

The input table:
```plsql
create table ranges (
  sku   varchar2(10) not null,
  a     int not null,
  b     int not null,
  prio  int not null,
  price int not null
);
alter table ranges add constraint ranges_pk primary key (sku, a, b);
```

Let's provide the opening example as input:
```plsql
insert into ranges(sku, a, b, prio, price) values ('sku1', ascii('b'), ascii('d'), 0, 200);
insert into ranges(sku, a, b, prio, price) values ('sku1', ascii('c'), ascii('e'), 1, 300);
```
The algorithm is implemented as a single view; let's comment each step and show its output over the example:
```plsql
create or replace view ranges_output_view
as
```
The instants in time where the ranges start or begin:
```plsql
with instants as (
  select sku, a as i from ranges
  union
  select sku, b as i from ranges
),
```
``` b,c,d,e.
```

The base ranges, i.e. the consecutive ranges that connect all the instants:
```plsql
base_ranges as (
  select *
    from (
  select sku,
         i as ba,
         lead(i) over (partition by sku order by i) as bb
    from instants
         )
   where bb is not null
),
```
``` b------c------d------e ```

The original ranges factored over the base ranges; in other words, "cut" by the instants:
```plsql
factored_ranges as (
  select i.sku, bi.ba, bi.bb, i.a, i.b, i.prio, i.price
    from ranges i, base_ranges bi
   where i.sku = bi.sku
     and (i.a &lt;= bi.ba and bi.ba &lt; i.b)
),
```
```
b---(0,$200)---c---(0,$200)---d
               c---(1,$300)---d---(1,$300)---e
```
Then, let's filter out the factored ranges with weaker priority (that have a stronger priority range with the same extremes "covering" them):
```plsql
strongest_factored_ranges as (
  select sku, ba, bb, prio, price
    from (
  select sku, ba, bb, prio, price,
         dense_rank () over (partition by sku, ba, bb order by prio) as rnk
    from factored_ranges
         )
   where rnk = 1
),
```
```
b---(0,$200)---c---(0,$200)---d---(1,$300)---e
```

The problem could be now considered solved, if you could live with consecutive intervals showing the same price (such as b--c and c--d above). If you can't for whatever reason (I couldn't), we can join them using analytics again in a way similar to this [asktom technique](http://www.oracle.com/technetwork/issue-archive/o24asktom-095715.html) (look at the bottom for "Analytics to the Rescue (Again)").

First, we calculate "step", a nonnegative number that will be zero if a range can be joined to the previous one, since:
 a- they are consecutive (no gap between them)
 b- they have the same price:
```plsql
ranges_with_step as (
  select sku, ba, bb, prio, price,
         decode ( price, lag(price) over (partition by sku order by ba),  ba - lag(bb) over (partition by sku order by ba), 1000 ) step
    from strongest_factored_ranges
),
```
```
RANGE_CODED                    STEP
------------------------ ----------
b---(0,$200)---c               1000
c---(0,$200)---d                  0
d---(1,$300)---e               1000
```

Then we compute the integral of step over the ranges;  joinable ranges will hence have the same value for "interval" since step is zero:
```plsql
ranges_with_step_integral as (
  select sku, ba, bb, prio, price, step,
         sum(step) over (partition by sku order by ba rows between unbounded preceding and current row) as integral
    from ranges_with_step
),
```
```
RANGE_CODED                INTEGRAL 
------------------------ ---------- 
b---(0,$200)---c               1000 
c---(0,$200)---d               1000 
d---(1,$300)---e               2000 
```

The joined joinable ranges :
```plsql
ranges_joined as (
  select *
    from (
  select sku, ba, bb, prio, price, step, integral,
         min(ba) over (partition by sku, integral) as a,
         max(bb) over (partition by sku, integral) as b
    from ranges_with_step_integral
         )
   where step < 0
)
select sku, a, b, price from ranges_joined;
```
```
b---(0,$200)---c---(1,$300)---e
```

### Predicate-"pushability"

The first desirable property of this view is that a predicate (such as an equality predicate, but it works even for the "between" operator, less-than, etc) on sku  can be pushed down the view to the base tables. 

For:
```plsql
select * from ranges_output_view where sku = 'k100';
```
the plan is:
```
----------------------------------------------------------
| Id  | Operation                            | Name      |
----------------------------------------------------------
...
|  10 |           TABLE ACCESS BY INDEX ROWID| RANGES    |
|* 11 |            INDEX RANGE SCAN          | RANGES_PK |
...
|* 17 |                INDEX RANGE SCAN      | RANGES_PK |
|* 18 |                INDEX RANGE SCAN      | RANGES_PK |
----------------------------------------------
---
11 - access(&quot;I&quot;.&quot;SKU&quot;='k100')
---
17 - access(&quot;SKU&quot;='k100')
18 - access(&quot;SKU&quot;='k100')
```
That means that only the required SKU(s) are fed to the view, and proper indexes (such as RANGES_PK in this case) can be used. So, if you need to refresh only a few skus the response time is going to be almost istantaneous - provided that you have only sane (a few) ranges per sku. Hence you can use the same view for both calculating in bulk prices of all skus (say, in a nightly batch) and calculating a small subset of skus (say, online), and that is a great help for maintenance and testing.

### Running in parallel

Another desirable property is that the view can operate efficiently in parallel, at least in 11.2.0.3 (I have not tested other versions):
```
-------------------------------------------------------------------
| Operation                                   |IN-OUT| PQ Distrib |
-------------------------------------------------------------------
| SELECT STATEMENT                            |      |            |
|  PX COORDINATOR                             |      |            |
|   PX SEND QC (RANDOM)                       | P-<S | QC (RAND)  |
|    VIEW                                     | PCWP |            |
|     WINDOW SORT                             | PCWP |            |
|      VIEW                                   | PCWP |            |
|       WINDOW SORT                           | PCWP |            |
|        VIEW                                 | PCWP |            |
|         WINDOW BUFFER                       | PCWP |            |
|          VIEW                               | PCWP |            |
|           WINDOW SORT PUSHED RANK           | PCWP |            |
|            HASH JOIN                        | PCWP |            |
|             PX RECEIVE                      | PCWP |            |
|              PX SEND HASH                   | P-<P | HASH       |
|               PX BLOCK ITERATOR             | PCWC |            |
|                TABLE ACCESS FULL            | PCWP |            |
|             PX RECEIVE                      | PCWP |            |
|              PX SEND HASH                   | P-<P | HASH       |
|               VIEW                          | PCWP |            |
|                WINDOW SORT                  | PCWP |            |
|                 PX RECEIVE                  | PCWP |            |
|                  PX SEND HASH               | P-<P | HASH       |
|                   VIEW                      | PCWP |            |
|                    SORT UNIQUE              | PCWP |            |
|                     PX RECEIVE              | PCWP |            |
|                      PX SEND HASH           | P-<P | HASH       |
|                       UNION-ALL             | PCWP |            |
|                        PX BLOCK ITERATOR    | PCWC |            |
|                         INDEX FAST FULL SCAN| PCWP |            |
|                        PX BLOCK ITERATOR    | PCWC |            |
|                         INDEX FAST FULL SCAN| PCWP |            |
-------------------------------------------------------------------
```
There's no point of serialization (all servers communicate parallel-to-parallel), the rows are distributed evenly using an hash distribution function (probably over the sku) and all operations are parallel.

### Sku subsetting and partitioning

It is well known that analytics functions use sort operations heavily, and that means (whether or not you are running in parallel) that the temporary tablespace may be used a lot, possibly too much - as it actually happened to me, leading to (in my case) unacceptable performance.

_Side note: as I'm writing this, I realize now that I had probably been hit by the bug illustrated by Jonathan Lewis in [Analytic Agony](http://jonathanlewis.wordpress.com/2009/09/07/analytic-agony/), but of course, overuse of temp could happen, for large datasets, without the bug kicking in._  

A possible solution is to process only a sub-batch of the skus at a time, to keep the sorts running in memory (or with one-pass to temp), leveraging the predicate-pushability of the view. In my case, I have made one step further: I have partitioned the table "ranges" by "sku\_group", replaced in the view every occurrence of "sku" with the pair "sku\_group, sku", and then run something like:  
```plsql  
 for s in (select sku_group from "list of sku_group") loop  
 select .. from ranges_output_view where sku_group = s.sku_group;  
end loop;  
```

The predicate gets pushed down to the table, hence partition elimination kicks in and I can visit the input table one time only, one partition at a time, using a fraction of the resources at a time, and hence vastly improving performance.

And that naturally leads to "do-it-yourself parallelism": running a job for every partition in parallel. I'm going to implement it since the customer is salivating about it ... even if it is probably over-engineering :D .
