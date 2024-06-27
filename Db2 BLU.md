Documentatie: Sessie C07 idug 2019 rotterdam.&#x20;

## When can you benefit from blu?

| **Probably**                                          | **Probably not**                                                 |
| ----------------------------------------------------- | ---------------------------------------------------------------- |
| Analytical workload                                   | OLTP                                                             |
| Grouping, aggregation, range scans, joins             | Insert, update, delete of few rows per transaction               |
| Queries touch only a subset of the columns in a table | Queries touch many or all columns in a table                     |
| Star schema                                           | Use of XML, pureScale, etc. which are not supported by BLU (yet) |
| SAP Business Warehouse                                |                                                                  |
| Netteza migration                                     |                                                                  |

## Database configuration

The following is set automatically when workload is set to analytics

- dft\_table\_org=COLUMN
- default page size 32k
- dft\_extent\_sz=4
- intra-query parellelism enabled
- catalogcache\_sz higher than default
- sortheap and sheapthres\_shr higher than default
- util\_heap\_sz higher than default (1,000,000 default, 4,000,000 for db's > 128gb)
- WLM controls concurrency on SYSDEFAULTMANAGEDSUBCLASS
- auto\_reorg=on

## Do not do

- Specify compression, MDC or partitioning for BLU tables
- create non-unique indexes or MQT's

# Build offline dictionay

Maximizing Compression with the Load Utility&#x20;

- Use sufficiently large amount of representative data in 1st Load that builds dictionaries
- Set util\_heap\_sz >= 1,000,000 pages with AUTOMATIC option (4,000,000 for databases > 128GB memory)
- To minimize amount of time the table is offline and create a nearoptimal dictionary
  - Step 1: Manually build dictionary using load utility and Bernoulli sampling
  - Step 2: Insert data (consider pre-sorting data by columns that use predicates and are joined often)

The load utility samples input data to collect up to 128 GB of data to create column-level dictionaries. The sampling load performs by default may favor earlier incoming data without any special handling.&#x20;

The example below incorporates Bernoulli sampling to get a more representative sample. Primary drawback to load utility is that the table is taken offline during the load.&#x20;

NOTE that in the example below, it is recommended that the percentage X provided to the Bernoulli sampling be carefully calculated based on the size of the table being sampled. It is recommended that \~5 million rows be included in the sample.

```
create table SourceTable(
state char(2),
zipcode char(5))
organize by column;
commit;

drop table ExtTable;
create external table ExtTable(
state char(2),
zipcode char(5))
USING(dataobject ('/nfshome/blyle/test/zipdata/zip10m.del') DELIMITER ',' QUOTEDVALUE 'DOUBLE' );
commit;

declare cursor1 CURSOR FOR
select * from exttable tablesample bernoulli(X);

load from cursor1 OF CURSOR MODIFIED BY CDEANALYZEFREQUENCY=100 replace resetDictionaryOnly into SourceTable;
insert into SourceTable select * from ExtTable;

runstats on table SourceTable;

```

# Load with blu

Four phases

1. &#x20;Analyze
2. load
3. build
4. delete

## Analyze phase

Blu performance scale with compression. The compression is calculated during the analyse phase of the load. This is trigger when:

- Dictionaries are needed for column-organized tables
- Load Replace or Load Insert into empty table is used
- KEEPDICTIONARY not specified

Additionally, if you are loading from a source that can only be scanned once, DB2 needs to scan that data twice – once for the ANALYZE phase and once for the LOAD phase. This means for pipes or other sources that can only be scanned once, DB2 will create a copy of the data on the TEMPFILES PATH specified on the load command. This can be time consuming and use a lot of disk space.

## Load phase

The LOAD phase is modified for column organized tables. The following occurs for column-organized tables in the load phase:

- Column and page compression dictionaries (existing or built in the ANALYZE phase) are used to compress data
- Compressed values are written to data pages
- The Synopsis table is maintained
- Keys are built for the page map index and any unique indexes

## BUILD

For column-organized tables, the BUILD phase includes building the page map index and any unique indexes. Because this is BLU, no indexes other than Primary Key or Unique Constraint indexes are allowed, so this phase should be faster than in a traditional row-organized scenario.

## DELETE

In addition to the traditional role of deleting any rows that are rejected because of the Primary Key or Unique Constraints, the DELETE phase for BLU tables includes deleting any temp files that were used to be able to scan through the data twice.

## Load from Pipe

The process for load from pipe is not difficult, but requires that the target database server can connect to the source database server. It also requires two sessions. The general steps are:

1. (session1)Connect to the source database from the server where the target database is
2. (session1)Make a pipe using the mkfifo command \`mkfifo datapipe1\`
3. (session1)Export to the pipe created \`db2 “export to datapipe1 of del messages test.msg select \* from schema.table with ur”\`
4. (session2)Connect to the target database locally
5. (session2)Load from the pipe created \` db2 “load from datapipe1 of del messages test\_load.msg replace into schema.table NONRECOVERABLE”\`
6. (session3)Use \`db2pd -utilities -repeat 5\` to monitor the load progress

The db2pd -utilities command is good for monitoring because you can see progress and the time that each phase starts. If you’re expecting a longer load, you may want to go with a longer refresh interval than 5 seconds.

## Load from Cursor

Load from cursor for a remote source is not as hard as I had expected. There is no need to federate the source database. There are good instructions on how to load from cursor here: <http://www.ibm.com/developerworks/data/library/techarticle/dm-0901fechner/>

There are essentially three steps once the source database is cataloged on the server of the target database:

1. On target server, connect to target database
2. Declare cursor against the source database: \`db2 “DECLARE C1 CURSOR DATABASE sourcedb user uname using pw for select \* from schema.table with ur”\`
3. Load from cursor: \`db2 “LOAD FROM C1 of CURSOR MESSAGES test\_load.msg replace into schema.table nonrecoverable”\`

And as for the results, all I can say is “Whoa, that was fast!”

<br>

# COL efficiency

pysical storage (user data + dictionary)

```sql
SELECT CAST(TABSCHEMA as char(16)) TABSCHEMA,
CAST(TABNAME as char(20)) TABNAME,
DBPARTITIONNUM,
(DATA_OBJECT_P_SIZE+COL_OBJECT_P_SIZE+INDEX_OBJECT_P_SIZE)/1024 AS PHYSICAL_SIZE_MB,
RECLAIMABLE_SPACE AS RECLAIMABLE_SPACE
FROM TABLE (SYSPROC.ADMIN_GET_TAB_INFO('<schema>','<table>') ) ;
```

Compression ratio

```sql
SELECT CAST(TABSCHEMA as char(16)) TABSCHEMA,
CAST(TABNAME as char(20)) TABNAME,
PCTPAGESSAVED,
DEC(1.0/(1.0 - (PCTPAGESSAVED*1.0)/100.0),31,2) AS compression_ratio
FROM SYSCAT.TABLES tab
WHERE TABSCHEMA = '<schema>' AND TABNAME = '<table>' with UR;
```

Percentage of values encoded (compressed) by column level\
dictionary (not compression ratio)

```sql
SELECT CAST(COLNAME AS CHAR(20)) COLNAME,
PCTENCODED,
COLCARD
FROM SYSCAT.COLUMNS
WHERE TABSCHEMA = '<schema>' AND TABNAME = '<table>';
```

# Columnar table performance

see [Finding the access path for Columnar queries | Triton Consulting](https://www.triton.co.uk/finding-access-path-columnar-queries/ "Finding the access path for Columnar queries | Triton Consulting")

<br>
