---
layout: post
title: 'Xplan: now with "self" measures for row source operations'
date: 2012-08-27 12:21:04.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- CBO
- performance tuning
- xplan
tags: []
meta:
  _syntaxhighlighter_encoded: '1'
  _sg_subscribe-to-comments: pauline_snow_lvi41@lycos.com
author:
  login: alberto.dellera
  email: alberto.dellera@gmail.com
  display_name: Alberto Dell'Era
  first_name: Alberto
  last_name: Dell'Era
permalink: "/blog/2012/08/27/xplan-now-with-self-measures-for-row-source-operations/"
---
<p>One of the most useful information that the Oracle kernel attaches to plans in the library cache are measures of various resource consumption figures, such as elapsed time, consistent and current gets, disk reads, etcetera. These can be made available for each plan line (aka "row source operation").</p>
<p>These figures are always cumulative, that is, include both the resource consumed by the line itself and all of its progeny. It is very often extremely useful to <i>exclude</i> the progeny from the measure, to get what we could name the "self" figure (following, of course, the terminology introduced by Cary Millsap and Jeff Holt in their famous book <a href="http://www.amazon.com/Optimizing-Oracle-Performance-Cary-Millsap/dp/059600527X">Optimizing Oracle Performance</a>).</p>
<p>My sqlplus script <a href="http://www.adellera.it/scripts_etcetera/xplan">xplan</a>  now implements the automatic calculation of the "self" for the most important measures, including elapsed time and buffer gets, the most used ones when tuning a statement. </p>
<p>Let's see an example, and then elaborate on their most important application: as a resource profile when tuning.</p>
<p><b>A simple example</b><br />
Here's an illustrative example for the measure "elapsed time":<br />
[sql light="true"]<br />
---------------------------------------------------<br />
|Ela    |Ela+    |Id|Operation                    |<br />
-last----last--------------------------------------<br />
|801,097|       =| 0|SELECT STATEMENT             |<br />
|801,097| +79,017| 1| HASH JOIN                   |<br />
|673,010|+262,274| 2|  TABLE ACCESS BY INDEX ROWID|<br />
|410,736| 410,736| 3|   INDEX FULL SCAN           |<br />
| 49,070|  49,070| 4|  TABLE ACCESS FULL          |<br />
-usec----usec--------------------------------------
  
[/sql]  
The first column ("Ela"), whose values are read straight from v$sql\_plan\_statistics, is the cumulative elapsed time of each row source operation and all its progeny (children, grandchildren, etc). Hence for example, you can see that line#1 (HASH JOIN) run for 801msec, including the time spent by line #2,3,4 (its progeny). 

The second column ("Ela+") is the corresponding "self" column, derived from "Ela" by subtracting the time spent by the children - line#1 has two children (#2 and #4), and hence we get 801-673-49=79msec.

**Self measures as a resource profile for the plan**  
Having the "self" measures available makes extremely easy to identify the most expensive row source operations, which are (usually) the first worth considering when tuning (or studying) a SQL statement. Actually, the "self" set _is_ the resource profile of the plan: it blames each consumer (here, the plan lines) for its share of the resource consumed.

For example, line#3 is the most expensive with its 410 msec worth of time - if we are lucky and can reduce its time consumption almost to zero, we would cut the consumption of the whole statement by (about) 50%. It is definitely a line on which to invest some of our tuning time - by e.g. investigating whether a predicate failed to being pushed down; try building a more optimal (e.g. smaller) index; try hinting it into a "FAST FULL SCAN", etc etc.

The second best option for tuning is line#2, a "TABLE ACCESS BY INDEX ROWID"... maybe we could eliminate it completely by adding the fetched columns at the end of the index read by line#3, thus possibly saving 262msec (about 25%) of time.

And so on.

I have found these "self" figures extremely useful in _all_ my recent tuning projects - I hope that the same could turn true for some of you, and maybe that you could suggest me some way to improve xplan :)

