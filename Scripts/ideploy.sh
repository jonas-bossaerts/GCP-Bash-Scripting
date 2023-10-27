#!/bin/bash
# shellcheck disable=SC2128
####################################################################################
#
#   FILE: ideploy.sh
#   USAGE: sudo ./ideploy.sh [ ((test | prod) -d) | deleteall ] -h
#   DESCRIPTION: Create the Google Cloud environment with MySQL, Cloud Storage,
#				 Load balancers & more.
#	  OPTIONS: ---
#   REQUIREMENTS: Root permissions when executing.
#                 Script adeploy.sh in same directory as ideploy.sh.
#                 Google Cloud service account
#	  BUGS: ---
#	  NOTES: ---
#	  AUTHOR: Jonas Bossaerts
#	  COMPANY: KdG
#	  VERSION: 2.0.0
#	  CREATED: 28/04/2021
#   REVISION: ---
#
####################################################################################

#############
# VARIABLES #
#############

## SCRIPT
GRN=$'\e[1;32m'
RED=$'\e[1;31m'
ENDCOL=$'\e[0m'
LOGFILE_DIR="/var/log/EduBox/"
LOGFILE="ideploy.log"
TOTAL_TIME_ELAPSED=0
CURRDATE=$(date +"%d%m%y")
VERBOSE_MODE=false

## GOOGLE CLOUD PLATFORM
# PROJECT
PROJECT_ID="ip-deployment"
ZONE="europe-west1-b"
REGION="europe-west1"
SERV_ACC_KEY_FILE="./gcloudSA.json"
SERV_ACC_EMAIL="edubox-ideploy@ip-deployment.iam.gserviceaccount.com"
# VM INSTANCE
VM_NAME="edubox-ubuntu"
VM_PROJECT="ubuntu-os-cloud"
VM_FAMILY="ubuntu-1804-bionic-v20210415"
VM_MACHINE_TYPE="e2-medium"
NUMBER_CPUS="4"
MEMORY_SIZE="15360MB"
# DATABASE
INSTANCE_NAME="edubox-mysql-test-$CURRDATE"
INSTANCE_NAME_PROD="edubox-mysql-prod-$CURRDATE"
# VPC
VPC_NETWORK_NAME="default"
# FIREWALL
FIREWALL_TEST="allow-http-8080"
FIREWALL_HTTP="fw-allow-http"
FIREWALL_PROD_FRONT="allow-front-end-production"
FIREWALL_PROD_BACK="allow-back-end-production"
# STORAGE
BUCKET_LOCATION="europe-west1"
STORAGE_CLASS="standard"
BUCKET_NAME="edubox-storage"
# VM INSTANCE GROUPS
PROD_VM_NAME="edubox-group-1"
PROD_VM_TEMP="edubox-template-1"
HEALTH_CHECK_PROD="healthcheck-group"
# LOAD BALANCER
PROD_EXTERNAL_IP="production-external-ip-1"
HTTPS_HEALTH_CHECK="dotnet-health-check-1"
BACKEND_SERVICE="backend-service-1"
URL_MAP="web-map-https"
PROD_IP=""
## REDIS
REDIS_INSTANCE="edubox-redis"
REDIS_CONNECTION_STRING=""
## DNS
MANAGED_ZONE_NAME="edubox-dns-zone"
MANAGED_ZONE_DESCRIPTION="Managed DNS zone for EduBox production environment."
DNS_NAME="edubox.be."
DNSSEC_ENABLED="on"
DOMAIN_NAME="edubox.be"

#############
# FUNCTIONS #
#############
# 0. Initializer
function init() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  printf "%s## Running initializer...\n" "${GRN}"
  # Check if root
  printf "## Checking permissions... (1/6)%s\n" "${ENDCOL}"
  if [ "$EUID" -ne 0 ]; then
    printf "%s!! Error: Please run ideploy.sh as root." "${RED}"
    printf "## Use sudo ./ideploy.sh --help for more information.\n"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%s## Done.\n" "${GRN}"
  # Create log file
  printf "## Creating log file %s%s... (2/6)%s\n" "${LOGFILE_DIR}" "${LOGFILE}" "${ENDCOL}"
  mkdir -p "$LOGFILE_DIR"
  touch "$LOGFILE_DIR"/"$LOGFILE"
  if [ "${VERBOSE_MODE}" == false ];  then
    exec 2>"$LOGFILE_DIR"/"$LOGFILE"
  fi
  printf "%s## Done.\n" "${GRN}"
  # Check if adeploy.sh is present in same directory
  printf "## Locating script adeploy.sh... (3/6)%s\n" "${ENDCOL}"
  if [ ! -f ./adeploy.sh ]; then
    printf "%s!! Error: File adeploy.sh is missing or could not be found." "${RED}"
    printf "## adeploy.sh should exist in the present working directory.\n"
    printf "## Use ideploy.sh --help or check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%s## Done.\n" "${GRN}"
  # Check if gcloudSA.json is present in same directory
  printf "## Locating file gcloudSA.json... (4/6)%s\n" "${ENDCOL}"
  if [ ! -f ./gcloudSA.json ]; then
    printf "%s!! Error: File gcloudSA.json is missing or could not be found." "${RED}"
    printf "## gcloudSA.json should exist in the present working directory.\n"
    printf "## Use ideploy.sh --help or check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  # Perform gcloud SDK check/install to prevent duplicate entries for the cloud-sdk repo
  printf "%s## Checking if gcloud SDK has been installed... (5/6)%s\n" "${GRN}" "${ENDCOL}"
  # Check SDK
  if [ -z "$(apt list -qq google-cloud-sdk --installed)" ]; then
    gcloud_install
  fi
  printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  # Perform gcloud service account check
  printf "%s## Checking if gcloud service account has been configured... (6/6)%s\n" "${GRN}" "${ENDCOL}"
  if [[ ! $(gcloud auth list --filter=status:ACTIVE --format="value(account)") =~ $SERV_ACC_EMAIL ]]; then
    gcloud_config
  fi
  printf "%s## Done.\n" "${GRN}"
  ENDTIME=$(date +%s)
  TIME_ELAPSED=$((ENDTIME - STARTTIME))
  printf "## Time elapsed: %s seconds.\n" "${TIME_ELAPSED}"
  printf "## Initialization complete.\n%s" "${ENDCOL}"
  TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
}

