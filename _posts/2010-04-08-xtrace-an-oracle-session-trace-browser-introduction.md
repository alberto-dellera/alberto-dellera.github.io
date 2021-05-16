---
layout: post
title: 'Xtrace: an Oracle session trace browser (introduction)'
date: 2010-04-08 18:23:17.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- xtrace
tags: []
meta:
  _syntaxhighlighter_encoded: '1'
  _sg_subscribe-to-comments: aliandrea73@yahoo.it
author:
  login: alberto.dellera
  email: alberto.dellera@gmail.com
  display_name: Alberto Dell'Era
  first_name: Alberto
  last_name: Dell'Era
permalink: "/blog/2010/04/08/xtrace-an-oracle-session-trace-browser-introduction/"
excerpt: Xtrace is a graphical tool that can navigate Oracle trace files, manipulate
  them, and optionally get them back as a text file. It actually makes (much) more,
  but in this first post we are going to focus on its basic browsing capabilities.
---
<p><a href="http://www.adellera.it/xtrace">Xtrace</a> is a graphical tool that can navigate Oracle trace files, manipulate them, and optionally get them back as a text file. It actually makes (much) more, but in this first post we are going to focus on its basic browsing capabilities.</p>
<p>Let’s see the tool in action on the trace file produced by this simple PL/SQL block:<br />
[sql]<br />
begin<br />
  for r in (select * from t) loop<br />
    null;<br />
  end loop;<br />
end;<br />
[/sql]</p>
<p>The resulting trace file is<br />
[text wraplines="false" gutter="false"]<br />
WAIT #2: nam='SQL*Net message from client' ela= 61126 driver id=1413697536 #bytes=1 p3=0 obj#=76357 tim=5789636384898<br />
=====================<br />
PARSING IN CURSOR #26 len=66 dep=0 uid=73 oct=47 lid=73 tim=5789636385129 hv=3421439103 ad='aeb809c8'<br />
begin<br />
  for r in (select * from t) loop<br />
    null;<br />
  end loop;<br />
