---
layout: post
title: Tom Kyte in Italia - 5 Aprile 2011
date: 2011-05-01 17:38:08.000000000 +02:00
type: post
parent_id: '0'
published: true
password: ''
status: publish
categories:
- Social Events
- Technical Meetings
tags: []
meta:
author: Alberto Dell'Era
permalink: "/blog/2011/05/01/tom-kyte-in-italia-5-aprile-2011/"
migration_from_wordpress:
  approved_on: 20241017
---
[_Note: I'm writing in Italian since this post is about a local event_]
   
Anche quest'anno Thomas "Tom" Kyte, il "Tom dietro [asktom.oracle.com](http://asktom.oracle.com)" e autore di diversi libri, è tornato in Italia per tenere una delle sue conferenze ricorrenti più popolari (ecco le [slides](http://asktom.oracle.com/pls/asktom/z?p_url=ASKTOM%2Edownload_file%3Fp_file%3D11017632703950282679&p_cat=Rome_Milan.zip&p_company=822925097021874)) - quella sulle features più significative della versione corrente di Oracle (quindi 11gR2 al momento).   

Non avevo mai visto Tom sul palco nonostante ci conoscessimo da tempo, per cui ho approfittato subito della gentile offerta dell'Ufficio Stampa Oracle di incontrarlo a valle della conferenza - un'incontro che si è trasformato in una lunga informale chiacchierata di due ore (insieme a [Christian Antognini]( http://antognini.ch/blog)) cominciata a pranzo e continuata sul taxi. Oltre al piacere di parlare con Tom (sempre molto disponibile e amichevole) ne ho tratto diverse informazioni e impressioni che espongo in ordine sparso.   

**La conferenza in generale**. L'aspetto che meglio descrive Tom Kyte, come chiunque abbia avuto modo di leggere uno dei suoi libri può intuire, è di essere una perfetta (quanto rarissima) sintesi fra un ottimo tecnico ed un efficace comunicatore: e difatti, dalla conferenza ho ricavato una conoscenza molto più netta e chiara delle features presentate, anche se già le conoscevo. Mi sono dunque pentito di non aver partecipato alle conferenze degli anni passati - sarebbe stato un ottimo investimento del mio tempo ...   

**Total Recall (Flashback Data Archive)**. A mio parere è la killer feature di 11g (era già presente in 10g ma i miglioramenti in 11g riguardo al supporto di molti tipi di DDL sulle tabelle tracciate la rendono nettamente più usabile): poter eseguire una query nel passato (anche anni) semplicemente aggiungendo la clausola "AS OF TIMESTAMP" può davvero "cambiare la vita", sia agli sviluppatori che ai DBA. Basti solo pensare alle investigazioni di problemi segnalati oggi ma verificatosi giorni addietro, al ripristino dei dati a fronte di errori, etc. Uno degli usi che voglio indagare è l'estrazione di dati dai sistemi operazionali verso i DWH; a prima vista è più efficiente (e senz'altro infinitamente più manutenibile e generalizzabile) delle classiche tecniche utilizzate. Importantissimo poi sapere come le history tables delle tabelle tracciate vengano aggiornate leggendo le informazioni dagli undo segments, dunque senza impatti sul tempo di esecuzione degli statements DML operanti sulle tabelle tracciate. Total Recall è anche una delle extra-cost options più economiche.   

**Smart Flash Cache**. L'informazione cruciale è che il disco a stato solido ("SSD" o "Flash") della Flash Cache viene usato solo per i blocchi clean, quelly dirty vengono scritti solo sui datafile: quindi solo sistemi il cui bottleneck sono le letture da disco possono trarne beneficio.   
La mia impressione è che il suo uso più interessante sia di rendere disponibile memoria veloce per la nuova feature "In-Memory Parallel Execution" (che permette di leggere blocchi nella buffer cache invece che solo nella UGA del processo); sarebbe interessante verificarlo. 

**Edition-based Redefinition**. Certamente è possibile usare questa feature per installare nuove versioni sia dei dati (tabelle con colonne nuove, etc) che del software (package, stored procedures), ma mentre il primo caso è relativamente complesso da gestire, il secondo è semplicissimo - c'è un baratro nella difficoltà d'uso nei due casi. Quindi ritengo che salvo casi particolarissimi (in sistemi con requisiti di altissima disponibilità, gestiti da personale molto preparato, e con alti budget), questa feature troverà uso diffuso "solo" nel secondo caso. Forse era voluto che la demo della conferenza fosse incentrata proprio sul secondo caso ...   

**Kernel Programmers**. Non faceva parte della conferenza, ma gentilmente Tom ha soddisfatto alcune mie curiosità riguardo il kernel di Oracle. Ho così scoperto che vengono seguite delle coding covention strettissime che sono un poco difficili da comprendere inizialmente, ma che permettono a chiunque sia membro del team di leggere e modificare agevolmente il codice (scritto in C ovviamente) del kernel. Inoltre, per entrare a far parte del Team (o meglio di uno dei Team) che lavorano sul kernel, o si è brillantissimi laureati di Università di primo piano, oppure si proviene dall'interno dell'azienda e dunque si è già conosciuti come ottimi professionisti. Ed ovviamente (ma questo è noto), prima di introdurre una nuova feature, questa viene descritta dettagliatamente in appositi documenti ed analizzata per rilevanza e fattibilità con un preciso flusso decisionale. Insomma, un ambiente di lavoro rigorosissimo ed estremamente professionale - un tipo di ambiente ormai raro oggigiorno, ma certamente al cuore del successo di Oracle.  

**Conclusione**. Queste erano le mie considerazioni principali, che ovviamente riflettono i miei interessi e le mie necessità professionali. Per il futuro, mi ripropongo di partecipare più spesso alle conferenze tenute da Oracle Italia - sono sempre state utili e di alta qualità, con un approccio "americano" : tanti fatti, poche chiacchiere, e impostati sulle necessità di chi ascolta.