# 1. Parameter -h | --help
function help() {
  echo "
NAME
	Deployment script EduBox - IP.05

DESCRIPTION
	This is the automatic deployment script made for EduBox.
	Create the Google Cloud environment with MySQL, Cloud Storage, Load balancers & more.

USAGE: sudo ./ideploy.sh [ ((test | prod) -d) | deleteall ] -h

ARGUMENTS
	test			        This starts the deployment of the testing environment
	prod			        This starts the deployment of the production environment
	deleteall		      Deletes everything - Both environments and all backups
	--help or -h		  Shows the help page
	--delete or -d    Deletes the testing or production environment, depending on which was chosen

EXAMPLES
	sudo ./ideploy.sh test (creates and deploys the testing environment)
	sudo ./ideploy.sh prod (creates and deploys the production environment)
	sudo ./ideploy.sh test -d | --delete (deletes testing environment)
	sudo ./ideploy.sh prod -d | --delete (deletes production environment)
	sudo ./ideploy.sh deleteall

REQUIREMENTS: Root permissions, gcloud service account, script adeploy.sh and key file gcloudSA.json in pwd.
AUTHOR: Jonas Bossaerts & Senna Pex
COMPANY: KdG
VERSION: 2.0.0
CREATED: 24/04/2021"
}

## 2. Create Test/Prod environment
function create_environment_test() {
  create_sql
  create_storage
  create_instance
  create_firewall_test
  reset_adeploy
}
function create_environment_prod() {
  create_sql_prod
  create_instance_template
  create_storage
  create_instance_group
  create_reserve_ip_prod
  create_load_balancer
  create_memorystore
  create_firewalls_prod
  configure_dns
  reset_adeploy
}
# 2.1.1 Create single GCP CE - VM instance (startup-script=adeploy.sh)
function create_instance() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  printf "\n%s## Creating a GCP Compute Engine VM instance...%s\n" "${GRN}" "${ENDCOL}"
  #edit adeploy.sh before passing as startup script to add gcloud compatibility (2.1.2)
  edit_adeploy
  #creating instance
  if gcloud compute \
    --project="${PROJECT_ID}" instances create "${VM_NAME}" \
    --zone=${ZONE} \
    --network="${VPC_NETWORK_NAME}" \
    --machine-type="${VM_MACHINE_TYPE}" \
    --tags=test,http-server,https-server \
    --image=${VM_FAMILY} \
    --image-project=${VM_PROJECT} \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard \
    --metadata-from-file startup-script="./adeploy.sh"; then
    # confirmation message
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_CREATION}"
    printf "## Instance successfully created.\n%s" "${ENDCOL}"
    sed -i "s/SQL_IP\=.*/SQL_IP=\"\"/" ./adeploy.sh
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
  else
    if [ -f ./adeploy.sh.bak ]; then reset_adeploy; fi
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
    printf "%s!! Creating compute instance failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
}
# 2.1.2 Edit adeploy.sh before passing as startup-script
function edit_adeploy() {
  touch adeploy.sh.bak
  cp adeploy.sh adeploy.sh.bak
  local SQL_IP
  if [ "$1" == "prod" ]; then
    SQL_IP=$(gcloud sql instances describe "${INSTANCE_NAME_PROD}" | grep ipAddress: | awk '{printf $3}')
  else
    SQL_IP=$(gcloud sql instances describe "${INSTANCE_NAME}" | grep ipAddress: | awk '{printf $3}')
  fi
  local FUNC_A
  local FUNC_B
  # shellcheck disable=SC2016
  FUNC_A='function connect_to_storage() {\nsed -i "s\/\\"GoogleCloudStorageBucket\\": \\".*\\"\/\\"GoogleCloudStorageBucket\\": \\"$BUCKET_NAME\\"\\n\/" \/tmp\/EduBox\/src\/Edubox.Presentation\/appsettings.json\n}'
  # shellcheck disable=SC2016
  FUNC_B='function connect_to_redis() {\nsed -i "s\/redis_conn_string_placeholder\/$REDIS_CONNECTION_STRING\/" \/tmp\/EduBox\/src\/Edubox.Presentation\/appsettings.json\n}'
  local MAIN_A
  # shellcheck disable=SC2016
  MAIN_A='printf "\\n%s## Providing connection string for Cloud Storage...%s\\n" "${grn}" "${endcol}"\nif connect_to_storage; then\n  printf "%s## Successfully added storage connection string.%s\\n" "${grn}" "${endcol}"\nelse\n  printf "%s!! Connecting to storage failed.\\n" "${red}"\n  printf "## Check log in %s%s for more information.\\n" "$logfile_dir" "$logfile"\n  printf "## Exiting...%s\\n" "${endcol}"\n  [[ "$0" == "$BASH_SOURCE" ]] \&\& exit 1 || return 1\nfi'
  # shellcheck disable=SC2016
  MAIN_B='printf "\\n%s## Providing connection string for Redis...%s\\n" "${grn}" "${endcol}"\nif connect_to_redis; then\n  printf "%s## Successfully added Redis connection string.%s\\n" "${grn}" "${endcol}"\nelse\n  printf "%s!! Connecting to Redis failed.\\n" "${red}"\n  printf "## Check log in %s%s for more information.\\n" "$logfile_dir" "$logfile"\n  printf "## Exiting...%s\\n" "${endcol}"\n  [[ "$0" == "$BASH_SOURCE" ]] \&\& exit 1 || return 1\nfi'
  # Use hooks provided in adeploy.sh
  sed -i "s/SQL_IP\=.*/SQL_IP=\"${SQL_IP}\"/" ./adeploy.sh
  sed -i "s/#variable_hook/BUCKET_NAME=\"${BUCKET_NAME}\"\nREDIS_CONNECTION_STRING=\"${REDIS_CONNECTION_STRING}\"/" ./adeploy.sh
  sed -i "s/#function_hook/${FUNC_A}\n${FUNC_B}/" ./adeploy.sh
  sed -i "s/#main_before_build_hook/${MAIN_A}\n${MAIN_B}/" ./adeploy.sh
}
# 2.1.3 Reset adeploy.sh
function reset_adeploy() {
  cp adeploy.sh.bak adeploy.sh
  rm adeploy.sh.bak
}
# 2.2. Create GCP Cloud SQL - MySQL instance
function create_sql() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)

  SQL_INSTANCES="$(sudo gcloud sql instances list | grep "edubox-mysql-test-[0-9]+" | awk '{printf $1}')"
  if [ -z "${SQL_INSTANCES}" ]; then
    printf "\n%s## Creating a GCP MySQL database...%s\n" "${GRN}" "${ENDCOL}"
    #creating MySQL database
    if gcloud beta sql instances create "${INSTANCE_NAME}" \
      --project="${PROJECT_ID}" \
      --network="${VPC_NETWORK_NAME}" \
      --cpu="${NUMBER_CPUS}" \
      --memory="${MEMORY_SIZE}" \
      --region="${REGION}" \
      --no-assign-ip \
      --storage-auto-increase; then
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_CREATION}"
      printf "## MySQL testing instance successfully created.\n"
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    else
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
      printf "%s!! Creating MySQL database for testing environment failed.\n" "${RED}"
      printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
      printf "## Exiting...%s\n" "${ENDCOL}"
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
    printf "\n## Configuring default MySQL user...%s\n" "${ENDCOL}"
    if gcloud sql users set-password root --host=% --instance="${INSTANCE_NAME}" --password="root"; then
      printf "## MySQL user successfully configured.\n"
    else
      printf "%s!! Configuring MySQL user for testing environment failed.\n" "${RED}"
      printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
      printf "## Exiting...%s\n" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
  elif [ "$(grep -c "edubox-mysql-[0-9]+" <<<"$SQL_INSTANCES")" -gt 1 ]; then
    printf "## Choose which instance you want to use.%s\n" "${ENDCOL}"
    while IFS= read -r line; do
      printf "%s. %s\n" "${COUNTER}" "${line}"
      COUNTER=$((COUNTER + 1))
    done <<<"${SQL_INSTANCES}"
    printf "%s?? Enter a number from above list:%s " "${GRN}" "${ENDCOL}"
    read -n 1 -r
    "${INSTANCE_NAME}"="$(grep --line-number "${REPLY}" "${SQL_INSTANCES}")"
  else
    "${INSTANCE_NAME}"="${SQL_INSTANCES}"
    printf "%s!! There is already a MySQL client created for the test environment.\n" "${RED}"
    printf "## Using this MySQL client: %s %s\n" "${INSTANCE_NAME}" "${ENDCOL}"
  fi

}
function create_sql_prod() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  SQL_INSTANCES="$(sudo gcloud sql instances list | grep "edubox-mysql-prod" | awk '{printf $1}')"
  if [ -z "${SQL_INSTANCES}" ]; then
    printf "\n%s## Creating a GCP MySQL instance...%s\n" "${GRN}" "${ENDCOL}"
    #creating MySQL database
    if gcloud beta sql instances create "${INSTANCE_NAME_PROD}" \
      --project="${PROJECT_ID}" \
      --network="${VPC_NETWORK_NAME}" \
      --cpu="${NUMBER_CPUS}" \
      --memory="${MEMORY_SIZE}" \
      --region="${REGION}" \
      --no-assign-ip \
      --storage-auto-increase; then
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED+=$TIME_ELAPSED

      printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_CREATION}"
      printf "## MySQL instance successfully created.\n%s" "${ENDCOL}"
    else
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
      printf "%s!! Creating MySQL database for production environment failed.\n" "${RED}"
      printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
      printf "## Exiting...%s\n" "${ENDCOL}"
      TOTAL_TIME_ELAPSED+=$TIME_ELAPSED
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
    printf "\n## Configuring default MySQL user...%s\n" "${ENDCOL}"
    if gcloud sql users set-password root \
      --host=% --instance="${INSTANCE_NAME_PROD}" --password="root"; then
      printf "## MySQL user successfully configured.\n"
    else
      printf "%s!! Configuring MySQL user for production environment failed.\n" "${RED}"
      printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
      printf "## Exiting...%s\n" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
  elif [ "$(grep -c "edubox-mysql-prod" <<<"${SQL_INSTANCES}")" -gt 1 ]; then
    printf "## Choose which instance you want to use.%s\n" "${ENDCOL}"
    while IFS= read -r line; do
      printf "%s. %s\n" "${COUNTER}" "${line}"
      COUNTER=$((COUNTER + 1))
    done <<<"${SQL_INSTANCES}"
    printf "%s?? Enter a number from above list:%s " "${GRN}" "${ENDCOL}"
    read -n 1 -r
    "${INSTANCE_NAME_PROD}"="$(grep --line-number "${REPLY}" "${SQL_INSTANCES}")"
  else
    "${INSTANCE_NAME_PROD}"="${SQL_INSTANCES}"
    printf "%s!! There is already a MySQL client created for the prod environment.\n" "${GRN}"
    printf "## Using this MySQL client: %s %s\n" "${INSTANCE_NAME_PROD}" "${ENDCOL}"
  fi

}
# 2.3. Create GCP Cloud Storage
function create_storage() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)

  BUCKETS=$(gsutil ls)
  if [ -z "${BUCKETS}" ]; then
    printf "\n%s## Creating a GCP Cloud Storage bucket...%s\n" "${GRN}" "${ENDCOL}"
    #creating Cloud Storage
    if gsutil mb -p "${PROJECT_ID}" -c "${STORAGE_CLASS}" -l "${BUCKET_LOCATION}" -b on gs://"${BUCKET_NAME}" && gsutil iam ch allUsers:objectViewer gs://"${BUCKET_NAME}"; then
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
      printf "%s## Cloud Storage successfully created.%s\n" "${GRN}" "${ENDCOL}"
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    else
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
      printf "%s!! Creating Cloud Storage failed.\n" "${RED}"
      printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
      printf "## Exiting...%s\n" "${ENDCOL}"
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi

  elif [ "${BUCKETS}" -gt 1 ]; then
    printf "## Choose which bucket you want to use.%s\n" "${ENDCOL}"
    while IFS= read -r line; do
      printf "%s. %s\n" "${COUNTER}" "${line}"
      COUNTER=$((COUNTER + 1))
    done <<<"${SQL_INSTANCES}"
    printf "%s?? Enter a number from above list:%s " "${GRN}" "${ENDCOL}"
    read -n 1 -r
    "${BUCKET_NAME}"="$(grep --line-number "${REPLY}" "${BUCKETS}")"
  else
    "${BUCKET_NAME}"="${BUCKETS}"
    printf "%s!! Using this bucket: ${BUCKET_NAME}\n %s" "${GRN}" "${ENDCOL}"
  fi

}
# 2.5. Create GCP Firewall rules
function create_firewall_test() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  printf "\n%s## Creating firewall rules for test environment...%s\n" "${GRN}" "${ENDCOL}"
  #creating firewall rules
  if
    gcloud compute firewall-rules create "${FIREWALL_HTTP}" --allow=tcp:80 --target-tags=test \
    && gcloud compute firewall-rules create "${FIREWALL_TEST}" --allow=tcp:8080 --target-tags=test
  then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
    printf "%s## Test firewalls were successfully created.%s\n" "${GRN}" "${ENDCOL}"
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
    printf "%s!! Error: Creating test firewalls failed%s\n" "${RED}" "${ENDCOL}"
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi

}
function create_firewalls_prod() {
  # Firewall rule for health check
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  printf "\n%s## Starting process to create production firewalls...  (1/4)\n" "${GRN}" "${ENDCOL}"
  printf "\n%s## Creating health check firewall for production...  (2/5)\n" "${GRN}" "${ENDCOL}"
  if gcloud compute firewall-rules create fw-allow-health-check \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags="${HEALTH_CHECK_PROD}" \
    --rules=tcp:80; then
    printf "%s## Health check firewall for production was successfully created.%s\n" "${GRN}" "${ENDCOL}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
    printf "%s!! Error: Creating health check firewall for production failed%s\n" "${RED}" "${ENDCOL}"
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  # Firewall rule for backend
  printf "\n%s## Creating firewall backend for production...  (3/5)\n" "${GRN}" "${ENDCOL}"
  if gcloud compute --project="${PROJECT_ID}" firewall-rules create "${FIREWALL_PROD_BACK}" \
    --priority=1000 \
    --action=allow \
    --rules=tcp:8080 \
    --source-ranges=10.132.0.0/20; then
    printf "%s## Firewall backend for production was successfully created.%s\n" "${GRN}" "${ENDCOL}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
    printf "%s!! Error: Creating firewall backend for production failed%s\n" "${RED}" "${ENDCOL}"
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  # Firewall rule for frontend
  printf "\n%s## Creating firewall frontend for production...  (4/5)\n" "${GRN}" "${ENDCOL}"
  if gcloud compute firewall-rules create "${FIREWALL_PROD_FRONT}" \
    --priority=1000 \
    --action=allow \
    --rules=tcp:80 \
    --source-ranges=10.132.0.0/20; then
    printf "%s## Firewall frontend for production was successfully created.%s\n" "${GRN}" "${ENDCOL}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
    printf "%s!! Error: Creating firewall frontend for production failed%s\n" "${RED}" "${ENDCOL}"
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  ENDTIME=$(date +%s)
  TIME_ELAPSED=$((ENDTIME - STARTTIME))
  printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_CREATION}" "${ENDCOL}"
  TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
}
# 2.7. Create GCP Memorystore with Redis
function create_memorystore() {
  printf "\n%s## Creating Memorystore instance...\n" "${GRN}" "${ENDCOL}"
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  local REDIS_IP
  local REDIS_PORT
  STARTTIME=$(date +%s)
  if gcloud redis instances create ${REDIS_INSTANCE} --size=1 --region=${REGION} --redis-version=redis_4_0; then
    REDIS_IP=$(sudo gcloud redis instances describe ${REDIS_INSTANCE} --region=${REGION} | grep host: | awk '{printf $2}')
    REDIS_PORT=$(sudo gcloud redis instances describe ${REDIS_INSTANCE} --region=${REGION} | grep port | awk '{printf $2}')
    REDIS_CONNECTION_STRING="${REDIS_IP}:${REDIS_PORT}"
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
    printf "\n%s## Memorystore instance successfully created.\n" "${GRN}" "${ENDCOL}"
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
  else
    printf "%s## Time elapsed: %s seconds.%s\n" "${RED}" "${TIME_ELAPSED}" "${ENDCOL}"
    printf "%s!! Creating Memorystore failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
}
# 2.8. Create GCP instance template
function create_instance_template() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  local TEMPLATE
  STARTTIME=$(date +%s)
  TEMPLATE=$(gcloud compute instance-templates list)
  edit_adeploy "prod"
  if [ -z "${TEMPLATE}" ]; then
    printf "\n%s## Creating instance template...%s\n" "${GRN}" "${ENDCOL}"
    if gcloud beta compute --project=ip-deployment instance-templates create "${PROD_VM_TEMP}" --machine-type=e2-medium \
      --network=projects/ip-deployment/global/networks/default --network-tier=STANDARD --metadata-from-file startup-script="./adeploy.sh" \
      --maintenance-policy=MIGRATE --service-account=554984403185-compute@developer.gserviceaccount.com \
      --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
      --tags=prod,http-server,https-server,"${HEALTH_CHECK_PROD}" --image="${VM_FAMILY}" --image-project="${VM_PROJECT}" --boot-disk-size=25GB \
      --boot-disk-type=pd-balanced --boot-disk-device-name="${PROD_VM_TEMP}"; then
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
      printf "%s## Production template was successfully created.%s\n" "${GRN}" "${ENDCOL}"
    else
      if [ -f ./adeploy.sh.bak ]; then reset_adeploy; fi
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
      printf "%s!! Error: Creating production template failed%s\n" "${RED}" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
  elif [ "$(grep -c "edubox-template-" <<<"${TEMPLATE}")" -gt 1 ]; then
    printf "## Choose which template you want to use.%s\n" "${ENDCOL}"
    while IFS= read -r line; do
      printf "%s. %s\n" "${COUNTER}" "${line}"
      COUNTER=$((COUNTER + 1))
    done <<<"$${TEMPLATE}"
    printf "%s?? Enter a number from above list:%s " "${GRN}" "${ENDCOL}"
    read -n 1 -r
    "${PROD_VM_TEMP}"="$(grep --line-number "${REPLY}" "${TEMPLATE}")"
  else
    "${PROD_VM_TEMP}"="${TEMPLATE}"
    printf "%s!! There is already a template created for the prod environment.\n" "${GRN}"
    printf "## Using this template: %s %s\n" "${PROD_VM_TEMP}" "${ENDCOL}"
  fi

}
# 2.9. Create GCP instance group
function create_instance_group() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  local GROUP
  STARTTIME=$(date +%s)
  GROUP=$(gcloud compute instance-groups list)

  if [ -z "${GROUP}" ]; then
    # Health check
    printf "\n%s## Creating instance group...%s" "${GRN}" "${ENDCOL}"
    printf "\n%s## Creating HTTPS health check...  (1/4)%s\n" "${GRN}" "${ENDCOL}"
    if gcloud compute health-checks create http "${HEALTH_CHECK_PROD}" --check-interval=300s --timeout=30s --port "80" --request-path "/"; then
      printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
    else
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
      printf "%s!! Error: Creating health checks for production failed%s\n" "${RED}" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
    # Instance group
    printf "%s## Configuring instance group...  (2/4)%s\n" "${GRN}" "${ENDCOL}"
    if gcloud compute --project="${PROJECT_ID}" instance-groups managed create "${PROD_VM_NAME}" \
      --base-instance-name="${PROD_VM_NAME}" --template="${PROD_VM_TEMP}" --size=1 --zone="${ZONE}" --health-check="${HEALTH_CHECK_PROD}" &&
      gcloud compute instance-groups managed update ${PROD_VM_NAME} --zone="${ZONE}" --initial-delay 600; then
      printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
    else
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
      printf "%s!! Error: Creating instance group failed.%s\n" "${RED}" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
    # Auto-scaling
    printf "%s## Setting up autoscaling... (3/4)%s\n" "${GRN}" "${ENDCOL}"
    if gcloud beta compute --project "${PROJECT_ID}" instance-groups managed set-autoscaling "${PROD_VM_NAME}" \
      --zone "${ZONE}" --cool-down-period "600" --max-num-replicas "10" --min-num-replicas "1" \
      --target-cpu-utilization "0.8" --mode "on"; then
      printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
    else
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
      printf "%s!! Error: Autoscaling for production failed%s\n" "${RED}" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
    # Named ports
    printf "%s## Setting up named ports for production...  (4/4)%s\n" "${GRN}" "${ENDCOL}"
    if gcloud compute instance-groups set-named-ports "${PROD_VM_NAME}" \
      --named-ports=http:80,http-api:8080,https:443 \
      --zone="${ZONE}"; then
      printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
    else
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
      printf "%s!! Error: Setting up named ports failed.%s\n" "${RED}" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
  elif [ "${GROUP}" -gt 1 ]; then
    printf "## Choose which instance-group you want to use.%s\n" "${ENDCOL}"
    while IFS= read -r line; do
      printf "%s. %s\n" "${COUNTER}" "${line}"
      COUNTER=$((COUNTER + 1))
    done <<<"${SQL_INSTANCES}"
    printf "%s?? Enter a number from above list:%s " "${GRN}" "${ENDCOL}"
    read -n 1 -r
    "${PROD_VM_NAME}"="$(grep --line-number "${REPLY}" "${GROUP}")"
  else
    "${PROD_VM_NAME}"="${GROUP}"
    printf "%s!! Using this group: ${PROD_VM_NAME}\n %s" "${GRN}" "${ENDCOL}"
  fi
  printf "%s## Instance group successfully created.%s\n" "${GRN}" "${ENDCOL}"

}
# 2.10. Reserve static external ip address
function create_reserve_ip_prod() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  RESERVE_IP="$(gcloud compute addresses list | grep "production" | awk '{printf $1}')"
  if [ -z "${RESERVE_IP}" ]; then
    printf "\n%s## Reserving static external ip address...%s\n" "${GRN}" "${ENDCOL}"
    if gcloud compute addresses create "${PROD_EXTERNAL_IP}" \
      --project="${PROJECT_ID}" --global --network-tier=PREMIUM; then
      PROD_IP=$(gcloud compute addresses describe "${PROD_EXTERNAL_IP}" --global | grep address: | awk '{printf $2}')
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
      printf "%s## Static external ip address was successfully reserved.%s\n" "${GRN}" "${ENDCOL}"
    else
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
      printf "%s!! Error: Failed to reserve static external ip address.%s\n" "${RED}" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi

  elif [ "${RESERVE_IP}" -gt 1 ]; then
    printf "## Choose which IP you want to use.%s\n" "${ENDCOL}"
    while IFS= read -r line; do
      printf "%s. %s\n" "${COUNTER}" "${line}"
      COUNTER=$((COUNTER + 1))
    done <<<"${SQL_INSTANCES}"
    printf "%s?? Enter a number from above list:%s " "${GRN}" "${ENDCOL}"
    read -n 1 -r
    "${PROD_EXTERNAL_IP}"="$(grep --line-number "${REPLY}" "${RESERVE_IP}")"
  else
    "${PROD_EXTERNAL_IP}"="${RESERVE_IP}"
    printf "%s!! Using this reserved IP: ${PROD_EXTERNAL_IP}\n %s" "${GRN}" "${ENDCOL}"
  fi

}
# 2.11. Create GCP load balancer
function create_load_balancer() {
  # create dotnet health check
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  printf "\n%s## Creating load balancer...%s" "${GRN}" "${ENDCOL}"
  printf "\n%s## Creating health checks for load balancer... (1/8)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud compute health-checks create http "${HTTPS_HEALTH_CHECK}" \
    --global \
    --request-path="/" \
    --port=80; then
    printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
    printf "%s!! Error: Creating health check for load balancer failed%s\n" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  # create backend service
  printf "%s## Creating backend service for load balancer... (2/8)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud compute backend-services create "${BACKEND_SERVICE}" \
    --protocol=HTTP \
    --global \
    --port-name=http \
    --health-checks="${HTTPS_HEALTH_CHECK}"; then
    printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
    printf "%s!! Error: Creating backend service for load balancer failed%s\n" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  # add instance group to the backend service
  printf "%s## Adding instance group to backend service... (3/8)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud compute backend-services add-backend "${BACKEND_SERVICE}" \
    --instance-group="${PROD_VM_NAME}" \
    --instance-group-zone="${ZONE}" \
    --global \
    --balancing-mode="UTILIZATION"; then
    printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
    printf "%s!! Error: Adding instance group to backend service failed%s\n" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  # create an URL MAP to route incoming request
  printf "%s## Creating URL MAP to route incoming request... (4/8)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud compute url-maps create "${URL_MAP}" --default-service "${BACKEND_SERVICE}" --global; then
    printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
    printf "%s!! Error: Creating URL MAP to route incoming request failed%s\n" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  # create target https proxy
  printf "%s## Creating target https proxy... (5/8)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud compute target-https-proxies create https-lb-proxy --url-map "${URL_MAP}" --ssl-certificates="edubox-ssl-cert" --global; then
    printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
    printf "%s!! Error: Creating target https proxy failed.%s\n" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  # create forwarding rule
  printf "%s## Creating forwarding rule... (6/8)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud compute forwarding-rules create https-content-rule \
    --address="${PROD_EXTERNAL_IP}" \
    --global \
    --target-https-proxy=https-lb-proxy \
    --ports=443; then
    printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
    printf "%s!! Error: Creating forwarding rule failed.%s\n" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  touch loadbalancer.yaml
  echo "kind: compute#urlMap
name: loadbalancerinternal
defaultUrlRedirect:
  redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
  httpsRedirect: True" >./loadbalancer.yaml

  gcloud compute url-maps import loadbalancerinternal \
    --source loadbalancer.yaml \
    --global

  gcloud compute target-http-proxies create http-lb-proxy \
    --url-map=loadbalancerinternal \
    --global

  gcloud compute forwarding-rules create http-content-rule \
    --address="${PROD_EXTERNAL_IP}" \
    --global \
    --target-http-proxy=http-lb-proxy \
    --ports=80
}
# 2.12. Configure GCP Cloud DNS
function configure_dns() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  printf "%s## Configuring the DNS...\n%s" "${GRN}" "${ENDCOL}"
  printf "%s## Creating managed DNS zone... (1/2)%s" "${GRN}" "${ENDCOL}"
  if gcloud dns --project="${PROJECT_ID}" managed-zones create "${MANAGED_ZONE_NAME}" --description="${MANAGED_ZONE_DESCRIPTION}" --dns-name="${DNS_NAME}" \
    --visibility="public" --dnssec-state="${DNSSEC_ENABLED}"; then
    printf "%s## Done." "${GRN}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
    printf "%s!! Error: Creating managed DNS zone failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "## Adding DNS records... (2/2)%s" "${ENDCOL}"
  if gcloud dns --project="${PROJECT_ID}" record-sets transaction start --zone="${MANAGED_ZONE_NAME}" --quiet &&
    gcloud dns --project="${PROJECT_ID}" record-sets transaction add "${PROD_IP}" --name="${DOMAIN_NAME}" --ttl=300 --type=A --zone="${MANAGED_ZONE_NAME}" --quiet &&
    gcloud dns --project="${PROJECT_ID}" record-sets transaction add "${PROD_IP}" --name="*.${DOMAIN_NAME}." --ttl=300 --type=A --zone="${MANAGED_ZONE_NAME}" --quiet &&
    gcloud dns --project="${PROJECT_ID}" record-sets transaction execute --zone="${MANAGED_ZONE_NAME}" --quiet; then
    printf "%s## Done." "${GRN}"
  else
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.%s\n" "${GRN}" "${TIME_ELAPSED}" "${ENDCOL}"
    printf "%s!! Error: Adding DNS records failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  TIME_END=$(date +%s)
  TIME_ELAPSED=$((TIME_END - TIME_START))
  TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
  printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_ELAPSED}"
  printf "## DNS records successfully configured.\n%s" "${ENDCOL}"
}

