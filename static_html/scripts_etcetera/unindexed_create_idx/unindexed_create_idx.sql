-- adapted from http://asktom.oracle.com/pls/asktom/f?p=100:11:0::::P11_QUESTION_ID:4530093713805#26568859366976
set lines 150
set trimspool on
spool unindexed_create_idx.lst

select 'create index '||owner||'.'||substr(constraint_name,1,26)||'_idx'||
       ' on '||owner||'.'||table_name||' ('||columns||')'||
       ' tablespace '||decode (owner, 'MH', 'mhindex_medium', 'BTSLIDE', 'btslide', 'users')||
       ' compute statistics;' as stmt
 from  (
select owner, table_name, constraint_name,
       cname1 || nvl2(cname2,','||cname2,null) ||
       nvl2(cname3,','||cname3,null) || nvl2(cname4,','||cname4,null) ||
       nvl2(cname5,','||cname5,null) || nvl2(cname6,','||cname6,null) ||
       nvl2(cname7,','||cname7,null) || nvl2(cname8,','||cname8,null) columns
 from  (select b.owner,
               b.table_name,
               b.constraint_name,
               max(decode( position, 1, column_name, null )) cname1,
               max(decode( position, 2, column_name, null )) cname2,
               max(decode( position, 3, column_name, null )) cname3,
               max(decode( position, 4, column_name, null )) cname4,
               max(decode( position, 5, column_name, null )) cname5,
               max(decode( position, 6, column_name, null )) cname6,
               max(decode( position, 7, column_name, null )) cname7,
               max(decode( position, 8, column_name, null )) cname8,
               count(*) col_cnt
          from (select owner,
                       substr(table_name,1,30) table_name,
                       substr(constraint_name,1,30) constraint_name,
                       substr(column_name,1,30) column_name,
                       position
                  from all_cons_columns 
               ) a,
               all_constraints b
         where a.owner = b.owner
           and a.constraint_name = b.constraint_name
           and b.constraint_type = 'R'
           and b.owner not in ('SYS', 'SYSTEM', 'PERFSTAT', 'OLAPSYS', 'WKSYS', 'MDSYS', 'SH', 'HR', 'ODM')
         group by b.owner, b.table_name, b.constraint_name
       ) cons
 where col_cnt > ALL
       ( select count(*)
          from all_ind_columns i
         where i.table_owner = cons.owner  
           and i.table_name = cons.table_name
           and i.column_name in (cname1, cname2, cname3, cname4,
                                 cname5, cname6, cname7, cname8 )
           and i.column_position <= cons.col_cnt
         group by i.index_name
       )
       )
 order by stmt
/
     