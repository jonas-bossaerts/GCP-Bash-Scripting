#!/bin/bash
# shellcheck disable=SC2128
####################################################################################
#
#   FILE: backup.sh
#   USAGE: sudo ./backup.sh test | prod | (-h | --help)
#   DESCRIPTION: Create backups of the SQL instances
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
REGION="europe-west1"
CURRDATE=$(date +"%d%m%y")
CURRTIME=$(date +"%T")
SQL_INSTANCE=""
SERV_ACC_EMAIL="edubox-ideploy@ip-deployment.iam.gserviceaccount.com"
DESCRIPTION=""

## SCRIPT
GRN=$'\e[1;32m'
RED=$'\e[1;31m'
ENDCOL=$'\e[0m'
LOGFILE_DIR="/var/log/EduBox/"
LOGFILE="backup.log"

# 0. Initializer
function init() {
	TIME_START=$(date +%s)
  printf "%s## Running initializer...\n" "${GRN}"
  # Check if root
  printf "## Checking permissions... (1/4)%s\n" "${ENDCOL}"
  if [ "$EUID" -ne 0 ]; then
    printf "%s!! Error: Please run backup.sh as root." "${RED}"
    printf "## Use sudo ./backup.sh --help for more information.\n"
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
  SQL_INSTANCES="$(sudo gcloud sql instances list | grep edubox-mysql- | awk '{printf $1}')"
  # Check if instance exists
  if [ "$(grep -c "edubox-mysql-$1-" <<< "$SQL_INSTANCES")" -eq 0 ]; then
    printf "%s!! No SQL instances found in environment \"$1\"! Make sure you have created one.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  # Check if multiple instances exist
  if [ "$(grep -c "edubox-mysql-$1-" <<< "$SQL_INSTANCES")" -gt 1 ]; then
    printf "## Choose which instance you want to backup.%s\n" "${ENDCOL}"
    while IFS= read -r line
    do
      printf "%s. %s\n" "${COUNTER}" "${line}"
      COUNTER=$((COUNTER + 1))
    done <<< "${SQL_INSTANCES}"
    printf "%s?? Enter a number from above list:%s " "${GRN}" "${ENDCOL}"
    read -n 1 -r
    SQL_INSTANCE="$(grep --line-number "${REPLY}" "${SQL_INSTANCES}")"
  elif [ "$(grep -c "edubox-mysql-$1-" <<< "$SQL_INSTANCES")" -eq 1 ]; then
    SQL_INSTANCE="${SQL_INSTANCES}"
    printf "%s## Only 1 SQL instance was found. Using %s. %s\n" "${GRN}" "${SQL_INSTANCE}" "${ENDCOL}"
  fi
}

