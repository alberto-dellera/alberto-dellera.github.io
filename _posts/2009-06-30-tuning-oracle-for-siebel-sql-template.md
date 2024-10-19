---
layout: post
title: Tuning Oracle for Siebel - SQL template
date: 2009-06-30 00:31:04.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- performance tuning
- siebel
tags: []
meta:
author: Alberto Dell'Era
permalink: "/blog/2009/06/30/tuning-oracle-for-siebel-sql-template/"
migration_from_wordpress:
  approved_on: working
---
The time has come to write down some of the most relevant discoveries I've made so far while being part of a team that is tuning a huge Siebel installation for a leading Italian company ("huge" especially because of the user base dimension and secondarily because of the hardware deployed, a three-node RAC on pretty powerful SMP machines).

This blog entry is about the structure of the Siebel queries and the effect of the settings of some CBO-related parameters - settings made by the Siebel clients by altering the session at connect time, or required as mandatory in the Siebel installation notes. Other postings may follow in case I discover something worth writing about.

But first of all, let me thank for their support all the fellow members of the *OakTable network* (especially [Tim Gorman](http://www.evdbt.com/) that has exchanged long emails with me) and *Andy Cowling* (introduced to me by [Doug Burns](http://www.oracledoug.com/serendipity)) that kindly provided me with a lot of detailed information coming from their vast hands-on experience with Siebel on Oracle.

For the record, the environment is Siebel 8.0, using a three-node 10.2.0.4 RAC cluster on identical SMP machines with 16 CPUs each.

Most of the Siebel queries follow this template:  
```plsql 
select ...  
  from base, inner1, ..., innerN  
 where base.j1 = inner1.j1(+)  
   and base.j2 = inner2.j2(+)  
 ...  
   and base.jN = innerN.jN(+)  
   and "filter conditions on base"  
 order by base.order1 [asc|desc], base.order2 [asc|desc], ..., base.orderK [asc|desc];  
``` 
which must be discussed keeping in mind another critical and subtle information: the Siebel clients read only a subset of the returning rows (probably the ones that fit on the screen, sometimes only 2 or 3 on average) - an intention that the Siebel client wisely communicates to the CBO by altering the session and setting optimizer\_mode = first\_rows\_10.

Side note: there are variants to this template; sometimes there are two or three base tables that are joined and filtered together, and more frequently, some of the outer join relations are based on one of the innerN tables, not on the base tables (eg. innerM.jN = innerN.jN), but that is inessential for what we are going to discuss here.

The Siebel client's intention is clear: get some rows from the base table, order them by the columns order1, order2, ..., orderK, get only the first rows, and then get additional information (columns) by following the outer join relations. Note the order of the operations.

Visiting the outer-joined tables almost always comes out as the most expensive part. The reason is two-fold; first, the sheer number of outer-joined tables (ten tables is the norm, up to about 50, since the Siebel relational model is highly normalized and hence the information is highly dispersed), and second and most importantly, because of the join method the CBO is forced to follow.

In fact, Siebel blocks HASH JOINS (\_hash\_join\_enabled=false) and SORT MERGE JOINS (\_optimizer\_sortmerge\_join\_enabled=false), which leaves NESTED LOOPS as the only surviving join method. When nested looping, Oracle must obviously start from the outer table listed in the SQL statement (base) and then visit the SQL inner tables (inner1 ... innerN) using the join conditions, something that can be efficiently done only by visiting an index that has innerN.jN as the leading column of its definition. Each of these visits requires blevel+1 consistent gets for the index and some additional consistent gets for every row that is found - usually one or two, sometimes zero, at least in the scenarios I've seen.

So it is clear that every row that is fetched from the base table may easily produce tens and tens of consistent gets coming from the outer joins - and that can easily lead to a disaster if the number of rows from the base table is not very very small. In one of our queries, for example, about one million rows came out from the base table, and since the CBO chose to outer join first and then order, each execution caused a whopping 15,000,000 consistent gets - only to have the Siebel client select the first 3 rows or so. Needless to say, such a huge number of gets is completely unacceptable; the impact on the response time and CPU consumption is obvious, but scalability suffers as well (gets cause latches or mutexes acquisitions that are the most frequent cause of contention) - that means that even a slight increase on the workload may cause severe degradation of response time (especially on RAC).

The solution is to have Oracle order first, and then join - to very quickly feed the first 3 or 4 rows to the client thus sparing the effort to outer join the remaing ones, that will never (or rarely) be fetched. That usually means that you must prepare an ad-hoc index for the query that has the order1,order2, orderK column as the last columns; the first\_rows\_10 setting will strongly encourage the CBO into choosing the index. For example, say that the last "filter conditions on base" and the order clause are  
```plsql 
...  
and base.col1 = :1 and upper(base.col2) = :2  
order by base.order1 desc, base.order2 asc;  
```
a suitable index might be (col1, upper(col2), order1 desc, order2 asc).  
Oracle will hopefully reach the start of the index range (or "slice") corresponding to the filter condition, a range that has the rows sorted exactly as Siebel wants them, and then scan the index range rows in succession; for each of them, it will outer join and then return the result to Siebel, and hence stop after a few rows read from the index and a few outer joins performed.

This is the main "tuning" technique in Siebel; of course there are others (using covering indexes for the outer join tables for example) that can provide some additional advantage to our beloved Oracle instances, that we are going to investigate and that I will blog about if they turn out as being useful. But I doubt that they can be as effective as this one.
