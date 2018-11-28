-- ======================================
-- (c) 2018 Adrian Newby
-- ======================================

set echo on
spool &&logDir.&&dirSep.CreateDBCatalog.log

connect SYS/&&sysPassword. as SYSDBA

@&&oraHome.&&dirSep.rdbms&&dirSep.admin&&dirSep.catalog.sql;
@&&oraHome.&&dirSep.rdbms&&dirSep.admin&&dirSep.catblock.sql;
@&&oraHome.&&dirSep.rdbms&&dirSep.admin&&dirSep.catproc.sql;
@&&oraHome.&&dirSep.rdbms&&dirSep.admin&&dirSep.catoctk.sql;
@&&oraHome.&&dirSep.rdbms&&dirSep.admin&&dirSep.owminst.plb;

connect SYSTEM/&&systemPassword.
@&&oraHome.&&dirSep.sqlplus&&dirSep.admin&&dirSep.pupbld.sql;

connect SYSTEM/&&systemPassword.
set echo on

spool &&logDir.&&dirSep.sqlPlusHelp.log
@&&oraHome.&&dirSep.sqlplus&&dirSep.admin&&dirSep.help&&dirSep.hlpbld.sql helpus.sql;
spool off


spool off