## 3. Delete Test/Prod environment
function delete_environment() {
  printf "%s!! You are attempting to delete ALL resources within the $1 environment.\n!! This includes all backups.%s Are you sure? (N/y): " "${RED}" "${ENDCOL}"
  read -n 1 -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    printf "\n%s## Exiting...%s\n" "${RED}" "${ENDCOL}"
    # shellcheck disable=SC2128
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "\n%s## Deleting ALL Google Cloud resources and backups in %s environment...\n" "${GRN}" "$1"
  printf "## Deleting resources...%s\n" "${ENDCOL}"
  if [ "$1" == "test" ]; then
    delete_instance
  fi
  if [ "$1" == "prod" ]; then
    delete_load_balancer
    release_static_ip
    delete_prod_instance_group
    delete_prod_template
    delete_redis
  fi
  printf "%s?? Delete storage bucket containing all images?%s (N/y): " "${GRN}" "${ENDCOL}"
  read -n 1 -r
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    delete_cloud_storage
  fi
  printf "\n%s?? Delete application database?%s (N/y): " "${GRN}" "${ENDCOL}"
  read -n 1 -r
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    delete_sql "$1"
  fi
  delete_firewall "$1"
  printf "%## Done.%s\n" "${GRN}" "${ENDCOL}"
  printf "%s## All Google Cloud resources and backups have been successfully deleted.%s\n" "${GRN}" "${ENDCOL}"
}
# 3.1 Delete instance template
function delete_prod_template() {
  # Delete production template
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  printf "%sAttempting to delete the Google Cloud production template... (1/1)%s" "${GRN}" "${ENDCOL}"
  if gcloud compute instances-templates delete "${PROD_VM_TEMP}" --quiet; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## Instance template has been successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting the instance template failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
}
# 3.2 Delete instance group
function delete_prod_instance_group() {
  # Delete production instance group
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  printf "%sAttempting to delete the Google Cloud production instance group... (1/2)%s" "${GRN}" "${ENDCOL}"
  if gcloud compute instance-groups managed delete "${PROD_VM_NAME}" --region "${REGION}" --quiet; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## Instance group has been successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting the instance group failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%sDeleting health check... (2/2)%s" "${GRN}" "${ENDCOL}"
  if gcloud compute health-checks delete "${HEALTH_CHECK_PROD}" --global --quiet; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## Health check successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting health check failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
}
# 3.3 Delete storage
function delete_cloud_storage() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  # Delete the buckets
  printf "\n%sAttempting to delete bucket %s... (1/1)%s\n" "${GRN}" "${BUCKET_NAME}" "${ENDCOL}"
  if gsutil rm -r gs://"${BUCKET_NAME}"; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## Bucket has been successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting Google Cloud Storage Bucket failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "${LOGFILE_DIR}" "${LOGFILE}"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
}
# 3.4 Delete SQL instance
function delete_sql() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  # Delete the instance
  printf "\n%s## Attempting to delete the MySQL database and backups... (1/1)%s\n" "${GRN}" "${ENDCOL}"
  if [ "$1" == "test" ]; then
    if gcloud sql instances delete "${INSTANCE_NAME}" --quiet; then
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
      printf "## Done.\n"
      printf "## MySQL instance has been successfully deleted.%s\n" "${ENDCOL}"
    else
      printf "%s!! Deleting MySQL database for testing environment failed.\n" "${RED}"
      printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
      printf "## Exiting...%s\n" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
  elif [ "$1" == "prod" ]; then
    if gcloud sql instances delete "${INSTANCE_NAME_PROD}" --quiet; then
      ENDTIME=$(date +%s)
      TIME_ELAPSED=$((ENDTIME - STARTTIME))
      TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
      printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
      printf "## Done.\n"
      printf "## MySQL instance has been successfully deleted.%s\n" "${ENDCOL}"
    else
      printf "%s!! Deleting MySQL database for production environment failed.\n" "${RED}"
      printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
      printf "## Exiting...%s\n" "${ENDCOL}"
      [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
  fi
}
# 3.5 Release static ip
function release_static_ip() {
  # Release the external IP
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  printf "%sAttempting to release the external IP... (1/1)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud compute addresses delete "${PROD_EXTERNAL_IP}" --global --quiet; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## Releasing the external IP was successful.%s\n" "${ENDCOL}"
  else
    printf "%s!! Release the external IP for production environment failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
}
# 3.6 Delete load balancer
function delete_load_balancer() {
  # Delete the load balancer
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  printf "%sAttempting to delete the load balancer...\n" "${GRN}"
  printf "%sStarting with deleting forwarding-rules... (1/5)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud compute forwarding-rules delete https-content-rule --global --quiet; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## forwarding-rules are successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting forwarding-rules for production environment failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%sStarting with deleting target https proxies... (2/5)%s" "${GRN}" "${ENDCOL}"
  if gcloud compute target-https-proxies delete https-lb-proxy --global --quiet; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## target https proxies are successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting target https proxies for production environment failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%sStarting with deleting url maps... (3/5)%s" "${GRN}" "${ENDCOL}"
  if gcloud compute url-maps delete "${URL_MAP}" --global --quiet; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## url map is successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting the url map for production environment failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%sStarting with deleting backend-services... (4/5)%s" "${GRN}" "${ENDCOL}"
  if gcloud compute backend-services delete "${BACKEND_SERVICE}" --global --quiet; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## Backend-services are successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting the backend-services for production environment failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%sStarting with deleting health checks ... (5/5)%s" "${GRN}" "${ENDCOL}"
  if gcloud compute health-checks delete "${HTTPS_HEALTH_CHECK}" --global --quiet; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## Health checks api are successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting the Health checks api for production environment failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
}
# 3.7 Delete firewalls
function delete_firewall() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  # Delete the instance
  printf "%sRequesting to delete the firewall rules... (1/1)%s" "${GRN}" "${ENDCOL}"
  if [ "$1" == "test" ]; then
    gcloud compute firewall-rules delete "${FIREWALL_HTTP}" --quiet
    gcloud compute firewall-rules delete "$FIREWALL_TEST" --quiet
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## Firewall rules for testing environment are successfully deleted.%s\n" "${ENDCOL}"

  elif [ "$1" == "prod" ]; then
    gcloud compute firewall-rules delete "${FIREWALL_PROD_FRONT}" --quiet
    gcloud compute firewall-rules delete "${FIREWALL_PROD_BACK}" --quiet
    gcloud compute firewall-rules delete fw-allow-health-check --quiet
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## Firewall rules for production environment are successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting Firewall rules for %s environment failed.\n" "${RED}" "$1"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
}
# 3.8 Delete VM instance
function delete_instance() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  # Stop the instance
  printf "%s## Stopping the VM instance... (1/2)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud compute instances stop "${VM_NAME}" --quiet --zone=${ZONE}; then
    printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
  else
    printf "%s!! Failed to stop VM instance.\n" "${RED}"
    printf "## Has the machine already been stopped? (Ignore this error!)\n"
    printf "## Are you running a VM with a local SSD? (Not supported!)\n"
    printf "## Check log in %s%s for more information.\n" "${LOGFILE_DIR}" "${LOGFILE}"
  fi
  # Delete the instance
  printf "%sAttempting to delete the VM instance... (2/2)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud compute instances delete "${VM_NAME}" --quiet --zone=${ZONE}; then
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
    printf "%s## Time elapsed: %s seconds.\n" "${GRN}" "${TIME_DELETE}"
    printf "## Done.\n"
    printf "## VM Instance has been successfully deleted.%s\n" "${ENDCOL}"
  else
    printf "%s!! Deleting compute engine instance failed.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
}
# 3.9 Delete Redis
function delete_redis() {
  local STARTTIME
  local ENDTIME
  local TIME_ELAPSED
  STARTTIME=$(date +%s)
  # Stop the instance
  printf "%s## Deleting Redis instance... (1/2)%s\n" "${GRN}" "${ENDCOL}"
  if gcloud redis instances delete "${REDIS_INSTANCE}" --quiet --region=${REGION}; then
    printf "%s## Done.%s\n" "${GRN}" "${ENDCOL}"
    ENDTIME=$(date +%s)
    TIME_ELAPSED=$((ENDTIME - STARTTIME))
    TOTAL_TIME_ELAPSED=$((TOTAL_TIME_ELAPSED + TIME_ELAPSED))
  else
    printf "%s!! Failed to delete Redis instance.\n" "${RED}"
    printf "## Check log in %s%s for more information.\n" "${LOGFILE_DIR}" "${LOGFILE}"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
}

