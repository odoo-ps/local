#!/bin/bash

set -e

INSTALL_DIR="/usr/local/lib/docker/cli-plugins"
FRESH_START=false
DELETE_ONLY=false
RESTART_ONLY=false

# Parse arguments immediately to check for quick actions.
# This loop will run regardless of how the script is executed.
OPTIND=1 
while getopts "fdr" opt; do
  case ${opt} in
    f ) FRESH_START=true;;
    d ) DELETE_ONLY=true;;
    r ) RESTART_ONLY=true;;
    \? ) echo "Invalid option: -$OPTARG" >&2; exit 1;;
  esac
done

# Handle quick delete or restart actions immediately, bypassing all installation checks.
# This assumes the user's environment is already correctly set up.
if [ "$DELETE_ONLY" = true ] || [ "$RESTART_ONLY" = true ]; then
    if ! docker compose version &> /dev/null; then
        echo "ERROR: Docker Compose is not available or the Docker daemon is not running." >&2
        echo "Cannot perform a quick delete/restart. Please ensure Docker is installed and running." >&2
        exit 1
    fi

    if [ "$DELETE_ONLY" = true ]; then
        echo "'-d' (delete) flag detected. Removing all containers and volumes..."
        docker compose down --volumes --remove-orphans
        echo "All services and associated volumes have been successfully deleted."
        exit 0
    fi

    if [ "$RESTART_ONLY" = true ]; then
        echo "'-r' (restart) flag detected. Stopping and starting services..."
        docker compose down --remove-orphans
        docker compose up -d --remove-orphans --wait
        echo "All services have been restarted."
        exit 0
    fi
fi

install_docker() {
    echo "---"
    echo "Docker not found. Installing Docker Engine..."
    if ! curl -fsSL https://get.docker.com -o get-docker.sh; then
        echo "ERROR: Failed to download the Docker installation script. Please check your internet connection." >&2
        exit 1
    fi
    
    sh get-docker.sh
    rm get-docker.sh

    echo "Starting and enabling the Docker service..."
    systemctl start docker
    systemctl enable docker

    if [ -n "$SUDO_USER" ]; then
        echo "Adding user '$SUDO_USER' to the 'docker' group..."
        usermod -aG docker "$SUDO_USER"
        echo "IMPORTANT: User '$SUDO_USER' must log out and log back in for group changes to take effect in their terminal."
    else
        echo "WARNING: Could not determine the original user. You may need to manually run: 'sudo usermod -aG docker \$USER'"
    fi

    echo "Docker installed successfully."
}

