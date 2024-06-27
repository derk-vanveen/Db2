-- Dit script maakt tabellen aan ten behoeve van Db2 monitoring. De monitoring informatie slaan we op in de database
-- zelf. We slaan alleen informatie op om vast te leggen wat er op de database gebeurt. Deze informatie wordt niet
-- gebruikt door check_mk om meldingen uit te sturen.

-- We monitoren de volgende objecten
--  - bufferpools
--  - transactions logs
--  - hadr
--  - tablespaces
--  - tables
--  - package cache
--  - locks
--  - database
--  - activity

-- bufferpools
create table mon.bp as (
WITH BPMETRICS AS (
        SELECT bp_name,
               pool_data_l_reads + pool_temp_data_l_reads + pool_index_l_reads + pool_temp_index_l_reads as logical_reads,
               pool_data_p_reads + pool_temp_data_p_reads + pool_index_p_reads + pool_temp_index_p_reads as physical_reads,
               member
        FROM TABLE(MON_GET_BUFFERPOOL('',-2)) AS METRICS)
select
	VARCHAR(BPMETRICS.bp_name,20) AS bp_name,
	BP_CUR_BUFFSZ,
	BLOCK_IOS, PAGES_FROM_BLOCK_IOS, pages_from_block_ios / (BLOCK_IOS + 1) as block_efficiency,
	vectored_ios, pages_from_vectored_ios,
	pool_data_p_reads, pool_temp_data_p_reads, pool_index_p_reads, pool_temp_index_p_reads,
	pool_data_l_reads, pool_temp_data_l_reads, pool_index_l_reads, pool_temp_index_l_reads,
	pool_async_data_reads, pool_async_index_reads,
	CASE WHEN logical_reads > 0
			THEN DEC((1 - (FLOAT(physical_reads) / FLOAT(logical_reads))) * 100,5,2)
		ELSE
			NULL
		END AS HIT_RATIO,
	DEC(100 - (((pool_async_data_reads + pool_async_index_reads) * 100 ) / (pool_data_p_reads + pool_index_p_reads + 1)),5,2) as Sync_read_perc,
	pool_lsn_gap_clns, pool_drty_pg_steal_clns, pool_drty_pg_thrsh_clns
FROM BPMETRICS
join TABLE(MON_GET_BUFFERPOOL('',-2)) AS T on T.bp_name = BPMETRICS.bp_name ) with no data;

ALTER TABLE mon.bp
	ADD COLUMN DT DATE NOT NULL WITH DEFAULT CURRENT DATE
	ADD COLUMN TM TIME NOT NULL WITH DEFAULT CURRENT TIME
	ADD COLUMN TS TIMESTAMP NOT NULL WITH DEFAULT CURRENT TIMESTAMP
	ADD COLUMN HOSTNAME CHAR(12);

ALTER TABLE mon.bp
    alter column hostname set not null;

reorg table mon.bp;

-- transaction logs
create table mon.txlog as (
select
    CUR_COMMIT_DISK_LOG_READS,
    CUR_COMMIT_TOTAL_LOG_READS,
    CUR_COMMIT_LOG_BUFF_LOG_READS,
	LOG_HADR_WAIT_TIME,
	LOG_HADR_WAITS_TOTAL,
	LOG_WRITE_TIME  / NUM_LOG_WRITE_IO as avg_log_write_time
from table(MON_GET_TRANSACTION_LOG(-1))) with no data;

ALTER TABLE mon.txlog
	ADD COLUMN DT DATE NOT NULL WITH DEFAULT CURRENT DATE
	ADD COLUMN TM TIME NOT NULL WITH DEFAULT CURRENT TIME
	ADD COLUMN TS TIMESTAMP NOT NULL WITH DEFAULT CURRENT TIMESTAMP
	ADD COLUMN HOSTNAME CHAR(12);

ALTER TABLE mon.txlog
    alter column hostname set not null;

reorg table mon.txlog;

-- HADR
create table mon.hadr as (
select
	log_hadr_wait_cur,
	LOG_HADR_WAIT_TIME,
	LOG_HADR_WAITS_TOTAL,
	HADR_LOG_GAP,
	PRIMARY_LOG_TIME,
	standby_replay_log_time,
	PRIMARY_LOG_POS,
	STANDBY_LOG_POS,
	HEARTBEAT_MISSED,
	heartbeat_expected,
	HADR_CONNECT_STATUS,
	HADR_CONNECT_STATUS_TIME
from table(mon_get_hadr(-2))) with no data;