## 4. Delete everything: both test & prod environment as well as backups
function delete_all() {
  echo
  read -p "${RED}!! You are attempting to delete ALL resources within the EduBox Google Cloud project. This includes all backups.${ENDCOL} Are you sure? (N/y): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    printf "%s## Exiting...%s\n" "${RED}" "${ENDCOL}"
    # shellcheck disable=SC2128
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  printf "%s## Deleting ALL Google Cloud resources and backups...\n" "${GRN}"
  delete_environment "test"
  delete_environment "prod"
  printf "%s## All Google Cloud resources and backups have been successfully deleted.%s\n" "${GRN}" "${ENDCOL}"
}

## 5. Set up gcloud SDK
function gcloud_install() {
  printf "%s!! The gcloud SDK was not found on this machine.%s\n" "${RED}" "${ENDCOL}"
  printf "%s## Installing gcloud SDK...%s\n" "${GRN}" "${ENDCOL}"
  apt-get install -y apt-transport-https ca-certificates gnupg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" |
    tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
  apt-get update -y && apt-get install -y google-cloud-sdk
  printf "%s## The gcloud SDK has been successfully installed.%s\n" "${GRN}" "${ENDCOL}"
}

## 6. Set up gcloud service account
function gcloud_config() {
  printf "%s!! No active gcloud service account was found on this machine.%s\n" "${RED}" "${ENDCOL}"
  printf "%s## Configuring gcloud service account...%s\n" "${GRN}" "${ENDCOL}"
  # Check for key file
  if [ ! -f ${SERV_ACC_KEY_FILE} ]; then
    printf "%s!! Error: Key file gcloudSA.json is missing or could not be found." "${RED}"
    printf "## gcloudSA.json should be present in the same directory as ideploy.sh.\n"
    printf "## Use ideploy.sh --help or check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
    printf "## Exiting...%s\n" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  gcloud auth activate-service-account "${SERV_ACC_EMAIL}" --key-file="${SERV_ACC_KEY_FILE}" --project="${PROJECT_ID}"
  gcloud config set project "${PROJECT_ID}"
  printf "%s## The gcloud service account has been successfully configured.\n" "${GRN}"
}

