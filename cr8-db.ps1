# ======================================
# (c) 2018 Adrian Newby
# ======================================
#
# The databases set up by this script will always have 2 control files, 4 redo logs in 2 groups
# and SYSTEM, SYSAUX, TEMP and UNDO tablespaces.  All other tablespaces are optional and defined
# in the tablespace configuration file passed as parameter 3.  Additional redo log files, grouped
# in pairs, are defined in the configuration file passed as parameter 2.
#
# All three configuration files are required, even if they define no additional tablespaces or 
# redo log groups (unlikely, at least for tablespaces).
#
# Note, prior to running this script, the following directories or mountpoints
# must exist and be owned by the oracle user:
#
# /archive
# /coldbackups
# /hotbackups
#
# It is expected that this script will be run from a directory
# named $ORACLE_BASE/admin/$DBNAME/scripts
+#
#
# ======================================

function Process-Error([string]$msg="*")
{
    Write-Output "`nERROR:`t$msg";
    exit 1;
}

# ---------------------------------------------------------
# ---------------------- Validation -----------------------
# ---------------------------------------------------------

Write-Output "Capturing configuration information ..."

# The config files we will use
$MAIN_CFG_FILE=$args[0]
$REDO_CFG_FILE=$args[1]
$TBS_CFG_FILE=$args[2]

Write-Output "Validating configuration items ..."

if ($args.length -ne 3)
{
    Process-Error "Incorrect arguments supplied`n`tUsage: cr8-db <main-config-file> <redo-config-file> <tablespace-config-file>"
}


if (-not( Test-Path "$MAIN_CFG_FILE" ))
{
	Write-Output "Main configuration file cannot be found: $MAIN_CFG_FILE"
	exit 1
}

if (-not( Test-Path "$REDO_CFG_FILE" ))
{
	Process-Error "Redo log configuration file cannot be found: $REDO_CFG_FILE"
}

if (-not( Test-Path "$TBS_CFG_FILE" ))
{
	Process-Error "Tablespace configuration file cannot be found: $TBS_CFG_FILE"
}

Write-Output ""
Write-Output "----------------------------------------------------------"
Write-Output "Main       CFG : $MAIN_CFG_FILE"
Write-Output "Tablespace CFG : $TBS_CFG_FILE"
Write-Output "----------------------------------------------------------"
Write-Output ""

# ---------------------------------------------------------
# ---- Set up environment parameters from config file -----
# ---------------------------------------------------------

Write-Output "Setting up main Oracle environment variables ..."

# Read main config file, excluding lines beginning with "#"
$EnvVars = Get-Content -Path $MAIN_CFG_FILE | Where-Object -FilterScript { -not $_.StartsWith("#")}

# Set environment variables by splitting each array element around the "=" sign
$EnvVars | ForEach-Object -Process { $TheVar = $_.split('='); Set-Variable -name $TheVar[0] -value $TheVar[1] -option constant}

# Validate configuration entries
if ( $STORAGE_MODEL.equals("RAW") )
{
    Process-Error "Configuration file: RAW devices not certified for Windows-based databases"
}
elseif  ( -not $STORAGE_MODEL.equals("FILE") )
{
    Process-Error "Configuration file: STORAGE_MODEL must be FILE"
}

if ( $DEFAULT_TBS.length -eq 0 )
{
	Process-Error "Configuration file: DEFAULT_TBS must identify a valid tablespace name"
}

# ---------------------------------------------------------
# ----         Make necessary infrastructure          -----
# ---------------------------------------------------------

Write-Output "Setting up basic Oracle directories ..."

New-Item -Path $ORACLE_BASE_DRV\archive\$DB_NAME -ItemType "directory" -Force     | Out-Null
New-Item -Path $ORACLE_BASE_DRV\hotbackups\$DB_NAME -ItemType "directory" -Force  | Out-Null
New-Item -Path $ORACLE_BASE_DRV\coldbackups\$DB_NAME -ItemType "directory" -Force | Out-Null

