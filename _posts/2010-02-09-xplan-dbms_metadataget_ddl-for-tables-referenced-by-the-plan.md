---
layout: post
title: 'xplan: dbms_metadata.get_ddl for tables referenced by the plan'
date: 2010-02-09 17:59:40.000000000 +01:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- performance tuning
- tools
- xplan
tags: []
meta:
author: Alberto Dell'Era
permalink: "/blog/2010/02/09/xplan-dbms_metadataget_ddl-for-tables-referenced-by-the-plan/"
migration_from_wordpress:
  approved_on: 20241017
---
As a minor but useful new feature, [xplan](https://github.com/alberto-dellera/xplan) is now able to integrate into its report the DDL of tables (and indexes) referenced by the plan, calling dbms\_metadata.get\_ddl transparently.

This is mostly useful to get more details about referenced tables' constraints and partitions definition - to complement their CBO-related statistics that xplan reports about.

This feature can be activated by specifing dbms\_metadata=y or dbms\_metadata=all (check xplan.sql header of xplan.sql for more informations).

We spoke about xplan in general [here](/blog/2009/06/07/optimizing-sql-statements-with-xplan/).