install_docker_compose() {
    echo "---"
    echo "Docker Compose not found. Installing the plugin..."
    
    mkdir -p "${INSTALL_DIR}"

    echo "Fetching the latest Docker Compose version..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -oP '"tag_name": "\K(v[0-9]+\.[0-9]+\.[0-9]+)(?=")')

    if [ -z "$LATEST_VERSION" ]; then
        echo "ERROR: Could not automatically determine the latest Docker Compose version. Exiting." >&2
        exit 1
    fi

    echo "Latest version is ${LATEST_VERSION}."

    MACHINE_ARCH=$(uname -m)
    KERNEL_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')
    DOWNLOAD_URL="https://github.com/docker/compose/releases/download/${LATEST_VERSION}/docker-compose-${KERNEL_TYPE}-${MACHINE_ARCH}"
    DESTINATION_PATH="${INSTALL_DIR}/docker-compose"

    echo "Downloading Docker Compose from ${DOWNLOAD_URL}..."
    if ! curl -SL "${DOWNLOAD_URL}" -o "${DESTINATION_PATH}"; then
        echo "ERROR: Download failed. Exiting." >&2
        exit 1
    fi

    echo "Making the Docker Compose binary executable..."
    chmod +x "${DESTINATION_PATH}"

    echo "Docker Compose plugin was installed successfully!"
}

create_odoo_env_file() {
    echo "---"
    echo "Attempting to create .env file with Odoo versions..."

    local odoo_repo_info
    odoo_repo_info=$(curl -s --connect-timeout 5 https://api.github.com/repos/odoo/odoo)

    if [ -z "$odoo_repo_info" ]; then
        echo "WARNING: Could not fetch Odoo repository information from GitHub. Skipping .env file creation."
        return
    fi

    local default_branch
    default_branch=$(echo "$odoo_repo_info" | grep -oP '"default_branch": "\K([^"]+)')

    if [ -z "$default_branch" ]; then
        echo "WARNING: Could not determine the default branch for odoo/odoo. Skipping .env file creation."
        return
    fi

    local version3
    version3=$(echo "$default_branch" | cut -d'.' -f1)

    if ! [[ "$version3" =~ ^[0-9]+$ ]]; then
        echo "WARNING: Failed to parse a valid version number from branch '$default_branch'. Skipping .env file creation."
        return
    fi

    local version2=$((version3 - 1))
    local version1=$((version3 - 2))

    echo "Latest Odoo version detected: ${version3}.0"
    echo "Creating .env file with versions ${version1}.0, ${version2}.0, and ${version3}.0..."

    cat > .env << EOL
VERSION_1=${version1}
VERSION_2=${version2}
VERSION_3=${version3}
EOL

    echo ".env file created successfully."
}

manage_docker_services() {
    echo "---"
    echo "Checking for local docker-compose.yml to manage services..."
    if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        export HOST_UID=$(id -u)
        export HOST_GID=$(id -g)

        echo "Pre-creating directories to ensure correct ownership..."
        if [ -f ".env" ]; then
            # Source the .env file to get the versions
            set -a
            # shellcheck source=/dev/null
            source .env
            set +a
            
            for version in ${VERSION_1} ${VERSION_2} ${VERSION_3}; do
                if [ -n "$version" ]; then
                    echo "Creating directories for Odoo version ${version}..."
                    mkdir -p "./${version}/custom"
                    mkdir -p "./${version}/design"
                    mkdir -p "./${version}/enterprise"
                fi
            done
        else
            echo "WARNING: .env file not found. Skipping directory creation. Volumes might be owned by root."
        fi

        echo "Found docker-compose file. Shutting down existing services to avoid conflicts..."
        if [ "$FRESH_START" = true ]; then
            echo "'-f' (fresh) flag detected. Removing volumes for a fresh start..."
            docker compose down --volumes --remove-orphans
        else
            docker compose down --remove-orphans
        fi
        echo "Local services have been shut down."

        echo "Starting services with the latest configuration (as user ${HOST_UID}:${HOST_GID})..."
        docker compose up -d --build --remove-orphans --wait
        echo "Docker Compose services have been started."
    else
        echo "No local docker-compose.yml or docker-compose.yaml found. Skipping service management."
    fi
}

if [ "$(id -u)" -eq 0 ]; then
    echo "Running with root privileges for installation..."
    
    if ! command -v docker &> /dev/null; then
        install_docker
    else
        echo "Docker is already installed."
    fi
    
    if ! docker compose version &> /dev/null; then
        install_docker_compose
    else
        echo "Docker Compose is already installed."
        docker compose version
    fi
    
    echo "---"
    echo "Installation tasks complete. Exiting root mode."
    exit 0
fi

if [[ "$1" == "--post-install" ]]; then
    shift # Consume --post-install
    
    # Flags were already parsed at the top of the script.
    # We just need to proceed with the normal flow.

    echo "Running post-installation tasks with new permissions..."
    create_odoo_env_file
    manage_docker_services
    echo "---"
    echo "All done!"
    echo "You can place your addons in the created directories for each version."
    exit 0
fi

# This section only runs on initial execution as a normal user.
# Argument parsing has already been done at the top.

NEEDS_DOCKER_INSTALL=false
if ! command -v docker &> /dev/null; then
    NEEDS_DOCKER_INSTALL=true
    echo "Docker is not installed."
fi

NEEDS_COMPOSE_INSTALL=false
if ! docker compose version &> /dev/null; then
    NEEDS_COMPOSE_INSTALL=true
    if [ "$NEEDS_DOCKER_INSTALL" = false ]; then
        echo "Docker Compose plugin is not installed."
    fi
fi

if [ "$NEEDS_DOCKER_INSTALL" = true ] || [ "$NEEDS_COMPOSE_INSTALL" = true ]; then
    echo "---"
    echo "Installation of Docker and/or Docker-Compose is required."
    echo "This script will now re-run with sudo."
    
    # Pass original arguments to the sudo call
    sudo -- "$0" "$@"
    
    if [ "$NEEDS_DOCKER_INSTALL" = true ]; then
        echo "---"
        echo "Installation finished. Re-executing script with new group permissions..."
        # Re-execute with `sg` to gain the new 'docker' group permissions.
        # Pass along any original arguments using "$@".
        exec sg docker -c "\"$0\" --post-install \"$@\""
    fi
    
    echo "Docker Compose installation finished. Continuing..."
fi

echo "Docker and Docker Compose are installed."

if ! docker info &> /dev/null; then
    echo "---"
    echo "ERROR: Cannot connect to the Docker daemon." >&2
    echo "This can happen if the service is not running or if you haven't re-logged in after a previous installation." >&2
    echo "Please try the following:" >&2
    echo "1. Ensure the Docker service is running: sudo systemctl start docker" >&2
    echo "2. If that doesn't work, please log out and log back in." >&2
    exit 1
fi

echo "Successfully connected to the Docker daemon."

create_odoo_env_file
manage_docker_services

echo "---"
echo "All done!"
echo "You can place your addons in the created directories for each version."
echo "Don't forget to restart the servers with ./odoo.sh -r after adding new modules."
exit 0
