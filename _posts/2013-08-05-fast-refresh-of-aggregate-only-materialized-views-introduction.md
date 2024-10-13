---
layout: post
title: Fast refresh of aggregate-only materialized views - introduction
date: 2013-08-05 14:48:43.000000000 +02:00
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
permalink: "/blog/2013/08/05/fast-refresh-of-aggregate-only-materialized-views-introduction/"
migration_from_wordpress:
  approved_on: 20241012 BUT CHECK 2009 LINKS 
---
This post introduces a series about the algorithm used by Oracle (in 11.2.0.3) to fast refresh a materialized view (MV) containing only an aggregate:

```plsql
create materialized view test_mv
build immediate
refresh fast on demand
with rowid
as
select gby        as mv_gby,
       count(*)   as mv_cnt_star,
       AGG  (dat) as mv_AGG_dat,
       count(dat) as mv_cnt_dat
  from test_master
 where whe = 0
 group by gby
;
```

Where AGG is either SUM or MAX, the most important aggregates.

In the next posts, I will illustrate the algorithms used to propagate conventional (not direct-load) inserts, updates and deletes on the master table; I will illustrate also the specialized versions of the algorithms used when only one type of DML has been performed (if they exist).

In this post, we sets the stage, make some general observations, and illustrate the very first steps of the algorithm that are common to all scenarios. Everything is supported by the usual
[test case](/assets/files/2013/08/gby_mv_intro.zip).


## Materialized view logs configuration


I have configured the materialized view log on the master table to "log everything", to give the most complete information possible to the MV refresh engine:

```plsql
create materialized view log on test_master
with rowid ( whe, gby, dat ), sequence
including new values;
```

With this configuration, each modification to the master table logs the rowid of the affected rows (in column m_row\$\$), and it is labeled with an increasing value (in sequence\$\$) that enables the MV refresh engine to reconstruct the order in which the modifications happened. In detail, let’s see what’s inside the logs after we modify a single row (from mvlog_examples.sql):

# After an INSERT:
```
SEQUENCE$$ M_ROW$$              DMLTYPE$$ OLD_NEW$$    WHE    GBY    DA
---------- -------------------- --------- --------- ------ ------ ------
     10084 AAAWK0AAEAAAxTHAD6   I         N             10     10     10
```

This logs the *new values* (old_new\$\$=’N’) of an Insert (dmltype\$\$=’I’).

# After a DELETE:
```
SEQUENCE$$ M_ROW$$              DMLTYPE$$ OLD_NEW$$    WHE    GBY    DA
---------- -------------------- --------- --------- ------ ------ ------
     10085 AAAWK0AAEAAAxTFAAA   D         O              0      0      1
```

This logs the *old values* (old_new\$\$=’O’) of a Delete (dmltype\$\$=’D’).

# After an UPDATE:
```
SEQUENCE$$ M_ROW$$              DMLTYPE$$ OLD_NEW$$    WHE    GBY    DA
---------- -------------------- --------- --------- ------ ------ ------
     10086 AAAWK0AAEAAAxTHAD6   U         U             10     10     10
     10087 AAAWK0AAEAAAxTHAD6   U         N             10     10     99
```

This logs both the *old values* (old_new\$\$=’U’)  and the the *new values* (old_new\$\$=’N’)  of an Update (dmltype\$\$=’U’). So we see that the update changed DAT from 10 to 99, without changing the other columns.

Note that the update log format is the same as a delete (at sequence 10086) immediately followed by an insert (at sequence 10087) at the same location on disk (AAAWK0AAEAAAxTHAD6), the only differences being dmltype\$\$=’U’ and old_new\$\$ set to ’U’ instead of ‘O’ for the old values.

But if you ignore these differences, you can consider the log a sequence of deletes/inserts, or if you prefer, a stream of old/new values. And this is *exactly what the refresh engine does* - it does not care whether an old value is present because it logs a delete or the "erase side" of an update, and ditto for new values. It "sees" the log as a stream of old/new values, as we will demonstrate. 

## Log snapshots

