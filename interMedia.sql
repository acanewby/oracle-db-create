-- ======================================
-- (c) 2018 Adrian Newby
-- ======================================


set echo on
spool &&logDir.&&dirSep.interMedia.log

connect SYS/&&sysPassword. as SYSDBA
@&&oraHome.&&dirSep.ord&&dirSep.im&&dirSep.admin&&dirSep.iminst.sql;

spool off


