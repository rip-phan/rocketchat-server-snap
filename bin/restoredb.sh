#! /bin/bash

if [[ ${EUID} != 0 ]]
then
    echo "[-] This task must be run with 'sudo'."
    exit
fi

backup_file=${1}
if [[ ! -f ${backup_file} ]]
then
    echo "[-] Usage: snap run rocketchat-server.rcrestore ${SNAP_COMMON}/backup_file.tgz"
    exit
fi

cd ${backup_file%/*}
if [[ -z $(pwd | grep "${SNAP_COMMON}") ]]
then
    echo "[-] Backup file must be within ${SNAP_COMMON}."
    exit
fi

function ask_backup {
    echo -n "\
*** ATTENTION ***
* Your current database WILL BE DROPPED prior to the restore!
* Would you like to make a backup of the current database before proceeding?
* (y/n/Q)> "

    read choice
    [[ "${choice,,}" = n* ]] && return
    [[ "${choice,,}" = y* ]] && backupdb.sh && return
    exit
}

function warn {
        echo "[!] ${1}"
        echo "[*] Check ${restore_dir}/${log_name} for details."
}

function abort {
        echo "[!] ${1}"
        echo "[*] Check ${restore_dir}/${log_name} for details."
        echo "[-] Restore aborted!"
        exit
}

mongo parties --eval "db.getCollectionNames()" | grep "\[ \]" >> /dev/null || ask_backup

echo "[*] Extracting backup file..."
restore_dir="${SNAP_COMMON}/restore"
log_name="extraction.log"
mkdir -p ${restore_dir}
cd ${restore_dir}
tar --no-same-owner --overwrite -zxvf ${backup_file} &> "${restore_dir}/${log_name}"

[[ $? != 0 ]] && abort "Failed to extract backup files to ${restore_dir}!"

echo "[*] Restoring data..."
data_dir=$(tail "${restore_dir}/${log_name}" | grep parties/. | head -n 1)

[[ -z ${data_dir} ]] && abort "Restore data not found within ${backup_file}!
    Please check that your backup file contains the backup data within the \"parties\" directory."

data_dir=$(dirname ${data_dir})
log_name="mongorestore.log"
mongorestore --db parties --noIndexRestore --drop ${data_dir} &> "${restore_dir}/${log_name}"

[[ $? != 0 ]] && abort "Failed to execute mongorestore from ${data_dir}!"

# If mongorestore.log only has a few lines, it likely didn't find the dump files
log_lines=$(wc -l < "${restore_dir}/${log_name}")
[[ ${log_lines} -lt 24 ]] && warn "Little or no restore data found within ${backup_file}!
    Please check that your backup file contains all the backup data within the \"parties\" directory."

echo "[*] Preparing database..."
log_name="mongoprepare.log"
mongo parties --eval "db.repairDatabase()" --verbose &> "${restore_dir}/${log_name}"

[[ $? != 0 ]] && abort "Failed to prepare database for usage!"

echo "[+] Restore completed! Please restart the snap.rocketchat services to verify."
