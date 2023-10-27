# Deployment to GCP with Bash scripts

## Description
This project includes 4 bash scripts and 1 JSON file containing information about our service accounts. We have created the following scripts: adeploy.sh, which is used to deploy our application on VM instances, installing various software programs and fetching the latest version of our project from GitLab. In addition to adeploy.sh, we also have ideploy.sh, which sets up and maintains the entire Google Cloud environment. We also have backup.sh and restore.sh, which allow us to take and restore backups of our MySQL database. The user can choose the name for the backup and which backup to restore.

## INstructions
These are the instructions for running the following scripts:

To initiate the entire process, start with `sudo ./ideploy.sh (test|prod) (-d|-deleteall).`
For the first parameter, you have a choice between 'test' or 'prod' to select the environment you wish to work with. The '-d' and '-deleteall' are options that you can use if you want to, for example, delete everything or only test/prod.

For adeploy.sh, you don't need to execute any commands separately since it is included with ideploy.

You can take a backup by running `sudo ./backup.sh (test|prod)`, where it checks how many MySQL instances are available. You can then choose which one to use if there is more than one. After that, you can choose the name by either selecting a predefined one or typing your own.

To restore backups, use `sudo ./restore.sh`. After executing this command, a list of all available backups on the selected MySQL instance will appear. You can then select which one to restore in a list format.












