---
layout: post
title: Fast refresh of aggregate-only materialized views with SUM - algorithm
date: 2013-08-19 14:26:04.000000000 +02:00
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
  _sg_subscribe-to-comments: taylor_raymond_mxb92@hotmail.com
author:
  login: alberto.dellera
  email: alberto.dellera@gmail.com
  display_name: Alberto Dell'Era
  first_name: Alberto
  last_name: Dell'Era
permalink: "/blog/2013/08/19/fast-refresh-of-aggregate-only-materialized-views-with-sum-algorithm/"
---
In this post I will illustrate the algorithm used by Oracle (in 11.2.0.3) to fast refresh a materialized view (MV) containing only the SUM aggregate function:

[sql light="true"]  
create materialized view test\_mv  
build immediate  
refresh fast on demand  
with rowid  
as  
select gby as mv\_gby,  
 count(\*) as mv\_cnt\_star,  
 sum (dat) as mv\_sum\_dat,  
 count(dat) as mv\_cnt\_dat  
 from test\_master  
 where whe = 0  
 group by gby  
;  
[/sql]

Note that count(dat) is specified - you could avoid that if column dat is constrained to be not-null (as stated in the documentation), but I'm not covering that corner case here.

The MV log is configured to "log everything":  
[sql light="true"]  
create materialized view log on test\_master  
with rowid ( whe, gby, dat ), sequence  
including new values;  
[/sql]

