-- Dit script maakt stored procedures aan om opgeslagen monitoring informatie uit de interne monitoring tabellen die ouder is dan
-- nr_days te verwijderen. Voor iedere tabel is er een functie voor het opschonen van de data.

-- Voer dit script uit met het volgende commando:
--     db2 -svtd@f monitoring_clean.ddl

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

CREATE OR REPLACE PROCEDURE mon.clean_bp_data(IN nr_days int)
LANGUAGE SQL
BEGIN
	delete from mon.bp where DT < current date - nr_days days;
END
@

CREATE OR REPLACE PROCEDURE mon.clean_txlog_data(IN nr_days int)
LANGUAGE SQL
BEGIN
	delete from mon.txlog where DT < current date - nr_days days;
END
@

CREATE OR REPLACE PROCEDURE mon.clean_hadr_data(IN nr_days int)
LANGUAGE SQL
BEGIN
	delete from mon.hadr where DT < current date - nr_days days;
END
@

CREATE OR REPLACE PROCEDURE mon.clean_ts_data(IN nr_days int)
LANGUAGE SQL
BEGIN
	delete from mon.ts where DT < current date - nr_days days;
END
@

CREATE OR REPLACE PROCEDURE mon.clean_pck_cache_data(IN nr_days int)
LANGUAGE SQL
BEGIN
	delete from mon.pckcache where DT < current date - nr_days days;
END
@

CREATE OR REPLACE PROCEDURE mon.clean_tab_data(IN nr_days int)
LANGUAGE SQL
BEGIN
	delete from mon.tab where DT < current date - nr_days days;
END
@

CREATE OR REPLACE PROCEDURE mon.clean_lock_data(IN nr_days int)
LANGUAGE SQL
BEGIN
	delete from mon.locks where DT < current date - nr_days days;
END
@

CREATE OR REPLACE PROCEDURE mon.clean_db_data(IN nr_days int)
LANGUAGE SQL
BEGIN
	delete from mon.db where DT < current date - nr_days days;
END
@

CREATE OR REPLACE PROCEDURE mon.clean_act_data(IN nr_days int)
LANGUAGE SQL
BEGIN
	delete from mon.act where DT < current date - nr_days days;
END
@