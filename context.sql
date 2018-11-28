-- ======================================
-- (c) 2018 Adrian Newby
-- ======================================

set echo on
spool &&logDir.&&dirSep.context.log

connect SYS/&&sysPassword. as SYSDBA
@&&oraHome.&&dirSep.ctx&&dirSep.admin&&dirSep.catctx change_on_install SYSAUX TEMP NOLOCK;

connect "CTXSYS"/"change_on_install"
@&&oraHome.&&dirSep.ctx&&dirSep.admin&&dirSep.defaults&&dirSep.dr0defin.sql "AMERICAN";

spool off


