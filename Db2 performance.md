A query performs well if the plan to retrieve the resultset consists the optimal combination to exploit the available resources and the database is able to provide these resources during runtime. &#x20;

# Performance in 3 numbers

## Index read efficiency

**IREF = Rows read / Rows Selected (Fetched)**

```sql
select ROWS_READ/rows_returned from table(mon_get_database(null));
```

- 0-10 → Very good (OLTP)
- 10 - 100 → Potentially acceptable
- 100 - 1000 → Poor
- \> 1000 → Very bad

## Synchronous read percentage

```
SRP = 100 - (((Asynchronous pool data page reads + Asynchronous pool index page reads) x 100) / (Buffer pool data physical reads + Buffer pool index physical reads))
```

```sql
select 100 - (
  	(
      	(pool_async_data_reads + pool_async_index_reads + POOL_ASYNC_COL_READS) * 100 ) 
  		/ 
  		(pool_data_p_reads + pool_index_p_reads + POOL_COL_P_READS + 1)
	) as SRP 
from table(mon_get_database(null))
```

SRP Guidelines for OLTP environments

- SRP > 90% → Excellent
- 80 \< SRP \< 90 → Good, possibilities for improvement
- 50 \< SRP \< 80 → Marginal
- SRP \< 50 → Work to do.

SRP Guidelines for DWH environments

- SRP > 50% → Excellent
- 25 \< SRP \< 50 → Good
- SRP \< 25% → Work to do

<br>

## Table rows read per transaction

```sql
select 
	substr(a.tabschema, 1,20) as tabschema, 
    substr(a.tabname,1,30) as TABNAME,
    a.rows_read as RowsRead,
	(a.rows_read / (b.total_app_commits + b.TOTAL_APP_ROLLBACKS + 1)) as TBRRTX,
	(b.total_app_commits + b.TOTAL_APP_ROLLBACKS) as TXCNT
from 
	table(mon_get_table(null, null, -1)) a, 
    table(mon_get_database(null)) b
where a.member = b.member
order by a.rows_read desc
fetch first 15 rows only;
```

# Analyse database

## Current activity

```
vmstat 2 10
iostat 2 10

db2pd -edus
db2pd -latches
db2pd -locks
db2pd -wlocks
db2pd -transactions
db2pd -dynamic
```

tcpdump: <https://danielmiessler.com/study/tcpdump/>

## Index read efficiency

