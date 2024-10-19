---
layout: post
title: Order of keys inside index blocks
date: 2009-05-24 18:11:56.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- Indexes
tags: []
meta: {}
author: Alberto Dell'Era
permalink: "/blog/2009/05/24/order-keys-inside-index-blocks/"
migration_from_wordpress:
  approved_on: 20241019
---
In this post we are going to illustrate how index keys are ordered inside a leaf block of an Oracle B+tree index.

It is well known that index blocks share most of their structure with "regular" (heap) table blocks; in particular, they share most of the way entries are stored inside the block. In tables, a row can be placed anywhere in the bottom part of the block (which is essentially managed like an "heap", in which the exact memory address that the row is stored at is not important); its row address is recorded into one of the slots of a vector named "row directory", located near the beginning of the block.

The address of the row is not published externally: only its position inside the row directory is (as the last part of the rowid, usually named "row number"), in order to enable the kernel to move the row inside the "bottom heap" as it likes - all it has to do is to update the row directory with the new address after the move, and the change will be perfectly transparent to the outside world. This of course enables the optimal utilization of the limited space inside the block, since space inside it can be re-organized at will.

Index entries are stored in the index blocks in exactly the same fashion (and probably much of the code that manages them is the very same, since, for example, they are frequently named "rows" in block dumps and documentation, a convention we will keep in this post). The only difference is that the position inside the row directory is not published as well (there is not such thing as a "keyid" that needs to be known outside of the block); the kernel uses this additional degree of freedom to keep the row directory **ordered by key value** (in binary order). 

Let's check it by using this [test case](/assets/files/2009/05/post_0005.zip). The script creates a table and defines a one-column index on it:
```plsql 
create table t (x varchar2(10));
create index t_idx on t(x);
```

and then inserts eight rows in "random" order:
```plsql 
insert into t values('000000');
insert into t values('777777');
insert into t values('111111');
insert into t values('666666');
insert into t values('222222');
insert into t values('555555');
insert into t values('333333');
insert into t values('444444');
```

The block dump (in 11.1.0.7) of the leaf (and root) block reveals the following index keys (my annotations are enclosed in curly braces):
```
...
kdxlebksz 8036
row#0[8020] flag: ------, lock: 2, len=16
  col 0; len 6; (6):  30 30 30 30 30 30    { '000000' }
  col 1; len 6; (6):  01 00 1c 74 00 00
row#1[7988] flag: ------, lock: 2, len=16
  col 0; len 6; (6):  31 31 31 31 31 31    { '111111' }
  col 1; len 6; (6):  01 00 1c 74 00 02
row#2[7956] flag: ------, lock: 2, len=16
  col 0; len 6; (6):  32 32 32 32 32 32    { '222222' }
  col 1; len 6; (6):  01 00 1c 74 00 04
row#3[7924] flag: ------, lock: 2, len=16
  col 0; len 6; (6):  33 33 33 33 33 33    { '333333' }
  col 1; len 6; (6):  01 00 1c 74 00 06
row#4[7908] flag: ------, lock: 2, len=16
  col 0; len 6; (6):  34 34 34 34 34 34    { '444444' }
  col 1; len 6; (6):  01 00 1c 74 00 07
row#5[7940] flag: ------, lock: 2, len=16
  col 0; len 6; (6):  35 35 35 35 35 35    { '555555' }
  col 1; len 6; (6):  01 00 1c 74 00 05
row#6[7972] flag: ------, lock: 2, len=16
  col 0; len 6; (6):  36 36 36 36 36 36    { '666666' }
  col 1; len 6; (6):  01 00 1c 74 00 03
row#7[8004] flag: ------, lock: 2, len=16
  col 0; len 6; (6):  37 37 37 37 37 37    { '777777' }
  col 1; len 6; (6):  01 00 1c 74 00 01
----- end of leaf block dump -----
...  
```  
The address where the "row" (actually an index key) is stored is dumped between square brackets; for example, row#0 (which is the '000000' entry) is stored at address \[8020\], near the end of the block. You might note that the rows are placed bottom-up in insert order (the first row that was inserted was '000000' and was placed at \[8020\]; the second was '777777' and was placed at \[8004\], right above the first, etcetera); they are not ordered by binary value. 

The binary dump of the portion of the block containing the "row directory" is  
```  
C6E0280 00000000 00001F64 1F341F54 1EF41F14 [....d...T.4.....]  
C6E0290 1F041EE4 1F441F24 10E81128 106810A8 [....$.D.(.....h.]  
```

removing auxiliary tracing info, grouping the bytes in two-byte chunks and converting them in decimal, we have  
```  
 1F64=8036 end of "bottom heap" (kdxlebksz), also 8020 + 16  
 1F34=7988 address of '111111'  
 1F54=8020 address of '000000'  
 1EF4=7924 address of '333333'  
 1F14=7956 address of '222222'  
 1F04=7940 address of '555555'  
 1EE4=7908 address of '444444'  
 1F44=8004 address of '777777'  
 1F24=7972 address of '666666'  
```  
that is, the addresses in the row directory are ordered by the (binary) value of the key they point to - remember that you must swap the high and low 2-byte quantities in each 32-bit word (the usual [little-endian](http://en.wikipedia.org/wiki/Endianness) ordering; I haven't checked whether the results would be different on a machine that is not little-endian, as my one - an x86 - is).

So the number after the hash is, indeed, the position (aka index) in the row directory vector; so "row#0\[8020\]" means "row at position 0 in the row directory, the row being placed at address 8020", and the index positions are actually stored ordered.

The reason for this ordering is to improve the efficiency of typical visits to the index block. Consider a range scan, when the kernel has to find all the index keys contained in the search interval [min\_extreme, max\_extreme] (possibly min\_extreme=max\_extreme for equality predicates). As it is well known, the kernel first walks the branch blocks to identify the leaf block that contains min\_extreme (or max\_extreme, but that would be the same for our discussion); then, it has to identify all the keys that are \>= min\_extreme and \<= max\_extreme. Thanks to the ordering, it can simply perform a [binary search](http://en.wikipedia.org/wiki/Binary_search) to locate the first key \>= min\_extreme, and then walk the next entries in the row directory until it gets to the last one that is \<= max\_extreme (possibly jumping on the next leaf block). Without this ordering, the kernel would be forced to visit all the keys contained in the block.

The advantage is huge, since visiting all the keys is a O( N ) operation, while a **binary search has only O ( log(2,N) ) complexity**.

To fully appreciate this on a concrete example, consider that each key of our example needs 16+2 bytes of storage, hence a perfectly packed 8K block might contain approximately 8000 / 18 = 444 keys. Thanks to the ordering, for the very frequent equality search (classic for Primary Key searches for example), the processing consists essentially of the binary search only - hence the number of keys to be considered are down to about ceil( log(2, 444) ) = 9, thus consuming only 9/444 = 2% (!!) of the resources.

It is also worth remembering that this way, only a portion of the block is accessed, thus needing less accesses to central memory (it is unlikely in fact that the whole 8K can be found in the processor's caches), thus reducing the elapsed time considerably since stalling for central memory is a very common bottleneck in database systems - and thus improving scalability for the whole system thanks to the reduction of the traffic on the memory bus.

Of course there's a price to be paid for modifications, since each modification has to keep the row directory ordered, thus shifting the slots of the row directory, which is a relatively expensive operation. Oracle pays an higher bill at modification time to save (hugely) at read time.

As a final observation: note that the branch block visit is a generalization of the binary search (actually named binary+ search) as well, "pre-calculated" by the B+tree structure - the ordering inside a block is just the same divide-and-conquer algorithm applied in a different way.
