GRANT EXECUTE ON FUNCTION SYSPROC.MON_GET_BUFFERPOOL(VARCHAR(),INTEGER) TO USER monuser;
GRANT EXECUTE ON FUNCTION SYSPROC.MON_GET_TRANSACTION_LOG(INTEGER) TO USER monuser;
GRANT EXECUTE ON FUNCTION SYSPROC.MON_GET_HADR(INTEGER) TO USER monuser;
GRANT EXECUTE ON FUNCTION SYSPROC.MON_GET_TABLESPACE(VARCHAR(),INTEGER) TO USER monuser;
GRANT EXECUTE ON FUNCTION SYSPROC.MON_GET_TABLE(VARCHAR(),VARCHAR(),INTEGER) TO USER monuser;
GRANT EXECUTE ON FUNCTION SYSPROC.MON_GET_PKG_CACHE_STMT(CHAR(), VARCHAR(), CLOB(), INTEGER) TO USER monuser;
GRANT EXECUTE ON FUNCTION SYSPROC.MON_GET_APPL_LOCKWAIT(BIGINT,INTEGER, SMALLINT) TO USER monuser;
GRANT EXECUTE ON FUNCTION SYSPROC.MON_GET_DATABASE(INTEGER) TO USER monuser;
GRANT EXECUTE ON FUNCTION SYSPROC.MON_GET_ACTIVITY(BIGINT,INTEGER) TO USER monuser;
GRANT EXECUTE ON FUNCTION SYSPROC.ENV_GET_SYS_INFO() TO USER monuser;

create schema mon;
grant createin on schema mon to user monuser;

grant connect on database to user monuser;

grant execute on package NULLID.SQLC2J25 to user monuser;
grant execute on package NULLID.SQLC3J24 to user monuser;
grant execute on package NULLID.SQLC4J24 to user monuser;
grant execute on package NULLID.SQLC5J24 to user monuser;
grant execute on package NULLID.SQLC6J24 to user monuser;
-- FOR v10.5 and higher
grant execute on package NULLID.SQLC2K26 to user monuser;
grant execute on package NULLID.SQLC3K25 to user monuser;
grant execute on package NULLID.SQLC4K25 to user monuser;
grant execute on package NULLID.SQLC5K25 to user monuser;
grant execute on package NULLID.SQLC6K25 to user monuser;
-- FOR v11.1 and higher
grant execute on package NULLID.SQLC2O26 to user monuser;
-- COMMON STATEMENTS
grant execute on package NULLID.SYSLH200 to user monuser;
grant execute on package NULLID.SYSLH201 to user monuser;
grant execute on package NULLID.SYSLH202 to user monuser;
grant execute on package NULLID.SYSSH201 to user monuser;
grant execute on package NULLID.SYSSH202 to user monuser;
grant execute on package NULLID.SYSSH300 to user monuser;
grant execute on package NULLID.SYSSH301 to user monuser;
grant execute on package NULLID.SYSSH401 to user monuser;
grant execute on package NULLID.SYSSH402 to user monuser;
grant execute on package NULLID.SYSSH102 to user monuser;
grant execute on package NULLID.SYSSH200 to user monuser;
grant execute on package NULLID.SYSSH302 to user monuser;
grant execute on package NULLID.SYSSH400 to user monuser;
grant execute on package NULLID.SYSSH100 to user monuser;
grant execute on package NULLID.SYSSH101 to user monuser;
grant execute on package NULLID.SYSSN102 to user monuser;
grant execute on package NULLID.SYSSN200 to user monuser;
grant execute on package NULLID.SYSSN100 to user monuser;
grant execute on package NULLID.SYSSN101 to user monuser;
grant execute on package NULLID.SYSSN201 to user monuser;
grant execute on package NULLID.SYSSN202 to user monuser;
grant execute on package NULLID.SYSSN300 to user monuser;
grant execute on package NULLID.SYSSN301 to user monuser;
grant execute on package NULLID.SYSSN302 to user monuser;
grant execute on package NULLID.SYSSN400 to user monuser;
grant execute on package NULLID.SYSSN401 to user monuser;
grant execute on package NULLID.SYSSN402 to user monuser;
grant execute on package NULLID.SYSSH200 to user monuser;
grant execute on package NULLID.SYSLH200 to user monuser;
grant execute on package NULLID.SYSLH201 to user monuser;
grant execute on package NULLID.SYSLH202 to user monuser;
grant execute on package NULLID.SYSLH203 to user monuser;
grant execute on procedure SYSIBM.SQLCAMESSAGECCSID to user monuser;
grant execute on procedure SYSIBM.SQLPRIMARYKEYS to user monuser;
grant execute on procedure SYSIBM.SQLCOLUMNS to user monuser;
grant select on SYSIBMADM.DBCFG to user monuser;
grant usage on workload SYSDEFAULTUSERWORKLOAD to user monuser;