function backup() {
  printf "\n%s## Creating backup for SQL instance...\n" "${GRN}"
  printf "## Choose a name for your backup file.%s
  1. [instance-name]-Backup-File-[date]-[time]
  2. [instance-name]-Weekly-Backup-File-[date]-[time]
  3. Enter a custom name
  4. Cancel" "${ENDCOL}"
  TIME_START=$(date +%s)
  while true; do
    printf "\n%s?? Enter a number between 1 and 4:%s " "${GRN}" "${ENDCOL}"
    read -n 1 -r
    case $REPLY in
      "1")
        DESCRIPTION="${SQL_INSTANCE}-Backup-File-${CURRDATE}-${CURRTIME}"
        if [[ $(gcloud sql instances list --filter=status:ACTIVE --format="value(NAME)") =~ ${SQL_INSTANCE} ]]; then
          gcloud sql backups create --instance "${SQL_INSTANCE}" --location "${REGION}" --description "${DESCRIPTION}"
        else
          printf "%s## Instance is not running. Starting instance first...%s" "${GRN}" "${ENDCOL}"
          gcloud sql instances patch "${SQL_INSTANCE}" --activation-policy ALWAYS && gcloud sql backups create \
          --instance "${SQL_INSTANCE}" --location "${REGION}" --description "${DESCRIPTION}" && gcloud sql instances \
          patch "${SQL_INSTANCE}" --activation-policy NEVER && printf "\n%s## Done. Instance was stopped.%s" "${GRN}" "${ENDCOL}"
        fi
        break
        ;;
      "2")
        DESCRIPTION="${SQL_INSTANCE}-Weekly-Backup-File-${CURRDATE}-${CURRTIME}"
        if [[ $(gcloud sql instances list --filter=status:ACTIVE --format="value(NAME)") =~ ${SQL_INSTANCE} ]]; then
          gcloud sql backups create --instance "${SQL_INSTANCE}" --location "${REGION}" --description "${DESCRIPTION}"
        else
          printf "\n%s## Instance is not running. Starting instance first...%s " "${GRN}" "${ENDCOL}"
          gcloud sql instances patch "${SQL_INSTANCE}" --activation-policy ALWAYS && gcloud sql backups create \
          --instance "${SQL_INSTANCE}" --location "${REGION}" --description "${DESCRIPTION}" && gcloud sql instances \
          patch "${SQL_INSTANCE}" --activation-policy NEVER && printf "\n%s## Done. Instance was stopped.%s" "${GRN}" "${ENDCOL}"
        fi
        break
        ;;
      "3")
        printf "\n## Enter a custom name for your backup: "
        read -re
        DESCRIPTION="${REPLY}"
        if [[ $(gcloud sql instances list --filter=status:ACTIVE --format="value(NAME)") =~ ${SQL_INSTANCE} ]]; then
          gcloud sql backups create --instance "${SQL_INSTANCE}" --location "${REGION}" --description "${DESCRIPTION}"
        else
          printf "\n%s## Instance is not running. Starting instance first...%s " "${GRN}" "${ENDCOL}"
          gcloud sql instances patch "${SQL_INSTANCE}" --activation-policy ALWAYS && gcloud sql backups create \
          --instance "${SQL_INSTANCE}" --location "${REGION}" --description "${DESCRIPTION}" && gcloud sql instances \
          patch "${SQL_INSTANCE}" --activation-policy NEVER && printf "\n%s## Done. Instance was stopped.%s" "${GRN}" "${ENDCOL}"
        fi
        break
        ;;
      "4")
        printf "\n"
        [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
        ;;
      * )
        printf "\n%s!! Please enter a number between 1 and 4.%s" "${RED}" "${ENDCOL}"
        ;;
    esac
  done
  printf "\n%s## Creating backup completed.\n" "${GRN}"
  TIME_END=$(date +%s)
	TIME_CREATION=$((TIME_END - TIME_START))
	printf "## Time elapsed: %s seconds.\n%s" "${TIME_CREATION}" "${ENDCOL}"
}

# 1. Parameter -h | --help
function help() {
	echo "
NAME
	Backup script EduBox - IP.05

DESCRIPTION
	This is the backup script made for EduBox.
	Create a backup for the sql instances for both production and testing environments.

USAGE: sudo ./backup.sh test | prod | (-h | --help)

ARGUMENTS
	test			      This starts the backup process for the testing environment
	prod			      This starts the backup process for the production environment
	--help or -h		  Shows the help page

EXAMPLES
	sudo ./backup.sh test (creates backup for the testing environment)
	sudo ./backup.sh prod (creates backup for the production environment)

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
case $1 in
  "test"|"prod")
    if [ $# -ne 1 ]; then
      printf "%s!! Wrong arguments specified. Only one argument is allowed. (Use ./backup.sh -h | --help for help)%s" "${RED}" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
    init
    checkSql "$1"
    backup
    ;;
  "-h"|"--help")
    help
    ;;
  *)
    printf "%s!! Wrong arguments specified. (Use ./backup.sh -h | --help for help)%s" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    ;;
esac
[[ "$0" == "$BASH_SOURCE" ]] && exit 0 || return 0;