New-Item -Path $ORACLE_HOME\database -ItemType "directory" -Force                 | Out-Null

New-Item -Path $ORACLE_BASE\admin\$DB_NAME\adump -ItemType "directory" -Force     | Out-Null
New-Item -Path $ORACLE_BASE\admin\$DB_NAME\diags -ItemType "directory" -Force     | Out-Null
New-Item -Path $ORACLE_BASE\admin\$DB_NAME\pfile -ItemType "directory" -Force     | Out-Null



# Only need this if we're symlinking, which can't be done under NTFS 4 or 5
# Need to wait until Windows Server 2008
#
#Set-Variable -name ORADATA -value $ORACLE_BASE\admin\$DB_NAME\oradata
#New-Item -Path $ORADATA -ItemType "directory" -Force

Remove-Item $LOG_DIR -Force -Recurse -ErrorAction SilentlyContinue
New-Item -Path $LOG_DIR -ItemType "directory" -Force                              | Out-Null

# ---------------------------------------------------------
# --- Generate additional redo log groups and symlinks ----
# ---------------------------------------------------------


Write-Output "Setting up additional Oracle redo log configuration ..."

Set-Variable -name REDO_CREATE_SCRIPT -value $ORACLE_BASE\admin\$DB_NAME\scripts\CreateAdditionalRedoLogGroups.sql
Remove-Item $REDO_CREATE_SCRIPT -Force -ErrorAction SilentlyContinue
 
Write-Output "-- ==========================================================================" | Out-File -FilePath $REDO_CREATE_SCRIPT -append -encoding ASCII
Write-Output "-- $(Get-Date): This is an automatically-generated script"                     | Out-File -FilePath $REDO_CREATE_SCRIPT -append -encoding ASCII
Write-Output "-- ==========================================================================" | Out-File -FilePath $REDO_CREATE_SCRIPT -append -encoding ASCII
Write-Output ""

Write-Output "connect SYS/&&sysPassword. as SYSDBA"											| Out-File -FilePath $REDO_CREATE_SCRIPT -append -encoding ASCII
Write-Output "set echo on"																	| Out-File -FilePath $REDO_CREATE_SCRIPT -append -encoding ASCII
Write-Output "spool &&logDir.\CreateAdditionalRedoLogGroups.log"							| Out-File -FilePath $REDO_CREATE_SCRIPT -append -encoding ASCII
Write-Output ""        																		| Out-File -FilePath $REDO_CREATE_SCRIPT -append -encoding ASCII

# Set up variables
Set-Variable -name REDO_LOG_GROUP  -value 3		# We already have 2 redo log groups in the main config, so the first here would be number 3
Set-Variable -name REDO_LOG_MEMBER_A  -value ""
Set-Variable -name REDO_LOG_MEMBER_B  -value ""
Set-Variable -name REDO_LOG_FILE_A  -value ""
Set-Variable -name REDO_LOG_FILE_B  -value ""                                                                      

# Read redo config file, excluding lines beginning with "#"
$RedoLogFiles = Get-Content -Path $REDO_CFG_FILE | Where-Object -FilterScript { -not $_.StartsWith("#")}

