#!/bin/bash
# Usage: ./install_java_python.sh <python_version> <java_version>
# Example: ./install_java_python.sh 3.12 17

# Note: Python version should now be in X.Y format, e.g., 3.11, 3.12

PYTHON_VERSION=$1
JAVA_VERSION=$2

if [ -z "$PYTHON_VERSION" ] || [ -z "$JAVA_VERSION" ]; then
  echo "Usage: $0 <python_version> <java_version>"
  echo "Example: $0 3.12 17"
  exit 1
fi

echo ">>> Installing base dependencies..."
sudo apt-get update
# software-properties-common is needed to add PPAs
sudo apt-get install -y wget curl software-properties-common

######################################
#         Install Python (from PPA)        #
######################################
echo ">>> Installing Python $PYTHON_VERSION using the deadsnakes PPA..."

# Add the deadsnakes PPA repository
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt-get update

# Install the specific Python version, its dev package, venv, and pip
sudo apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv python3-pip

# Use update-alternatives to make our new version the default `python3`
# This is safer than manual symlinks.
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1
sudo update-alternatives --set python3 /usr/bin/python${PYTHON_VERSION}


######################################
#         Install OpenJDK (from APT)       #
######################################
echo ">>> Installing OpenJDK $JAVA_VERSION..."
sudo apt-get install -y openjdk-${JAVA_VERSION}-jdk

echo ">>> Locating OpenJDK installation directory..."
JAVA_HOME_PATH=""
# This robust logic for finding JAVA_HOME is still excellent and will be kept.
if command -v update-alternatives &> /dev/null; then
  JAVA_HOME_PATH=$(update-alternatives --get-selections | grep "^java " | tr -s " " | cut -d " " -f 3 | sed 's|/bin/java||')
fi

if [ -z "$JAVA_HOME_PATH" ] || [ ! -d "$JAVA_HOME_PATH" ] || [[ "$JAVA_HOME_PATH" == *"oracle"* ]]; then
  POSSIBLE_PATHS=(
    "/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64"
    "/usr/lib/jvm/openjdk-${JAVA_VERSION}"
  )
  for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path" ]; then
      JAVA_HOME_PATH="$path"
      break
    fi
  done
fi

if [ -z "$JAVA_HOME_PATH" ] || [ ! -d "$JAVA_HOME_PATH" ]; then
  echo "------------------------------------------------------------"
  echo "FATAL: Could not automatically determine OpenJDK home path."
  echo "Available JVM directories found:"
  find /usr/lib/jvm -maxdepth 1 -type d | grep -v "^/usr/lib/jvm$"
  echo "------------------------------------------------------------"
  exit 1
fi
echo "Found OpenJDK at: $JAVA_HOME_PATH"

######################################
#  Update System & User Environments #
######################################
echo ">>> Updating system-wide Java configuration..."
sudo tee /etc/profile.d/jdk.sh > /dev/null << EOF
# OpenJDK Environment
export JAVA_HOME=${JAVA_HOME_PATH}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
sudo chmod +x /etc/profile.d/jdk.sh

update_bashrc() {
  local bashrc_file="$1"
  if [ ! -f "$bashrc_file" ]; then return; fi
  sudo sed -i '/# === Custom Java Setup ===/d' "$bashrc_file"
  sudo sed -i '/export JAVA_HOME=/d' "$bashrc_file"
  sudo sed -i '/export PATH="\$JAVA_HOME\/bin:\$PATH"/d' "$bashrc_file"
  sudo tee -a "$bashrc_file" > /dev/null << EOF

# === Custom Java Setup ===
export JAVA_HOME="${JAVA_HOME_PATH}"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF
}

echo ">>> Updating .bashrc files for users..."
update_bashrc "/root/.bashrc"
for user_home in /home/*; do
  if [ -d "$user_home" ]; then
    username=$(basename "$user_home")
    user_id=$(id -u "$username" 2>/dev/null || echo "0")
    if [ "$user_id" -ge 1000 ]; then
      update_bashrc "$user_home/.bashrc"
    fi
  fi
done

######################################
#           Final Check              #
######################################
echo ">>> Verifying Installation..."
echo -n "➡ Python version: "
python3 --version
echo -n "➡ Pip version: "
pip3 --version

echo -n "➡ Java version: "
java -version
echo "➡ JAVA_HOME is set to: $JAVA_HOME_PATH"

echo ""
echo "All done! For changes to take effect, users must log out and back in, or run 'source ~/.bashrc'."