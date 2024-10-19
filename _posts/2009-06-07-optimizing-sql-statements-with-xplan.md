---
layout: post
title: Optimizing SQL statements with xplan
date: 2009-06-07 17:07:06.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- performance tuning
- tools
tags: []
meta:
author: Alberto Dell'Era
permalink: "/blog/2009/06/07/optimizing-sql-statements-with-xplan/"
---
[Xplan](https://github.com/alberto-dellera/xplan) is a utility to simplify and automate the first part of every SQL statement tuning effort, that is, collecting the real plan of the statement, its execution statistics (number of executions, number of buffer gets performed, etc), getting the definition of all the accessed tables (and their indexes), and, last but not least, the CBO-related statistics of the accessed tables (and their indexes and columns) stored in the data dictionary by dbms_stats or ANALYZE.

The utility doesn't need to install any object inside the database since it is a read-only sqlplus script, thus needing minimal support from the customers' DBA production team. It is also so simple to run that I am normally able to ask people with minimal Oracle skills to run xplan on my behalf and then to ship me the output report - with obvious benefits for all. 

The report is light and concise, designed with the needs of the SQL tuner in mind; to illustrate, the following small fragment of the report helps to get an immediate picture of the indexes layout:
```
-----------------------------------
|ColName     |1|2|3|4|5|P|U1|U2|R1|
--------------------U-U------------
|X           |1|1|2|1| |1|  |2 |  |
|PADDING     | | |1|2|1|2|R1|1 |  |
|RR          | | | | | | |  |  |1 |
|SYS_NC00004$|2| | | | | |  |  |  |
|SYS_NC00005$| |2| | | | |  |  |  |
-----------------------------------
```

You can see at a glance that column X is indexed as the first column of indexes #1, #2 and #4 (#4 being a unique index) and as the second of index #3. Constraints are reported as well, for example the PK is (X, PADDING) and there are two unique constraints (U1, U2) and a FK (R1) constraint.

To see all the information that the report provides, you can check the showcase example in the xplan main page linked above, whose report is annotated to explain the various sections meaning. The most interesting ones are surely the plan section and the table/index/column/partition information.

Using xplan is very simple; just connect to the database with sqlplus (SELECT ANY DICTIONARY and SELECT ANY TABLE are the only necessary privileges) and run the xplan.sql script. There are various ways to tell xplan which statements to report about; probably the most useful one is to ask for statements whose text matches a SQL like expression, for example

```
SQL>@xplan "select%from%customer%" ""
```

will dump all the SELECT statements that were run on the CUSTOMER table.

It is also possible to dump a statement by by sql\_id (or hash value, module, action, parsing user, and even child number):
```
SQL>@xplan "" "sql_id=7h35uxf5uhmm1"
```
```
SQL>@xplan "" "hash=3280933266"
```
Some further customizations are possible - for example, you can order the matching statements (technically, the matching child cursors in the shared sql area) by elapsed\_time, buffer\_gets, etc; you can get a different output file for each hash\_value, instead of a single output file; you can suppress or enable certain sections of the report; and so on. For the full list and further details, please check the xplan.sql header.

Xplan is free to download and use. If you decide to try it - for any question, comment or feature request, feel free to send an email to me.
