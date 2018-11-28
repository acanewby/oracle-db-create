-- ======================================
-- (c) 2018 Adrian Newby
-- ======================================


set echo on
set verify on



spool &&logDir.&&dirSep.CreateDB.log

connect SYS/&&sysPassword. as SYSDBA
startup nomount pfile=&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.pfile&&dirSep.init.ora;

CREATE DATABASE &&dbName.
	MAXINSTANCES 8
	MAXLOGHISTORY 1
	MAXLOGFILES 16
	MAXLOGMEMBERS 3
	MAXDATAFILES 100
	CONTROLFILE REUSE
	DATAFILE '&&systemFile.' 
		SIZE &&systemSz. REUSE
		EXTENT MANAGEMENT LOCAL
	SYSAUX DATAFILE '&&sysauxFile.'
		SIZE &&sysauxSz. REUSE
	BIGFILE DEFAULT TEMPORARY TABLESPACE TEMP 
		TEMPFILE '&&tempFile.'
		SIZE &&tempSz. REUSE
	BIGFILE UNDO TABLESPACE "UNDO" 
		DATAFILE '&&undoFile.'
		SIZE &&undoSz. REUSE
	CHARACTER SET AL32UTF8
	NATIONAL CHARACTER SET UTF8
	LOGFILE GROUP 1 ('&&redo1File.','&&redo3File.') SIZE &&redoSz. REUSE,
		GROUP 2 ('&&redo2File.','&&redo4File.') SIZE &&redoSz. REUSE
	USER SYS IDENTIFIED BY &&sysPassword. 
	USER SYSTEM IDENTIFIED BY &&systemPassword.
	SET TIME_ZONE = '&timeZone.';

spool off