end;<br />
END OF STMT<br />
PARSE #26:c=0,e=153,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,tim=5789636385122<br />
BINDS #26:<br />
=====================<br />
PARSING IN CURSOR #28 len=15 dep=1 uid=73 oct=3 lid=73 tim=5789636386184 hv=1406298530 ad='a0503300'<br />
SELECT * FROM T<br />
END OF STMT<br />
PARSE #28:c=0,e=804,p=0,cr=0,cu=0,mis=1,r=0,dep=1,og=1,tim=5789636386181<br />
BINDS #28:<br />
EXEC #28:c=0,e=64,p=0,cr=0,cu=0,mis=0,r=0,dep=1,og=1,tim=5789636386284<br />
WAIT #28: nam='db file sequential read' ela= 19 file#=4 block#=59 blocks=1 obj#=76357 tim=5789636386383<br />
WAIT #28: nam='db file sequential read' ela= 11 file#=4 block#=60 blocks=1 obj#=76357 tim=5789636386457<br />
FETCH #28:c=0,e=243,p=2,cr=3,cu=0,mis=0,r=100,dep=1,og=1,tim=5789636386566<br />
FETCH #28:c=0,e=54,p=0,cr=1,cu=0,mis=0,r=100,dep=1,og=1,tim=5789636386663<br />
FETCH #28:c=0,e=3,p=0,cr=0,cu=0,mis=0,r=0,dep=1,og=1,tim=5789636386693<br />
EXEC #26:c=0,e=1543,p=2,cr=4,cu=0,mis=0,r=1,dep=0,og=1,tim=5789636386746<br />
WAIT #26: nam='SQL*Net message to client' ela= 2 driver id=1413697536 #bytes=1 p3=0 obj#=76357 tim=5789636387057<br />
WAIT #26: nam='SQL*Net message from client' ela= 42743 driver id=1413697536 #bytes=1 p3=0 obj#=76357 tim=5789636429824<br />
STAT #28 id=1 cnt=200 pid=0 pos=1 obj=76357 op='TABLE ACCESS FULL T (cr=4 pr=2 pw=0 time=363 us)'<br />
[/text]<br />
Even for this artificially simple trace file, it takes a lot of effort to read and understand it; for example, it takes a while to associate the recursive SQL lines to the execution of the PL/SQL blocks (the “EXEC #26” line).</p>
<p>With Xtrace, the trace reading experience is remarkably much better:<br />
<img src="{{ site.baseurl }}/assets/images/2010/04/xtrace_hello_10_2_0_4_lines.gif" /><br />
<script type="text/javascript" src="http://www.java.com/js/deployJava.js"></script><br />
<script type="text/javascript"><br />
        // you can enable tracing using the "Java Control Panel"; in Windows is inside the "Control Panel"<br />
        // check "http://www.java.com/js/deployJava.txt" for code of deployJava.js<br />
        // using JavaScript to get location of JNLP file relative to HTML page<br />
        var dir = location.href.substring(0, location.href.lastIndexOf('/')+1);<br />
        var url =  "http://www.adellera.it/xtrace/dist/xtrace_hello_10_2_0_4.jnlp";<br />
        // following requires Java SE 6 update 18, downloads it automatically<br />
        // minimumVersion is of the form #[.#[.#[_#]]]<br />
        //deployJava.createWebStartLaunchButtonEx(url, '1.6.0_18'); DOES NOT WORK starting from 6u19<br />
        deployJava.createWebStartLaunchButton(url);<br />
</script><br />
Note the indentation by recursive level (which is provided out-of-the -box) and the color of the lines by statement (that takes perhaps a minute in order to be set up).<br />
You can try this example live by pressing the “Launch” button above if you are interested;  in particular, try the “Options” button of the middle pane, and the “set color” popup menus of the top pane.  </p>
<p>Suggestion: you might even check the hyperlinks that links together the lines; for example, the xct pointer that links the SQL recursive calls to the parent “EXEC #26” (check the <a href="http://www.adellera.it/xtrace/manual/xtrace_manual.html ">interactive manual</a> for more information).</p>
<p>You can also get the trace back as a text file, if so desired:<br />
[text wraplines="false" gutter="false"]<br />
000 line zero<br />
001 xtrace: log file 'E:\localCVS30\TrilogyLectures\MioSitoWeb\xtrace\dist\xtrace.log'<br />
002 VIRTUAL CALL #-4: 'null call - ignore this'<br />
003 VIRTUAL CALL #-4: 'null call - ignore this'<br />
004 +WAIT #2: nam='SQL*Net message from client' xe=ela=61126 p1='driver id'=1413697536 p2='#bytes'=1 p3=''=0 xphy=0 obj#=76357 tim=5789636384898<br />
005 VIRTUAL CALL #-8: 'wait-for-client'<br />
006 VIRTUAL CALL #-5: 'client-message-received'<br />
007 ---------------------PARSING IN CURSOR #26: len=66 dep=0 uid=73 oct=47 lid=73 tim=5789636385129 hv=3421439103 ad='0eb809c8'<br />
    begin<br />
      for r in (select * from t) loop<br />
        null;<br />
      end loop;<br />
    end;<br />
    END OF STMT<br />
008 PARSE #26: mis=0 r=0 dep=0 og=1 tim=5789636385122 e=153 c=0 p=0 cr=0 cu=0<br />
009 BINDS #26:<br />
010   ---------------------
PARSING IN CURSOR #28: len=15 dep=1 uid=73 oct=3 lid=73 tim=5789636386184 hv=1406298530 ad='00503300'  
 SELECT \* FROM T  
 END OF STMT  
011 PARSE #28: mis=1 r=0 dep=1 og=1 tim=5789636386181 e=804 c=0 p=0 cr=0 cu=0  
012 BINDS #28:  
013 EXEC #28: mis=0 r=0 dep=1 og=1 tim=5789636386284 e=64 c=0 p=0 cr=0 cu=0  
014 +WAIT #28: nam='db file sequential read' xe=ela=19 p1='file#'=4 p2='block#'=59 p3='blocks'=1 xphy=1 obj#=76357 tim=5789636386383  
015 +WAIT #28: nam='db file sequential read' xe=ela=11 p1='file#'=4 p2='block#'=60 p3='blocks'=1 xphy=1 obj#=76357 tim=5789636386457  
016 FETCH #28: mis=0 r=100 dep=1 og=1 tim=5789636386566 e=243 c=0 p=2 cr=3 cu=0  
017 FETCH #28: mis=0 r=100 dep=1 og=1 tim=5789636386663 e=54 c=0 p=0 cr=1 cu=0  
018 FETCH #28: mis=0 r=0 dep=1 og=1 tim=5789636386693 e=3 c=0 p=0 cr=0 cu=0  
019 EXEC #26: mis=0 r=1 dep=0 og=1 tim=5789636386746 e=1543 c=0 p=2 cr=4 cu=0  
020 -WAIT #26: nam='SQL\*Net message to client' xe=ela=2 p1='driver id'=1413697536 p2='#bytes'=1 p3=''=0 xphy=0 obj#=76357 tim=5789636387057  
021 +WAIT #26: nam='SQL\*Net message from client' xe=ela=42743 p1='driver id'=1413697536 p2='#bytes'=1 p3=''=0 xphy=0 obj#=76357 tim=5789636429824  
022 VIRTUAL CALL #-8: 'wait-for-client'  
023 VIRTUAL CALL #-5: 'client-message-received'  
024 STAT #28: id=1 pid=0 pos=1 obj=76357 op='TABLE ACCESS FULL T' cnt=200 avg(cnt)=200.0 card=n/a cr=4 avg(cr)=4.0 cost=n/a pr=2 pw=0 time=363 size=n/a xnexecs=1 xstatn=0 xplannum=0  
025  
026 VIRTUAL CALL #-4: 'null call - ignore this'  
[/text]  
This can be obtained using the “save as text“ popup menu of the middle pane.

We are going to keep exploring Xtrace in the upcoming posts.

