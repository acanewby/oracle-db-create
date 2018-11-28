-- ======================================
-- (c) 2018 Adrian Newby
-- ======================================


set echo on
spool &&logDir.&&dirSep.ordinst.log

connect SYS/&&sysPassword. as SYSDBA
@&&oraHome.&&dirSep.ord&&dirSep.admin&&dirSep.ordinst.sql SYSAUX SYSAUX;

spool off


