#!/bin/bash
# Usage: ./install_java_python.sh "<python_versions>" "<java_versions>"
# Example: ./install_java_python.sh "3.12.0" "17 21"

set -e

# The first argument is a space-separated string of Python versions
PYTHON_VERSIONS_STRING="$1"
# The second argument is a space-separated string of Java versions
JAVA_VERSIONS_STRING="$2"

echo ">>> Received Python versions to install: [${PYTHON_VERSIONS_STRING}]"
echo ">>> Received Java versions to install: [${JAVA_VERSIONS_STRING}]"

echo ">>> Installing base dependencies..."
sudo apt-get update
sudo apt-get install -y wget curl software-properties-common

# This variable will hold the path of the last Java version installed, to set it as the default JAVA_HOME
LATEST_JAVA_HOME_PATH=""

######################################
#      Install Python Versions       #
######################################
if [ -n "$PYTHON_VERSIONS_STRING" ]; then
    # Track the last version to set it as default later
    LAST_PYTHON_XY_VERSION=""
    for FULL_PYTHON_VERSION in $PYTHON_VERSIONS_STRING; do
        PYTHON_XY_VERSION=$(echo "$FULL_PYTHON_VERSION" | cut -d. -f1,2)
        echo ">>> Processing Python ${PYTHON_XY_VERSION}..."

        # **CHECK 1: Check if the version is already installed before trying to install it.**
        if command -v "python${PYTHON_XY_VERSION}" &> /dev/null; then
            echo "--> Python ${PYTHON_XY_VERSION} is already installed. Skipping installation."
        else
            echo "--> Installing Python ${PYTHON_XY_VERSION} from APT..."
            # The deadsnakes PPA provides a wider range of Python versions for Ubuntu
            sudo add-apt-repository -y ppa:deadsnakes/ppa
            sudo apt-get update
            sudo apt-get install -y "python${PYTHON_XY_VERSION}" "python${PYTHON_XY_VERSION}-dev" "python${PYTHON_XY_VERSION}-venv" python3-pip
        fi
        
        # Make this version a candidate for the default 'python3' command
        sudo update-alternatives --install /usr/bin/python3 python3 "/usr/bin/python${PYTHON_XY_VERSION}" 1
        LAST_PYTHON_XY_VERSION=$PYTHON_XY_VERSION
    done
    # After installing all, explicitly set the last one found as the default
    if [ -n "$LAST_PYTHON_XY_VERSION" ]; then
        echo "--> Setting default python3 to python${LAST_PYTHON_XY_VERSION}"
        sudo update-alternatives --set python3 "/usr/bin/python${LAST_PYTHON_XY_VERSION}"
    fi
fi

######################################
#         Install Java Versions        #
######################################
if [ -n "$JAVA_VERSIONS_STRING" ]; then
    for JAVA_VERSION in $JAVA_VERSIONS_STRING; do
        echo ">>> Processing Java (OpenJDK) ${JAVA_VERSION}..."
        
        # **CHECK 2: Use dpkg to check if the JDK package is already installed.**
        if dpkg -s "openjdk-${JAVA_VERSION}-jdk" &> /dev/null; then
            echo "--> OpenJDK ${JAVA_VERSION} is already installed. Skipping installation."
        else
            echo "--> Installing OpenJDK ${JAVA_VERSION} from APT..."
            sudo apt-get install -y "openjdk-${JAVA_VERSION}-jdk"
        fi
        
        # Find the installation path for this version. This will be overwritten on each loop, 
        # so the last one becomes the default JAVA_HOME.
        LATEST_JAVA_HOME_PATH="/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64"
    done
fi

######################################
#  Update System & User Environments #
######################################
if [ -n "$LATEST_JAVA_HOME_PATH" ] && [ -d "$LATEST_JAVA_HOME_PATH" ]; then
    echo ">>> Setting system-wide JAVA_HOME to the last installed version: ${LATEST_JAVA_HOME_PATH}"
    sudo tee /etc/profile.d/jdk_custom.sh > /dev/null << EOF
export JAVA_HOME=${LATEST_JAVA_HOME_PATH}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
    sudo chmod +x /etc/profile.d/jdk_custom.sh
fi

######################################
#           Final Verification       #
######################################
echo ">>> Verifying all requested versions are installed..."
all_ok=true

# Verify Python versions
if [ -n "$PYTHON_VERSIONS_STRING" ]; then
    for FULL_PYTHON_VERSION in $PYTHON_VERSIONS_STRING; do
        PYTHON_XY_VERSION=$(echo "$FULL_PYTHON_VERSION" | cut -d. -f1,2)
        if ! command -v "python${PYTHON_XY_VERSION}" &> /dev/null; then
            echo " VERIFICATION FAILED: Python ${PYTHON_XY_VERSION} is not installed."
            all_ok=false
        else
            echo " Verified: Python ${PYTHON_XY_VERSION} is installed."
        fi
    done
fi

# Verify Java versions
if [ -n "$JAVA_VERSIONS_STRING" ]; then
    for JAVA_VERSION in $JAVA_VERSIONS_STRING; do
        if ! dpkg -s "openjdk-${JAVA_VERSION}-jdk" &> /dev/null; then
            echo " VERIFICATION FAILED: OpenJDK ${JAVA_VERSION} is not installed."
            all_ok=false
        else
            echo "Verified: OpenJDK ${JAVA_VERSION} is installed."
        fi
    done
fi

# Final status check
if [ "$all_ok" = false ]; then
    echo "--------------------------------------------------------"
    echo "FATAL: One or more required dependencies were not found after installation. Please check the logs."
    echo "--------------------------------------------------------"
    exit 1
else
    echo "All requested dependencies have been successfully verified."
fi

echo ""
echo "All done! For changes to take effect, users must log out and back in or run 'source ~/.bashrc'."