In the [general introduction to aggregate-only MVs](http://www.adellera.it/blog/2013/08/05/fast-refresh-of-aggregate-only-materialized-views-introduction/) we have seen how the refresh engine first marks the log rows, then inspects TMPDLT (loading its rows into the result cache at the same time) to classify its content as insert-only (if it contains only new values), delete-only (if it contains only old values) or general (if it contains a mix of new/old values). Here we illustrate the refreshing SQL in all three scenarios, extracted from the supporting [test case](http://34.247.94.223/wp-content/uploads/2013/08/post_0270_gby_mv_sum.zip).

**refresh for insert-only TMPDLT**

The refresh is made using this single merge statement:  
[sql light="true"]  
/\* MV\_REFRESH (MRG) \*/  
merge into test\_mv  
using (  
 with tmpdlt$\_test\_master as (  
 -- check introduction post for statement  
 )  
 select gby,  
 sum( 1 ) as cnt\_star,  
 sum( 1 \* decode(dat, null, 0, 1) ) as cnt\_dat,  
 nvl( sum( 1 \* dat), 0 ) as sum\_dat  
 from (select gby, whe, dat  
 from tmpdlt$\_test\_master  
 ) as of snapshot(:b\_scn)  
 where whe = 0  
 group by gby  
) deltas  
on ( sys\_op\_map\_nonnull(test\_mv.mv\_gby) = sys\_op\_map\_nonnull(deltas.gby) )  
when matched then  
 update set  
 test\_mv.mv\_cnt\_star = test\_mv.mv\_cnt\_star + deltas.cnt\_star,  
 test\_mv.mv\_cnt\_dat = test\_mv.mv\_cnt\_dat + deltas.cnt\_dat,  
 test\_mv.mv\_sum\_dat = decode( test\_mv.mv\_cnt\_dat + deltas.cnt\_dat,  
 0, null,  
 nvl(test\_mv.mv\_sum\_dat,0) + deltas.sum\_dat  
 )  
when not matched then  
 insert ( test\_mv.mv\_gby, test\_mv.mv\_cnt\_dat, test\_mv.mv\_sum\_dat, test\_mv.mv\_cnt\_star )  
 values ( deltas.gby, deltas.cnt\_dat, decode (deltas.cnt\_dat, 0, null, deltas.sum\_dat), deltas.cnt\_star)  
[/sql]  
It simply calculates the delta values to be propagated by grouping-and-summing the new values contained in TMPDLT that satisfy the where-clause (essentially, it executes the MV statement on the mv log without redundant values), and then looks for matches over the grouped-by expression (using the null-aware function sys\_op\_map\_nonnull, more on this later). It then applies the deltas to the MV, or simply inserts them if no match is found.

Note that mv\_sum\_dat (that materializes sum(dat)) is set to null if, and only if, (the updated value of) mv\_cnt\_dat (that materializes count(dat)) is zero (signaling that for this value of mv\_gby, all values of dat in the master table are null). This is done in all three scenarios of the algorithm.

The matching function sys\_op\_map\_nonnull() is there to match null values with null values, since aggregating by null is perfectly legal, yet you cannot match null with null in a merge/join. This function returns a raw value that is never null, and set to 0xFF when the input is null and to the binary representation of the input postfixed with 0x00 for other input values. Note that a function-based index, named I\_SNAP$\_TEST\_MV in our case, is automatically created on sys\_op\_map\_nonnull(mv\_gby) to give the CBO the opportunity to optimize the match (unless the MV is created specifying USING NO INDEX, which is probably almost never a good idea when you need to fast refresh).

Note also that the master table, test\_master, is not accessed at all, as it is always the case for SUM (but not necessarily for MAX, as we will see in the next post). This elegant decoupling (possible thanks to the mathematical properties of the addition, of course) of the master table from the MV greatly improves performance and also simplifies performance tuning.

**refresh for delete-only TMPDLT**

The refresh is made in two steps, the first being this update statement:  
[sql light="true"]  
/\* MV\_REFRESH (UPD) \*/  
update /\*+ bypass\_ujvc \*/ (  
 select test\_mv.mv\_cnt\_dat,  
 deltas .cnt\_dat,  
 test\_mv.mv\_sum\_dat,  
 deltas .sum\_dat,  
 test\_mv.mv\_cnt\_star,  
 deltas .cnt\_star  
 from test\_mv,  
 ( with tmpdlt$\_test\_master as (  
 -- check introduction post for statement  
 )  
 select gby,  
 sum( -1 ) as cnt\_star  
 sum( -1 \* decode(dat, null, 0, 1) ) as cnt\_dat,  
 nvl( sum(-1 \* dat), 0) as sum\_dat  
 from (select gby, whe, dat  
 from tmpdlt$\_test\_master mas$  
 ) as of snapshot(:b\_scn)  
 where whe = 0  
 group by gby  
 ) deltas  
 where sys\_op\_map\_nonnull(test\_mv.mv\_gby) = sys\_op\_map\_nonnull(deltas.gby)  
)  
set mv\_cnt\_star = mv\_cnt\_star + cnt\_star,  
 mv\_cnt\_dat = mv\_cnt\_dat + cnt\_dat,  
 mv\_sum\_dat = decode(mv\_cnt\_dat + cnt\_dat, 0, null, nvl(mv\_sum\_dat,0) + sum\_dat)  
[/sql]  
this calculates the same deltas as the insert-only case, just with signs reversed since, of course, we are propagating deletes instead of inserts; it then applies them using an updatable join in-line view instead of a merge.

Then, this delete statement is issued:  
[sql light="true"]  
/\* MV\_REFRESH (DEL) \*/  
delete from test\_mv where mv\_cnt\_star = 0;  
[/sql]  
this is because, when mv\_cnt\_star (that materializes count(\*)) is zero after the deltas application, it means that all the rows belonging to that value of mv\_gby have been deleted in the master table, and hence that value must be removed from the MV as well.

Note that an index on mv\_cnt\_star is NOT automatically created (as of 11.2.0.3) - it might be a very good idea to create it, to avoid a full scan of the MV at every refresh, which is O(mv size) and not O(modifications) as the other steps (thus rendering the whole refresh process O(mv size)).

**refresh for mixed-DML TMPDLT**

The refresh is accomplished using a single merge statement, which is an augmented version of the insert-only statement plus a delete clause that implements the last part of the delete-only refresh:

[sql light="true"]  
/\* MV\_REFRESH (MRG) \*/  
merge into test\_mv  
using (  
 select gby,  
 sum( decode(dml$$, 'I', 1, -1) ) as cnt\_star,  
 sum( decode(dml$$, 'I', 1, -1) \* decode(dat, null, 0, 1)) as cnt\_dat,  
 nvl( sum(decode(dml$$, 'I', 1, -1) \* dat), 0) as sum\_dat  
 from (select chartorowid(m\_row$$) rid$, gby, whe, dat,  
 decode(old\_new$$, 'N', 'I', 'D') as dml$$,  
 dmltype$$  
 from mlog$\_test\_master  
 where snaptime$$ \> :b\_st0  
 ) as of snapshot(:b\_scn)  
 where whe = 0  
 group by gby  
 ) deltas  
on ( sys\_op\_map\_nonnull(test\_mv.mv\_gby) = sys\_op\_map\_nonnull(deltas.gby) )  
when matched then  
 update set  
 test\_mv.mv\_cnt\_star = test\_mv.mv\_cnt\_star + deltas.cnt\_star,  
 test\_mv.mv\_cnt\_dat = test\_mv.mv\_cnt\_dat + deltas.cnt\_dat,  
 test\_mv.mv\_sum\_dat = decode( test\_mv.mv\_cnt\_dat + deltas.cnt\_dat,  
 0, null,  
 nvl(test\_mv.mv\_sum\_dat,0) + deltas.sum\_dat  
 ),  
 delete where ( test\_mv.mv\_cnt\_star = 0 )  
when not matched then  
 insert ( test\_mv.mv\_gby, test\_mv.mv\_cnt\_dat, test\_mv.mv\_sum\_dat, test\_mv.mv\_cnt\_star )  
 values ( deltas.gby, deltas.cnt\_dat, decode (deltas.cnt\_dat, 0, null, deltas.sum\_dat), deltas.cnt\_star)  
 where (deltas.cnt\_star \> 0)  
[/sql]  
Here the deltas are calculated by reversing the sign of "old" values (dml$$ not equal to 'I', which is the same as old\_new$$ not equal to 'N'; note in passing that it does not distinguish between old\_new$$ equal to 'O' or 'U', as stated in the introduction post), of course adjusting cnt\_star and cnt\_dat accordingly.

The removal of rows that get their mv\_cnt\_star set to zero is performed as a side case of the update, which is very nice since it does not call for an index on that column.

Surprisingly, this statement does not use TMPDLT, but reads straight from the log; I don't know the reason behind this, and whether this is always the case or if TMPDLT is sometimes used, depending, perhaps, on some heuristic decision. Surely, while using TMPDLT is mandatory in the other two cases (since the statements work only if their input is insert/delete only, and that is checked over TMPDLT only), it is just a possible optimization choice here.

**optimizations**

Knowing the "internal" workings presented here makes it vastly easier (I hope) to optimize the refresh process and avoid pitfalls; it is of course unfeasible to cover all possible real-life scenarios, but I can offer some general high-level considerations.

Obviously, fast refreshing is better than complete refreshing only when the number of modifications stored in the MV log is "small" compared to the MV size. In this scenario the usual optimal values propagation plan reads from the log, computes TMPDLT (when used), and joins the MV using NESTED LOOPS using the (automatically created) index on sys\_op\_map\_nonnull(mv\_gby) - or possibly using HASH JOIN, or SORT MERGE JOIN, again using the same index.

Hence the only optimization worth making is to create the index on mv\_cnt\_star, unless you can be absolutely sure that you will never be in the delete-only scenario, or unless you don't care about the resulting full MV scan.

Since the master table is never read during the refresh, it can be left alone. This is great.

The best access method for the log is usually a full table scan, since all rows are normally read, and hence usually nothing has to be done on the log. I can imagine that in rare cases one might consider optimizing the log by e.g. creating an index - for example a covering index on all the referenced columns; or one to speed up the analytic functions computations of TMPDLT avoiding the sort; or one prefixed by snaptime$$ if other MVs read from the log and refreshes at different times, etc.

Maybe, sometimes, it might prove beneficial to disable TMPDLT, as discussed in the introduction post.