[Index Read Efficiency - A Key Performance Indicator for Db2](https://www.virtual-dba.com/index-read-efficiency-db2/ "Index Read Efficiency - A Key Performance Indicator for Db2")

Calculate the index read efficiency

```sql
select  case when rows_returned > 0
                then decimal(float(rows_read)/float(rows_returned),10,5)
                else -1
        end as read_eff
from table(mon_get_database(-2))

```

- 0-10 → Very good (OLTP)
- 10 - 100 → Potentially acceptable
- 100 - 1000 → Poor
- \> 1000 → Very bad

## Use package cacke

```sql
WITH PCKCACHE_STATS (NUM_EXEC) AS (SELECT
CASE
	WHEN NUM_EXEC_WITH_METRICS BETWEEN 0 AND 1 THEN 'max. 1 Execution'
	WHEN NUM_EXEC_WITH_METRICS BETWEEN 2 AND 5 THEN 'max. 5 Executions'
	WHEN NUM_EXEC_WITH_METRICS BETWEEN 201 AND 500 THEN 'max. 500 Executions'
	WHEN NUM_EXEC_WITH_METRICS > 500 THEN 'over 500 Executions'
END
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL,NULL,NULL,-2))
WHERE 
	STMT_TYPE_ID LIKE 'DML%' )
SELECT 
	NUM_EXEC, 
    COUNT(*) AS NUM_STMT, 
    COUNT(*) * 100 / (SELECT COUNT(*) FROM PCKCACHE_STATS)
FROM PCKCACHE_STATS
GROUP BY NUM_EXEC
UNION ALL
SELECT '# Statements in PCKCACHE', COUNT(*) AS NUM_STMT, NULL FROM PCKCACHE_STATS
UNION ALL
SELECT 'Package Cache Size (4K)', INT(VALUE), NULL FROM SYSIBMADM.DBCFG WHERE NAME = 'pckcachesz'
with ur;
```

Example output

```
NUM_EXEC                 NUM_STMT      Percentage             
------------------------ ------------- ------------- 
max. 1 Execution         2061          47            
max. 5 Executions        1059          24            
max. 500 Executions      88            2             
over 500 Executions      130           3             
NULL                     958           22            
# Statements in PCKCACHE 4296          NULL          
Package Cache Size (4K)  95740         NULL          
```

## Table require a reorg

A table write overflow occurs when a VARCHAR column is updated such that its length increases and, because the row is now larger (or wider), the row no longer fits on the data page where it was originally stored. DB2 relocates the row to a new data page and places a pointer in the original location to the new location.

A table read overflow occurs when DB2 attempts to read the row from its original location, then discovers the pointer and has to go read the row from its new location. Read overflows are particularly expensive because DB2 is now forced to do double the logical read I/O and probably double the physical I/O as well.

As a rule of thumb, **when TBROVP exceeds 3% for any given table, then that table should be reorganized.** Several companies use this metric in place of the reorgchk utility as an indicator for when to REORG a table. As a plus for avoiding reorgchk, the catalog statistics will not be updated so dynamic SQL access plans won't be disrupted and performance should be more predictable.

```sql
select 
	substr(tabschema, 1,20) as tabschema, 
    substr(tabname,1,30) as TABNAME, 
    OVERFLOW_ACCESSES * 100 / (rows_read + 1)
from table(mon_get_table(null, null, -1))
order by OVERFLOW_ACCESSES * 100 / (rows_read + 1) desc
fetch first 20 rows only;
```

### Reorg progress

```sql
SELECT 
	SUBSTR(TABNAME, 1, 15) AS TAB_NAME, 
    SUBSTR(TABSCHEMA, 1, 15) AS TAB_SCHEMA, 
    REORG_PHASE, 
    SUBSTR(REORG_TYPE, 1, 20) AS REORG_TYPE, 
   	REORG_STATUS, REORG_COMPLETION, 
    DBPARTITIONNUM 
FROM SYSIBMADM.SNAPTAB_REORG ORDER BY DBPARTITIONNUM; 

SELECT 
	SUBSTR(TABNAME, 1, 15) AS TAB_NAME, 
    SUBSTR(TABSCHEMA, 1, 15) AS TAB_SCHEMA, 
    REORG_PHASE, 
    REORG_MAX_PHASE,
    SUBSTR(REORG_TYPE, 1, 60) AS REORG_TYPE, 
   	REORG_STATUS, 
    REORG_COMPLETION, 
    DBPARTITIONNUM,
    decimal(float(reorg_current_counter) / (float(reorg_max_counter)) * 100, 5,2) as percentage_complete,
    REORG_PHASE_START + integer(100 * timestampdiff(4, char(SNAPSHOT_TIMESTAMP - REORG_PHASE_START)) / decimal(float(reorg_current_counter) / (float(reorg_max_counter)) * 100, 7,3)) minutes as estimed_phase_completion
FROM TABLE( SNAP_GET_TAB_REORG('', -1)) AS T
where reorg_max_counter <> 0;
```

## Monreport dbsummary

Monreport.dbsummary provides a very useful set of basic metrics that help us tackle common performance bottlenecks in DB2.

```
monreport.dbsummary(<number of seconds>)
```

[IDUG : Blogs : DB2 LUW ‘Performance First Aid’ with monreport.dbsummary](https://www.idug.org/p/bl/et/blogid=278\&blogaid=625 "IDUG : Blogs : DB2 LUW ‘Performance First Aid’ with monreport.dbsummary")

When analysing a monreport the request metrics are most closely relate to the mon get tablefunctions.&#x20;

![445d3a05-a527-4eb8-93a8-68bb8eb9e854.png](https://files.nuclino.com/files/275a653b-bfd0-4fbd-802e-2f14a5577aee/445d3a05-a527-4eb8-93a8-68bb8eb9e854.png)

### Q1 Waar wordt de meeste tijd doorgebracht? In Db2 of erbuiten?

Gebruik hier de wait time as percentage of elapsed time

```
 -- Wait time as a percentage of elapsed time --

                                           %    Wait time/Total time

                                           ---  ----------------------------------

  For requests                             48   58160/118766

  For activities                           47   55408/115982

  -- Time waiting for next client request --

  CLIENT_IDLE_WAIT_TIME               = 440572

  CLIENT_IDLE_WAIT_TIME per second    = 7342
```

|   |
| - |

Deel de CLIENT\_IDLE\_WAIT\_TIME door total time for request: 440572/118766.

+--------------------------------------------------------------------------------------------------------------------------------------------------------------+
|Controleer in het blok Application performance by connection of er geen idle verbindingen waren. Is dit wel het geval pas de bovenstaande formule dan aan naar|
|                                                                                                                                                              |
|+--------------------------------------------------------------------------------+                                                                            |
||Idle connection time = (# of idle connection) \* (monitoring period) \* 1000s/ms|                                                                            |
||                                                                                |                                                                            |
||<br>                                                                            |                                                                            |
||                                                                                |                                                                            |
||ratio = (CIWT - Idle connection time)/Total request time                        |                                                                            |
||                                                                                |                                                                            |
||<br>                                                                            |                                                                            |
|+--------------------------------------------------------------------------------+                                                                            |
|                                                                                                                                                              |
|<br>                                                                                                                                                          |
+--------------------------------------------------------------------------------------------------------------------------------------------------------------+

### Q2 Is het systeem aan het wachten of processing?

Gebruik hier weer het blok -- Wait time as a percentage of elapsed time --.

```
-- Wait time as a percentage of elapsed time --

                                           %    Wait time/Total time

                                           ---  ----------------------------------

  For requests                             48   58160/118766


```

|   |
| - |

Kijk naar de verhouding tussen wait time en total time. De wait time zou niet meer dan 25% mogen zijn van de totale tijd. Boven de 40% is het echt een probleem. Bij een hoge wait time kijken je naar disk reads, transaction log writes, lock waits, enz

### Q3 Wachten we op disk reads?

Controleer hiervoor in het blok -- Detailed breakdown of TOTAL\_WAIT\_TIME -- de regel POOL\_READ\_TIME.

Als dit percentage hoog is kijk dan naar hoe de bufferpools worden gebruikt, worden de juiste indexen gebruikt

### Q4 wachten we op transaction log?

Controleer hiervoor in het blok -- Detailed breakdown of TOTAL\_WAIT\_TIME -- de regel LOG\_DISK\_WAIT\_TIME. Als het systeem heel druk is met schrijven is 25% hier geen uitzondering.

Bereken ook de gemiddelde log write time:

+------------------------------------------------------------------------------------------------------------------------------+
|db2 "select decimal(log\_write\_time) / num\_log\_write\_io as avg\_log\_write\_ms from table(mon\_get\_transaction\_log(-2))"|
|                                                                                                                              |
|<br>                                                                                                                          |
+------------------------------------------------------------------------------------------------------------------------------+

De output is het gemiddelde sinds de database geactiveerd is. Wanneer dit een probleem is controleer dan of de logbugsz groot genoeg staat om overflows te voorkomen.

### Q5 wachten we op lockwaits?

Gebruik hiervoor de monreport module: monreport.lockwait of onderstaande db2pd commando

+---------------------------------------+
|db2pd -db \<dbname> -wlocks \[ detail ]|
|                                       |
|<br>                                   |
|                                       |
|db2pd -db \<dbname> -apinfo \<AppHandl>|
|                                       |
|<br>                                   |
+---------------------------------------+

Verdere analyse individuele locks

+---------------------------------------------------------------------------------------------------------------------------------------------+
|db2 "SELECT SUBSTR(NAME,1,20) AS NAME,SUBSTR(VALUE,1,50) AS VALUE FROM TABLE( MON\_FORMAT\_LOCK\_NAME('0002000F000000000000000452')) as LOCK"|
|                                                                                                                                             |
|<br>                                                                                                                                         |
+---------------------------------------------------------------------------------------------------------------------------------------------+

### Q6 wachten we op compiling SQL?

Controleer hiervoor de regel total\_compilation\_proc\_time in het blok -- Detailed breakdown of processing time--.

### Q7 Problemen met individuele statements?

Doe bekende onderzoeken

<br>

Client Idle wait time

![84b5594a-2718-4c03-b2c7-0f4b82842568.png](https://files.nuclino.com/files/a10aac35-3837-47a0-9131-e90f0c57d507/84b5594a-2718-4c03-b2c7-0f4b82842568.png)

<br>

Calculate the time spent within/outside Db2

```
Idel connection time = # idle connections * report time * 1000
(CIWT - Idle connection time) / Total Request time
```

Is the system waiting or processing?

![2e5e202d-d909-4250-842d-c5848b5766b6.png](https://files.nuclino.com/files/01dfb8b9-0480-4eaa-97db-ae4c833d4554/2e5e202d-d909-4250-842d-c5848b5766b6.png)

As a general rule-of-thumb, anything less than about 25% wait time is pretty good (no major blockages in the system), but when it starts to get above 40% or so, we should dig in.

Check&#x20;

- [ ] breakdown of total wait time
- [ ] breakdown of processing time

<br>

## Statements recenty added to the package cache

Statements added last \<n> minutes to the package cache

```sql
Select stmt_text 
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL,NULL,’<modified_within>n</modified_within’,-2))

```

## Sort performance including sort I/O time

```sql
select 
	sort_heap_allocated,
	sort_shrheap_allocated,
	sort_shrheap_top,
	total_sorts,
	sort_overflows,
	100*sort_overflows/total_sorts as "percentage overflows",
	active_sorts,
	total_section_sorts,
	total_section_sort_time,
	total_section_sort_proc_time,
	total_section_sort_time - total_section_sort_proc_time as "Sort IO Time"
from table(MON_GET_DATABASE(-1))
with ur;
```

## Low cardinality indexes

<https://www.ibm.com/developerworks/data/library/techarticle/dm-1309cardinal/index.html>

When the number of index keys that fits on an index page is close to the number of data rows that fit on a data page, index access is likely to introduce additional page reads beyond what a full table scan would do. To compare the table row size and the index row size, use a query like the one below to look at all indexes for a particular table:

```sql
select
        substr(t.TABNAME,1,12) as tabname
        , substr(i.INDNAME,1,20) as indnameA
        , AVGROWSIZE as RowSIZE
        , AVGLEAFKEYSIZE as IndexKeySIZE
        , 100*(DECIMAL((FLOAT(AVGLEAFKEYSIZE)/FLOAT(AVGROWSIZE)),7,5)) as PCT_OF_ROWSIZE
from syscat.indexes i, syscat.tables t
where i.tabschema=t.tabschema and i.tabname=t.tabname
        and type='T'
        and AVGROWSIZE>0
        and t.tabname='table'
        and t.tabschema='QIS'
order by PCT_OF_ROWSIZE desc
with ur;
```

## Cluster factor

```sql
select  
	substr(INDNAME,1,18) as indname, 
    decimal((100*CLUSTERFACTOR),5,2) as CLUSTERFACTOR 
from SYSCAT.INDEXES 
where tabname='table' 
	and tabschema='QIS' 
with ur;
```

## Latches

```
db2pd -latches -rep 1 50 -file latches.log > /dev/null 2>&1
 
 
Database Member 0 -- Active -- Up 3 days 17:08:40 -- Date 2016-07-18-15.12.55.033746
Latches:
Address            Holder     Waiter     Filename             LOC        LatchType            HoldCount
 
0x0780000001340478 1029       0          ../include/sqle_workload_disp.h 1391       SQLO_LT_sqeWLDispatcher__m_tunerLatch 1

```

In het geval van latch problemen verwijzen de getallen onder "Holder" en "Waiter" naar de EDU id's.

```
db2pd -db <dbname> -apinfo|egrep "EDU|AppHan"|paste - - |grep <eduid> 
db2pd -agents|awk -v "edu=<eduid>" '/^0x/ { if( $4 == edu ) print "Apphandle: "$2;}'

```

## High user CPU

```
db2pd -db <dbname> -edus interval=5 top=10 -file topEdus.txt > /dev/null &
db2pd -db <dbname> -apinfo -rep 2 5 -file apinfo.txt > /dev/null 2>/dev/null &
```

## Large number of simultanus queries

```
db2pd -db <dbname> -active -rep 2 5 -file active.txt > /dev/null
db2pd -db <dbname> -active | awk '/^0x/ { print $6","$7; }' | sort | uniq -c | sort -nr
```

## Pck cache hitratio

```sql
select 
    PKG_CACHE_INSERTS as PKG_CACHE_INSERTS, 
    PKG_CACHE_LOOKUPS as PKG_CACHE_LOOKUPS, 
    decimal(1-decimal(PKG_CACHE_INSERTS,10,3)/decimal(PKG_CACHE_LOOKUPS,10,3),10,3) as pkg_cache_hit_ratio 
from table(SYSPROC.MON_GET_DATABASE(-1)) as t 
with ur;
```

## db2pd commands

```
# logspace per transaction
db2pd -db <dbname> -transactions

# transactievolume, voer meerdere keren uit:
db2pd -db <dbname> -transactions | egrep "commit|rollback"

# Query volume, voer meerdere keren uit:
db2pd -db <dbname> -workload | egrep "WorkloadName|ActCompleted"

# Page cleaners
db2pd -db <dbname> -dirty summary -cleaners

# bufferpools
db2pd -db <dbname> -bufferpool

# Stacks
db2pd -stack all dumpdir=<dir you want the stacks to dump> 
```

## Stack per EDU

\~/sqllib/pd/analysestack -i .

```
~/sqllib/pd/analysestack -i .
~/sqllib/pd/analysestack -L (latchAnalysis.out)
```

# Trace

<br>

## DB2TRC

Expert: pavel sustr (psustr@ca.ibm.com)

```
Trace last, include timestamp
db2trc on -l <buffer> -t -appId <>

Trace first, include timestamp
db2trc on -i <buffer> -t -appId <>

-perfcount --> callstack
```

## FODC

FODC executable calls

1. db2cos\_hang
2. db2cos\_perf
3. enz

Je kunt deze bestanden zelf aanpassen. Maak daarvoor een kopie van sqllib/bin/ naar sqllib/adm. Wanneer er een bestand met dezelfde naam in de adm map staat, wordt dat bestand gebruikt.&#x20;

Om het proces te versnellen in het script db2cos\_hang maak je een kopie naar sqllib/adm/db2cos\_hang. Zet in de kopie de variable NO\_WAIT op "ON".&#x20;

FODC -HANG heeft twee varianten:

- Basic (no connect)
- Full (wel connect)

## Partitioned environment

rah ";db2fodc -hang -alldbs"

# Identify problem sql

## Key database resource consumers

```sql
WITH SUM_TAB (SUM_RR, SUM_CPU, SUM_EXEC, SUM_SORT, SUM_NUM_EXEC) AS (
        SELECT  FLOAT(SUM(ROWS_READ)),
                FLOAT(SUM(TOTAL_CPU_TIME)),
                FLOAT(SUM(STMT_EXEC_TIME)),
                FLOAT(SUM(TOTAL_SECTION_SORT_TIME)),
                FLOAT(SUM(NUM_EXECUTIONS))
            FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', NULL, NULL, -2)) AS T
        )
SELECT
        SUBSTR(STMT_TEXT,1,300) as STATEMENT,
        ROWS_READ,
        DECIMAL(100*(FLOAT(ROWS_READ)/SUM_TAB.SUM_RR),5,2) AS PCT_TOT_RR,
        TOTAL_CPU_TIME,
        DECIMAL(100*(FLOAT(TOTAL_CPU_TIME)/SUM_TAB.SUM_CPU),5,2) AS PCT_TOT_CPU,
        STMT_EXEC_TIME,
        DECIMAL(100*(FLOAT(STMT_EXEC_TIME)/SUM_TAB.SUM_EXEC),5,2) AS PCT_TOT_EXEC,
        TOTAL_SECTION_SORT_TIME,
        DECIMAL(100*(FLOAT(TOTAL_SECTION_SORT_TIME)/SUM_TAB.SUM_SORT),5,2) AS PCT_TOT_SRT,
        NUM_EXECUTIONS,
        DECIMAL(100*(FLOAT(NUM_EXECUTIONS)/SUM_TAB.SUM_NUM_EXEC),5,2) AS PCT_TOT_EXEC,
        DECIMAL(FLOAT(STMT_EXEC_TIME)/FLOAT(NUM_EXECUTIONS),10,2) AS AVG_EXEC_TIME
    FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', NULL, NULL, -2)) AS T, SUM_TAB
    WHERE DECIMAL(100*(FLOAT(ROWS_READ)/SUM_TAB.SUM_RR),5,2) > 10
        OR DECIMAL(100*(FLOAT(TOTAL_CPU_TIME)/SUM_TAB.SUM_CPU),5,2) >10
        OR DECIMAL(100*(FLOAT(STMT_EXEC_TIME)/SUM_TAB.SUM_EXEC),5,2) >10
        OR DECIMAL(100*(FLOAT(TOTAL_SECTION_SORT_TIME)/SUM_TAB.SUM_SORT),5,2) >10
        OR DECIMAL(100*(FLOAT(NUM_EXECUTIONS)/SUM_TAB.SUM_NUM_EXEC),5,2) >10
    ORDER BY ROWS_READ DESC FETCH FIRST 20 ROWS ONLY WITH UR;

```

## Average vs maximum execution time

```sql
SELECT 
    NUM_EXEC_WITH_METRICS,
    TOTAL_ACT_TIME,
    TOTAL_ACT_TIME/NUM_EXEC_WITH_METRICS AS AVG_ACT_TIME,
    MAX_COORD_STMT_EXEC_TIME AS MAX_EXEC_TIME, 
    STMT_TEXT
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL, NULL, NULL, -1))
WHERE TOTAL_ACT_TIME IS NOT NULL
AND NUM_EXEC_WITH_METRICS > 0
AND TOTAL_ACT_TIME > 0
AND MAX_COORD_STMT_EXEC_TIME / (1+(TOTAL_ACT_TIME/NUM_EXEC_WITH_METRICS)) > 5
ORDER BY AVG_ACT_TIME DESC
fetch first 10 rows only
with ur;
```

## Top 5 CPU statements

```sql
select stmt_exec_time, num_executions, (total_cpu_time / 1000 ) as cpu_time, stmt_text
from table(mon_get_pkg_cache_stmt(null, null, null, -2))
order by cpu_time desc
fetch first 5 rows only
with ur;
```

## Top 5 IO statements

```sql
select stmt_exec_time, num_executions, 
(pool_read_time + pool_write_time + direct_read_time + direct_write_time ) as io_time, stmt_text
from table(mon_get_pkg_cache_stmt(null, null, null, -2))
order by io_time desc
fetch first 5 rows only
with ur;
```

## Read efficiency

```sql
select rows_returned, rows_read,
(case when rows_returned > 0
then rows_read / rows_returned 
else
0
end) as read_efficiency,
stmt_text
from table(mon_get_pkg_cache_stmt(null, null, null, -2)) 
order by read_efficiency
fetch first 10 rows only
with ur;
```

## Relative velocity

```sql
select total_act_time, total_act_wait_time,
case when total_act_time > 0
then ((total_act_time - total_act_wait_time) * 100 / total_act_time)
else
100
end) as rel_velocity, -- percentage of query time processing
stmt_text
from table(mon_get_pkg_cache_stmt(null, null, null, -2)) 
order by rel_velocity
fetch first 10 rows only
with ur;
```

## Spilling

```sql
with ops as
( select
	(total_sorts + total_hash_joins + total_hash_grpbys) as sort_ops,
	(sort_overflows + hash_join_overflows + hash_grpby_overflows) as overflows,
	sort_shrheap_top as shr_sort_top
from table(mon_get_database(-2))
)
select 
	sort_ops,
	overflows,
	(overflows * 100) / nullif(sort_ops,0) as pctoverflow,
	shr_sort_top
from ops;
```

## Query Sort Usage and Consumers

```sql
SELECT 
	SORT_SHRHEAP_TOP,
	SORT_CONSUMER_SHRHEAP_TOP,
	ACTIVE_SORT_CONSUMERS_TOP,
	NUM_EXECUTIONS,
	(TOTAL_SORTS +
		TOTAL_HASH_JOINS +
		TOTAL_HASH_GRPBYS +
		TOTAL_COL_VECTOR_CONSUMERS) AS SORT_OPS,
	(SORT_OVERFLOWS +
		HASH_JOIN_OVERFLOWS +
		HASH_GRPBY_OVERFLOWS) AS SORT_OVERFLOWS,
	(POST_THRESHOLD_SORTS +
		POST_THRESHOLD_HASH_JOINS +
		POST_THRESHOLD_HASH_GRPBYS +
		POST_THRESHOLD_COL_VECTOR_CONSUMERS) AS THROTTLED_SORT_OPS,
	SUBSTR(STMT_TEXT,1,255) AS STMT_TEXT
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL,NULL,NULL,-2))
with ur;
```

## Monitor package cache to save relevant query information

```sql
CREATE TABLESPACE TS_PKGC PAGESIZE 32768 MANAGED BY AUTOMATIC STORAGE AUTORESIZE YES INITIALSIZE 100 M MAXSIZE 1 G BUFFERPOOL BP32; 

CREATE EVENT MONITOR PKGC FOR PACKAGE CACHE
WHERE STMT_EXEC_TIME > 100000 -- 100.000 milliseconds
 COLLECT DETAILED DATA -- collect section data as well 
WRITE TO TABLE 
	PKGCACHE (TABLE PKGC IN TS_PKGC), 
    PKGCACHE_METRICS (TABLE PKGC_MET IN TS_PKGC), 
    PKGCACHE_STMT_ARGS (TABLE PKGC_ARGS IN TS_PKGC), 
    CONTROL (TABLE PKGC_CTRL IN TS_PKGC) 
AUTOSTART;
```

```sql
SELECT 
	P.EVENT_ID, 
    VARCHAR(P.STMT_TEXT) STMT_TEXT, 
    LISTAGG(VARCHAR(A.STMT_VALUE_DATA),' | ') DATA 
FROM PKGC P 
JOIN PKGC_ARGS A 
	ON P.EVENT_ID = A.EVENT_ID 
       AND P.EVENT_TIMESTAMP = A.EVENT_TIMESTAMP 
GROUP BY 
	P.EVENT_ID, 
    VARCHAR(P.STMT_TEXT) 
ORDER BY 
	P.EVENT_ID
WITH UR;
```

### Explain statements from pck monitor

```sql
WITH EVENT AS (
  	SELECT 
  		EVENT_ID, 
  		EVENT_TIMESTAMP, 
  		STMT_TEXT 
  	FROM PKGC 
  	WHERE STMT_TYPE_ID LIKE 'DML, Select%' -- we’re only interested in DML, in particular SELECTs 
  	AND LENGTH(SECTION_ENV) > 0 -- Only on existing section data 
  	ORDER BY MAX_COORD_STMT_EXEC_TIME DESC) -- we’re only interested in long running activities 
SELECT 
	EXPL.EXFMT_CMD, 
    EVENT.STMT_TEXT 
FROM EVENT, TABLE(EXPLAIN_DATA(EVENT.EVENT_ID, EVENT.EVENT_TIMESTAMP)) EXPL 
FETCH FIRST 2 ROWS ONLY
```

## Trace

To trace your own or another agent

[sqltrace.db2](https://files.nuclino.com/files/c2cd475f-f595-41da-a1e1-7b8a7335d322/sqltrace.db2)

[sqltrace\_cleanup.db2](https://files.nuclino.com/files/fba77ce4-02d0-45ba-b018-ce2f481ed61c/sqltrace_cleanup.db2)

```sql
db2 -td@ -f sqltrace.db2
db2 "CALL SQLTRACE.TRACE_ON()"
db2 "select * from application"
db2 "select * from qis.customer"
db2 "CALL SQLTRACE.TRACE_OFF()"
 
db2 "select * from SQLTRACE.ACTIVITYMETRICS_TRACE_EVMON" > act_met.out
db2 "select * from SQLTRACE.ACTIVITY_TRACE_EVMON" > act.out
db2 -td@ -f sqltrace_cleanup.db2
```

```sql
select
    (select substr(stmt_text,1,200) as stmt_text from SQLTRACE.ACTIVITYSTMT_TRACE_EVMON as as1 where as1.EXECUTABLE_ID=as.EXECUTABLE_ID fetch first 1 row only),
    count(*) as NUM_EXECS,
    sum(ACT_EXEC_TIME) as SUM_STMT_EXEC_TIME,
    sum(SYSTEM_CPU_TIME) as SUM_SYSTEM_CPU_TIME,
    sum(USER_CPU_TIME) as SUM_USER_CPU_TIME,
    sum(POOL_DATA_L_READS) as total_POOL_DATA_L_READS,
    sum(POOL_DATA_P_READS) as total_POOL_DATA_P_READS, 
    sum(POOL_INDEX_L_READS) as total_POOL_INDEX_L_READS, 
    sum(POOL_INDEX_P_READS) as total_POOL_INDEX_P_READS
from SQLTRACE.ACTIVITYSTMT_TRACE_EVMON as as
left outer join SQLTRACE.ACTIVITY_TRACE_EVMON av
        on as.appl_id=av.appl_id
                and as.uow_id=av.uow_id
                and as.activity_id=av.activity_id
group by EXECUTABLE_ID
order by 3 desc
with ur;

```

# Explain queries

Create explain tables

```sql
db2 CALL SYSPROC.SYSINSTALLOBJECTS('EXPLAIN', 'C', 
        CAST (NULL AS VARCHAR(128)), CAST (NULL AS VARCHAR(128)))
```

Explain query

```
set current explain mode explain
<execute query>
set currentt explain mode no
db2exfmt -d <database> -1 -o <output>
```

Explain query with parameter markers

```
explain plan for <query>;
```

## Explain with actuals

### db2caem

N.B. The output directory must exists!

```
db2caem -d <db_name> -o <output_dir> -tbspname <admin_ts> -sf <query_file>
```

### With activity event monitor

Create a dedicated tablespace

```sql
CREATE TABLESPACE TS_ACT MANAGED BY AUTOMATIC STORAGE AUTORESIZE YES INITIALSIZE 32 M MAXSIZE 1 G; 
```

Enable section actuals

```
CALL WLM_SET_CONN_ENV( NULL, '<collectactdata>WITH DETAILS, SECTION</collectactdata>
<collectsectionactuals>BASE</collectsectionactuals>')
```

Capture section actuals

```
ALTER WORKLOAD SYSDEFAULTUSERWORKLOAD COLLECT ACTIVITY DATA on coordinator WITH
DETAILS,SECTION
```

Create the event monitor

```sql
CREATE EVENT MONITOR ACT FOR ACTIVITIES 
	WRITE TO TABLE ACTIVITY (
    	TABLE ACT IN TS_ACT), 
        ACTIVITYVALS (TABLE ACT_VALS IN TS_ACT), 
        ACTIVITYSTMT (TABLE ACT_STMT IN TS_ACT), 
        ACTIVITYMETRICS (TABLE ACT_MET IN TS_ACT), 
        CONTROL (TABLE CONTROL IN TS_ACT) 
AUTOSTART;
```

adf

```
--CREATE THRESHOLD THRS_TEMPSPACE 
--	FOR DATABASE ACTIVITIES ENFORCEMENT DATABASE WHEN SQLTEMPSPACE > 500 M 
--    COLLECT ACTIVITY DATA WITH DETAILS, SECTION AND VALUES CONTINUE; 

SET EVENT MONITOR ACT STATE 1;
```

Generate plan

```
set current explain mode yes
db2 -vtf <query.sql>
```

<br>

Use explain from activity

## Explain from section

```sql
CALL EXPLAIN_FROM_SECTION (x'00000001000000000000000000104F7700000000000220191028102249622672','M', NULL, NULL, NULL, ?, ?, ?, ?, ?)
```

### Explain multiple statements from section

First create a function to explain a statement from section

```sql
create or replace function dba.explain_section(p_exec_id varchar(32) for bit data, p_exp_schema varchar(128)) returns table(exfmt_cmd varchar(128))

Language sql modifies sql data

begin atomic

declare v_exp_schema, v_exp_req, v_exfmt_cmd, v_src_name, v_src_schema, v_src_ver varchar(128);--
declare v_exp_time timestamp;--

set v_exp_schema=coalesce(p_exp_schema, current user);--

call explain_from_section(p_exec_id, 'M', NULL, 0, v_exp_schema, v_exp_req, v_exp_time, v_src_name, v_src_schema, v_src_ver);--

set v_exfmt_cmd='db2exfmt -d ' || current server || ' -e ' || v_exp_schema || ' -w ' || v_exp_time || ' -n ' || v_src_name || ' -s ' || v_src_schema || ' -# 0 -t';--

return values(v_exfmt_cmd);--

end;
```

```sql
WITH EXEC_ID AS (
	SELECT EXECUTABLE_ID, 
    STMT_TEXT FROM TABLE(MON_GET_PKG_CACHE_STMT('D', NULL, NULL, -1)) 
    WHERE NUM_EXEC_WITH_METRICS > 0 -- to avoid a division by zero 
    AND STMT_TYPE_ID LIKE 'DML, Select%' -- we’re only interested in DML, in particular SELECTs 
    ORDER BY TOTAL_ACT_TIME/NUM_EXEC_WITH_METRICS DESC
    ) -- we’re interested in long running acts 
SELECT 
	EXPL.EXFMT_CMD, 
    EXEC_ID.STMT_TEXT 
FROM 
	EXEC_ID, 
    TABLE(EXPLAIN_SECTION(EXEC_ID.EXECUTABLE_ID)) EXPL 
 FETCH FIRST 10 ROWS ONLY ;
```

## Explain from data

### Explain multiple

```sql
CREATE OR REPLACE FUNCTION EXPLAIN_DATA (p_EVENT_ID BIGINT, p_EVENT_TIMESTAMP TIMESTAMP) 
RETURNS TABLE (EXFMT_CMD VARCHAR (128)) 
LANGUAGE SQL 
MODIFIES SQL DATA 

BEGIN ATOMIC 

DECLARE v_EXP_SCHEMA, v_EXP_REQ, v_EXFMT_CMD, v_SRC_NAME, v_SRC_SCHEMA, v_SRC_VER VARCHAR(128);-- 
DECLARE v_EXP_TIME TIMESTAMP;-- 
DECLARE v_EXEC_ID VARCHAR(32) FOR BIT DATA;-- 
DECLARE v_SECTION BLOB(134M);-- 
DECLARE v_STMT_TEXT CLOB(2M);-- 

SET v_EXP_SCHEMA = CURRENT USER;-- 
SET (v_SECTION, v_STMT_TEXT, v_EXEC_ID) = (SELECT SECTION_ENV, STMT_TEXT, EXECUTABLE_ID FROM PKGC WHERE EVENT_ID = p_EVENT_ID AND EVENT_TIMESTAMP = p_EVENT_TIMESTAMP);-- 

CALL EXPLAIN_FROM_DATA( v_SECTION, v_STMT_TEXT, v_EXEC_ID, v_EXP_SCHEMA, v_EXP_REQ, v_EXP_TIME, v_SRC_NAME, v_SRC_SCHEMA, v_SRC_VER); -- 

SET v_EXFMT_CMD = 'db2exfmt -d ' || CURRENT SERVER || ' -e ' || v_EXP_SCHEMA || ' -w ' || v_EXP_TIME || ' -n ' || v_SRC_NAME || ' -s ' || v_SRC_SCHEMA || ' -# 0 -t' ;-- 

RETURN values (v_EXFMT_CMD);-- 

END;
```

## Explain from activity

### Explain multiple

```sql
CREATE OR REPLACE FUNCTION EXPLAIN_ACTIVITY (p_APPL_ID VARCHAR(64), p_UOW_ID INT, p_ACTIVITY_ID INT ,p_ACTMON VARCHAR(128)) 
RETURNS TABLE (EXFMT_CMD VARCHAR (128)) 
LANGUAGE SQL 
MODIFIES SQL DATA 

BEGIN ATOMIC 

DECLARE v_EXP_SCHEMA, v_EXP_REQ, v_EXFMT_CMD, v_SRC_NAME, v_SRC_SCHEMA, v_SRC_VER VARCHAR(128);-- 
DECLARE v_EXP_TIME TIMESTAMP;-- 
SET v_EXP_SCHEMA = CURRENT USER;-- 

CALL EXPLAIN_FROM_ACTIVITY(p_APPL_ID, p_UOW_ID, p_ACTIVITY_ID, p_ACTMON, v_EXP_SCHEMA, v_EXP_REQ, v_EXP_TIME ,v_SRC_NAME, v_SRC_SCHEMA, v_SRC_VER);-- 
SET v_EXFMT_CMD = 'db2exfmt -d ' || CURRENT SERVER || ' -e ' || v_EXP_SCHEMA || ' -w ' || v_EXP_TIME || ' -n ' || v_SRC_NAME || ' -s ' || v_SRC_SCHEMA || ' -# 0 -t' ;-- 
RETURN values (v_EXFMT_CMD);-- 

END;
```

## Alternative explain view

```sql
from: http://use-the-index-luke.com/sql/explain-plan/db2/getting-an-execution-plan

-- Copyright (c) 2014-2015, Markus Winand - NO WARRANTY
-- Modifications by Ember Crooks - NO WARRANTY
-- Info & license: http://use-the-index-luke.com/s/last_explained
--
--#SET TERMINATOR ;

CREATE OR REPLACE VIEW last_explained AS
WITH tree(operator_ID, level, path, explain_time, cycle)
AS
(
SELECT 1 operator_id 
     , 0 level
     , CAST('001' AS VARCHAR(1000)) path
     , max(explain_time) explain_time
     , 0
  FROM SYSTOOLS.EXPLAIN_OPERATOR O
 WHERE O.EXPLAIN_REQUESTER = SESSION_USER

UNION ALL

SELECT s.source_id
     , level + 1
     , tree.path || '/' || LPAD(CAST(s.source_id AS VARCHAR(3)), 3, '0')  path
     , tree.explain_time
     , CASE WHEN (POSITION(path IN '%/' || LPAD(CAST(s.source_id AS VARCHAR(3)), 3, '0')  || '/%' USING OCTETS) >0)
            THEN 1
            ELSE 0
       END
  FROM tree
     , SYSTOOLS.EXPLAIN_STREAM S
 WHERE s.target_id    = tree.operator_id
   AND s.explain_time = tree.explain_time
   AND S.Object_Name IS NULL
   AND S.explain_requester = SESSION_USER
   AND tree.cycle = 0
   AND level < 100
)
SELECT * 
  FROM (
SELECT "Explain Plan"
  FROM (
SELECT CAST(   LPAD(id,        MAX(LENGTH(id))        OVER(), ' ')
            || ' | ' 
            || RPAD(operation, MAX(LENGTH(operation)) OVER(), ' ')
            || ' | ' 
            || LPAD(rows,      MAX(LENGTH(rows))      OVER(), ' ')
            || ' | ' 
            -- Don't show ActualRows columns if there are no actuals available at all 
            || CASE WHEN COUNT(ActualRows) OVER () > 1 -- the heading 'ActualRows' is always present, so "1" means no OTHER values
                    THEN LPAD(ActualRows, MAX(LENGTH(ActualRows)) OVER(), ' ') || ' | ' 
                    ELSE ''
               END
            || LPAD(cost,      MAX(LENGTH(cost))      OVER(), ' ')
         AS VARCHAR(100)) "Explain Plan"
     , path
  FROM (
SELECT 'ID' ID
     , 'Operation' Operation
     , 'Rows' Rows
     , 'ActualRows' ActualRows
     , 'Cost' Cost
     , '0' Path
  FROM SYSIBM.SYSDUMMY1
-- TODO: UNION ALL yields duplicate. where do they come from?
UNION
SELECT CAST(tree.operator_id as VARCHAR(254)) ID
     , CAST(LPAD(' ', tree.level, ' ')
       || CASE WHEN tree.cycle = 1
               THEN '(cycle) '
               ELSE ''
          END     
       || COALESCE (
             TRIM(O.Operator_Type)
          || COALESCE(' (' || argument || ')', '') 
          || ' '
          || COALESCE(S.Object_Name,'')
          , ''
          )
       AS VARCHAR(254)) AS OPERATION
     , COALESCE(CAST(rows AS VARCHAR(254)), '') Rows
     , CAST(ActualRows as VARCHAR(254)) ActualRows -- note: no coalesce
     , COALESCE(CAST(CAST(O.Total_Cost AS BIGINT) AS VARCHAR(254)), '') Cost
     , path
  FROM tree
  LEFT JOIN ( SELECT i.source_id
              , i.target_id
              , CAST(CAST(ROUND(o.stream_count) AS BIGINT) AS VARCHAR(12))
                || ' of '
                || CAST (total_rows AS VARCHAR(12))
                || CASE WHEN total_rows > 0
                         AND ROUND(o.stream_count) <= total_rows THEN
                   ' ('
                   || LPAD(CAST (ROUND(ROUND(o.stream_count)/total_rows*100,2)
                          AS NUMERIC(5,2)), 6, ' ')
                   || '%)'
                   ELSE ''
                   END rows
              , CASE WHEN act.actual_value is not null then
                CAST(CAST(ROUND(act.actual_value) AS BIGINT) AS VARCHAR(12))
                || ' of '
                || CAST (total_rows AS VARCHAR(12))
                || CASE WHEN total_rows > 0 THEN
                   ' ('
                   || LPAD(CAST (ROUND(ROUND(act.actual_value)/total_rows*100,2)
                          AS NUMERIC(5,2)), 6, ' ')
                   || '%)'
                   ELSE NULL
                   END END ActualRows
              , i.object_name
              , i.explain_time
         FROM (SELECT MAX(source_id) source_id
                    , target_id
                    , MIN(CAST(ROUND(stream_count,0) AS BIGINT)) total_rows
                    , CAST(LISTAGG(object_name) AS VARCHAR(50)) object_name
                    , explain_time
                 FROM SYSTOOLS.EXPLAIN_STREAM
                WHERE explain_time = (SELECT MAX(explain_time)
                                        FROM SYSTOOLS.EXPLAIN_OPERATOR
                                       WHERE EXPLAIN_REQUESTER = SESSION_USER
                                     )
                GROUP BY target_id, explain_time
              ) I
         LEFT JOIN SYSTOOLS.EXPLAIN_STREAM O
           ON (    I.target_id=o.source_id
               AND I.explain_time = o.explain_time
               AND O.EXPLAIN_REQUESTER = SESSION_USER
              )
         LEFT JOIN SYSTOOLS.EXPLAIN_ACTUALS act
           ON (    act.operator_id  = i.target_id
               AND act.explain_time = i.explain_time
               AND act.explain_requester = SESSION_USER
               AND act.ACTUAL_TYPE  like 'CARDINALITY%'
              )
       ) s
    ON (    s.target_id    = tree.operator_id
        AND s.explain_time = tree.explain_time
       )
  LEFT JOIN SYSTOOLS.EXPLAIN_OPERATOR O
    ON (    o.operator_id  = tree.operator_id
        AND o.explain_time = tree.explain_time
        AND o.explain_requester = SESSION_USER
       ) 
  LEFT JOIN (SELECT LISTAGG (CASE argument_type
                             WHEN 'UNIQUE' THEN
                                  CASE WHEN argument_value = 'TRUE'
                                       THEN 'UNIQUE'
                                  ELSE NULL
                                  END
                             WHEN 'TRUNCSRT' THEN
                                  CASE WHEN argument_value = 'TRUE'
                                       THEN 'TOP-N'
                                  ELSE NULL
                                  END   
                             WHEN 'SCANDIR' THEN
                                  CASE WHEN argument_value != 'FORWARD'
                                       THEN argument_value
                                  ELSE NULL
                                  END                     
                             ELSE argument_value     
                             END
                           , ' ') argument
                  , operator_id
                  , explain_time
               FROM SYSTOOLS.EXPLAIN_ARGUMENT EA
              WHERE argument_type IN ('AGGMODE'   -- GRPBY
                                     , 'UNIQUE', 'TRUNCSRT' -- SORT
                                     , 'SCANDIR' -- IXSCAN, TBSCAN
                                     , 'OUTERJN' -- JOINs
                                     )
                AND explain_requester = SESSION_USER
              GROUP BY explain_time, operator_id

            ) A
    ON (    a.operator_id  = tree.operator_id
        AND a.explain_time = tree.explain_time
       )
     ) O
UNION ALL
SELECT 'Explain plan (c) 2014-2015 by Markus Winand - NO WARRANTY - V20151017'
     , 'Z0' FROM SYSIBM.SYSDUMMY1
UNION ALL
SELECT 'Modifications by Ember Crooks - NO WARRANTY'
     , 'Z1' FROM SYSIBM.SYSDUMMY1
UNION ALL
SELECT 'http://use-the-index-luke.com/s/last_explained'
     , 'Z2' FROM SYSIBM.SYSDUMMY1
UNION ALL
SELECT '', 'A' FROM SYSIBM.SYSDUMMY1
UNION ALL
SELECT '', 'Y' FROM SYSIBM.SYSDUMMY1
UNION ALL
SELECT 'Predicate Information', 'AA' FROM SYSIBM.SYSDUMMY1
UNION ALL
SELECT CAST (LPAD(CASE WHEN operator_id = LAG  (operator_id)
                                          OVER (PARTITION BY operator_id
                                                    ORDER BY pred_order
                                               )
                       THEN ''
                       ELSE operator_id || ' - '
                  END
                , MAX(LENGTH(operator_id )+4) OVER()
                , ' ')
             || how_applied
             || ' ' 
             || predicate_text
          AS VARCHAR(100)) "Predicate Information"
     , 'P' || LPAD(id_order, 5, '0') || pred_order path
  FROM (SELECT CAST(operator_id AS VARCHAR(254)) operator_id
             , LPAD(trim(how_applied)
                  ,  MAX (LENGTH(TRIM(how_applied)))
                    OVER (PARTITION BY operator_id)
                  , ' '
               ) how_applied
               -- next: capped to length 80 to avoid
               -- SQL0445W  Value "..." has been truncated.  SQLSTATE=01004
               -- error when long literal values may appear (space padded!)
             , CAST(substr(predicate_text, 1, 80) AS VARCHAR(80)) predicate_text
             , CASE how_applied WHEN 'START' THEN '1'
                                WHEN 'STOP'  THEN '2'
                                WHEN 'SARG'  THEN '3'
                                ELSE '9'
               END pred_order
             , operator_id id_order
          FROM systools.explain_predicate p
         WHERE explain_time = (SELECT MAX(explain_time)
                                 FROM systools.explain_operator)
       )
)
ORDER BY path
);
```

### Alternative explain view with row actuals (not tested)

```
db2 create event monitor act_stmt for activities write to table manualstart
db2 "set event monitor act_stmt state = 1"

db2 "CALL WLM_SET_CONN_ENV(NULL, '<collectactdata>WITH DETAILS, SECTION</collectactdata>')"

db2 update db cfg for SAMPLE using section_actuals BASE immediate
-- db2 "CALL WLM_SET_CONN_ENV(NULL, '<collectsectionactuals>BASE</collectsectionactuals>')"



select
    substr(i.indschema,1,12) as indschema, 
    substr(i.indname,1,25) as indname, 
    uniquerule,
    (select cast(listagg((
        case 
        when ic.colorder = 'A' then '+' || ic.colname 
        when ic.colorder = 'D' then '-' || ic.colname 
        when ic.colorder = 'I' then '|' || ic.colname 
        end
        ), '') within group (order by ic.colseq) as varchar(100)) 
        from syscat.indexcoluse ic 
        where ic.indschema = i.indschema and ic.indname = i.indname
    ) as colnames 
from    syscat.indexes as i 
where   tabschema = 'QIS'
    and tabname = 'POLICY'
order by    i.tabschema, 
        i.tabname, 
        i.indname;


db2 "CALL WLM_SET_CONN_ENV(NULL, '<collectactdata>NONE</collectactdata>')"
-- db2 "CALL WLM_SET_CONN_ENV(NULL, '<collectsectionactuals>NONE</collectsectionactuals>')"

db2 flush event monitor act_stmt
db2 "set event monitor act_stmt state = 0"


db2 "select executable_id, stmt_text from ACTIVITYSTMT_ACT_STMT where stmt_text like '%POLICY%'"
x'0100000000000000AF0000000000000000000000020020180302103257195663'

db2 "select application_id, uow_id, activity_id from ACTIVITYSTMT_ACT_STMT where executable_id=x'0100000000000000AF0000000000000000000000020020180302103257195663'"

db2 "CALL EXPLAIN_FROM_ACTIVITY('*LOCAL.db2inst1.180302080805', 131,1, 'ACT_STMT', Null, ?, ?, ?, ?, ? )"

db2 "select * from last_explained"
```

Compare access plans

[compare\_accessplans.txt](https://files.nuclino.com/files/82b9e461-5322-4b37-8ace-aa6684458a16/compare_accessplans.txt)

# Analyse query

## Arguments used in query during maximum execution time

```sql
SELECT 
	SQL.STMT_TEXT, 
    ARGS.INDEX , 
    ARGS.DATATYPE, 
    ARGS.DATA
FROM 
	TABLE(MON_GET_PKG_CACHE_STMT('D',NULL,NULL,-1)) AS SQL
	,XMLTABLE(XMLNAMESPACES(DEFAULT 'http://www.ibm.com/xmlns/prod/db2/mon'),
		'$ARGS/max_coord_stmt_exec_time_args/max_coord_stmt_exec_time_arg'
		PASSING XMLPARSE(DOCUMENT SQL.MAX_COORD_STMT_EXEC_TIME_ARGS) AS "ARGS"
		COLUMNS INDEX INT PATH 'stmt_value_index',
		DATATYPE CLOB PATH 'stmt_value_type',
		DATA CLOB PATH 'stmt_value_data'
    ) AS ARGS
WHERE 
	SQL.EXECUTABLE_ID = x'00000001000000000000000000106C6000000000000220191028131724314034'
ORDER BY 
	ARGS.INDEX
WITH UR;
```

## Overview single query performance

```sql
SELECT
        SUBSTR(STMT_TEXT,1,10) as STATEMENT
        , ROWS_READ
        , ROWS_READ/ROWS_RETURNED as STMT_IXREF
        , ROWS_RETURNED/NUM_EXECUTIONS as ROWS_RETURNED_PER_EXEC
        , TOTAL_ACT_TIME as TOTAL_ACT_TIME_MS
        , decimal(float(TOTAL_ACT_WAIT_TIME)/float(TOTAL_ACT_TIME),5,2)*100 as PCT_WAIT
        , decimal(1 - ((float(pool_data_p_reads) + float(pool_xda_p_reads) +
                float(pool_index_p_reads) + float(pool_temp_data_p_reads)
                + float(pool_temp_xda_p_reads) + float(pool_temp_index_p_reads) )
                / (float(pool_data_l_reads) + float(pool_xda_l_reads) + float(pool_index_l_reads) +
                float(pool_temp_data_l_reads) + float(pool_temp_xda_l_reads)
                + float(pool_temp_index_l_reads) )) ,5,2) as stmt_bphr
        , TOTAL_SORTS/NUM_EXECUTIONS as SORTS_PER_EXEC
        , decimal(float(SORT_OVERFLOWS)/float(TOTAL_SORTS),5,2) * 100 as SORT_OVERFLOW_PCT
        , POST_THRESHOLD_SORTS+POST_SHRTHRESHOLD_SORTS as POST_THRESHOLD_SORTS
        , NUM_EXECUTIONS
        , DECIMAL(FLOAT(STMT_EXEC_TIME)/FLOAT(NUM_EXECUTIONS),10,2) AS AVG_EXEC_TIME
        , DEADLOCKS
        , LOCK_TIMEOUTS
        , INSERT_TIMESTAMP
    FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', x'01000000000000001E1906000000000000000000020020170903070924368243', NULL, -2)) AS T
;
```

Wait times

```sql
SELECT
        decimal(float(TOTAL_ACT_WAIT_TIME)/float(TOTAL_ACT_TIME),9,4) as PCT_WAIT
        , TOTAL_ACT_WAIT_TIME
        , LOCK_WAIT_TIME
        , LOG_BUFFER_WAIT_TIME
        , LOG_DISK_WAIT_TIME
    FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', x'01000000000000001E1906000000000000000000020020170903070924368243', NULL, -2)) AS T
;
```

Processing time

```sql
SELECT
        TOTAL_ACT_TIME - TOTAL_ACT_WAIT_TIME as TOTAL_ACT_EXECUTING
        , PREP_TIME
        , TOTAL_CPU_TIME
        , POOL_READ_TIME
        , POOL_WRITE_TIME
        , DIRECT_READ_TIME
        , DIRECT_WRITE_TIME
        , TOTAL_SECTION_SORT_TIME
        , TOTAL_SECTION_SORT_PROC_TIME
        , WLM_QUEUE_TIME_TOTAL
        , TOTAL_ROUTINE_TIME
    FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', x'01000000000000001E1906000000000000000000020020170903070924368243', NULL, -2)) AS T

```

## Time breakdown

```sql
select 
	p.executable_id, 
    r.metric_name, 
    r.parent_metric_name,
	r.total_time_value as time, 
    r.count, 
    p.member
from
	(select 
      		stmt_exec_time, 
      		executable_id
		from table(mon_get_pkg_cache_stmt(null,null,null,-2)) as s
		order by stmt_exec_time desc 
     	fetch first row only
    ) as stmts, -- statement of interest
	table(mon_get_pkg_cache_stmt_details(null,stmts.executable_id,null,-2)) as p,
	table(mon_format_xml_times_by_row(p.details)) as r
order by stmts.executable_id, total_time_value desc
with ur;
```

## Queries using temp tablespace

```sql
WITH SUM_TAB (SUM_RR, SUM_CPU, SUM_EXEC, SUM_SORT, SUM_NUM_EXEC, SUM_TMP_READS) AS (
        SELECT  FLOAT(SUM(ROWS_READ))+1,
                FLOAT(SUM(TOTAL_CPU_TIME))+1,
                FLOAT(SUM(STMT_EXEC_TIME))+1,
                FLOAT(SUM(TOTAL_SECTION_SORT_TIME))+1,
                FLOAT(SUM(NUM_EXECUTIONS))+1,
                FLoat(SUM(POOL_TEMP_DATA_L_READS+POOL_TEMP_XDA_L_READS+POOL_TEMP_INDEX_L_READS)) +1
            FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', NULL, NULL, -2)) AS T
        )
SELECT
        INSERT_TIMESTAMP,
        STMT_TEXT,
        POOL_TEMP_DATA_L_READS+POOL_TEMP_XDA_L_READS+POOL_TEMP_INDEX_L_READS TMP_READS,
        DECIMAL(100*(FLOAT(POOL_TEMP_DATA_L_READS+POOL_TEMP_XDA_L_READS+POOL_TEMP_INDEX_L_READS)/SUM_TAB.SUM_TMP_READS),5,2) AS PCT_TOT_TMP,
        ROWS_READ,
        DECIMAL(100*(FLOAT(ROWS_READ)/SUM_TAB.SUM_RR),5,2) AS PCT_TOT_RR,
        TOTAL_CPU_TIME,
        DECIMAL(100*(FLOAT(TOTAL_CPU_TIME)/SUM_TAB.SUM_CPU),5,2) AS PCT_TOT_CPU,
        STMT_EXEC_TIME,
        DECIMAL(100*(FLOAT(STMT_EXEC_TIME)/SUM_TAB.SUM_EXEC),5,2) AS PCT_TOT_EXEC,
        TOTAL_SECTION_SORT_TIME,
        DECIMAL(100*(FLOAT(TOTAL_SECTION_SORT_TIME)/SUM_TAB.SUM_SORT),5,2) AS PCT_TOT_SRT,
        NUM_EXECUTIONS,
        DECIMAL(100*(FLOAT(NUM_EXECUTIONS)/SUM_TAB.SUM_NUM_EXEC),5,2) AS PCT_TOT_EXEC,
        DECIMAL(FLOAT(STMT_EXEC_TIME)/FLOAT(NUM_EXECUTIONS+1),10,2) AS AVG_EXEC_TIME
    FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', NULL, NULL, -2)) AS T, SUM_TAB
    ORDER BY TMP_READS DESC FETCH FIRST 20 ROWS ONLY WITH UR
```

<br>

## Efficiency of Columnar Query

Compute the ratio of columnar processing time to overall section processing time to see how much we’re leveraging the columnar runtime

```sql
SELECT 
	TOTAL_SECTION_TIME, 
    TOTAL_COL_TIME,
	DEC((FLOAT(TOTAL_COL_TIME)/
		FLOAT(NULLIF(TOTAL_SECTION_TIME,0)))*100,5,2)
		AS PCT_COL_TIME
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL,NULL,NULL,-1)) AS T
WHERE STMT_TEXT = 'SELECT * FROM TEST.COLTAB A, TEST.ROWTAB B WHERE A.ONE
= B.ONE'
```

## db2batch

[DB2: How to troubleshoot a query with parameter markers...](https://www.ibm.com/developerworks/community/blogs/IMSupport/entry/DB2_How_to_troubleshoot_a_query_with_parameter_markers_using_section_actuals?lang=en "DB2: How to troubleshoot a query with parameter markers using section actuals? (Thoughts from Support)")

<br>

```sql
--#BGBLK 2
--#PARAM '000060' '000010'
--#PARAM 50000 60000 70000
 
SELECT e.empno,
       e.lastname,
       d.deptname
FROM   employee e,
       department d
WHERE  e.workdept = d.deptno
       AND d.mgrno = ?
       AND e.salary > ?;
--#EOBLK

```

Block is enclosed in BGBLK EOBLK directives, number after BGBLK, 2, says how many times we want the block to be executed. For each execution, one of provided parameters will be used ('000060' and '000010' for the input file above). Executing it as follows:

```
db2batch -d <db> -f <input> -i complete -o r 0 p 5 -r <output>.out
```

gives us:\
-i complete: breakdown of prepare, execute, and fetch time\
-o r 0: zero actual rows on the output (as we don't really want to see them, fetch will still happen though)\
-o p 5: all types of snapshot collected

> There is a couple of ways you can set up activity details monitoring, but there are 3 things you will need:\
> 1\. Section\_actuals have to be enabled:\
> $ db2 connect to sample\
> $ db2 update database configuration using section\_actuals base
>
> 2\. One needs to have an activity event monitor. If you don't have one yet, you can create it as follows:\
> $ db2 create event monitor actuals\_mon for activities write to table\
> (the name will be "ACTUALS\_MON")\
> \- this will create 5 new tables, where our data will be stored by event monitor infrastructure:\
> ACTIVITYMETRICS\_ACTUALS\_MON\
> ACTIVITYSTMT\_ACTUALS\_MON\
> ACTIVITYVALS\_ACTUALS\_MON\
> ACTIVITY\_ACTUALS\_MON\
> CONTROL\_ACTUALS\_MON
>
> 3\. Monitor has to be enabled to capture the data:\
> $ db2 set event monitor actuals\_mon state 1
>
>  
>
> Once we have the event monitor ready, metrics and actuals collection has to be enabled, either explicitly from given connection:\
> $ db2 "call wlm\_set\_conn\_env(NULL,'\<collectactdata>WITH DETAILS, SECTION\</collectactdata>\<collectactpartition>ALL\</collectactpartition>')"\
> or implicitly via workloads. We might don't want to have it enabled for all applications running in the database (likely in default workload SYSDEFAULTUSERWORKLOAD) to avoid overhead, so a new workload should be created. To assign "our" workload (one, in which we will execute our query), I tend to use the assignment based on client accounting string:\
> $ db2 "create workload actuals current client\_acctng('actuals') collect activity data with details,section"\
> $ db2 "grant usage on workload actuals to public"
>
> From now on, all connections which will have client accounting string set to 'actuals', what can be done via CLI ClientAcctStr keyword or by calling proper WLM procedure:\
> CALL SYSPROC.WLM\_SET\_CLIENT\_INFO(NULL, NULL, NULL, 'actuals', NULL);\
> will have both activity metrics and section actuals collected (as long as event monitor is active).
>
> Other option is to assign the workload based one.g  userid or name of application from which query is being run. For example, to have all db2batch executions assigned automatically to that workload, we can do it as follows:
>
> $ db2 "create workload actuals\_mon applname('db2batch') collect activity data with details,section"

<br>

```sql
db2 "SELECT a.time_completed,
       Substr(appl_name, 1, 20)   appl_name,
       Substr(a.appl_id, 1, 28)   appl_id,
       a.uow_id,
       a.activity_id,
       Length(a.section_actuals)  act_len,
       Substr(s.stmt_text, 1, 50) stmt
FROM   activity_actuals_mon a,
       activitystmt_actuals_mon s
WHERE  a.appl_id = s.appl_id
       AND a.uow_id = s.uow_id
       AND a.activity_id = s.activity_id"
```

```
To generate explain including actuals, EXPLAIN_FROM_ACTIVITY should be used, where we need to pass APPL_ID, UOW_ID, ACTIVITY_ID and name of event monitor, e.g:
$ db2 "CALL EXPLAIN_FROM_ACTIVITY( '*LOCAL.db2v105.160819104221', 3, 1, 'ACTUALS_MON', '', ?, ?, ?, ?, ? )"
$ db2exfmt -d sample -1 -t
```

# Optimizer profile

Mechanism to alter default access plan\
– Overrides the default access plan selected by the optimizer.\
– Instructs the optimizer how to perform table access or join.\
– Allows users to control specific parts of access plan.\
• Can be employed without changing the application code\
– Compose optimization profile, add to db, rebind targeted packages.\
• Should only be used after all other tuning options exhausted\
– Query improvement, RUNSTATS, indexes, optimization class, db and\
dbm configs, etc.\
– Should not be employed to permanently mitigate the effect of\
inefficient queries.\


• XML document\
– Elements and attributes used to define optimization guidelines.\
– Must conform to a specific optimization profile schema.\
• Profile Header (exactly one)\
– Meta data and processing directives.\
– Example: schema version.\
• Global optimization guidelines (at most one)\
– Applies to all statements for which profile is in effect.\
– Example: eligible MQTs guideline defining MQTs to be considered for routing.\
• Statement optimization guidelines (zero or more)\
– Applies to a specific statement for which profile is in effect.\
– Specifies directives for desired execution plan.

<br>

```xml
<?xml version="1.0" encoding="UTF-8"?>
<OPTPROFILE VERSION="9.7.0.0">
	<OPTGUIDELINES>
		<MQT NAME="Test.AvgSales"/>
		<MQT NAME="Test.SumSales"/>
	</OPTGUIDELINES>
  
	<STMTPROFILE ID="Guidelines for TPCD">
		<STMTKEY SCHEMA="TPCD">
			<![CDATA[SELECT * FROM TAB1]]>
		</STMTKEY>
		<OPTGUIDELINES>
			<IXSCAN TABLE="TAB1" INDEX="I_SUPPKEY"/>
		</OPTGUIDELINES>
	</STMTPROFILE>
</OPTPROFILE>
```

## Create opt\_profile table

```
db2 "call sysinstallobjects('opt_profiles', 'c', '', '')"
```

Compose optimization profile in XML file prof1.xml

Create file prof1.del as follows

```
"<schema>","PROF1","prof1.xml"
```

Import prof1.del into SYSTOOLS.OPT\_PROFILE table as follows

```
IMPORT FROM prof1.del OF DEL
MODIFIED BY LOBSINFILE
INSERT INTO SYSTOOLS.OPT_PROFILE;
```

Enable the PROF1 profile for the current session

```
db2 "set current optimization profile = 'EXAMPLE.PROF1'"
```

# Query rewrite

Herschrijven door gebruik te maken van (anti) joins

[A Visual Explanation of Db2 Joins with Practical Examples](https://www.db2tutorial.com/db2-basics/db2-join/ "A Visual Explanation of Db2 Joins with Practical Examples")

<br>