# Iterate through contents, generating an Oracle redo log group creation statement for each pair of redo logs found
$RedoLogFiles | ForEach-Object -Process { 

		# Initialize redo log member
		if ( -not $REDO_LOG_MEMBER_A )
		{
			Set-Variable -name REDO_LOG_MEMBER_A -value $_
		}
		else
		{
			Set-Variable -name REDO_LOG_MEMBER_B -value $_
		}
	
		# Do we have both redo log members for the next group?
		if ( $REDO_LOG_MEMBER_B )
		{
			# Initialize the variable that will hold the actual redo log file names
			Set-Variable -name REDO_LOG_FILE_A -value	$REDO_LOG_MEMBER_A
			Set-Variable -name REDO_LOG_FILE_B -value	$REDO_LOG_MEMBER_B
		
			if ( $STORAGE_MODEL.equals("FILE") )
		        {
		            New-Item -Path $REDO_LOG_FILE_A -ItemType "directory" -ErrorAction SilentlyContinue
					New-Item -Path $REDO_LOG_FILE_B -ItemType "directory" -ErrorAction SilentlyContinue
	
		            Set-Variable -name REDO_LOG_FILE_A -value $REDO_LOG_FILE_A\redo_$REDO_LOG_GROUP_a
		            New-Item -path $REDO_LOG_FILE_A -itemtype File -ErrorAction SilentlyContinue
	
					Set-Variable -name REDO_LOG_FILE_B -value $REDO_LOG_FILE_A\redo_$REDO_LOG_GROUP_b
		            New-Item -path $REDO_LOG_FILE_B -itemtype File -ErrorAction SilentlyContinue
	
		        }
		    elseif ( $STORAGE_MODEL.equals("RAW") )
		        {
		            Process-Error "Configuration file: RAW devices not certified for Windows-based databases"
		        }
		    else
		        {
		            Process-Error "Configuration file: STORAGE_MODEL must be FILE"
		        }
	
			# Generate the redo log group creation entry
			Write-Output "ALTER DATABASE ADD LOGFILE GROUP $REDO_LOG_GROUP ('$REDO_LOG_FILE_A', '$REDO_LOG_FILE_B') SIZE $REDO_SZ;"   | Out-File -FilePath $REDO_CREATE_SCRIPT -append -encoding ASCII
	
			# Update and reinitialize variables
			$REDO_LOG_GROUP++
			Set-Variable -name REDO_LOG_MEMBER_A  -value ""
			Set-Variable -name REDO_LOG_MEMBER_B  -value ""
			Set-Variable -name REDO_LOG_FILE_A  -value ""
			Set-Variable -name REDO_LOG_FILE_B  -value ""
		
		}

    }

	Write-Output ""                                                 | Out-File -FilePath $REDO_CREATE_SCRIPT -append -encoding ASCII
	Write-Output "spool off"                                        | Out-File -FilePath $REDO_CREATE_SCRIPT -append -encoding ASCII


# ---------------------------------------------------------
# ---- Generate tablespace creation file and symlinks -----
# ---------------------------------------------------------

Write-Output "Setting up additional Oracle tablespace configuration ..."

Set-Variable -name TBS_CREATE_SCRIPT -value $ORACLE_BASE\admin\$DB_NAME\scripts\CreateDBFiles.sql

Remove-Item $TBS_CREATE_SCRIPT -Force -ErrorAction SilentlyContinue
 
Write-Output "-- ==========================================================================" | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII
Write-Output "-- $(Get-Date): This is an automatically-generated script"                     | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII
Write-Output "-- ==========================================================================" | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII
Write-Output ""                                                                              | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII

Write-Output "connect SYS/&&sysPassword. as SYSDBA"                                          | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII
Write-Output "set echo on"                                                                   | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII
Write-Output "spool &&logDir.\CreateDBFiles.log"                                             | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII
Write-Output ""                                                                              | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII

# Read tbs config file, excluding lines beginning with "#"
$TbsVars = Get-Content -Path $TBS_CFG_FILE | Where-Object -FilterScript { -not $_.StartsWith("#")}

