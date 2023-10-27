#!/bin/bash
# shellcheck disable=SC2128
####################################################################################
#
#   FILE: backup.sh
#   USAGE: sudo ./restore.sh (test | prod) -h
#   DESCRIPTION: Restores data from the backups of the SQL instances
#	  OPTIONS: ---
#   REQUIREMENTS: Root permissions when executing.
#                 Google Cloud service account
#	  BUGS: ---
#	  NOTES: ---
#	  AUTHOR: Jonas Bossaerts
#	  COMPANY: KdG
#	  VERSION: 1.0.0
#	  CREATED: 11/05/2021
#   REVISION: ---
#
####################################################################################

#############
# VARIABLES #
#############
SERV_ACC_EMAIL="edubox-ideploy@ip-deployment.iam.gserviceaccount.com"
SQL_INSTANCE=""

## SCRIPT
GRN=$'\e[1;32m'
RED=$'\e[1;31m'
ENDCOL=$'\e[0m'
LOGFILE_DIR="/var/log/EduBox/"
LOGFILE="restore.log"

# 0. Initializer
function init() {
	TIME_START=$(date +%s)
  printf "%s## Running initializer...\n" "${GRN}"
  # Check if root
  printf "## Checking permissions... (1/4)%s\n" "${ENDCOL}"
  if [ "$EUID" -ne 0 ]; then
    printf "%s!! Error: Please run restore.sh as root." "${RED}"
    printf "## Use sudo ./restore.sh --help for more information.\n"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%s## Done.\n" "${GRN}"
  # Create log file
  printf "## Creating log file %s%s... (2/4)%s\n" "${LOGFILE_DIR}" "${LOGFILE}" "${ENDCOL}"
  mkdir -p "$LOGFILE_DIR"
  touch "$LOGFILE_DIR"/"$LOGFILE"
  exec 2> "$LOGFILE_DIR"/"$LOGFILE"
  printf "%s## Done.\n" "${GRN}"
  # Perform gcloud SDK check/install to prevent duplicate entries for the cloud-sdk repo
  printf "%s## Checking if gcloud SDK has been installed... (3/4)%s\n" "${GRN}" "${ENDCOL}"
  # Check SDK
  if [ -z "$(apt list -qq google-cloud-sdk --installed)" ]; then
    gcloud_install
  fi
  printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  # Perform gcloud service account check
  printf "%s## Checking if gcloud service account has been configured... (4/4)%s\n" "${GRN}" "${ENDCOL}"
  # Check service account
  if [[ ! $(gcloud auth list --filter=status:ACTIVE --format="value(account)") =~ $SERV_ACC_EMAIL ]]; then
    gcloud_config
  fi
  printf "%s## Done.\n" "${GRN}"
  printf "## Initialization complete.\n"
  TIME_END=$(date +%s)
  TIME_CREATION=$((TIME_END - TIME_START))
  printf "## Time elapsed: %s seconds.\n%s" "${TIME_CREATION}" "${ENDCOL}"
}

function checkSql() {
  printf "\n%s## Checking environment for MySQL instances...\n" "${GRN}"
  local COUNTER
  local SQL_INSTANCES
  COUNTER=1
  SQL_INSTANCES="$(gcloud sql instances list | grep edubox-mysql-"$1"- | awk '{printf $1}')"
  # Check if instance exists
  if [ -z "${SQL_INSTANCES}" ]; then
    printf "%s!! No SQL instances found! Make sure you have created one.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  # Check if multiple instances exist
  if [ "$(grep -c "edubox-mysql-" <<< "$SQL_INSTANCES")" -gt 1 ]; then

  printf "## Choose which instance you want to backup.%s\n" "${ENDCOL}"
  while IFS= read -r line
  do
    printf "%s. %s\n" "${COUNTER}" "${line}"
    COUNTER=$((COUNTER + 1))
  done <<< "${SQL_INSTANCES}"
  printf "%s?? Enter a number from above list:%s " "${GRN}" "${ENDCOL}"
  read -n 1 -r
  SQL_INSTANCE="$(grep --line-number "${REPLY}" "${SQL_INSTANCES}")"
  else
  SQL_INSTANCE="${SQL_INSTANCES}"
  printf "%s## Only 1 SQL instance was found %s.%s\n" "${GRN}" "${SQL_INSTANCE}" "${ENDCOL}"
  fi
}