ALTER TABLE mon.hadr
	ADD COLUMN DT DATE NOT NULL WITH DEFAULT CURRENT DATE
	ADD COLUMN TM TIME NOT NULL WITH DEFAULT CURRENT TIME
	ADD COLUMN TS TIMESTAMP NOT NULL WITH DEFAULT CURRENT TIMESTAMP
	ADD COLUMN HOSTNAME CHAR(12);

ALTER TABLE mon.hadr
    alter column hostname set not null;

reorg table mon.hadr;

-- tablespace
create table mon.ts as (
SELECT
	varchar(tbsp_name, 30) as tbsp_name,
	TBSP_CUR_POOL_ID,
	TBSP_USED_PAGES,
	TBSP_FREE_PAGES,
	TBSP_USABLE_PAGES,
	TBSP_TOTAL_PAGES,
	TBSP_PAGE_TOP,
	TBSP_MAX_PAGE_TOP,
	TBSP_LAST_RESIZE_TIME
from table(mon_get_tablespace('',-2))) with no data;

ALTER TABLE mon.ts
	ADD COLUMN DT DATE NOT NULL WITH DEFAULT CURRENT DATE
	ADD COLUMN TM TIME NOT NULL WITH DEFAULT CURRENT TIME
	ADD COLUMN TS TIMESTAMP NOT NULL WITH DEFAULT CURRENT TIMESTAMP
	ADD COLUMN HOSTNAME CHAR(12);

ALTER TABLE mon.ts
    alter column hostname set not null;

reorg table mon.ts;

-- table
create table mon.tab as (
SELECT
	varchar(tabschema,20) as tabschema,
	varchar(tabname,20) as tabname,
	rows_read,
	rows_inserted,
	rows_updated,
	rows_deleted,
	TABLE_SCANS,
	LOCK_WAIT_TIME,
	LOCK_WAIT_TIME_GLOBAL,
	LOCK_WAITS,
	LOCK_ESCALS,
	LOCK_ESCALS_GLOBAL,
	STATS_ROWS_MODIFIED,
	OVERFLOW_ACCESSES,
	OVERFLOW_CREATES
FROM TABLE(MON_GET_TABLE('QIS','',-2))) with no data;

ALTER TABLE mon.tab
	ADD COLUMN DT DATE NOT NULL WITH DEFAULT CURRENT DATE
	ADD COLUMN TM TIME NOT NULL WITH DEFAULT CURRENT TIME
	ADD COLUMN TS TIMESTAMP NOT NULL WITH DEFAULT CURRENT TIMESTAMP
	ADD COLUMN HOSTNAME CHAR(12);

ALTER TABLE mon.tab
    alter column hostname set not null;

reorg table mon.tab;

-- package cache
create table mon.pckcache as (
SELECT
		MEMBER,
    	SECTION_TYPE ,
    	TOTAL_CPU_TIME/NUM_EXEC_WITH_METRICS as AVG_CPU_TIME,
    	SUBSTR(STMT_TEXT, 1, 2000) as stmt_text,
    	EXECUTABLE_ID,
    	INSERT_TIMESTAMP,
    	NUM_EXECUTIONS,
    	PREP_TIME,
    	STMT_EXEC_TIME,
    	QUERY_COST_ESTIMATE,
    	STMTID,
    	TOTAL_ACT_WAIT_TIME,
    	TOTAL_CPU_TIME,
    	POOL_READ_TIME,
    	POOL_WRITE_TIME,
    	DIRECT_READ_TIME,
    	DIRECT_WRITE_TIME,
    	LOCK_WAIT_TIME,
    	TOTAL_SECTION_SORT_TIME,
    	TOTAL_SECTION_SORT_PROC_TIME,
    	TOTAL_SECTION_SORTS,
    	LOCK_ESCALS,
    	LOCK_WAITS,
    	ROWS_MODIFIED,
    	ROWS_READ,
    	ROWS_RETURNED,
    	DIRECT_READS,
    	DIRECT_WRITES,
    	POOL_DATA_L_READS,
    	POOL_INDEX_L_READS,
    	POOL_DATA_P_READS,
    	POOL_INDEX_P_READS,
    	POOL_DATA_WRITES,
    	POOL_INDEX_WRITES,
    	TOTAL_SORTS,
    	SORT_OVERFLOWS,
    	LOG_DISK_WAIT_TIME,
    	LOG_DISK_WAITS_TOTAL,
    	TOTAL_SECTION_TIME,
    	TOTAL_SECTION_PROC_TIME,
    	PREFETCH_WAIT_TIME,
    	PREFETCH_WAITS,
    	ROWS_DELETED,
    	ROWS_INSERTED,
    	ROWS_UPDATED,
    	TOTAL_HASH_JOINS,
    	HASH_JOIN_OVERFLOWS,
    	HASH_JOIN_SMALL_OVERFLOWS,
    	TOTAL_HASH_GRPBYS,
    	HASH_GRPBY_OVERFLOWS
FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', NULL, NULL, -2)) as T
WHERE T.NUM_EXEC_WITH_METRICS <> 0) with no data;

