#!/bin/bash

set -Eeuo pipefail

############################################################
# JFrog Artifactory OSS Installation
# Ubuntu / Debian
# Version: 7.161.19
#
# FRESH TRAINING / LAB INSTALL ONLY
#
# WARNING:
# Existing /opt/jfrog/artifactory will be deleted.
# sudo bash <script.sh> ----> use bash for script execution do not use sh
############################################################

ARTIFACTORY_VERSION="7.161.19"

JFROG_HOME="/opt/jfrog"
ARTIFACTORY_HOME="${JFROG_HOME}/artifactory"

ARTIFACTORY_USER="artifactory"
ARTIFACTORY_GROUP="artifactory"

SYSTEM_YAML="${ARTIFACTORY_HOME}/var/etc/system.yaml"

SECURITY_DIR="${ARTIFACTORY_HOME}/var/etc/security"
MASTER_KEY="${SECURITY_DIR}/master.key"
JOIN_KEY="${SECURITY_DIR}/join.key"

ARCHIVE_NAME="jfrog-artifactory-oss-${ARTIFACTORY_VERSION}-linux.tar.gz"

DOWNLOAD_URL="https://releases.jfrog.io/artifactory/bintray-artifactory/org/artifactory/oss/jfrog-artifactory-oss/${ARTIFACTORY_VERSION}/${ARCHIVE_NAME}"

MAX_WAIT_SECONDS=600
CHECK_INTERVAL=10


############################################################
# HEADER
############################################################

echo
echo "################################################################"
echo "#                                                              #"
echo "#                 *** SS TRAINING ***                          #"
echo "#                                                              #"
echo "#          JFrog Artifactory OSS Installation                  #"
echo "#                                                              #"
echo "################################################################"
echo


############################################################
# ERROR HANDLER
############################################################

trap 'echo; echo "ERROR: Script failed at line $LINENO"; exit 1' ERR


############################################################
# ROOT CHECK
############################################################

if [ "$(id -u)" -ne 0 ]; then

    echo "ERROR: Run this script using sudo."
    echo
    echo "Example:"
    echo "sudo bash $0"

    exit 1
fi


############################################################
# OPERATING SYSTEM CHECK
############################################################

echo "***** Checking operating system..."

if [ ! -f /etc/os-release ]; then

    echo "ERROR: Cannot determine operating system."
    exit 1
fi

. /etc/os-release

echo "Detected OS: ${PRETTY_NAME}"


############################################################
# SYSTEM MEMORY CHECK
############################################################

echo
echo "***** Checking system memory..."

TOTAL_MEMORY_MB=$(free -m | awk '/^Mem:/ {print $2}')

echo "Total memory: ${TOTAL_MEMORY_MB} MB"


############################################################
# DISK SPACE CHECK
############################################################

echo
echo "***** Checking available disk space..."

AVAILABLE_DISK_MB=$(df -Pm / | awk 'NR==2 {print $4}')

echo "Available disk space: ${AVAILABLE_DISK_MB} MB"

if [ "${AVAILABLE_DISK_MB}" -lt 5000 ]; then

    echo
    echo "WARNING: Less than 5 GB disk space available."
fi


############################################################
# INSTALL REQUIRED PACKAGES
############################################################

echo
echo "***** Installing required packages..."

apt-get update -y

apt-get install -y \
    curl \
    wget \
    tar \
    gzip \
    net-tools \
    ca-certificates \
    openssl

echo "Required packages installed."


############################################################
# STOP EXISTING ARTIFACTORY
############################################################

echo
echo "***** Stopping existing Artifactory if present..."

systemctl stop artifactory.service 2>/dev/null || true

sleep 5


############################################################
# REMOVE OLD CUSTOM SYSTEMD SERVICE
############################################################

echo
echo "***** Removing old custom Artifactory systemd service..."

rm -f /etc/systemd/system/artifactory.service

systemctl daemon-reload


############################################################
# REMOVE OLD JFROG SERVICE
############################################################

if [ -f /usr/lib/systemd/system/artifactory.service ]; then

    rm -f /usr/lib/systemd/system/artifactory.service
fi

systemctl daemon-reload


############################################################
# CLEAN PREVIOUS ARTIFACTORY INSTALL
############################################################

