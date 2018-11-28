#!/bin/sh

# ======================================
# (c) 2018 Adrian Newby
# ======================================
#
# The databases set up by this script will always have 2 control files, 4 redo logs in 2 groups
# and SYSTEM, SYSAUX, TEMP and UNDO tablespaces.  All other tablespaces are optional and defined
# in the tablespace configuration file passed as parameter 2.  Additional redo log files, grouped
# in pairs, are defined in the configuration file passed as parameter 3.
#
# All three configuration files are required, even if they define no addtional tablespaces or 
# redo log groups (unlikely, at least for tablespaces).
#
# Note, prior to running this script, the following directories or mountpoints
# must exist and be owned by the oracle user:
#
# /archive
# /coldbackups
# /hotbackups
# /dpumps
#
# It is expected that this script will be run from a directory
# named $ORACLE_BASE/admin/$DBNAME/scripts
#
# ======================================

# ---------------------------------------------------------
# ---------------------- Validation -----------------------
# ---------------------------------------------------------

# The config files we will use
MAIN_CFG_FILE=$1
REDO_CFG_FILE=$2
TBS_CFG_FILE=$3


if [ $# -ne 3 ]
then
	echo "Incorrect arguments supplied"
	echo "Usage: `basename $0` <main-config-file> <redo-config-file> <tablespace-config-file>"
	exit
fi

if [ ! -f "$MAIN_CFG_FILE" ]
then
	echo "Main configuration file cannot be found: $MAIN_CFG_FILE"
	exit
fi

if [ ! -f "$REDO_CFG_FILE" ]
then
	echo "Redo log configuration file cannot be found: $REDO_CFG_FILE"
	exit
fi

if [ ! -f "$TBS_CFG_FILE" ]
then
	echo "Tablespace configuration file cannot be found: $TBS_CFG_FILE"
	exit
fi

# ---------------------------------------------------------
# ---- Set up environment parameters from config file -----
# ---------------------------------------------------------

ENV_FILE=/tmp/set-up-env
rm -f $ENV_FILE >/dev/null

echo "#!/bin/sh" >> $ENV_FILE

while read line
do
	# Avoid comment lines
	if [ "`echo $line | awk '{print substr($0,1,1)}'`" != "#" ] ; then
		echo "export ${line}"  >> $ENV_FILE
	fi
done < $MAIN_CFG_FILE
. $ENV_FILE


rm $ENV_FILE

# Validate configuration entries
if [ "$STORAGE_MODEL" != "RAW" ] && [ "$STORAGE_MODEL" != "FILE" ] ; then
	echo "Configuration file error: STORAGE_MODEL must be RAW or FILE"
	exit
fi 

if [ -z $DEFAULT_TBS ] ; then
	echo "Configuration file error: DEFAULT_TBS must identify a valid tablespace name"
	exit
fi

# ---------------------------------------------------------
# ----         Make necessary infrastructure          -----
# ---------------------------------------------------------

OLD_UMASK=`umask`
umask 0027

mkdir -p /archive/${DB_NAME}
mkdir -p /hotbackups/${DB_NAME}
mkdir -p /coldbackups/${DB_NAME}
mkdir -p /dpumps/${DB_NAME}
mkdir -p ${ORACLE_HOME}/dbs
mkdir -p ${ORACLE_BASE}/admin/${DB_NAME}/adump
mkdir -p ${ORACLE_BASE}/admin/${DB_NAME}/diags
mkdir -p ${ORACLE_BASE}/admin/${DB_NAME}/pfile

ORADATA=${ORACLE_BASE}/admin/${DB_NAME}/oradata
export ORADATA
mkdir -p $ORADATA

rm -rf $LOG_DIR
mkdir -p $LOG_DIR

umask ${OLD_UMASK}

# ---------------------------------------------------------
# --- Generate additional redo log groups and symlinks ----
# ---------------------------------------------------------

REDO_CREATE_SCRIPT=${ORACLE_BASE}/admin/${DB_NAME}/scripts/CreateAdditionalRedoLogGroups.sql
rm -f $REDO_CREATE_SCRIPT >/dev/null

echo "-- ==========================================================================" >> $REDO_CREATE_SCRIPT
echo "-- `date`: This is an automatically-generated script" >> $REDO_CREATE_SCRIPT
echo "-- ==========================================================================" >> $REDO_CREATE_SCRIPT
echo "" >> $REDO_CREATE_SCRIPT

echo "connect SYS/&&sysPassword. as SYSDBA"    >> $REDO_CREATE_SCRIPT
echo "set echo on"                             >> $REDO_CREATE_SCRIPT
echo "spool &&logDir./CreateAdditionalRedoLogGroups.log"       >> $REDO_CREATE_SCRIPT
echo "" >> $REDO_CREATE_SCRIPT

# Set up variables
REDO_LOG_GROUP=3		# We already have 2 redo log groups in the main config, so the first here would be number 3
REDO_LOG_MEMBER_A=""
REDO_LOG_MEMBER_B=""
REDO_LOG_FILE_A=""
REDO_LOG_FILE_B=""

while read LINE
do
	# Avoid comment lines
	if [ "`echo $LINE | awk '{print substr($0,1,1)}'`" != "#" ]; then
	
		# Get fields
		if [ "z$REDO_LOG_MEMBER_A" == "z" ]; then
			REDO_LOG_MEMBER_A=$LINE
		else
			REDO_LOG_MEMBER_B=$LINE
		fi
		
		# If B is non-null then we have a pair and we can set up the new redo log group
		if [ "z$REDO_LOG_MEMBER_B" != "z" ]; then
			
			# Initialize the variable that will hold the actual redo log file names		
			REDO_LOG_FILE_A=$REDO_LOG_MEMBER_A
			REDO_LOG_FILE_B=$REDO_LOG_MEMBER_B
			
			# Generate a directory and file name if necessary
			if [ "$STORAGE_MODEL" == "FILE" ]; then
				
				mkdir -p $REDO_LOG_FILE_A
				mkdir -p $REDO_LOG_FILE_B
				
				REDO_LOG_FILE_A=${REDO_LOG_FILE_A}/redo${REDO_LOG_GROUP}a
				REDO_LOG_FILE_B=${REDO_LOG_FILE_B}/redo${REDO_LOG_GROUP}b
			fi
			
			# Make symlinks
			ln -fs $REDO_LOG_FILE_A ${ORADATA}/redo_${REDO_LOG_GROUP}_a
			ln -fs $REDO_LOG_FILE_B ${ORADATA}/redo_${REDO_LOG_GROUP}_b
			
			touch ${ORADATA}/redo_${REDO_LOG_GROUP}_a
			touch ${ORADATA}/redo_${REDO_LOG_GROUP}_b
			
			# Add a line to the redo log script, identifying the redo logs via their symlink
			#
			# -- This is an emergency hack to bypass the use of symlinks - ACN - 09272011
			#
			#echo "ALTER DATABASE ADD LOGFILE GROUP $REDO_LOG_GROUP ('${ORADATA}/redo_${REDO_LOG_GROUP}_a', '${ORADATA}/redo_${REDO_LOG_GROUP}_b') SIZE $REDO_SZ;"   >> $REDO_CREATE_SCRIPT
			echo "ALTER DATABASE ADD LOGFILE GROUP $REDO_LOG_GROUP ('$REDO_LOG_FILE_A', '$REDO_LOG_FILE_B') SIZE $REDO_SZ REUSE;"   >> $REDO_CREATE_SCRIPT
			
			# Initialize for the next redo log pair
			REDO_LOG_MEMBER_A=""
			REDO_LOG_MEMBER_B=""			
			REDO_LOG_FILE_A=""
			REDO_LOG_FILE_B=""	
			
			# Bump the redo log group number to the next one		
			REDO_LOG_GROUP=`expr $REDO_LOG_GROUP + 1`
			
		fi
			
	fi
done < $REDO_CFG_FILE

echo "" >> $REDO_CREATE_SCRIPT
echo "spool off" >> $REDO_CREATE_SCRIPT

# ---------------------------------------------------------
# ---- Generate tablespace creation file and symlinks -----
# ---------------------------------------------------------

TBS_CREATE_SCRIPT=${ORACLE_BASE}/admin/${DB_NAME}/scripts/CreateDBFiles.sql
rm -f $TBS_CREATE_SCRIPT >/dev/null

echo "-- ==========================================================================" >> $TBS_CREATE_SCRIPT
echo "-- `date`: This is an automatically-generated script" >> $TBS_CREATE_SCRIPT
echo "-- ==========================================================================" >> $TBS_CREATE_SCRIPT
echo "" >> $TBS_CREATE_SCRIPT

echo "connect SYS/&&sysPassword. as SYSDBA"    >> $TBS_CREATE_SCRIPT
echo "set echo on"                             >> $TBS_CREATE_SCRIPT
echo "spool &&logDir./CreateDBFiles.log"       >> $TBS_CREATE_SCRIPT

while read line
do
	# Avoid comment lines
	if [ "`echo $line | awk '{print substr($0,1,1)}'`" != "#" ]; then
	
		# Get fields
		TBS_NM=`echo $line | cut -d^ -f1`
		TBS_SZ=`echo $line | cut -d^ -f2`
		TBS_LOC=`echo $line | cut -d^ -f3`
		EXT_SZ=`echo $line | cut -d^ -f4`
		SEG_MGT=`echo $line | cut -d^ -f5`
		
		# Generate a file name if necessary
		if [ "$STORAGE_MODEL" == "FILE" ]; then
			mkdir -p ${TBS_LOC}
			DATAFILE=${TBS_LOC}/${TBS_NM}.dbf
			# Touch the file to avoid Oracle errors trying to reuse non-existent files
			touch $DATAFILE
		else
			DATAFILE=${TBS_LOC}
		fi 

		# Set up the symlink
		ln -fs $DATAFILE $ORADATA/$TBS_NM		
		
		# Add a line to the tablespace create script, identifying the datafile via its symlink
		#
                # -- This is an emergency hack to bypass the use of symlinks - ACN - 09272011
                #
		#echo "@./util/make-tablespace   ${TBS_NM}   ${TBS_SZ}   ${ORADATA}/${TBS_NM}   ${EXT_SZ}   ${SEG_MGT}"   >> $TBS_CREATE_SCRIPT
		echo "@./util/make-tablespace   ${TBS_NM}   ${TBS_SZ}   $DATAFILE   ${EXT_SZ}   ${SEG_MGT}"   >> $TBS_CREATE_SCRIPT
		

		
	fi
done < $TBS_CFG_FILE

echo "" >> $TBS_CREATE_SCRIPT
echo "ALTER DATABASE DEFAULT TABLESPACE $DEFAULT_TBS;"  >> $TBS_CREATE_SCRIPT
echo "" >> $TBS_CREATE_SCRIPT
echo "spool off"                                        >> $TBS_CREATE_SCRIPT

# ---------------------------------------------------------
# ------ Generate Data Pump directory setting script ------
# ---------------------------------------------------------

DPUMP_DIR_CREATE_SCRIPT=${ORACLE_BASE}/admin/${DB_NAME}/scripts/SetDataPumpDirectory.sql
rm -f $DPUMP_DIR_CREATE_SCRIPT >/dev/null

echo "-- ==========================================================================" >> $DPUMP_DIR_CREATE_SCRIPT
echo "-- `date`: This is an automatically-generated script" >> $DPUMP_DIR_CREATE_SCRIPT
echo "-- ==========================================================================" >> $DPUMP_DIR_CREATE_SCRIPT
echo "" >> $DPUMP_DIR_CREATE_SCRIPT

echo "connect SYS/&&sysPassword. as SYSDBA"    >> $DPUMP_DIR_CREATE_SCRIPT
echo "set echo on"                             >> $DPUMP_DIR_CREATE_SCRIPT
echo "spool &&logDir./SetDataPumpDirectory.log"       >> $DPUMP_DIR_CREATE_SCRIPT
echo "" >> $DPUMP_DIR_CREATE_SCRIPT

echo "CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR AS '/dpumps/${DB_NAME}';"   >> $DPUMP_DIR_CREATE_SCRIPT

echo "" >> $DPUMP_DIR_CREATE_SCRIPT
echo "spool off" >> $DPUMP_DIR_CREATE_SCRIPT

# ---------------------------------------------------------

# Set up meaningful symlinks to datafiles / raw devices
echo "Making ${ORADATA}"
mkdir -p ${ORADATA}

# Begin with the location
CTL1_FILE=$CTL1_LOC
CTL2_FILE=$CTL2_LOC

REDO1_FILE=$REDO1_LOC
REDO2_FILE=$REDO2_LOC
REDO3_FILE=$REDO3_LOC
REDO4_FILE=$REDO4_LOC	

SYSTEM_FILE=$SYSTEM_LOC
SYSAUX_FILE=$SYSAUX_LOC	
TEMP_FILE=$TEMP_LOC
UNDO_FILE=$UNDO_LOC		


# If we're using filesystems, then the location is a directory, so we need a filename as well
if [ "$STORAGE_MODEL" == "FILE" ]; then

	# Make sure the directory locations exist
	mkdir -p $CTL1_LOC
	mkdir -p $CTL2_LOC
	mkdir -p $REDO1_LOC
	mkdir -p $REDO2_LOC
	mkdir -p $REDO3_LOC
	mkdir -p $REDO4_LOC
	mkdir -p $SYSTEM_LOC
	mkdir -p $SYSAUX_LOC
	mkdir -p $TEMP_LOC
	mkdir -p $UNDO_LOC

	# Generate the filenames
	CTL1_FILE=$CTL1_FILE/ctl1
	CTL2_FILE=$CTL2_FILE/ctl2
	
	REDO1_FILE=$REDO1_FILE/redo1a
	REDO2_FILE=$REDO2_FILE/redo1b
	REDO3_FILE=$REDO3_FILE/redo2a
	REDO4_FILE=$REDO4_FILE/redo2b
	
	SYSTEM_FILE=$SYSTEM_FILE/system.dbf
	SYSAUX_FILE=$SYSAUX_FILE/sysaux.dbf
	TEMP_FILE=$TEMP_FILE/temp.dbf
	UNDO_FILE=$UNDO_FILE/undo.dbf		
fi 


# Now set up the symlinks
ln -fs $CTL1_FILE ${ORADATA}/ctl1
ln -fs $CTL2_FILE ${ORADATA}/ctl2

ln -fs $REDO1_FILE ${ORADATA}/redo1
ln -fs $REDO2_FILE ${ORADATA}/redo2
ln -fs $REDO3_FILE ${ORADATA}/redo3
ln -fs $REDO4_FILE ${ORADATA}/redo4

ln -fs $SYSTEM_FILE ${ORADATA}/system
ln -fs $SYSAUX_FILE ${ORADATA}/sysaux
ln -fs $UNDO_FILE ${ORADATA}/undo
ln -fs $TEMP_FILE ${ORADATA}/temp

# Touch the files to avoid Oracle errors trying to reuse non-existent files
touch ${ORADATA}/ctl1
touch ${ORADATA}/ctl2
touch ${ORADATA}/redo1
touch ${ORADATA}/redo2
touch ${ORADATA}/redo3
touch ${ORADATA}/redo4
touch ${ORADATA}/system
touch ${ORADATA}/sysaux
touch ${ORADATA}/undo
touch ${ORADATA}/temp

# ---------------------------------------------------------
# Prepare init.ora file
echo ${ORADATA} | sed 's/\//\\\//g' > /tmp/oradata-esc
export ORADATA_ESC=`cat /tmp/oradata-esc`
rm /tmp/oradata-esc

echo ${ORACLE_BASE} | sed 's/\//\\\//g' > /tmp/orabase-esc
export ORACLE_BASE_ESC=`cat /tmp/orabase-esc`
rm /tmp/orabase-esc

#CTL1="$ORADATA_ESC\/ctl1"
#CTL2="$ORADATA_ESC\/ctl2"


echo ${CTL1_FILE} | sed 's/\//\\\//g' > /tmp/ctl1file
export CTL1_FILE_ESC=`cat /tmp/ctl1file`
rm /tmp/ctl1file

echo ${CTL2_FILE} | sed 's/\//\\\//g' > /tmp/ctl2file
export CTL2_FILE_ESC=`cat /tmp/ctl2file`
rm /tmp/ctl2file

CTL1="$CTL1_FILE_ESC"
CTL2="$CTL2_FILE_ESC"

# %%WINDRV%% is replaced with NULL since UNIX has no concept of "drive" (thankfully)
cat ./init-generic.ora | sed -e s/%%DB%%/$DB_NAME/g -e s/%%WINDRV%%// -e s/%%COMPAT%%/$ORA_COMPAT/ -e s/%%ORABAS%%/$ORACLE_BASE_ESC/ -e s/%%MEM%%/$MEM_SZ/ -e s/%%BLK%%/$BLK_SZ/ -e s/%%MBRC%%/$MBR_CNT/ -e s/%%CTL1%%/$CTL1/ -e s/%%CTL2%%/$CTL2/  -e s/%%LOGBUF%%/$LOGBUF_SZ/ > ${ORACLE_BASE}/admin/${DB_NAME}/pfile/init.ora 

# ---------------------------------------------------------
# Modify /etc/oratab
cat /etc/oratab | grep -v ${DB_NAME} > /tmp/oratab
echo "${DB_NAME}:${ORACLE_HOME}:N" >> /tmp/oratab
cat /tmp/oratab > /etc/oratab
rm -f /tmp/oratab >/dev/null


# ---------------------------------------------------------
# Create the database
ORACLE_SID=${DB_NAME}; export ORACLE_SID


${ORACLE_HOME}/bin/sqlplus /nolog @${ORACLE_BASE}/admin/${DB_NAME}/scripts/cr8-db.sql ${SYS_PWD} ${SYSTEM_PWD} ${DB_NAME} ${LOG_DIR} ${ORADATA} ${REDO_SZ} ${SYSTEM_SZ} ${SYSAUX_SZ} ${TEMP_SZ} ${UNDO_SZ} ${REDO1_FILE} ${REDO2_FILE} ${REDO3_FILE} ${REDO4_FILE} ${SYSTEM_FILE} ${SYSAUX_FILE} ${TEMP_FILE} ${UNDO_FILE} ${ORACLE_BASE} ${ORACLE_HOME} dbs "/" "rm -f" UNIX ${TIMEZONE}

echo ---------------------------------------
echo (c) Adrian Newby, 2018-
echo ---------------------------------------


