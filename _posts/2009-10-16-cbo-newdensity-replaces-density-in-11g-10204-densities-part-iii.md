---
layout: post
title: 'CBO: "NewDensity" replaces "density" in 11g, 10.2.0.4 (densities part III)'
date: 2009-10-16 22:33:46.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- CBO
tags: []
meta:
author: Alberto Dell'Era
permalink: "/blog/2009/10/16/cbo-newdensity-replaces-density-in-11g-10204-densities-part-iii/"
migration_from_wordpress:
  approved_on: 20241018
---
In this post we are going to explore and explain the rationale for the formula used by the CBO to compute the "NewDensity" figure that replaces, from 10.2.0.4 onwards, the "density" column statistic in the cardinality estimation formulae for columns with height-balanced (HB) histograms defined.

In a [previous post](/blog/2009/10/10/cbo-the-formula-for-the-density-column-statistic-densities-part-ii/), we already discussed the pre-10.2.0.4 scenario: we saw how and when the "density" column statistic is used in the cardinality formula for equality filter predicates, we explained its statistical rationale and defining formula, introduced the concept of the NPS (Not Popular Subtable), and built a test case. Now we are going to use the very same test case and explain the differences in the most recent versions (the previous post zip file contains logs for them also).

To summarize the test case - we have a table T with a single column VALUE, exponentially distributed, and with a SIZE 5 Height-Balanced histogram collected on. The histogram is:
```plsql
SQL> select ep, value, popularity from formatted_hist;
```
```
        EP      VALUE POPULARITY
---------- ---------- ----------
         0          1          0  
         1         16          0  
         5         64          1  
```  
Thus, we have a single popular value, 64; all the others are unpopular.

In this "densities" series of post, we focus on a SQL statement that contains only an equality filter predicate on table T:  
```plsql  
select ...  
 from t  
 where value = 2.4;  
```  
the literal value is not a popular value (but inside the 1-64 interval) and hence, in pre-10.2.0.4, the formula used for the expected cardinality calculation is equal to:  
```  
E[card] = density * num_rows;  
```

We discussed, in the previous post, how density is carefully calculated by dbms\_stats to get back the expected cardinality of the family (class) of all possible equality filter predicate statements that hit the NPS, under the usual "[non-empty result set assumption](/blog/2009/09/03/cbo-the-non-empty-result-set-assumption/)" and the further (strange and strong) assumption that the more a value is represented in the NPS, the higher the probability that the value is used as the literal of the equality predicate (an assumption that mathematically translates into the formula "w(:x) = count(:x) / num\_rows\_nps").

Switching to 10.2.0.4 - the formula for E\[card\] is still the same, but with "density" replaced by "NewDensity" (as hinted by the fact that "density" is reported as "OldDensity" in the 10053 trace files, as we are going to see in a moment):  
``` 
E[card] = NewDensity * num_rows;  
```

NewDensity is not stored anywhere in the data dictionary, but it is computed at query optimization time by the CBO (note that density is still computed by dbms\_stats using the old formula, but then it is ignored by the CBO). The NewDensity formula is based mainly on some histogram-derived figures; using the same names found in 10053 traces:

``` 
NewDensity = [(BktCnt - PopBktCnt) / BktCnt] / (NDV - PopValCnt)  
```

Where BktCnt ("Bucket Count") is the number of buckets (the "N" in the "SIZE N" clause);  
PopBktCnt ("Popular Bucket Count") the number of buckets _covered_ by the popular values;  
PopValCnt ("Popular Value Count") is the number of popular values; NDV ("Number of Distinct Values") is the traditional name used by CBO developers for the num\_distinct column statistic. With the exception of NDV, all these values are derived from the histogram.

Side note: if the numerator is equal to zero, NewDensity is set to 0.5 / num\_rows, thus giving an E\[card\] = 0.5, as far as I have seen (not exaustively) in a few test cases; it looks like a lower-bound "sanity check". The denominator cannot be zero for HB histograms.

To illustrate the formula: the histogram of our test case has 5 buckets, hence BktCnt=5; 64 is the only popular value, hence PopValCnt =1; this popular value covers 4 buckets (since its EP is 5 and the previous EP is 1), hence PopBktCnt=4; we know that the column has num\_distinct=6, hence NDV=6. This is in fact what we see in the 10053 trace file (in 11.1.0.7 and 11.2.0.1):