ALTER TABLE mon.pckcache
	ADD COLUMN DT DATE NOT NULL WITH DEFAULT CURRENT DATE
	ADD COLUMN TM TIME NOT NULL WITH DEFAULT CURRENT TIME
	ADD COLUMN TS TIMESTAMP NOT NULL WITH DEFAULT CURRENT TIMESTAMP
	ADD COLUMN HOSTNAME CHAR(12);

ALTER TABLE mon.pckcache
    alter column hostname set not null;

reorg table mon.pckcache;

-- locks
create table mon.locks as (
select
	LOCK_WAIT_START_TIME,
	LOCK_NAME,
	lock_object_type,
	LOCK_MODE,
	LOCK_CURRENT_MODE,
	LOCK_MODE_REQUESTED,
	LOCK_STATUS,
	LOCK_ESCALATION
from table(MON_GET_APPL_LOCKWAIT(NULL, -2))) with no data;

ALTER TABLE mon.locks
	ADD COLUMN DT DATE NOT NULL WITH DEFAULT CURRENT DATE
	ADD COLUMN TM TIME NOT NULL WITH DEFAULT CURRENT TIME
	ADD COLUMN TS TIMESTAMP NOT NULL WITH DEFAULT CURRENT TIMESTAMP
	ADD COLUMN HOSTNAME CHAR(12);

ALTER TABLE mon.locks
    alter column hostname set not null;

reorg table mon.locks;

-- database
create table mon.db as (
select
	NUM_LOG_BUFFER_FULL,
	LOG_BUFFER_WAIT_TIME,
	LOCK_ESCALS,
	LOCK_TIMEOUTS,
	LOCK_WAIT_TIME,
	LOCK_WAITS,
	DEADLOCKS,
	DB_CONN_TIME,
	LAST_BACKUP,
	CONNECTIONS_TOP,
	APPLS_CUR_CONS,
	APPLS_IN_DB2,
	AGENTS_TOP,
	NUM_COORD_AGENTS,
	COORD_AGENTS_TOP,
	NUM_LOCKS_HELD,
	NUM_LOCKS_WAITING,
	ACTIVE_SORTS,
	ACTIVE_HASH_JOINS,
	AGENT_WAIT_TIME,
	AGENT_WAITS_TOTAL,
	SORT_OVERFLOWS,
	TOTAL_COMPILE_TIME,
	TOTAL_COMPILE_PROC_TIME,
	TOTAL_COMPILATIONS,
	TOTAL_IMPLICIT_COMPILE_TIME,
	TOTAL_IMPLICIT_COMPILE_PROC_TIME,
	TOTAL_IMPLICIT_COMPILATIONS,
	TOTAL_SECTION_TIME,
	TOTAL_SECTION_PROC_TIME,
	TOTAL_ACT_TIME,
	TOTAL_ACT_WAIT_TIME,
	TOTAL_COMMIT_TIME,
	TOTAL_COMMIT_PROC_TIME,
	TOTAL_APP_COMMITS,
	TOTAL_ROLLBACK_TIME,
	TOTAL_ROLLBACK_PROC_TIME,
	TOTAL_APP_ROLLBACKS,
	TOTAL_EXTENDED_LATCH_WAIT_TIME,
	TOTAL_EXTENDED_LATCH_WAITS,
	PREFETCH_WAIT_TIME,
	PREFETCH_WAITS,
	TOTAL_CONNECT_AUTHENTICATIONS,
	HASH_JOIN_OVERFLOWS,
	HASH_JOIN_SMALL_OVERFLOWS,
	SELECT_SQL_STMTS,
	UID_SQL_STMTS,
	DDL_SQL_STMTS,
	NUM_POOLED_AGENTS,
	SORT_HEAP_ALLOCATED,
	SORT_SHRHEAP_TOP,
	SORT_SHRHEAP_ALLOCATED,
	SORT_HEAP_TOP,
	TOTAL_INDEXES_BUILT,
	(1-(pkg_cache_inserts/pkg_cache_lookups))*100 as pkg_cache_hitratio
from table(mon_get_database(-2))) with no data;