# Tokenize elements using ":" as delimiter
$TbsVars | ForEach-Object -Process { 
    # Tokenize line
    $ThisTbs = $_.split('^');
    # Only proceed if we have a full set of variables
    Set-Variable -name TBS_NM  -value $ThisTbs[0] 
    Set-Variable -name TBS_SZ  -value $ThisTbs[1] 
    Set-Variable -name TBS_LOC -value $ThisTbs[2] 
    Set-Variable -name EXT_SZ  -value $ThisTbs[3] 
    Set-Variable -name SEG_MGT -value $ThisTbs[4] 
    if ( $STORAGE_MODEL.equals("FILE") )
        {
            New-Item -Path $TBS_LOC -ItemType "directory" -ErrorAction SilentlyContinue
            Set-Variable -name DATAFILE -value $TBS_LOC\$TBS_NM.dbf
            New-Item -path $DATAFILE -itemtype File -ErrorAction SilentlyContinue
        }
    elseif ( $STORAGE_MODEL.equals("RAW") )
        {
            Process-Error "Configuration file: RAW devices not certified for Windows-based databases"
        }
    else
        {
            Process-Error "Configuration file: STORAGE_MODEL must be FILE"
        }
    Write-Output "@.\util\make-tablespace   $TBS_NM   $TBS_SZ   $DATAFILE   $EXT_SZ   $SEG_MGT"   | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII
        

    }


Write-Output ""                                                 | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII
Write-Output "ALTER DATABASE DEFAULT TABLESPACE $DEFAULT_TBS;"  | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII
Write-Output "spool off"                                        | Out-File -FilePath $TBS_CREATE_SCRIPT -append -encoding ASCII

# ---------------------------------------------------------

# Set up meaningful symlinks to datafiles / raw devices
# Can't be done under NTFS 4 or 5
# Need to wait until Windows Server 2008
#

# Make standard datafiles and locations

Write-Output "Setting up core Oracle tablespace configuration ..."

New-Item -Path $CTL1_LOC   -ItemType "directory" -Force | Out-Null
New-Item -Path $CTL2_LOC   -ItemType "directory" -Force | Out-Null

New-Item -Path $REDO1_LOC  -ItemType "directory" -Force | Out-Null
New-Item -Path $REDO2_LOC  -ItemType "directory" -Force | Out-Null
New-Item -Path $REDO3_LOC  -ItemType "directory" -Force | Out-Null
New-Item -Path $REDO4_LOC  -ItemType "directory" -Force | Out-Null

New-Item -Path $SYSTEM_LOC -ItemType "directory" -Force | Out-Null
New-Item -Path $SYSAUX_LOC -ItemType "directory" -Force | Out-Null
New-Item -Path $TEMP_LOC   -ItemType "directory" -Force | Out-Null
New-Item -Path $UNDO_LOC   -ItemType "directory" -Force | Out-Null

Set-Variable -name CTL1_FILE -value $CTL1_LOC\ctl.1
Set-Variable -name CTL2_FILE -value $CTL2_LOC\ctl.2

Set-Variable -name REDO1_FILE -value $REDO1_LOC\redo.1
Set-Variable -name REDO2_FILE -value $REDO2_LOC\redo.2
Set-Variable -name REDO3_FILE -value $REDO3_LOC\redo.3
Set-Variable -name REDO4_FILE -value $REDO4_LOC\redo.4	

Set-Variable -name SYSTEM_FILE -value $SYSTEM_LOC\system.dbf
Set-Variable -name SYSAUX_FILE -value $SYSAUX_LOC\sysaux.dbf
Set-Variable -name TEMP_FILE -value $TEMP_LOC\temp.dbf
Set-Variable -name UNDO_FILE -value $UNDO_LOC\undo.dbf

New-Item -path $CTL1_FILE -ItemType File   -ErrorAction SilentlyContinue
New-Item -path $CTL2_FILE -ItemType File   -ErrorAction SilentlyContinue

New-Item -path $REDO1_FILE -ItemType File  -ErrorAction SilentlyContinue
New-Item -path $REDO2_FILE -ItemType File  -ErrorAction SilentlyContinue
New-Item -path $REDO3_FILE -ItemType File  -ErrorAction SilentlyContinue
New-Item -path $REDO4_FILE -ItemType File  -ErrorAction SilentlyContinue

