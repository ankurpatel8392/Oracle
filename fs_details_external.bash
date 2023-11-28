#!/usr/bin/bash

## VARIABLE DECLARATION
SCRIPTLOG=/dbmonitoring/FS_DETAILS.log
DIR_FS=/dbmonitoring/ISCD
DIR_NAME=FS
TABLE_NAME=FS_DETAILS

## FUNCTION DEFINITION
set_oratab () {
OS=`uname -s`
case ${OS} in
   Linux ) HOSTNAME=`hostname -s` ;;
   SunOS ) HOSTNAME=`hostname` ;;
   AIX   ) HOSTNAME=`hostname -s` ;;
esac
if [ ${OS} = "SunOS" ] ; then
   export ORATAB=/var/opt/oracle/oratab
else
   export ORATAB=/etc/oratab
fi
}

check_read_write () {
echo "SET PAGES 0 FEEDBACK OFF
SELECT OPEN_MODE FROM V\$DATABASE;
EXIT" | ${ORACLE_HOME}/bin/sqlplus -s / as sysdba | awk NF
}

check_rman_db () {
if [ `ps -ef|grep -i pmon | grep RMANDB | wc -l` -eq 0 ]; then
   echo "RMANDB is not up and running. Please check" | tee -a ${SCRIPTLOG}
   exit 1
else
   if [ `cat ${ORATAB} | grep "^[^#]" | sort -u | grep -v "^$" | grep -v "*" | egrep -v "ASM|ORCL" | grep RMANDB | wc -l` -eq 0 ]; then
      echo "RMANDB is not in ${ORATAB}. Please update and include RMANDB entry." | tee -a ${SCRIPTLOG}
      exit 1
   else 
      if [[ "`check_read_write`" != "READ WRITE" ]]; then
         echo "RMANDB is not in READ WRITE mode. Please check" | tee -a ${SCRIPTLOG}
         exit 1
      fi
   fi 
fi
}

set_environment () {
export ORACLE_SID=`echo $i | tr ":" " " | awk '{print$1}'`
export ORACLE_HOME=`echo $i | tr ":" " " | awk '{print$2}'`
export PATH=${ORACLE_HOME}:${ORACLE_HOME}/bin:${PATH}
export LD_LIBRARY_PATH=${ORACLE_HOME}/lib
export TNS_ADMIN=${ORACLE_HOME}/network/admin
}

check_ext_table () {
echo "SET PAGES 0 FEEDBACK OFF
SELECT COUNT(*) FROM DBA_TABLES
WHERE TABLE_NAME='FS_DETAILS'
AND OWNER='RMAN';
EXIT" | sqlplus -s / as sysdba
}

create_fs_table () {
echo "CREATE OR REPLACE DIRECTORY ${DIR_NAME} AS '${DIR_FS}';
grant read on DIRECTORY ${DIR_NAME} TO RMAN;
 
CREATE TABLE RMAN.${TABLE_NAME}(
  FILESYSTEM VARCHAR2(50),
  TOTAL_SIZE_GB VARCHAR2(30),
  USED_GB VARCHAR2(30),
  FREE_GB VARCHAR2(30),
  PERCENT_USED VARCHAR2(30)
) ORGANIZATION EXTERNAL(
  TYPE oracle_loader
  DEFAULT DIRECTORY ${DIR_NAME}
  ACCESS PARAMETERS 
  (FIELDS TERMINATED BY ',')
  LOCATION ('FS_DETAILS.txt')
);
EXIT" | sqlplus -s / as sysdba
}

fs_aix () {
df -Pg | tail -n +2 | awk '{print$6","$2","$3","$4","$5}' > ${DIR_FS}/FS_DETAILS.txt
}

fs_linux () {
df -h | tail -n +2 | awk '{print$6","$2","$3","$4","$5}' > ${DIR_FS}/FS_DETAILS.txt
}

populate_fs () {
if [ "`uname`" == "Linux" ]; then 
   fs_linux 
else
   fs_aix
fi
} 

## MAIN EXECUTION
set_oratab
check_rman_db
for i in `cat ${ORATAB} | grep "^[^#]" | sort -u | grep -v "^$" | grep -v "*" | grep "RMAN" | awk '{print$1}'`
do
   set_environment
   if [ `check_ext_table` -eq 1 ]; then
      populate_fs
   else
      create_fs_table
	  populate_fs
   fi
done
