-- ======================================
-- (c) 2018 Adrian Newby
-- ======================================


set echo on
spool &&logDir.&&dirSep.JServer.log

connect SYS/&&sysPassword. as SYSDBA

@&&oraHome.&&dirSep.javavm&&dirSep.install&&dirSep.initjvm.sql;
@&&oraHome.&&dirSep.xdk&&dirSep.admin&&dirSep.initxml.sql;
@&&oraHome.&&dirSep.xdk&&dirSep.admin&&dirSep.xmlja.sql;
@&&oraHome.&&dirSep.rdbms&&dirSep.admin&&dirSep.catjava.sql;
@&&oraHome.&&dirSep.rdbms&&dirSep.admin&&dirSep.catexf.sql;

spool off

