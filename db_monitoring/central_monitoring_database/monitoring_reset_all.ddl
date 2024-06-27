-- Dit script maakt een stored procudure aan voor het verwijderen van alle data die is vastgelegd in de monitoring tabellen.

-- Voer dit script uit met het volgende commando:
--     db2 -svtd@f monitoring_reset_all.ddl

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

CREATE OR REPLACE PROCEDURE mon.reset_all()
LANGUAGE SQL
BEGIN
	delete from mon.bp;
	delete from mon.txlog;
	delete from mon.hadr;
	delete from mon.ts;
	delete from mon.tab;
	delete from mon.pckcache;
	delete from mon.locks;
	delete from mon.db;
	delete from mon.act;
END
@