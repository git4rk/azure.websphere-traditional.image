#!/bin/sh

#      Copyright (c) Microsoft Corporation.
# 
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#           http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

while getopts "u:p:" opt; do
    case $opt in
        u)
            userName=$OPTARG #IBM user id for downloading artifacts from IBM web site
        ;;
        p)
            password=$OPTARG #password of IBM user id for downloading artifacts from IBM web site
        ;;
    esac
done

# Wait untile the data disk is partitioned and mounted
output=$(df -h)
while echo $output | grep -qv "/datadrive"
do
    sleep 10
    echo "Waiting for data disk partition & mount complete..."
    output=$(df -h)
done
name=$(df -h | grep "/datadrive" | awk '{print $1;}' | grep -Po "(?<=\/dev\/).*")
echo "UUID=$(blkid | grep -Po "(?<=\/dev\/${name}\: UUID=\")[^\"]*(?=\".*)")   /datadrive   xfs   defaults,nofail   1   2" >> /etc/fstab

# Move entitlement check and application patch script to /var/lib/cloud/scripts/per-instance
mv was-check.sh /var/lib/cloud/scripts/per-instance

# Move installation properties file to /datadrive
mv virtualimage.properties /datadrive

# Get installation properties
source /datadrive/virtualimage.properties

# Create installation directories
mkdir -p ${IM_INSTALL_DIRECTORY} && mkdir -p ${IM_SHARED_DIRECTORY} \
    && mkdir -p ${IHS_INSTALL_DIRECTORY} && mkdir -p ${PLUGIN_INSTALL_DIRECTORY} && mkdir -p ${WCT_INSTALL_DIRECTORY}

# Install IBM Installation Manager
wget -O "$IM_INSTALL_KIT" "$IM_INSTALL_KIT_URL" -q
mkdir im_installer
unzip -q "$IM_INSTALL_KIT" -d im_installer
chmod -R 755 ./im_installer/*
./im_installer/userinstc -log log_file -acceptLicense -installationDirectory ${IM_INSTALL_DIRECTORY}

# Save credentials to a secure storage file
${IM_INSTALL_DIRECTORY}/eclipse/tools/imutilsc saveCredential -secureStorageFile storage_file \
    -userName "$userName" -userPassword "$password" -passportAdvantage

# Check whether IBMid is entitled or not
if [ $? -eq 0 ]; then
    output=$(${IM_INSTALL_DIRECTORY}/eclipse/tools/imcl listAvailablePackages -cPA -secureStorageFile storage_file)
    if echo "$output" | grep "$WAS_ND_VERSION_ENTITLED"; then
        echo "$(date): IBMid entitlement check succeeded."
    elif echo "$output" | grep "$NO_PACKAGES_FOUND"; then
        echo "$(date): IBMid entitlement check is not available."
        rm -rf storage_file && rm -rf log_file
        exit 1
    else
        echo "$(date): IBMid entitlement check failed."
        rm -rf storage_file && rm -rf log_file
        exit 1
    fi
else
    echo "$(date): Cannot connect to Passport Advantage."
    rm -rf storage_file && rm -rf log_file
    exit 1
fi

# Install IBM HTTP Server V9 using IBM Installation Manager
${IM_INSTALL_DIRECTORY}/eclipse/tools/imcl install "$IBM_HTTP_SERVER" "$IBM_JAVA_SDK" -repositories "$REPOSITORY_URL" \
    -installationDirectory ${IHS_INSTALL_DIRECTORY}/ -sharedResourcesDirectory ${IM_SHARED_DIRECTORY}/ \
    -secureStorageFile storage_file -acceptLicense -installFixes recommended -preferences $SSL_PREF,$DOWNLOAD_PREF -showProgress

if [ $? -eq 0 ]; then
    echo "$(date): IBM HTTP Server V9 installed successfully."
else
    echo "$(date): IBM HTTP Server V9 failed to be installed."
    rm -rf storage_file && rm -rf log_file
    exit 1
fi

# Install Web Server Plug-ins V9 for IBM WebSphere Application Server using IBM Installation Manager
${IM_INSTALL_DIRECTORY}/eclipse/tools/imcl install "$WEBSPHERE_PLUGIN" "$IBM_JAVA_SDK" -repositories "$REPOSITORY_URL" \
    -installationDirectory ${PLUGIN_INSTALL_DIRECTORY}/ -sharedResourcesDirectory ${IM_SHARED_DIRECTORY}/ \
    -secureStorageFile storage_file -acceptLicense -installFixes recommended -preferences $SSL_PREF,$DOWNLOAD_PREF -showProgress

if [ $? -eq 0 ]; then
    echo "$(date): Web Server Plug-ins V9 installed successfully."
else
    echo "$(date): Web Server Plug-ins V9 failed to be installed."
    rm -rf storage_file && rm -rf log_file
    exit 1
fi

# Install WebSphere Customization Toolbox V9 using IBM Installation Manager
${IM_INSTALL_DIRECTORY}/eclipse/tools/imcl install "$WEBSPHERE_WCT" "$IBM_JAVA_SDK" -repositories "$REPOSITORY_URL" \
    -installationDirectory ${WCT_INSTALL_DIRECTORY}/ -sharedResourcesDirectory ${IM_SHARED_DIRECTORY}/ \
    -secureStorageFile storage_file -acceptLicense -installFixes recommended -preferences $SSL_PREF,$DOWNLOAD_PREF -showProgress

if [ $? -eq 0 ]; then
    echo "$(date): WebSphere Customization Toolbox V9 installed successfully."
else
    echo "$(date): WebSphere Customization Toolbox V9 failed to be installed."
    rm -rf storage_file && rm -rf log_file
    exit 1
fi

# Update packages and apply iFixes
${IM_INSTALL_DIRECTORY}/eclipse/tools/imcl updateAll -repositories "$REPOSITORY_URL" \
            -acceptLicense -log log_file -installFixes recommended -secureStorageFile storage_file -preferences $SSL_PREF,$DOWNLOAD_PREF -showProgress

if [ $? -eq 0 ]; then
    echo "$(date): Successfully updated packages and applied iFixes."
else
    echo "$(date): Failed to update packages and apply iFixes."
    rm -rf storage_file && rm -rf log_file
    exit 1
fi

# Remove temporary files
rm -rf storage_file && rm -rf log_file
