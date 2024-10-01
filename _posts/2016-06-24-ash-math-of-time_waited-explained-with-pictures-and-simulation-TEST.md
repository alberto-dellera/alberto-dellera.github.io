---
layout: post
title: '"ASH math" of time_waited explained with pictures and simulation TEST'
date: 2016-06-24 11:41:18.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- ash
- ash math
tags: []
meta:
author:
permalink: "/blog/2016/06/23/ash-math-of-time_waited-explained-with-pictures-and-simulation-TEST/"
---

Ullalla

```plsql
select ... from table( sim_pkg.events( ... ) );
```

```plsql
select a,b from tab where x = 0 and y = 'Y';
```

```
SESSION_STATE ELAPSED_USEC
------------- ----------------
WAITING   180,759.713
ON CPU    500,000.000
WAITING   164,796.844
ON CPU    500,000.000
WAITING 2,068,034.610
ON CPU    500,000.000
WAITING 2,720,383.092
ON CPU    500,000.000
```

All the code and spools are available <a href="{{ site.baseurl }}/assets/files/2016/06/post_0310_ash_math.zip">here</a>.

Image:

<p><a href="http://34.247.94.223/wp-content/uploads/2016/06/events.png"><img class="aligncenter size-full wp-image-825" title="ashevents" src="{{ site.baseurl }}/assets/images/2016/06/events.png" alt="histogram of event stream" width="480" height="480" /></a></p>

Image 2:

<p><a href="{{ site.baseurl }}/assets/images/2016/06/events.png"><img class="aligncenter size-full wp-image-825" title="ashevents" src="{{ site.baseurl }}/assets/images/2016/06/events.png" alt="histogram of event stream" width="480" height="480" /></a></p>

