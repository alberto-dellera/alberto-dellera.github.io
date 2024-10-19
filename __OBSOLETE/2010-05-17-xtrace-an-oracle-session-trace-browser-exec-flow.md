---
layout: post
title: 'Xtrace: an Oracle session trace browser - exec flow'
date: 2010-05-17 16:21:06.000000000 +02:00
type: post
parent_id: '0'
published: false
password: ''
status: publish
categories:
- xtrace
tags: []
meta:
  _syntaxhighlighter_encoded: '1'
  _sg_subscribe-to-comments: will.hoffman.it89@lycos.com
author:
  login: alberto.dellera
  email: alberto.dellera@gmail.com
  display_name: Alberto Dell'Era
  first_name: Alberto
  last_name: Dell'Era
permalink: "/blog/2010/05/17/xtrace-an-oracle-session-trace-browser-exec-flow/"
excerpt: Tracing a session is extremely useful when you need to investigate how  a
  client interacts with the database - the client could be an application of yours,
  a third-party application, or an Oracle module such as dbms_stats or dbms_mview.  To
  get the perfect picture of the client-server dialogue,  you "simply" need to consider
  all EXEC lines in the trace file, and associate to each line the executed statement
  and the bind variable values; a very tedious and error-prone task  when done manually,
  that Xtrace  can make for you (and for free).
---
Tracing a session is extremely useful when you need to investigate how a client interacts with the database - the client could be an application of yours, a third-party application, or an Oracle module such as dbms\_stats or dbms\_mview. To get the perfect picture of the client-server dialogue, you "simply" need to consider all EXEC lines in the trace file, and associate to each line the executed statement and the bind variable values; a very tedious and error-prone task when done manually, that [Xtrace](http://www.adellera.it/xtrace) can make for you (and for free).

Let's see the tool in action. Consider tracing a call to this stored procedure, that executes a recursive SQL statement :  
[sql]  
create or replace procedure test\_proc( p\_x int )  
is  
begin  
 for i in 1..p\_x loop  
 for k in (select count(\*) from t where x \> i) loop  
 null;  
 end loop;  
 end loop;  
end;  
[/sql]  
Here is the output of Xtrace:  
 ![]({{ site.baseurl }}/assets/images/2010/05/xtrace_exec_flow_11_2_0_1_lines_no_binds.gif)  
Reading it bottom-up, you can see that the client called the SP, which in turn executed recursively (note the indentation) the SQL statement twice.

You can also ask Xtrace to display the bind variable values used for each execution:  
 ![]({{ site.baseurl }}/assets/images/2010/05/xtrace_exec_flow_11_2_0_1_lines_with_binds.gif)  
So - the client passed the value "2" for :p\_x to the SP, which in turn executed the SQL statement first passing "1" for :B1, and then passing "2".

Interested ? Try it live (requires Java Web Start):  
<script type="text/javascript" src="http://www.java.com/js/deployJava.js"></script>  
<script type="text/javascript"><br />
        // you can enable tracing using the "Java Control Panel"; in Windows is inside the "Control Panel"<br />
        // check "http://www.java.com/js/deployJava.txt" for code of deployJava.js<br />
        // using JavaScript to get location of JNLP file relative to HTML page<br />
        var dir = location.href.substring(0, location.href.lastIndexOf('/')+1);<br />
        var url = "http://www.adellera.it/xtrace/dist/xtrace_exec_flow_11_2_0_1.jnlp";<br />
        // following requires Java SE 6 update 18, downloads it automatically<br />
        // minimumVersion is of the form #[.#[.#[_#]]]<br />
        //deployJava.createWebStartLaunchButtonEx(url, '1.6.0_18'); DOES NOT WORK starting from 6u19<br />
        deployJava.createWebStartLaunchButton(url);<br />
</script>  
When Xtrace opens up, press the "options" button and then the "EXEC FLOW analysis" button. Enable/disable the bind variable values using the "display BINDS under EXEC" checkbox; color the statements as you like.

We introduced Xtrace in [this post](http://www.adellera.it/blog/2010/04/08/xtrace-an-oracle-session-trace-browser-introduction/); the [Xtrace home page](http://www.adellera.it/xtrace) contains the tool (which can be used online or downloaded) - and a manual for advanced uses.