ALTER TABLE mon.db
	ADD COLUMN DT DATE NOT NULL WITH DEFAULT CURRENT DATE
	ADD COLUMN TM TIME NOT NULL WITH DEFAULT CURRENT TIME
	ADD COLUMN TS TIMESTAMP NOT NULL WITH DEFAULT CURRENT TIMESTAMP
	ADD COLUMN HOSTNAME CHAR(12);

ALTER TABLE mon.db
    alter column hostname set not null;

reorg table mon.db;

-- activity
create table mon.act as (
select
	SUBSTR(STMT_TEXT, 1, 60) as stmt_text,
	TOTAL_SORTS,
	SORT_OVERFLOWS,
	SORT_SHRHEAP_TOP,
	SORT_SHRHEAP_ALLOCATED,
	SORT_HEAP_TOP,
	SORT_HEAP_ALLOCATED,
	SORT_CONSUMER_HEAP_TOP,
	SORT_CONSUMER_SHRHEAP_TOP,
	ACTIVE_SORTS,
	ACTIVE_SORTS_TOP,
	ACTIVE_SORT_CONSUMERS_TOP,
	ACTIVE_SORT_CONSUMERS,
	ROWS_READ,
	ROWS_RETURNED,
	case when ROWS_READ > 0 then
	ROWS_RETURNED/ROWS_READ
	else 0 end as rows_returned_per_read,
	TOTAL_ACT_TIME,
	TOTAL_ACT_WAIT_TIME,
	POOL_READ_TIME,
	POOL_WRITE_TIME,
	DIRECT_READ_TIME,
	DIRECT_WRITE_TIME,
	LOCK_WAIT_TIME,
	TOTAL_SECTION_SORT_TIME,
	TOTAL_SECTION_SORT_PROC_TIME,
	TOTAL_SECTION_SORTS,
	ROWS_DELETED,
	ROWS_INSERTED,
	ROWS_UPDATED,
	TOTAL_HASH_JOINS
from table(MON_GET_ACTIVITY(NULL,-1))) with no data;

ALTER TABLE mon.act
	ADD COLUMN DT DATE NOT NULL WITH DEFAULT CURRENT DATE
	ADD COLUMN TM TIME NOT NULL WITH DEFAULT CURRENT TIME
	ADD COLUMN TS TIMESTAMP NOT NULL WITH DEFAULT CURRENT TIMESTAMP
	ADD COLUMN HOSTNAME CHAR(12);

ALTER TABLE mon.act
    alter column hostname set not null;

reorg table mon.act;

-- Add indices
create index mon.txlog_hostname_dt on mon.txlog    (hostname, dt);
create index mon.hadr_hostname_dt on mon.hadr     (hostname, dt);
create index mon.ts_hostname_dt on mon.ts       (hostname, dt);
create index mon.tab_hostname_dt on mon.tab      (hostname, dt);
create index mon.pckcache_hostname_dt on mon.pckcache (hostname, dt);
create index mon.locks_hostname_dt on mon.locks    (hostname, dt);
create index mon.db_hostname_dt on mon.db       (hostname, dt);
create index mon.act_hostname_dt on mon.act      (hostname, dt);

-- grant connect to user monuser
grant connect on database to user monuser;

-- Add access for monitoring user
grant insert on mon.bp       to user monuser;
grant insert on mon.txlog    to user monuser;
grant insert on mon.hadr     to user monuser;
grant insert on mon.ts       to user monuser;
grant insert on mon.tab      to user monuser;
grant insert on mon.pckcache to user monuser;
grant insert on mon.locks    to user monuser;
grant insert on mon.db       to user monuser;
grant insert on mon.act      to user monuser;