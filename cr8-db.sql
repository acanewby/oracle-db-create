-- ======================================
-- (c) 2018 Adrian Newby
-- ======================================



set verify on
set echo on


DEFINE sysPassword=&1.
DEFINE systemPassword=&2.
DEFINE dbName=&3.
DEFINE logDir=&4.
DEFINE oraData=&5.
DEFINE redoSz=&6.
DEFINE systemSz=&7.
DEFINE sysauxSz=&8.
DEFINE tempSz=&9.
DEFINE undoSz=&10.

DEFINE redo1File=&11.
DEFINE redo2File=&12.
DEFINE redo3File=&13.
DEFINE redo4File=&14.
DEFINE systemFile=&15.
DEFINE sysauxFile=&16.
DEFINE tempFile=&17.
DEFINE undoFile=&18.

DEFINE oraBase=&19.
DEFINE oraHome=&20.
DEFINE dbsDir=&21.

DEFINE dirSep=&22.
DEFINE delCmd=&23.

DEFINE osPlatform=&24.

DEFINE timeZone=&25.




PROMPT 'Deleting password file'
host &&delCmd. &&oraHome.&&dirSep.&&dbsDir.&&dirSep.orapw&&dbName.
PROMPT 'Creating password file'
host &&oraHome.&&dirSep.bin&&dirSep.orapwd file=&&oraHome.&&dirSep.&&dbsDir.&&dirSep.orapw&&dbName. password=&&sysPassword. force=y


@&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.scripts&&dirSep.CreateDB.sql
@&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.scripts&&dirSep.CreateAdditionalRedoLogGroups.sql
@&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.scripts&&dirSep.CreateDBFiles.sql

@&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.scripts&&dirSep.CreateDBCatalog.sql
@&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.scripts&&dirSep.JServer.sql
@&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.scripts&&dirSep.context.sql
@&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.scripts&&dirSep.xdb_protocol.sql
@&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.scripts&&dirSep.lockAccount.sql

@&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.scripts&&dirSep.SetDataPumpDirectory.sql

@&&oraBase.&&dirSep.admin&&dirSep.&&dbName.&&dirSep.scripts&&dirSep.postDBCreation.sql


