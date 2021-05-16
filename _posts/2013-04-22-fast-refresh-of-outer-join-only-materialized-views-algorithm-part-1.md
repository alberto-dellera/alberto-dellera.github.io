---
layout: post
title: fast refresh of outer-join-only materialized views - algorithm, part 1
date: 2013-04-22 09:40:24.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- materialized views
tags: []
meta:
  _sg_subscribe-to-comments: deehoganwmi90@hotmail.com
  _syntaxhighlighter_encoded: '1'
author:
  login: alberto.dellera
  email: alberto.dellera@gmail.com
  display_name: Alberto Dell'Era
  first_name: Alberto
  last_name: Dell'Era
permalink: "/blog/2013/04/22/fast-refresh-of-outer-join-only-materialized-views-algorithm-part-1/"
---
In this series of posts we will discuss how Oracle refreshes materialized views (MV) containing only OUTER joins, covering only 11.2.0.3. We will use the very same scenario (MV log configuration, DML type, etc) as in the [_inner_ join]( http://www.adellera.it/blog/2009/08/04/fast-refresh-of-join-only-materialized-views-algorithm-summary/) case, "just" turning the inner join into an outer join:

[sql light="true"]  
create materialized view test\_mv  
build immediate  
refresh fast on demand  
as  
select test\_outer.\*, test\_outer.rowid as test\_outer\_rowid,  
 test\_inner.\*, test\_inner.rowid as test\_inner\_rowid  
 from test\_outer, test\_inner  
 where test\_outer.jouter = test\_inner.jinner(+)  
;  
[/sql]

For the outer case, the overall strategy is the same we already saw for inner joins: modifications from each master table are propagated separately to the MV, and by still performing, for each master table, the same two macro steps (first the DEL, and then the INS one).

Actually, propagation from the outer table is exactly the same (with the obvious slight difference of performing an outer join to recalculate the "slice" in the INS step), and hence we will discuss only the propagation from the inner table, which is considerably more complex.

There are actually _two_ different propagation algorithms, one much simpler and less resource-intensive that requires a **unique constraint on the joined columns** (here, "jinner" alone); in this post I will discuss the details of this specialized algorithm only, leaving the details of the "general" other one for the next post.

Does the existence of a a unique constraint on the joined colum(s) enable such a dramatic simplification of the propagation that justifies a specialized algorithm? Yes, absolutely - and it is interesting to understand the reason since it comes out naturally from the very semantic of the outer join SQL construct, and hence we can also improve our understanding of this important component of the SQL syntax as a by-product.

Let's start by remembering that every row of the outer table is always represented in the MV, possibly with all columns coming from the inner table set to null (including, most importantly, test\_inner\_rowid) if no match is found in the inner table. If M matches are found for a given outer row, M rows will be present in the MV; e.g. for M=2, we will see the following "outer slice" (my definition) corresponding to outer row ooo:

ooo inn1  
ooo inn2

Now, if a unique constraint exists on the joined column(s), M can be at most 1, and hence only two possible states are possible for our outer slice:

(a) ooo inn1  
(b) ooo \*null\*

Hence, if inn1 is marked in the log, propagating its deletion in the DEL step is just a matter of simply switching the slice from state (a) to (b) using an update statement, and conversely, propagating its insertion in the INS step is just a matter of updating the slice from state (b) to state (a). In other words, the possible matching rows of the outer table are already there, in the MV, and all we need to do is to "flip their state" if necessary. Thus it is possible to propagate using only quite efficient update statements - no delete or insert needs to be performed at all.

Now, consider how the absence of unique constraint adds additional complexity. In this case this scenario is possible:

ooo inn1  
ooo inn2

if only one of (inn1, inn2) is marked in the log, the DEL step can simply delete only the corresponding row in the MV, but if both are marked, it must leave a single row with all the columns coming from the inner table set to null:

ooo \*null\*

conversely, the INS step must remember to remove the above row if it finds at least a match in the outer table.

In other words, _the whole "outer slice" must be considered and examined by both steps_; it is not enough to consider only marked rows "in isolation", as it was the case in the inner join scenario and the constrained outer join scenario. This is considerably more complex, and in fact, the "general" algorithm was designed and implemented only in 10g - before 10g it was _mandatory_ to have a unique constraint on the joined columns to enable fast refresh.

**conventions and investigation scope**  
To reduce the visual clutter, instead of this log reading fragment (whose meaning we already discussed in the previous post)  
[sql light="true"]  
(select rid$  
 from (select chartorowid(mas$.m\_row$$) rid$  
 from mlog$\_test\_inner mas$  
 where mas$.snaptime$$ \> :b\_st0  
 )  
) as of snapshot(:b\_scn) mas$  
[/sql]  
I will use the following simplified notation  
[sql light="true"]  
(select rid$ from mlog$\_test\_inner)  
[/sql]  
And of course, I will restructure and simplify the SQL statements to increase readability (the original statements are included in the [test case](http://34.247.94.223/wp-content/uploads/2013/04/join_mv_outer_part1_unique.zip) of course).

I will also define a row as "marked in the log" if it has a match in the set "select rid$ from mlog$\_test\_inner" - the matching column being test\_inner\_rowid for the MV and the actual rowid for the inner table test\_inner.

I am covering only 11.2.0.3 in the same scenario of the inner join post quoted above: MV logs configured to "log everything" and a single fast refresh propagating all possible types of regular (no direct-path) INSERTs, UPDATEs and DELETEs performed on the master tables (I haven't investigated possible variants of the refresh algorithm if only a subset of those DML types is performed).

**The DEL macro step with the unique constraint**  
As stated above , it consists of a simple update:  
[sql light="true"]  
/\* MV\_REFRESH (UPD) \*/  
update test\_mv  
 set jinner = null, xinner = null, pkinner = null, test\_inner\_rowid = null  
 where test\_inner\_rowid in (select rid$ from mlog$\_test\_inner)  
[/sql]  
that simply flips to null the columns coming from the inner table of all marked rows of the MV.

**The INS macro step with the unique constraint**   
Again, as stated above, this step consists of a (not so simple) update:  
[sql light="true"]  
/\* MV\_REFRESH (UPD) \*/  
update /\*+ bypass\_ujvc \*/ (  
select test\_mv.jinner target\_0, jv.jinner source\_0,  
 test\_mv.xinner target\_1, jv.xinner source\_1,  
 test\_mv.pkinner target\_2, jv.pkinner source\_2,  
 test\_mv.test\_inner\_rowid target\_3, jv.rid$ source\_3  
 from ( select test\_inner.rowid rid$, test\_inner.\*  
 from test\_inner  
 where rowid in (select rid$ from mlog$\_test\_inner)  
 ) jv,  
 test\_outer,  
 test\_mv  
where test\_outer.jouter = jv.jinner  
 and test\_mv.test\_outer\_rowid = test\_outer.rowid  
)  
set target\_0 = source\_0,  
 target\_1 = source\_1,  
 target\_2 = source\_2,  
 target\_3 = source\_3  
[/sql]  
this statement joins the marked rows of the inner table with the outer table (using an inner join, not an outer join, of course) and then looks for matching slices (by test\_outer\_rowid) in the MV; for every match, it flips the columns coming from the inner table from null to their actual values.

As a side note, it's worth noting that the statement updates an updatable in-line view, which is actually "tagged as updatable" by the hint "bypass\_ujvc" ("bypass the Updatable Join Validity Check" probably), an hint that only Oracle code can use nowadays.

**speeding up**

Looking at the above SQL statements, it comes out naturally that if your fast refresh process propagates a small number of modifications, it is beneficial, to speed up the fast refresh from the inner table, to create  
- for the DEL step: an index on test\_mv (test\_inner\_rowid)  
- for the INS step: an index on test\_mv(test\_outer\_rowid) and another on test\_outer(jouter).

To also speed up the refresh from the outer table (not shown in this post), you would also create an index on on test\_inner(jinner) and test\_mv(test\_outer\_rowid).

So in essence, the very same indexes as in the inner join case need to be created for the outer join. But note that if you never propagate from the outer table, the index on test\_mv(test\_outer\_rowid) has to be created anyway - that index was not necessary in the inner join case.

Of course, as the number of modifications increase, and/or if you fast-refresh in parallel, the indexes might not be used by the CBO that could prefer full-scanning the tables; in that case they would just be update overhead. Your mileage may vary, as always - but knowing the actual algorithm and SQL submitted is for sure very helpful to decide. Hope this helps.