New-Item -path $SYSTEM_FILE -ItemType File -ErrorAction SilentlyContinue
New-Item -path $SYSAUX_FILE -ItemType File -ErrorAction SilentlyContinue
New-Item -path $TEMP_FILE -ItemType File   -ErrorAction SilentlyContinue
New-Item -path $UNDO_FILE -ItemType File   -ErrorAction SilentlyContinue


# ---------------------------------------------------------
# Prepare init.ora file

Write-Output "Building Oracle initialization parameter file ..."

Set-Variable -name InitOra -value $ORACLE_BASE\admin\$DB_NAME\pfile\init.ora -option constant

Remove-Item $InitOra -Force -ErrorAction SilentlyContinue

Get-Content -Path .\init-generic.ora | ForEach-Object -Process {
    $_.replace("%%DB%%",$DB_NAME).replace("%%WINDRV%%",$ORACLE_BASE_DRV).replace("%%COMPAT%%",$ORA_COMPAT).replace("%%ORABAS%%",$ORACLE_BASE).replace("%%MEM%%",$MEM_SZ).replace("%%BLK%%",$BLK_SZ).replace("%%MBRC%%",$MBR_CNT).replace("%%CTL1%%",$CTL1_FILE).replace("%%CTL2%%",$CTL2_FILE).replace("%%LOGBUF%%",$LOGBUF_SZ).replace("/","\"); 
    } | Out-File -FilePath $InitOra -append -encoding ASCII

# ---------------------------------------------------------
# Modify /etc/oratab

# Write-Output "Modifying /etc/oratab ..."

# cat /etc/oratab | grep -v ${DB_NAME} > /tmp/oratab
# echo "${DB_NAME}:${ORACLE_HOME}:N" >> /tmp/oratab
# cat /tmp/oratab > /etc/oratab
# rm -f /tmp/oratab >/dev/null


# ---------------------------------------------------------
# Create the database



Set-Item -Force -Path "env:ORACLE_HOME" -value $ORACLE_HOME
Set-Item -Force -Path "env:ORACLE_SID" -value $DB_NAME
Set-Item -Force -Path "env:PATH" -value "$ORACLE_HOME\bin;$env:PATH"

# See if db instance already exists - If yes, delete and reboot
$dbServices = Get-Service OracleService$DB_NAME -ErrorAction SilentlyContinue

if ($dbServices -ne $null)
{
	Write-Output "Shutting down instance  ..."
	oradim -SHUTDOWN -SID $DB_NAME -SHUTTYPE inst -SYSPWD $SYS_PWD
	
	Write-Output "Deleting instance  ..."
	oradim -DELETE -SID $DB_NAME
	
	Process-Error "Database instance $DB_NAME already existed and was deleted.`nYou must reboot and re-run this script."
}

# Delete password file
Write-Output "Deleting password file  ..."
Remove-Item $ORACLE_HOME\database\orapw$DB_NAME -Force -ErrorAction SilentlyContinue

# Create instance
Write-Output "Creating instance  ..."
oradim -NEW -SID $DB_NAME -SYSPWD $SYS_PWD -STARTMODE manual -PFILE $InitOra -SHUTMODE immediate

# Create database
Write-Output "Creating database ..."
sqlplus /nolog "@$ORACLE_BASE\admin\$DB_NAME\scripts\cr8-db.sql" $SYS_PWD $SYSTEM_PWD $DB_NAME $LOG_DIR dummy-oradata-parameter $REDO_SZ $SYSTEM_SZ $SYSAUX_SZ $TEMP_SZ $UNDO_SZ $REDO1_FILE $REDO2_FILE $REDO3_FILE $REDO4_FILE $SYSTEM_FILE $SYSAUX_FILE $TEMP_FILE $UNDO_FILE $ORACLE_BASE $ORACLE_HOME database "\" "del /f" WINDOWS


