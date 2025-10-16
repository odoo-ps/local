# Odoo Docker Environment Setup

This guide explains how to use the setup-odoo.sh script to manage your Odoo development environment and how to add Odoo Enterprise and other custom addons.



## 1. Initial Setup

First, make sure the setup-odoo.sh script is in the same directory as your docker-compose.yml file.
To set up the environment for the first time, simply run the script from your terminal:
```
./odoo.sh
```

If you don't already have docker compose installed, you might need to run this with:
```
sudo ./odoo.sh
```

This will automatically:
- Check for Docker and Docker Compose. If they are missing, it will prompt you for your sudo password to install them.
- Create a .env file with the latest Odoo versions.
- Create the necessary directory structure for your addons (e.g., ./17/enterprise, ./17/custom, etc.).
- Build and start the Odoo services.


## 2. Adding Odoo Enterprise Addons

The script creates placeholder directories for the Enterprise addons, but you need to download the source code yourself since you can only have access to enterprise if you have a contract with Odoo.

__Download Enterprise:__ Go to the official Odoo GitHub repository for the version you need (e.g., https://github.com/odoo/odoo/tree/17.0 for version 17) and download the source code as a ZIP file.

__Extract the Addons:__ Unzip the downloaded file. Inside, you will find a folder named addons.

__Copy to Directory:__ Copy all the folders from inside that addons directory and place them into the correct version-specific enterprise folder created by the script (e.g., ./17/enterprise/).


## 3. Adding Custom Addons

The process is the same for any other custom modules you have:

Place your custom addons inside the corresponding version's custom or design folder (e.g., ./17/custom/my_awesome_module).

## 4. Restarting the Server

After you add or remove any addons, you must restart the server for the changes to take effect.

Use the -r flag to do this quickly:
```
./odoo.sh -r
```

This command will gracefully stop and restart the containers, loading your new modules.

### Other Useful Commands

Fresh Start (-f): To completely reset your environment, including the database, run:
```
./odoo.sh -f
```

Delete Everything (-d): To stop all services and remove all containers and volumes, run:
```
./odoo.sh -d
```
