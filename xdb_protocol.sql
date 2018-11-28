-- ======================================
-- (c) 2018 Adrian Newby
-- ======================================


set echo on
spool &&logDir.&&dirSep.xdb_protocol.log

connect SYS/&&sysPassword. as SYSDBA
@&&oraHome.&&dirSep.rdbms&&dirSep.admin&&dirSep.catqm.sql change_on_install SYSAUX TEMP;


spool off


