-- Dit script bevat stored procedures voor het lokaal opslaan van monitoring informatie. Voor ieder object dat we
-- monitoring is er een aparte stored procedure.

-- Voer dit script uit met het volgende commando:
--     db2 -svtd@f monitoring_insert.ddl

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

CREATE OR REPLACE PROCEDURE mon.insert_bp_data()
LANGUAGE SQL
BEGIN
    insert into SERV_MON.mon.bp
        WITH BPMETRICS AS (
        SELECT bp_name,
               pool_data_l_reads + pool_temp_data_l_reads + pool_index_l_reads + pool_temp_index_l_reads as logical_reads,
               pool_data_p_reads + pool_temp_data_p_reads + pool_index_p_reads + pool_temp_index_p_reads as physical_reads,
               member
        FROM TABLE(MON_GET_BUFFERPOOL('',-2)) AS METRICS)
        SELECT
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
            pool_lsn_gap_clns, pool_drty_pg_steal_clns, pool_drty_pg_thrsh_clns,
            CURRENT DATE,
            CURRENT TIME,
            CURRENT TIMESTAMP,
            (SELECT substr(HOST_NAME,1,12) FROM TABLE(SYSPROC.ENV_GET_SYS_INFO())) as hostname
        FROM BPMETRICS
        join TABLE(MON_GET_BUFFERPOOL('',-2)) AS T on T.bp_name = BPMETRICS.bp_name ;
END
@

CREATE OR REPLACE PROCEDURE mon.insert_txlog_data()
LANGUAGE SQL
BEGIN
insert into SERV_MON.mon.txlog
	select
		CUR_COMMIT_DISK_LOG_READS,
		CUR_COMMIT_TOTAL_LOG_READS,
		CUR_COMMIT_LOG_BUFF_LOG_READS,
		LOG_HADR_WAIT_TIME,
		LOG_HADR_WAITS_TOTAL,
		LOG_WRITE_TIME  / (NUM_LOG_WRITE_IO + 1) as avg_log_write_time,
		CURRENT DATE,
		CURRENT TIME,
		CURRENT TIMESTAMP,
		(SELECT substr(HOST_NAME,1,12) FROM TABLE(SYSPROC.ENV_GET_SYS_INFO())) as hostname
	from table(MON_GET_TRANSACTION_LOG(-1));
END
@

CREATE OR REPLACE PROCEDURE mon.insert_hadr_data()
LANGUAGE SQL
BEGIN
insert into SERV_MON.mon.hadr
	select
		log_hadr_wait_cur,
		LOG_HADR_WAIT_TIME,
		LOG_HADR_WAITS_TOTAL,
		HADR_LOG_GAP,
		PRIMARY_LOG_TIME,
		standby_replay_log_time,
		PRIMARY_LOG_POS,
		STANDBY_LOG_POS,
		heartbeat_missed,
		heartbeat_expected,
		HADR_CONNECT_STATUS,
		HADR_CONNECT_STATUS_TIME,
		CURRENT DATE,
		CURRENT TIME,
		CURRENT TIMESTAMP,
		(SELECT substr(HOST_NAME,1,12) FROM TABLE(SYSPROC.ENV_GET_SYS_INFO())) as hostname
	from table(mon_get_hadr(-2));
END
@

CREATE OR REPLACE PROCEDURE mon.insert_ts_data()
LANGUAGE SQL
BEGIN
insert into SERV_MON.mon.ts
	SELECT
		varchar(tbsp_name, 30) as tbsp_name,
		TBSP_CUR_POOL_ID,
		TBSP_USED_PAGES,
		TBSP_FREE_PAGES,
		TBSP_USABLE_PAGES,
		TBSP_TOTAL_PAGES,
		TBSP_PAGE_TOP,
		TBSP_MAX_PAGE_TOP,
		TBSP_LAST_RESIZE_TIME,
		CURRENT DATE,
		CURRENT TIME,
		CURRENT TIMESTAMP,
		(SELECT substr(HOST_NAME,1,12) FROM TABLE(SYSPROC.ENV_GET_SYS_INFO())) as hostname
	from table(mon_get_tablespace('',-2));
END
@

CREATE OR REPLACE PROCEDURE mon.insert_pck_cache_data()
LANGUAGE SQL
BEGIN
insert into SERV_MON.mon.pckcache
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
        HASH_GRPBY_OVERFLOWS,
		CURRENT DATE,
		CURRENT TIME,
		CURRENT TIMESTAMP,
		(SELECT substr(HOST_NAME,1,12) FROM TABLE(SYSPROC.ENV_GET_SYS_INFO())) as hostname
	FROM TABLE(MON_GET_PKG_CACHE_STMT ( 'D', NULL, NULL, -2)) as T
	WHERE T.NUM_EXEC_WITH_METRICS <> 0;
END
@

CREATE OR REPLACE PROCEDURE mon.insert_tab_data()
LANGUAGE SQL
BEGIN
insert into SERV_MON.mon.tab
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
		OVERFLOW_CREATES,
		CURRENT DATE,
		CURRENT TIME,
		CURRENT TIMESTAMP,
		(SELECT substr(HOST_NAME,1,12) FROM TABLE(SYSPROC.ENV_GET_SYS_INFO())) as hostname
	FROM TABLE(MON_GET_TABLE('QIS','',-2));
END
@

CREATE OR REPLACE PROCEDURE mon.insert_lock_data()
LANGUAGE SQL
BEGIN
insert into SERV_MON.mon.locks
	select
		LOCK_WAIT_START_TIME,
		LOCK_NAME,
		lock_object_type,
		LOCK_MODE,
		LOCK_CURRENT_MODE,
		LOCK_MODE_REQUESTED,
		LOCK_STATUS,
		LOCK_ESCALATION,
		CURRENT DATE,
		CURRENT TIME,
		CURRENT TIMESTAMP,
		(SELECT substr(HOST_NAME,1,12) FROM TABLE(SYSPROC.ENV_GET_SYS_INFO())) as hostname
	from table(MON_GET_APPL_LOCKWAIT(NULL, -2));
END
@

CREATE OR REPLACE PROCEDURE mon.insert_db_data()
LANGUAGE SQL
BEGIN
insert into SERV_MON.mon.db
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
		(1-(pkg_cache_inserts/pkg_cache_lookups))*100 as pkg_cache_hitratio,
		CURRENT DATE,
		CURRENT TIME,
		CURRENT TIMESTAMP,
		(SELECT substr(HOST_NAME,1,12) FROM TABLE(SYSPROC.ENV_GET_SYS_INFO())) as hostname
	from table(mon_get_database(-2));
END
@

CREATE OR REPLACE PROCEDURE mon.insert_act_data()
LANGUAGE SQL
BEGIN
insert into SERV_MON.mon.act
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
		TOTAL_HASH_JOINS,
		CURRENT DATE,
		CURRENT TIME,
		CURRENT TIMESTAMP,
		(SELECT substr(HOST_NAME,1,12) FROM TABLE(SYSPROC.ENV_GET_SYS_INFO())) as hostname
	from table(MON_GET_ACTIVITY(NULL,-1));
END
@