```  
SINGLE TABLE ACCESS PATH  
 Single Table Cardinality Estimation for T[T]  
 Column (#1):  
 NewDensity:0.040000, OldDensity:0.115789 BktCnt:5, PopBktCnt:4, PopValCnt:1, NDV:6  
 Using density: 0.040000 of col #1 as selectivity of unpopular value pred  
 Table: T Alias: T  
 Card: Original: 95.000000 Rounded: 4 Computed: 3.80 Non Adjusted: 3.80  
```  
So NewDensity = \[(5-4)/5\] / (6-1) = 1/25 = 0.04 and E\[card\]=0.04\*95=3.8, which is exactly what we see in the above trace fragment.

The formula is statistically based on replacing the previous versions' assumption (that we labeled "strange and strong") about w(:x) with the standard assumption that the client will ask for the values in the NPS with the same probability; mathematically, that means replacing the formula "w(:x) = count(:x) / num\_rows\_nps" with the standard "w(:x) = 1 / num\_distinct\_nps" (where num\_distinct\_nps is of course the number of distinct values of the NPS).

If you plug this shape of w(:x) into the formula for E\[card\], you get  
```  
E[card] = sum ( w(:x) * E[count(:x)] ) =  
        = sum (E[count(:x)] ) / num_distinct_nps  
        for all values of :x (belonging to the NPS)  
```  
that is  
``` 
E[card] = num_rows_nps / num_distinct_nps  
```  
which is, not surprising, the standard formula used for columns without histograms, but applied to the NPS, not the whole table.

One possibility for producing the above E\[card\] value at run-time could have been to change dbms\_stats to compute a value for "density" equal to "(num\_rows\_nps / num\_distinct\_nps) / num\_rows"; but forcing users to recompute statistics for all their tables in their upgraded databases is not really a viable option. 

Hence, the CBO designers chose to simply ignore "density" and calculate the above formula at run-time, mining the histogram, at the cost of reduced precision. In fact, the easy part is num\_distinct\_nps, which is obviously exactly equal to num\_distinct minus the number of popular values; but num\_rows\_nps can only calculated approximately, since the histogram is a (deterministic) sample of the column values obtained by first sorting the column values and then sampling on a uniform grid (for more information and illustration, see the first part of [this article of mine](/assets/files/2007/04/JoinCardinalityEstimationWithHistogramsExplained.pdf)). Using the histogram, the best approximation for num\_rows\_nps is num\_rows times the fraction of buckets not covered by popular values. Hence, using the 10053 terminology  
```  
num_distinct_nps = NDV - PopValCnt (exactly)

num_rows_nps = [(BktCnt - PopBktCnt) / BktCnt] * num_rows (approximately)  
``` 
which gets back (again, approximately) the E\[card\] formula above, as can be trivially checked.

It might be desirable that one day, NewDensity gets calculated exactly by dbms\_stats and stored in the data dictionary, at least for columns with new statistics, albeit the precision reduction is probably more than acceptable (that is, I have never seen a case where that has been an issue). The test case script, just for the sake of completeness, calculates the exact figure as well; it gets back an E\[card\] of 6.2 instead of 3.8.

**TBD: clone the investigations: http://www.adellera.it/static_html/investigations/ **

[test link](investigations/test)

For a summary of the above discussion and some more discussion, check back [this investigation](http://www.adellera.it/investigations/11g_newdensity/index.html) of mine. By the way, NewDensity replaces "density" also in join cardinality formulae, even if I have not run a complete investigation - but that is not surprising at all.

As a final nore - NewDensity is used also for Frequency Histograms, and in a very creative way; we will discuss this in part IV of this series.

Other posts belonging to this series:  
[densities part I](/blog/2009/10/03/cbo-about-the-statistical-definition-of-cardinality-densities-part-i/)  
[densities part II](/blog/2009/10/10/cbo-the-formula-for-the-density-column-statistic-densities-part-ii/)  
[densities part IV](/blog/2009/10/23/cbo-newdensity-for-frequency-histograms11g-10204-densities-part-iv/)

