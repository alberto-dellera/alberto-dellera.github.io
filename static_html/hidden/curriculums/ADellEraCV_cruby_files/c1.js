<!--
function pd1_1(){
if(window.pUrl == null) pUrl="";if(window.pCid == null) pCid="";refR=escape(document.referrer);
if(refR.length>=252)refR=refR.substring(0,252)+"...";
var rsUA=navigator.appName+" "+navigator.appVersion;
var rsRUA=navigator.userAgent;
var rsWS=window.screen;
var rsBV=navigator.appVersion.substring(0, 1);
var rsNN=(rsUA.indexOf('Netscape'));
var rsMC=(rsUA.indexOf('Mac'));
var rsIE=(rsUA.indexOf('MSIE'));
var rsXP=(rsUA.indexOf('NT 5.1'));
var rsCE=(rsUA.indexOf('Windows CE'));
var rsLX=(rsUA.indexOf('Linux'));
var rsOP=(rsRUA.indexOf('Opera'));
var rsIEV=(parseInt(rsUA.substr(rsIE+5)));
var rsMSIE=false;var rsIE6=false;var rsOSXP=false;var rsIE6XP=false;
var rsSW="na";var rsSH="na";var rsCD="na";var rsSR="na";var rsLG="na";var rsCT="na";var rsHP="na";var rsCK="na";var rsJE="na";
var rsJE=(navigator.javaEnabled()==true)?"y":"n";
if((rsIE>0)||((rsNN!=-1)&&(rsBV >=5))){
var rsCK=(navigator.cookieEnabled==true)?"y":"n";}
if((rsIE>=0)&&(rsIEV>=5)&&(rsMC==-1)&&(rsOP==-1)){document.body.addBehavior("#default#clientCaps");rsCT=document.body.connectionType;document.body.addBehavior("#default#homePage");rsHP=(document.body.isHomePage(location.href))?"y":"n";}
var rsD= new Date();
var rsTZ=rsD.getTimezoneOffset()/-60;
if((typeof(rsWS)!="undefined")&&(rsWS!=null)){
rsSW=rsWS.width; 
rsSH=rsWS.height;
rsCD=rsWS.colorDepth;
if((rsNN!=-1)&&(rsBV >=4)){
rsCD=rsWS.pixelDepth;}}
if((rsNN!=-1)&&(rsBV >=4)||(rsOP>=0)){var rsLG=navigator.language;}if((rsIE!=-1)&&(rsBV >=4)&&(rsOP==-1)){var rsLG=navigator.userLanguage;}
document.write('<img src="http://server-it.imrworldwide.com/cgi-bin/count?url='+pUrl+'&rnd='+(new Date()).getTime()+'&cid='+pCid+'&ref='+refR+'&sr=sr'+rsSW+'x'+rsSH+':cd'+rsCD+':lg'+rsLG+':je'+rsJE+':ck'+rsCK+':tz'+rsTZ+':ct'+rsCT+':hp'+rsHP+'" width=1 height=1>');}
pd1_1();
//-->
