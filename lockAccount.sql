-- ======================================
-- (c) 2018 Adrian Newby
-- ======================================


set echo on
spool &&logDir.&&dirSep.lockAccount.log

connect SYS/&&sysPassword. as SYSDBA

BEGIN 
 FOR item IN ( SELECT USERNAME FROM DBA_USERS WHERE ACCOUNT_STATUS IN ('OPEN', 'LOCKED', 'EXPIRED') AND USERNAME NOT IN ( 
'SYS','SYSTEM') ) 
 LOOP 
  dbms_output.put_line('Locking and Expiring: ' || item.USERNAME); 
  execute immediate 'alter user ' ||
         sys.dbms_assert.enquote_name(
         sys.dbms_assert.schema_name(
         item.USERNAME),false) || ' password expire account lock' ;
 END LOOP;
END;
/

spool off


