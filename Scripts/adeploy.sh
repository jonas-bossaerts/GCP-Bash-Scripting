#!/bin/bash
# shellcheck disable=SC2128
####################################################################################
#
#  FILE: adeploy.sh
#  USAGE: sudo ./adeploy.sh
#  DESCRIPTION: Download required components and git clone the application,
#				          then build it on a server. Independent of cloud provider.
#	 OPTIONS: ---
#  REQUIREMENTS: ---
#	 BUGS: ---
#	 NOTES: Use hooks provided in this script to add cloud provider-specific commands
#	          from within your infrastructure deployment script (e.g. ideploy.sh).
#         If not edited before being passed as startup-script, variable SQL_IP will
#           be empty, causing the application to default to a localhost connection.
#	 AUTHOR: Jonas Bossaerts
#	 COMPANY: KdG
#	 VERSION: 3.0.0
#	 CREATED: 28/04/2021
#  REVISION: ---
#
####################################################################################


#############
# VARIABLES #
#############
## GITLAB
PROJ_REPO="*"
## SOURCES
NODE_SOURCE="https://deb.nodesource.com/setup_14.x"
DOTNET_SOURCE="https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb"
## SCRIPT
SQL_IP=""
GRN=$'\e[1;32m'
RED=$'\e[1;31m'
ENDCOL=$'\e[0m'
LOGFILE_DIR="/var/log/EduBox/"
LOGFILE="adeploy.log"
#variable_hook

#############
# FUNCTIONS #
#############
function install_prerequisites() {
  export DEBIAN_FRONTEND=noninteractive
  # add universe and update existing repos
  add-apt-repository universe
  apt-get update -y
  # install node.js and npm
  curl -sL ${NODE_SOURCE} | sudo -E bash
  apt-get install nodejs -y
  # install git
  apt-get install git -y
  # install wget
  apt-get install wget -y
  # wget microsoft-prod.deb
  wget ${DOTNET_SOURCE} -O packages-microsoft-prod.deb
  dpkg -i ./packages-microsoft-prod.deb
  apt-get update -y
  # install dotnet SDK (5.0)
  apt-get install apt-transport-https -y
  apt-get install dotnet-sdk-5.0 -y
  # install ASP.NET Core runtime (5.0)
  apt-get install aspnetcore-runtime-5.0 -y
  # install dotnet runtime (5.0)
  apt-get install dotnet-runtime-5.0 -y
  # install MySQL client (5.7)
  apt-get install mysql-client-core-5.7 -y
  export DEBIAN_FRONTEND=dialog
  # install nginx
  apt-get install nginx -y
  # install libgdiplus
  apt-get install libgdiplus -y
  # install ssmtp client
  apt-get install ssmtp -y
}
function git_clone_repo() {
  # download from GitLab to temp dir
  rm -rf /tmp/EduBox
  git clone --branch master ${PROJ_REPO} /tmp/EduBox
}
function connect_to_db() {
  # Change connection string's server address in appsettings.json
  sed -i "s/Server\=localhost;/Server=$SQL_IP;/" /tmp/EduBox/src/Edubox.Presentation/appsettings.json
}

function build_repo() {
  # build application from temp dir in permanent dir
  (
    cd /tmp/EduBox/src/Edubox.Presentation/ClientApp || exit
    npm install
  )
  export DOTNET_CLI_HOME="/tmp"
  dotnet publish /tmp/EduBox/src/Edubox.Presentation/Edubox.Presentation.csproj -c release -o /usr/local/bin/EduBox
  export PATH="$PATH:/tmp/.dotnet/tools"
  dotnet tool install --global dotnet-ef --version 5.0.5
  (
    cd /tmp/EduBox/src/Edubox.Presentation || exit
    dotnet-ef database update --context="EduboxPoCDbContext"
  )
  (
    cd /tmp/EduBox/src/Edubox.Presentation || exit
    dotnet-ef database update --context="EduboxIdentityDbContext"
  )
  chmod +x /usr/local/bin/EduBox
  chown root:root /usr/local/bin/EduBox
}

function create_edubox_service() {
  # create service for application
  touch /etc/systemd/system/EduBox.service
  echo "[Unit]
	Description=ASP.NET Core MVC
	[Service]
	WorkingDirectory=/usr/local/bin/EduBox
	ExecStart=/usr/bin/dotnet /usr/local/bin/EduBox/Edubox.Presentation.dll
	Restart=always
	RestartSec=10
	KillSignal=SIGINT
	SyslogIdentifier=api
	User=root
	Environment=ASPNETCORE_ENVIRONMENT=Production
	Environment=DOTNET_TELEMETRY_OPTOUT=trueest12
	Environment=DOTNET_CLI_HOME=/tmp
	Environment=ASPNETCORE_URLS=https://0.0.0.0:5001
	[Install]
	WantedBy=multi-user.target" >/etc/systemd/system/EduBox.service
  chmod 777 /etc/systemd/system/EduBox.service
  ufw allow from any to any port 5001 proto tcp
  systemctl enable EduBox.service
}