echo
echo "***** Cleaning previous Artifactory installation..."

if [ -d "${ARTIFACTORY_HOME}" ]; then

    echo "Removing:"
    echo "${ARTIFACTORY_HOME}"

    rm -rf "${ARTIFACTORY_HOME}"
fi


############################################################
# CREATE GROUP
############################################################

echo
echo "***** Creating Artifactory group..."

if ! getent group "${ARTIFACTORY_GROUP}" >/dev/null 2>&1; then

    groupadd --system "${ARTIFACTORY_GROUP}"
fi


############################################################
# CREATE USER
############################################################

echo
echo "***** Creating Artifactory user..."

if ! id "${ARTIFACTORY_USER}" >/dev/null 2>&1; then

    useradd \
        --system \
        --gid "${ARTIFACTORY_GROUP}" \
        --home-dir "${JFROG_HOME}" \
        --shell /bin/false \
        "${ARTIFACTORY_USER}"
fi

echo "Artifactory user/group verified."


############################################################
# CREATE JFROG HOME
############################################################

echo
echo "***** Creating JFrog home..."

mkdir -p "${JFROG_HOME}"


############################################################
# DOWNLOAD ARTIFACTORY
############################################################

echo
echo "***** Downloading Artifactory ${ARTIFACTORY_VERSION}..."

cd /tmp

rm -f "${ARCHIVE_NAME}"

curl \
    --fail \
    --location \
    --retry 3 \
    --retry-delay 5 \
    --output "${ARCHIVE_NAME}" \
    "${DOWNLOAD_URL}"

if [ ! -s "/tmp/${ARCHIVE_NAME}" ]; then

    echo "ERROR: Download failed."
    exit 1
fi

echo "Download completed."


############################################################
# EXTRACT ARTIFACTORY
############################################################

echo
echo "***** Extracting Artifactory..."

tar -xzf "/tmp/${ARCHIVE_NAME}" -C "${JFROG_HOME}"


############################################################
# CHECK EXTRACTED DIRECTORY
############################################################

EXTRACTED_DIR="${JFROG_HOME}/artifactory-oss-${ARTIFACTORY_VERSION}"

if [ ! -d "${EXTRACTED_DIR}" ]; then

    echo "ERROR: Extracted Artifactory directory not found:"
    echo "${EXTRACTED_DIR}"

    exit 1
fi


############################################################
# RENAME DIRECTORY
############################################################

echo
echo "***** Configuring Artifactory directory..."

mv "${EXTRACTED_DIR}" "${ARTIFACTORY_HOME}"


############################################################
# CREATE CONFIG DIRECTORIES
############################################################

echo
echo "***** Creating configuration directories..."

mkdir -p "${ARTIFACTORY_HOME}/var/etc"

mkdir -p "${SECURITY_DIR}"


############################################################
# CREATE SYSTEM.YAML
#
# FIX 1:
# allowNonPostgresql = true
#
# Required for embedded Derby.
#
# FIX 2:
# jfconnect.enabled = false
#
# Prevents slow login caused by JFConnect entitlement calls.
############################################################

echo
echo "***** Creating system.yaml..."

cat > "${SYSTEM_YAML}" <<EOF
configVersion: 1

shared:

    database:
        allowNonPostgresql: true

    user: ${ARTIFACTORY_USER}
    group: ${ARTIFACTORY_GROUP}

jfconnect:
    enabled: false
EOF


############################################################
# CREATE MASTER KEY
############################################################

echo
echo "***** Creating master key..."

openssl rand -hex 32 > "${MASTER_KEY}"


############################################################
# CREATE JOIN KEY
############################################################

echo
echo "***** Creating join key..."

openssl rand -hex 32 > "${JOIN_KEY}"


############################################################
# OWNERSHIP
############################################################

echo
echo "***** Setting ownership..."

chown -R \
    "${ARTIFACTORY_USER}:${ARTIFACTORY_GROUP}" \
    "${ARTIFACTORY_HOME}"


############################################################
# PERMISSIONS
############################################################

chmod 600 "${MASTER_KEY}"
chmod 600 "${JOIN_KEY}"
chmod 640 "${SYSTEM_YAML}"


