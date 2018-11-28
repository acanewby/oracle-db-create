-- ======================================
-- (c) 2018 Adrian Newby
-- ======================================


set echo on
spool &&logDir.&&dirSep.postDBCreation.log

-- Set up production init.ora file
prompt 'Setting up production init.ora file ...'
prompt '(One of these commands will fail, being inappropriate for the current OS)'
host copy &&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.pfile&&dirSep.init.ora &&oraHome.&&dirSep.&&dbsDir.&&dirSep.init&&dbName..ora
host ln -sf &&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.pfile&&dirSep.init.ora &&oraHome.&&dirSep.&&dbsDir.&&dirSep.init&&dbName..ora



-- Restart dataase using production init.ora file
connect SYS/&&sysPassword. as SYSDBA
shutdown immediate;

connect SYS/&&sysPassword. as SYSDBA
startup;

@&&oraHome.&&dirSep.rdbms&&dirSep.admin&&dirSep.undoaud.sql;
@&&oraHome.&&dirSep.rdbms&&dirSep.admin&&dirSep.undopwd.sql;


-- Recompile any invalid objects
select 'utl_recomp_begin: ' || to_char(sysdate, 'HH:MI:SS') from dual;
execute utl_recomp.recomp_serial();
select 'utl_recomp_end: ' || to_char(sysdate, 'HH:MI:SS') from dual;


-- Tar up logs if on *nix
prompt 'Archiving log files ...'
prompt '(This command will almost certainly fail under Windows)'
LOGARCHIVE=.&&dirSep.create-logs--`date +'%Y-%m-%d--%H-%M-%S'`.tar
host tar -cvf $LOGARCHIVE &&logDir.
host gzip $LOGARCHIVE



-- Identify data files
set linesize 255
set pagesize 0
column tablespace_name format a30
column file_name format a60


select tablespace_name, file_name, bytes/(1024*1024) MB, autoextensible, increment_by
from dba_data_files
union all
select tablespace_name, file_name, bytes/(1024*1024) MB, autoextensible, increment_by
from dba_temp_files
order by tablespace_name, file_name;

spool off

exit;