#############
#   MAIN    #
#############
# Check parameters
case $1 in
"test")
  init
  if [ -z "$2" ]; then
    create_environment_test
  fi
  ;;
"prod")
  init
  if [ -z "$2" ]; then
    create_environment_prod
  fi
  ;;
"deleteall")
  init
  delete_all "$1"
  ;;
"-h" | "--help")
  help
  ;;
*)
  printf "%sWrong arguments specified. (Use ./ideploy.sh -h | --help for help)%s" "${RED}" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  ;;
esac
case $2 in
"-d" | "--delete")
  if [ "$1" == "test" ]; then
    delete_environment "test"
  elif [ "$1" == "prod" ]; then
    delete_environment "prod"
  else
    printf "%s!! Error: Environment must be either test or prod%s\n" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  ;;
"-h" | "--help")
  help
  ;;
"-v" | "--verbose")
  VERBOSE_MODE=true
  ;;
*)
  if [ -n "$2" ]; then
    printf "%sWrong arguments specified. (Use ./ideploy.sh -h for help)%s" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  ;;
esac
case $3 in
"-v" | "--verbose")
  VERBOSE_MODE=true
  ;;
*)
  if [ -n "$3" ]; then
    printf "%sWrong arguments specified. (Use ./ideploy.sh -h for help)%s" "${RED}" "${ENDCOL}"
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
  ;;
esac
printf "\n%s## Execution of ideploy.sh has been completed. \n" "${GRN}"
printf "## Finished at %s.\n" "$(date +"%T")"
printf "## Total time elapsed: %s seconds.%s\n\n" "${TOTAL_TIME_ELAPSED}" "${ENDCOL}"
[[ "$0" == "$BASH_SOURCE" ]] && exit 0 || return 0
