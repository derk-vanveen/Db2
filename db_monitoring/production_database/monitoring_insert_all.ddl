-- Dit script roept alle individuele stored procedures aan voor het opslaan van monitoring informatie.

-- Voer dit script uit met het volgende commando:
--     db2 -svtd@f monitoring_insert_all.ddl

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

CREATE OR REPLACE PROCEDURE mon.insert_all()
LANGUAGE SQL
BEGIN
    -- bufferpools
    call mon.insert_bp_data();

    -- transaction logs
    call mon.insert_txlog_data();

    -- hadr
    call mon.insert_hadr_data();

    -- tablespaces
    call mon.insert_ts_data();

    -- tables
    call mon.insert_tab_data();

    -- package cache
    call mon.insert_pck_cache_data();

    -- locks
    call mon.insert_lock_data();

    -- database
    call mon.insert_db_data();

    -- activity
    call mon.insert_act_data();

END
@