function setup_reverse_proxy(){
  echo "server {
    listen 80;
    location / {
        proxy_set_header   X-Forwarded-For \$remote_addr;
        proxy_set_header   Host \$http_host;
        proxy_pass         \"https://localhost:5001\";
    }
  }" > /etc/nginx/sites-available/default
  # increase picture file size limit for upload
  sed -i "s/include \/etc\/nginx\/sites-enabled\/\*;/include \/etc\/nginx\/sites-enabled\/\*;\nclient_max_body_size 100M;/" /etc/nginx/nginx.conf
  # allow port 80 & 443
  ufw allow http
  ufw allow https
  # finalize and restart
  systemctl enable nginx
  service nginx restart
}

function configure_mail() {
  echo 'root=system@edubox.be
mailhub=mail.gandi.net:465
rewriteDomain=edubox.be
AuthUser=system@edubox.be
AuthPass=niw3k9G7EDWnmKbCKU9R
FromLineOverride=YES
UseTLS=YES' >> /etc/ssmtp/ssmtp.conf
}

#function_hook

#############
#   MAIN    #
#############
# Check if root
if [ "$EUID" -ne 0 ]; then
  printf "%sPlease run adeploy.sh as root.%s (Usage: sudo ./adeploy.sh)\n" "${RED}" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi
# Create LOGFILE
mkdir -p "$LOGFILE_DIR"
touch "$LOGFILE_DIR"/"$LOGFILE"
exec &>"$LOGFILE_DIR"/"$LOGFILE"

# Execute functions
printf "\n%s## Installing prerequisites... (1/7)%s\n" "${GRN}" "${ENDCOL}"
if install_prerequisites; then
  printf "%s## Prerequisites successfully installed.%s\n" "${GRN}" "${ENDCOL}"
else
  printf "%s!! Installing prerequisites failed.\n" "${RED}"
  printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
  printf "## Exiting...%s\n" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi

printf "\n%s## Cloning GitLab repository... (2/7)%s\n" "${GRN}" "${ENDCOL}"
if git_clone_repo; then
  printf "%s## GitLab repository successfully cloned.%s\n" "${GRN}" "${ENDCOL}"
else
  printf "%s!! Cloning GitLab repository failed.\n" "${RED}"
  printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
  printf "## Exiting...%s\n" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi

printf "\n%s## Connecting to database... (3/7)%s\n" "${GRN}" "${ENDCOL}"
if [  -n "$SQL_IP" ]; then
if connect_to_db; then
  printf "%s## Successfully connected to database.%s\n" "${GRN}" "${ENDCOL}"
else
  printf "%s!! Connecting to database failed.\n" "${RED}"
  printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
  printf "## Exiting...%s\n" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi
else
  printf "%s## No MySQL IP address configured.\n" "${GRN}"
  printf "## Using localhost...%s\n" "${ENDCOL}"
fi

#main_before_build_hook

printf "\n%s## Locally building downloaded repository... (4/7)%s\n" "${GRN}" "${ENDCOL}"
if build_repo; then
  printf "%s## Project successfully built.%s\n" "${GRN}" "${ENDCOL}"
else
  printf "%s!! Locally building project failed.\n" "${RED}"
  printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
  printf "## Exiting...%s\n" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi

printf "\n%s## Creating system service for application... (5/7)%s\n" "${GRN}" "${ENDCOL}"
if create_edubox_service; then
  printf "%s## System service successfully created.%s\n" "${GRN}" "${ENDCOL}"
else
  printf "%s!! Creating system service failed.\n" "${RED}"
  printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
  printf "## Exiting...%s\n" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi

printf "\n%s## Creating reverse proxy for application... (6/7)%s\n" "${GRN}" "${ENDCOL}"
if setup_reverse_proxy; then
  printf "%s## Reverse proxy successfully created.\n" "${GRN}"
  printf "## Incoming traffic on port 80 will be redirected to localhost:5001.%s\n" "${ENDCOL}"
else
  printf "%s!! Creating reverse proxy failed.\n" "${RED}"
  printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
  printf "## Exiting...%s\n" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi

printf "\n%s## Configuring mail client... (7/7)%s\n" "${GRN}" "${ENDCOL}"
if configure_mail; then
  printf "%s## Mail client successfully configured.\n%s" "${GRN}" "${ENDCOL}"
else
  printf "%s!! Configuring mail client failed.\n" "${RED}"
  printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
  printf "## Exiting...%s\n" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi

#main_after_build_hook

printf "\n%s## Done! Successfully deployed the EduBox application.\n" "${GRN}"
printf "\n## Starting the EduBox application...%s\n" "${ENDCOL}"
if systemctl start EduBox.service; then
  printf "%s## Application started successfully.\n" "${GRN}"
else
  printf "%s!! Starting application failed.\n" "${RED}"
  printf "## Check log in %s%s for more information.\n" "$LOGFILE_DIR" "$LOGFILE"
  printf "## Exiting...%s\n" "${ENDCOL}"
  [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1
fi
# End script
ssmtp admin@edubox.be < /var/log/EduBox/adeploy.log
[[ "$0" == "$BASH_SOURCE" ]] && exit 0 || return 0

