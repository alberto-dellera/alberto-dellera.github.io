---
layout: post
title: 'CBO: the formula for the "density" column statistic (densities part II)'
date: 2009-10-10 15:56:03.000000000 +02:00
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
permalink: "/blog/2009/10/10/cbo-the-formula-for-the-density-column-statistic-densities-part-ii/"
migration_from_wordpress:
  approved_on: working
---
In this post we are going to explore and explain the rationale for the formula used by dbms_stats to compute the "density" column statistic, used by the CBO in versions less than 10.2.0.4 to estimate the cardinality of a class of SQL statements. In the next post, we will speak about its replacement, named "NewDensity" in 10053 trace files.

We will consider only the non-trivial case of Height-Balanced histograms, since for Frequency Histograms density is a constant (0.5 / num_rows) and for columns without histogram, it is simply 1/num_distinct.

Let's illustrate the test case on which we will base our discussion, contained in [this zip] (/assets/files/2009/10/density_post.zip) file. 

First, a table T is created with the following exponential value distribution:
```plsql
SQL> select value, count(*)
  2    from t
  3   group by value
  4   order by value;
```
```
     VALUE   COUNT(*)
---------- ----------
         1          1
         2          2
         4          4
         8          8
        16         16
        64         64
```

The test case then computes a SIZE 5 Height-Balanced histogram. The resulting histogram (from dba_histograms) is as follows (note that I have added the column POPULARITY that marks popular values with "1"; EP is shorthand for column ENDPOINT_NUMBER, VALUE for column ENDPOINT_VALUE):
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

The test case then issues this SQL statement that contains only an equality filter predicate on table T:  
```plsql 
select ...  
 from t  
 where value = 2.4;  
```

The literal value 2.4 is not contained in the table (and hence in the histogram), in order to make the CBO factor in "density" in its estimate of the expected cardinality - in fact, as it might be known, density is used when the literal is not popular (that is, not equal to 64 in our case), and it doesn't matter whether the literal is not contained in the histogram, or contained as an unpopular value (1 and 16 in our case), or even contained in the table or not. All it takes is its being not popular.  
Side note: I'm assuming the literal is inside the closed min-max interval (1-64 in this case); when outside, it depends on the version.

When the literal is not popular, the formula used for the expected cardinality calculation is equal to  
```
E[card] = density * num_rows;  
```  
That is easy to verify from the test case logs; in 9i we can see that density = 0.115789474 and num\_rows=95, hence 0.115789474 \* 95 = 11.000000000 which is exactly equal to the CBO estimate for our statement.

The formula used by dbms\_stats to compute "density" was published in Jonathan Lewis' book [Cost Based Oracle](http://www.jlcomp.demon.co.uk/cbo_book/ind_book.html) (page 172) and Wolfgang Breitling's presentation [Histograms - Myths and Facts](http://www.centrexcc.com/). The key fact is that the formula takes as input the rows of what I've nicknamed the not-popular subtable (NPS), that is, the original table without the rows whose values are popular values (in this case, 64 is the only popular value). Letting num\_rows\_nps the number of rows of the NPS (for our example, num\_rows\_nps=1+2+4+8+16=31), we have:  
``` 
 density = (1 / num_rows) *  
           sum (count (value) ^ 2) / num_rows_nps  
           for "value" belonging to the NPS  
```  
The script performs this calculation automatically; it is anyway instructive to perform the calculation manually at least one time:  
density = (1/95) \* (1\*1+2\*2+4\*4+8\*8+16\*16) / 31 = .115789474  
that matches perfectly the density we observed in the script log before.

What is the statistical rationale for this seemingly strange computation?

If we plug it inside the formula for E\[card\], we can see that num\_rows is cancelled:  
```  
E[card] = sum (count (value) ^ 2) / num_rows_nps  
summed over all "values" belonging to the NPS  
```

Now we must reference the statistical concepts introduced in [this post](/blog/2009/10/03/cbo-about-the-statistical-definition-of-cardinality-densities-part-i/), and consider the family of all statements of our kind that can reference the NPS:  
```plsql  
select ...  
  from t  
 where x = :x;  
  :x being a value belonging to the NPS  
```
its E\[card\] is  
```  
E[card] = sum ( w(:x) * E[count(:x)] )  
          for all values of :x (belonging to the NPS)  
```  
dbms\_stats takes count(:x) as the best estimate for E\[count(:x)\] (for example, E\[count(4)\] = count(4) = 4 in our case). All we have to do in order to obtain the observed formula, is to assume w(:x) = count(:x) / num\_rows\_nps:  
```  
E[card] = sum ( (count(:x) / num_rows_nps) * count(:x) )  
        = sum ( count(:x) ^ 2 ) / num_rows_nps  
        for all values of :x (belonging to the NPS)  
```

The meaning of the above particular shape of w(:x) is that the probability that the client submits a certain value for :x is proportional to the number of rows (in the NPS) that has that value; more precisely, that if X% of rows has a certain common value, X% of user-submitted statements that "hit" the NPS will ask for that value. Under this assumption, dbms\_stats precomputes "density" to give back the above E[card] when the literal is known to be not popular, hence hitting the NPS - remember that the CBO operates under the "[non-empty result set assumption](/blog/2009/09/03/cbo-the-non-empty-result-set-assumption/)", hence if the literal does not hit a popular value, it must hit a value of the NPS.

The above assumption for w(:x) is quite a strange assumption - and in fact, we will see in the next post that in 11g (and 10.2.0.4), this assumption has been dropped and replaced with a more standard one. The "density" column statistics is in fact _ignored_ in 10.2.0.4+ and a value computed at run-time, named "newDensity" in 10053 trace files, is used instead.

Other posts belonging to this series:  
[densities part I](/blog/2009/10/03/cbo-about-the-statistical-definition-of-cardinality-densities-part-i/)  
[densities part III](/blog/2009/10/16/cbo-newdensity-replaces-density-in-11g-10204-densities-part-iii/)  
[densities part IV](/blog/2009/10/23/cbo-newdensity-for-frequency-histograms11g-10204-densities-part-iv/)