############################################################
# SHOW SYSTEM.YAML
############################################################

echo
echo "***** Generated system.yaml..."
echo

cat "${SYSTEM_YAML}"

echo


############################################################
# INSTALL OFFICIAL JFROG SERVICE
############################################################

echo
echo "***** Installing official JFrog systemd service..."

cd "${ARTIFACTORY_HOME}/app/bin"

chmod +x installService.sh

chmod +x artifactoryManage.sh 2>/dev/null || true
chmod +x artifactoryctl 2>/dev/null || true

./installService.sh


############################################################
# RELOAD SYSTEMD
############################################################

echo
echo "***** Reloading systemd..."

systemctl daemon-reload


############################################################
# ENABLE SERVICE
############################################################

echo
echo "***** Enabling Artifactory service..."

systemctl enable artifactory.service


############################################################
# CLEAN PARTIAL DERBY DATABASES
#
# Fresh installation only.
#
# Prevents:
#
# Topology error:
# Directory .../topology/derby already exists
#
# Artifactory migration error:
# Failed to convert v51
#
############################################################

echo
echo "***** Cleaning partial Derby databases..."

rm -rf "${ARTIFACTORY_HOME}/var/data/artifactory/derby"
rm -rf "${ARTIFACTORY_HOME}/var/data/topology/derby"

chown -R \
    "${ARTIFACTORY_USER}:${ARTIFACTORY_GROUP}" \
    "${ARTIFACTORY_HOME}/var"


############################################################
# START ARTIFACTORY
############################################################

echo
echo "***** Starting Artifactory..."

systemctl start artifactory.service || true


############################################################
# WAIT FOR UI
############################################################

echo
echo "***** Waiting for Artifactory to become ready..."
echo
echo "Maximum wait: ${MAX_WAIT_SECONDS} seconds"
echo

ELAPSED=0
UI_READY=false

while [ "${ELAPSED}" -lt "${MAX_WAIT_SECONDS}" ]; do

    HTTP_CODE=$(curl \
        --silent \
        --output /dev/null \
        --write-out "%{http_code}" \
        http://localhost:8082/ui/ \
        2>/dev/null || true)


    PORT_8020="DOWN"
    PORT_8040="DOWN"
    PORT_8081="DOWN"
    PORT_8082="DOWN"


    if ss -lnt | grep -q ':8020 '; then
        PORT_8020="UP"
    fi

    if ss -lnt | grep -q ':8040 '; then
        PORT_8040="UP"
    fi

    if ss -lnt | grep -q ':8081 '; then
        PORT_8081="UP"
    fi

    if ss -lnt | grep -q ':8082 '; then
        PORT_8082="UP"
    fi


    echo "------------------------------------------------------------"
    echo "Waited        : ${ELAPSED}s"
    echo "Topology 8020 : ${PORT_8020}"
    echo "Access   8040 : ${PORT_8040}"
    echo "Artifactory   : ${PORT_8081}"
    echo "Router   8082 : ${PORT_8082}"
    echo "UI HTTP Code  : ${HTTP_CODE}"
    echo "------------------------------------------------------------"


    if [ "${HTTP_CODE}" = "200" ]; then

        UI_READY=true
        break
    fi


    sleep "${CHECK_INTERVAL}"

    ELAPSED=$((ELAPSED + CHECK_INTERVAL))

done


############################################################
# FAILURE HANDLING
############################################################

if [ "${UI_READY}" != "true" ]; then

    echo
    echo "################################################################"
    echo "#                                                              #"
    echo "#           ARTIFACTORY STARTUP FAILED                         #"
    echo "#                                                              #"
    echo "################################################################"
    echo


    echo "Current ports:"
    echo

    ss -lntp | grep -E '8020|8040|8081|8082' || true


    echo
    echo "================ SYSTEMD STATUS ================="
    echo

    systemctl status artifactory.service \
        --no-pager \
        -l || true


    echo
    echo "================ ROUTER LOG ====================="
    echo

    tail -60 \
        "${ARTIFACTORY_HOME}/var/log/router-service.log" \
        2>/dev/null || true


    echo
    echo "================ ACCESS LOG ====================="
    echo

    tail -60 \
        "${ARTIFACTORY_HOME}/var/log/access-service.log" \
        2>/dev/null || true


    echo
    echo "================ TOPOLOGY LOG ==================="
    echo

    tail -60 \
        "${ARTIFACTORY_HOME}/var/log/topology-service.log" \
        2>/dev/null || true


    echo
    echo "================ ARTIFACTORY LOG ================="
    echo

    tail -60 \
        "${ARTIFACTORY_HOME}/var/log/artifactory-service.log" \
        2>/dev/null || true


    exit 1
