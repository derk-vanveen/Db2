-- Dit script roept alle individuele stored procedures voor het opschonen van monitoring informatie aan.

-- Voer dit script uit met het volgende commando:
--     db2 -svtd@f monitoring_clean_all.ddl

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

CREATE OR REPLACE PROCEDURE mon.clean_all(IN nr_days int)
LANGUAGE SQL
BEGIN
	call mon.clean_bp_data(nr_days);
	call mon.clean_txlog_data(nr_days);
	call mon.clean_hadr_data(nr_days);
	call mon.clean_ts_data(nr_days);
	call mon.clean_pck_cache_data(nr_days);
	call mon.clean_tab_data(nr_days);
	call mon.clean_lock_data(nr_days);
	call mon.clean_db_data(nr_days);
	call mon.clean_act_data(nr_days);
END
@