When the MV fast refresh is started, the first step is to "mark" the logged modifications to be propagated to the MV by setting snaptime$$ equal to the current time - check the description contained [in this post](/blog/2009/08/04/fast-refresh-of-join-only-materialized-views-algorithm-summary) for details (note also [another possible variant with "commit-scn mv logs"](/blog/2009/11/03/11gr2-materialized-view-logs-changes). MV log purging (at the end of the refresh) is the same as well.

# The "TMPDLT" CTE (deleting the redundant log values)

The stream of old/new values marked in the log might contain **pairs** of  redundant values, each pair being composed of a new value (insert) immediately followed by an old value (delete) on the same row; every such pair can be ignored without affecting the refresh result. Filtering out these pairs is the job of this SQL fragment (nicknamed "TMPDLT"), heavily edited for readability:

```plsql
with tmpdlt$_test_master as (
  select /*+ result_cache(lifetime=session) */
         rid$, gby, dat, whe,
         decode(old_new$$, 'N', 'I', 'D') dml$$,
         old_new$$,  snaptime$$,
         dmltype$$
   from (select log.*,
                min( sequence$$ ) over (partition by rid$) min_sequence$$,
                max( sequence$$ ) over (partition by rid$) max_sequence$$
           from (select chartorowid(m_row$$) rid$, gby, dat, whe,
                        dmltype$$, sequence$$, old_new$$, snaptime$$
                   from mlog$_test_master
                  where snaptime$$ &gt; :b_st0
                ) as of snapshot(:b_scn) log
        )
  where ( (old_new$$ in ('O', 'U') ) and (sequence$$ = min_sequence$$) )
     or ( (old_new$$ = 'N'         ) and (sequence$$ = max_sequence$$) )
)
```


The "log" in-line view is the usual one selecting the marked log rows; the outer query blocks, for each rowid, keeps only the first logged value *but only if it is old*, and the last logged one, *but only if it is new*.

So for example (check tmpdlt_pair_removal_examples.sql), TMPDLT filters out the rows marked with (*) from this triple update of the same row:
```
SEQUENCE$$ OLD_NEW$$    GBY    DAT    WHE
---------- --------- ------ ------ ------
     10142 U              0      1      0
     10143 N              0   1000      0  *
     10144 U              0   1000      0  *
     10145 N              0   2000      0  *
     10146 U              0   2000      0  *
     10147 N              0   3000      0
```

and it removes completely this pair (obtained by inserting a row and then deleting it):

```
SEQUENCE$$ OLD_NEW$$    GBY    DAT    WHE
---------- --------- ------ ------ ------
     10162 N             -1     -1     -1  *  
     10163 O             -1     -1     -1  *  
```

As we will see, the result of TMPDLT is (almost always) the actual input to the refreshing algorithm, instead of the "raw" log rows. Note that this prefiltering is relatively expensive, and while it might be somehow beneficial to remove some redundant values, it is useful especially when the log contains a mix of new and old values and TMPDLT is able to turn it into a stream of new-only(insert-only) or old-only(delete-only) one. When it happens, the more specialized versions of the algorithm can be used, thus saving resources - even if the savings could not repay the cost of TMPDLT, in general.

Even better, this prefiltering shows its greatest advantage when you have to refresh a so-called "insert-only MV", that is, a MV that refuses to fast-refresh if updates or deletes where performed, but it fast-refreshes happily when only inserts were performed: you might be able to _fast refresh and avoid a complete refresh_ if TMPDLT is able to filter out all the old values. This happens for example if you insert some rows first, and then modify (or delete) only the newly inserted rows before refreshing - as demonstrated by tmpdlt\_enables\_fast\_refresh\_of\_insert\_only\_mv.sql using the classic insert-only MV, a MV containing MAX and a where clause.

**TMPDLT caching**

The first operation performed by the refresh engine is to classify the log content as new-only(insert-only), old-only(delete-only) or mixed, both to decide which refresh algorithm to use (insert-only, delete-only, general) and to raise, possibly, "ORA-32314 REFRESH FAST unsupported after deletes/updates" for insert-only MVs.

To classify the log, it issues a SQL statement on TMPDLT, that lists for every possible DML (Insert,Update,Delete) the max value of snaptime$$ contained in the log. In passing, this might enable some optimizations such as multi-step refreshes, but I have not investigated this.

Immediately after this, the chosen refreshing algorithm version might reference TMPDLT again - this time (possibly) saving resources since TMPDLT is result-cached, thanks to the hint "result\_cache(lifetime=session)".

The caching is a potentially relevant optimization since analytic functions can use a lot or resources for big (long and/or wide) MV logs. It means also that one must check also the result cache size (and utilization) when tuning for performance - and check that the analytic functions in the first place, of course, have enough resources to operate efficiently.

Side note: the undocumented modifier "lifetime=session" simply means that the result is flushed (at least) when the session ends (check result\_cache\_session\_lifetime.sql), which is a nice optimization since TMPDLT is flashed back in time and hence is NOT flushed when the log is modified. It is anayway explicitly flushed as soon as the refresh ends, hence this is only a safe net just in case the refresh fails for some reason (e.g. disk full).

**TMPDLT disabling**

What if you don't benefit from TMPDLT since your log does not contain (enough) redundant values, and you don't want to pay the cost of its processing and/or caching ?

You can disable it by removing the sequence from the MV log, that actually, as far as I know, seems to be used only by this prefilter. If this is done, all the refreshing statements read directly from the log; script tmpdlt\_disabling\_all.sql proves this (you will better appreciate how it works and its output after the next two posts that illustrate the actual refreshing algorithms of SUM and MAX, but you can already see that TMPDLT disappears from the refreshing statements).

The same scripts investigates also disabling it by setting the undocumented parameter "\_mav\_refresh\_opt"=32, but as always, ask Oracle Support first (also because there's no official note explaining how it works on MOS, and I haven't used it in production yet - since I actually discovered it about one week ago while preparing this post).

In the next post, we will examine the SUM scenario.

