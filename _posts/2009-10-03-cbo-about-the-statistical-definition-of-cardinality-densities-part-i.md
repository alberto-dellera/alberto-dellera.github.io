---
layout: post
title: 'CBO: about the statistical definition of "cardinality" (densities part I)'
date: 2009-10-03 12:32:24.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- CBO
tags: []
meta: {}
author: Alberto Dell'Era
permalink: "/blog/2009/10/03/cbo-about-the-statistical-definition-of-cardinality-densities-part-i/"
migration_from_wordpress:
  approved_on: working
---
Let's explore the concept of cardinality from the point of view of the statistician; this is both to get a clearer vision of the matter (i.e. for fun) and to path the way for understanding the rationale for the "density" statistics as calculated by dbms\_stats (the topic of an upcoming post).

Let's consider a statement with input parameters (bind variables), and consider the most fundamental of them all, the one with a filter predicate:  
```plsql 
select ...  
 from t  
 where x = :x;  
``` 
the cardinality "card" of the set of rows retrieved depends on the table possible values and the actual inputs provided by the client as bind variable values. What about the expected value E\[card\] ?  
Let:  
1) w(:x) ("w" stands for "workload") the probability mass function of the random variable :x (that completely characterizes the workload);  
2) E\[count(:x)\] the expected value of the cardinality of the rows retrieved for each value of :x.

We have, assuming that the two are independent:  
``` 
E[card] = sum ( w(:x) * E[count(:x)] )  
         for all values of :x  
```

To solve the formula we have to know (or assume) the client-dictated w(:x). The same goes for the table [potential population](http://en.wikipedia.org/wiki/Statistical_population) (that -together with the statement of course- shapes E\[count(:x)\]); we must either have some statistical measurements about the table (for example, a frequency histogram on column X that we consider representative of the table population) or assume them (for example, assume a certain distribution for the column X values).

It is interesting to explore the most used scenario: a uniform (or assumed uniform) distribution for the column X values, of which we know the number of distinct values num\_distinct(X) and the total number of values num\_rows (let them be deterministically known for simplicity, and exclude null values). That means that E\[count(:x)\]) is equal to num\_rows / num\_distinct(X) _over a finite set that contains num\_distinct(X) values_ and is equal to zero over the remaining ones.

It is relatively easy to see that E\[card\] depends on how w(:x) and E\[count(:x)\]) overlap. At one end of the spectrum, if the client always submits values for :x that are not contained in the table, E\[card\] is zero - since the client choice matematically translates into E\[count(:x)]\) being zero over all values of :x for which w(:x) is non zero. At the other end of the spectrum, that is, under the [non empty result set assumption](/blog/2009/09/03/cbo-the-non-empty-result-set-assumption/), we have 
```
E[card] = sum ( w(:x) ) * num_rows / num_distinct(X) = num_rows / num_distinct(X)
```
that is the usual formula used by the CBO in many (most) situations.

The "density" column statistic formula can be derived in a similar way, but using a different assumption about w(:x) - as we will see in a dedicated post.

Other posts belonging to this series:  
[densities part II](/blog/2009/10/10/cbo-the-formula-for-the-density-column-statistic-densities-part-ii/)  
[densities part III](/blog/2009/10/16/cbo-newdensity-replaces-density-in-11g-10204-densities-part-iii/)  
[densities part IV](/blog/2009/10/23/cbo-newdensity-for-frequency-histograms11g-10204-densities-part-iv/)
