---
layout: post
title: 'CBO: the "non-empty result set" assumption'
date: 2009-09-03 15:14:58.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- CBO
- performance tuning
tags: []
meta: {}
author: Alberto Dell'Era
permalink: "/blog/2009/09/03/cbo-the-non-empty-result-set-assumption/"
migration_from_wordpress:
  approved_on: 20241019
---
The CBO assumes that SELECT statements are always going to retrieve at least one row - even if this is not necessarily the case, of course. Understanding _why_ this is done is both useful and fascinating.

We must start from the very beginning and remember that one of the most important tasks of the CBO is estimating the statement cardinality, that is, to make a guess about the number of rows that will be fetched. In statistics, that means that the CBO must calculate (estimate) the *expected value* of the cardinality *random variable*.

In order to calculate the expected value, in our case, we can consider the table [potential population]( http://en.wikipedia.org/wiki/Statistical_population) (i.e. the set of all possible row values), execute (ideally!) the statement over each table in the population, and compute (again ideally) the average of the cardinality of each result set.

The population must be coherent with the set of observations stored in the data dictionary when the table and column statistics were collected; in other words, the population must satisfy a set of statistical constraints. For example the number of distinct values in each column must be equal (or statistically equal) to the num\_distinct statistic; the range of values must be inside (or statistically inside) the min-max interval dictated by low\_value-high\_value, etc.

Now consider a simple statement with a filter predicate:  
```plsql
select ...  
  from t  
 where x = 1;  
```
Assuming that column X contains numbers, there are an _infinite number_ of values of X inside the min-max interval (assuming that min is not equal to max) that can satisfy the constraints. In the table population, how many tables have X=1, and how many rows will be retrieved by the statement?

If a frequency histogram has been collected on column X, the population is constrained to (statistically) satisfy it, and hence we have the answer: the expected cardinality is zero if value X is not contained in the histogram and strictly greater than zero (computed with the usual formula) otherwise.

But if no histogram is collected on the column, the number of tables with X=1 will be negligible, and hence the expected value will be zero. That is not very useful.

But if we assume that the **result set is never empty**, then we have another constraint to apply. That means that the value X is contained in all tables of the population, and (if we add the additional customary assumption of uniform distribution of values) we can easily derive the usual num\_rows / num\_distinct(X) formula.

Note that the "non-empty result set" assumption is very strong; it means that the statement and the table are not independent, but actually are highly correlated, since the assumption is equivalent to say that the client executes the statement in order to retrieve rows whose existence is certain before the statement execution. In other words, the CBO infers information about the data from the statement itself, not only from the data dictionary statistics, trusting that the user has some knowledge about the data stored in the table.

The assumption is of course more than reasonable for almost all statements and clients, but not always. For instance, X=1 might mean "new record" in a table-queue that contains the history of the last few years as well, and the table migth have no observable record with X=1 thanks to the consumer(s) being very quick or the producer(s) rarely enqueuing records. Or maybe, X=1 might mean "failed record" in a process that never fails, and the statement could be issued for checking the rows existence, not for retrieving them. In this kind of scenario, the CBO predictions can be affected by the "non-empty result set" assumption.