fi


############################################################
# FINAL PORT CHECK
############################################################

echo
echo "***** Checking JFrog ports..."
echo

ss -lntp | grep -E '8020|8040|8081|8082' || true


############################################################
# SERVICE HEALTH CHECKS
############################################################

echo
echo "***** Running health checks..."
echo


TOPOLOGY_HTTP=$(curl \
    --silent \
    --output /dev/null \
    --write-out "%{http_code}" \
    http://localhost:8020/topology/api/v1/system/readiness \
    2>/dev/null || true)


ACCESS_HTTP=$(curl \
    --silent \
    --output /dev/null \
    --write-out "%{http_code}" \
    http://localhost:8040/access/api/v1/system/ping \
    2>/dev/null || true)


UI_HTTP=$(curl \
    --silent \
    --output /dev/null \
    --write-out "%{http_code}" \
    http://localhost:8082/ui/ \
    2>/dev/null || true)


echo "Topology HTTP : ${TOPOLOGY_HTTP}"
echo "Access HTTP   : ${ACCESS_HTTP}"
echo "UI HTTP       : ${UI_HTTP}"


############################################################
# GET EC2 PUBLIC IP
############################################################

echo
echo "***** Detecting EC2 public IP..."

PUBLIC_IP=""

TOKEN=$(curl \
    --silent \
    --connect-timeout 2 \
    --request PUT \
    --header "X-aws-ec2-metadata-token-ttl-seconds: 60" \
    http://169.254.169.254/latest/api/token \
    2>/dev/null || true)


if [ -n "${TOKEN}" ]; then

    PUBLIC_IP=$(curl \
        --silent \
        --connect-timeout 2 \
        --header "X-aws-ec2-metadata-token: ${TOKEN}" \
        http://169.254.169.254/latest/meta-data/public-ipv4 \
        2>/dev/null || true)

fi


############################################################
# FALLBACK IP
############################################################

if [ -z "${PUBLIC_IP}" ]; then

    PUBLIC_IP=$(hostname -I | awk '{print $1}')
fi


############################################################
# REMOVE DOWNLOAD
############################################################

rm -f "/tmp/${ARCHIVE_NAME}"


############################################################
# SUCCESS
############################################################

echo
echo "################################################################"
echo "#                                                              #"
echo "#          ARTIFACTORY INSTALLATION SUCCESSFUL                 #"
echo "#                                                              #"
echo "################################################################"
echo

echo "Artifactory Version:"
echo "  ${ARTIFACTORY_VERSION}"
echo

echo "JFrog Home:"
echo "  ${JFROG_HOME}"
echo

echo "Artifactory Home:"
echo "  ${ARTIFACTORY_HOME}"
echo

echo "Important ports:"
echo
echo "  8020 -> Topology"
echo "  8040 -> Access"
echo "  8081 -> Artifactory"
echo "  8082 -> Router / Web UI"
echo

echo "Health:"
echo
echo "  Topology : HTTP ${TOPOLOGY_HTTP}"
echo "  Access   : HTTP ${ACCESS_HTTP}"
echo "  UI       : HTTP ${UI_HTTP}"
echo

echo "JFConnect:"
echo
echo "  Disabled"
echo
echo "  This avoids slow entitlement checks during login."
echo

echo "Artifactory UI:"
echo
echo "  http://${PUBLIC_IP}:8082/ui/"
echo

echo "Service:"
echo
echo "  sudo systemctl status artifactory"
echo

echo "Logs:"
echo
echo "  ${ARTIFACTORY_HOME}/var/log/"
echo

echo "AWS Security Group:"
echo
echo "  Allow TCP 8082 from your IP."
echo

echo "################################################################"
echo
