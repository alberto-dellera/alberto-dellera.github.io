---
layout: post
title: Bind Variables Checker for Oracle - now install-free
date: 2009-07-23 11:23:12.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- tools
tags: []
meta: {}
author: Alberto Dell'Era
permalink: "/blog/2009/07/23/bind-variables-checker-for-oracle-now-install-free/"
migration_from_wordpress:
  approved_on: working
---
I've finally managed to implement an install-free version of my utility to check for bind variables usage. The new script is named bvc_check.sql and when run, it examines the SQL statements stored in the library cache (through gv$sql) and dumps the ones that would be the same if the literals were replaced by bind variables. 

An example of the output:
```
------------------
statements count :  0000000003
bound    : select*from t where x=:n
example 1: select * from t where x = 2
example 2: select * from t where x = 3
------------------
``` 
So we have 3 statements that are the same once literals are replaced with bind variables. Two examples are provided; the action of replacing the literals 2 and 3 with the bind variable :n makes the statements the same.

The script are available on [this page](https://github.com/alberto-dellera/bvc), that also explains the script workings in more detail.