checkBackup() {
  printf "\n%s## Looking for existing MySQL backups...\n" "${GRN}"
  local COUNTER
  local SQL_INSTANCES_BACKUPS
  COUNTER=1
  SQL_INSTANCES_BACKUPS="$(sudo gcloud sql backups list --instance "${SQL_INSTANCE}" | grep SUCCESSFUL | awk '{printf $1; printf "\n"}')"
  # Check if backups exists
  if [ -z "${SQL_INSTANCES_BACKUPS}" ]; then
    printf "%s!! No SQL backups found! Make sure you have created one.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
  fi
  #######
  # Check if multiple backups exist
  #######
  local AANTAL
  AANTAL="$(grep -cE "[0-9]{13}" <<< "$SQL_INSTANCES_BACKUPS")"
  if [ "${AANTAL}" -gt 1 ]; then
  printf "## Choose which backup you want to restore.%s\n" "${ENDCOL}"
    while IFS="" read -r line
    do
      local BUP_ID_LIST
      # shellcheck disable=SC2207
      BUP_ID_LIST+=$(gcloud sql backups describe "${line}" --instance "${SQL_INSTANCE}" | grep description | awk '{printf $2; printf "\n"}')
    done <<< "${SQL_INSTANCES_BACKUPS}"
    while IFS="" read -r line
    do
      printf "%s. %s\n" "${COUNTER}" "${line}"
      COUNTER=$((COUNTER + 1))
    done <<< "${BUP_ID_LIST}"

    printf "%s?? Enter a number from above list:%s " "${GRN}" "${ENDCOL}"
    read -n 1 -r
    SQL_INSTANCE_BACKUP="$(grep --line-number "${REPLY}" "${SQL_INSTANCES}")"
  elif [ "${AANTAL}" -eq 1 ]; then
    printf "%s## Only 1 SQL backup was found: %s.%s\n" "${GRN}" "${SQL_INSTANCES_BACKUPS}" "${ENDCOL}"
    printf "%s?? Use the only existing backup?%s (N/y): " "${GRN}" "${ENDCOL}"
    read -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      printf "\n%s## Exiting...%s\n" "${RED}" "${ENDCOL}"
      # shellcheck disable=SC2128
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
      SQL_INSTANCE_BACKUP="${SQL_INSTANCES_BACKUPS}"
  fi
  #######
}

function restore() {
  TIME_START=$(date +%s)
  printf "\n%s## Restoring the following backup: %s...%s\n" "${GRN}" "${SQL_INSTANCE_BACKUP}" "${ENDCOL}"
  if [[ $(gcloud sql instances list --filter=status:ACTIVE --format="value(NAME)") =~ ${SQL_INSTANCE} ]]; then
    printf "## Instance is running.\n"
    if gcloud sql backups restore "${SQL_INSTANCE_BACKUP}" --restore-instance="${SQL_INSTANCE}" --quiet; then
      printf "%s## Restoring the backup succeeded %s\n" "${GRN}" "${ENDCOL}"
    else
      printf "%s!! Restoring a backup for SQL instance failed.\n" "${RED}"
      printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
      printf "## Exiting...%s\n" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
  else
    printf "%s## Instance is not running. Starting instance first...%s\n" "${GRN}" "${ENDCOL}"
    gcloud sql instances patch "${SQL_INSTANCE}" --activation-policy ALWAYS
    if gcloud sql backups restore "${SQL_INSTANCE_BACKUP}" --restore-instance="${SQL_INSTANCE}" --quiet; then
      printf "%s## Restoring the backup succeeded %s\n" "${GRN}" "${ENDCOL}"
    else
      printf "%s!! Restoring a backup for SQL instance failed.\n" "${RED}"
      printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
      printf "## Exiting...%s\n" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
    gcloud sql instances patch "${SQL_INSTANCE}" --activation-policy NEVER && \
    printf "%s## Done. Instance was stopped.%s\n" "${GRN}" "${ENDCOL}"
  fi
  TIME_END=$(date +%s)
	TIME_CREATION=$((TIME_END - TIME_START))
	printf "## Time elapsed: %s seconds.\n%s" "${TIME_CREATION}" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1;
}

# 1. Parameter -h | --help
function help() {
	echo "
NAME
	Restore script EduBox - IP.05

DESCRIPTION
	This is the restore script made for EduBox.
	Restore a backup of the sql instances for both production and testing environments.

USAGE: sudo ./restore.sh (test | prod) -h

ARGUMENTS
	test			      This starts the restore process for the testing environment
	prod			      This starts the restore process for the production environment
	--help or -h		  Shows the help page

EXAMPLES
	sudo ./restore.sh test (Starts the restore process for the testing environment)
	sudo ./restore.sh prod (Starts the restore process for the production environment)

REQUIREMENTS: Root permissions, gcloud service account.
AUTHOR: Jonas Bossaerts & Senna Pex
COMPANY: KdG
VERSION: 1.0.0
CREATED: 11/05/2021"
}

#############
#   MAIN    #
#############

# Check parameters
if [ $# -ne 1 ]; then
  printf "%s!! Wrong arguments specified. Only one argument is allowed. (Use ./backup.sh -h | --help for help)%s\n" "${RED}" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi
case $1 in
  "test"|"prod")
    init
    checkSql "$1"
    checkBackup
    restore
    ;;
  "-h"|"--help")
    help
    ;;
  *)
    printf "%s!! Wrong arguments specified. (Use ./backup.sh -h | --help for help)%s" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    ;;
esac
[[ "$0" == "$BASH_SOURCE" ]] && exit 0 || return 0
