#!/bin/bash
# Usage: ./install_python_openjdk.sh <python_version> <java_version>
# Example: ./install_python_openjdk.sh 3.11.7 17

PYTHON_VERSION=$1
JAVA_VERSION=$2

if [ -z "$PYTHON_VERSION" ] || [ -z "$JAVA_VERSION" ]; then
  echo "Usage: $0 <python_version> <java_version>"
  echo "Example: $0 3.11.7 17"
  exit 1
fi

echo ">>> Installing build dependencies..."
sudo apt update
sudo apt install -y wget curl build-essential libssl-dev zlib1g-dev \
  libbz2-dev libreadline-dev libsqlite3-dev llvm libncursesw5-dev \
  xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

######################################
#      Check Python Version Exists   #
######################################
echo ">>> Checking if Python $PYTHON_VERSION exists..."
PYTHON_URL="https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $PYTHON_URL)

if [ "$HTTP_STATUS" != "200" ]; then
  echo " Python version $PYTHON_VERSION does not exist or is not available for download."
  exit 1
fi
echo " Python version $PYTHON_VERSION is available."

######################################
#           Install Python           #
######################################
echo ">>> Installing Python $PYTHON_VERSION from source..."
cd /tmp
wget $PYTHON_URL
tar -xf Python-$PYTHON_VERSION.tgz
cd Python-$PYTHON_VERSION
./configure --enable-optimizations
make -j$(nproc)
sudo make altinstall
PY_SHORT=$(echo $PYTHON_VERSION | cut -d. -f1,2)  # e.g., 3.11
sudo ln -sf /usr/local/bin/python$PY_SHORT /usr/local/bin/python3
sudo ln -sf /usr/local/bin/pip$PY_SHORT /usr/local/bin/pip3

######################################
#         Install OpenJDK            #
######################################
echo ">>> Installing OpenJDK $JAVA_VERSION..."

# Install OpenJDK using apt
echo ">>> Installing OpenJDK from package repositories..."
sudo apt update

# First check if Oracle JDK is installed and warn user
if [ -d "/usr/lib/jvm/jdk-*-oracle-*" ] || dpkg -l | grep -q "oracle-java"; then
  echo "Warning: Oracle JDK appears to be installed on this system."
  echo "This script will install OpenJDK alongside it, but you may want to remove Oracle JDK first."
  echo "Continuing in 5 seconds..."
  sleep 5
fi

# Install OpenJDK
sudo apt install -y openjdk-${JAVA_VERSION}-jdk

# Wait a moment for installation to complete
sleep 2

# Find the actual JDK installation directory
echo ">>> Locating OpenJDK installation directory..."

# Get the specific version that was just installed
if command -v update-alternatives &> /dev/null; then
  # Try update-alternatives first
  JAVA_HOME_PATH=$(update-alternatives --get-selections | grep "^java " | tr -s " " | cut -d " " -f 3 | sed 's|/bin/java||')
fi

# If that didn't work, try other methods
if [ -z "$JAVA_HOME_PATH" ] || [ ! -d "$JAVA_HOME_PATH" ] || [[ "$JAVA_HOME_PATH" == *"oracle"* ]]; then
  # List of possible OpenJDK paths to check in order of preference
  POSSIBLE_PATHS=(
    "/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64"
    "/usr/lib/jvm/openjdk-${JAVA_VERSION}"
    "/usr/lib/jvm/java-${JAVA_VERSION}"
  )
  
  # Try each path in order
  for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path" ]; then
      JAVA_HOME_PATH="$path"
      break
    fi
  done
  
  # If still not found, search for any OpenJDK directory with the right version
  if [ -z "$JAVA_HOME_PATH" ] || [ ! -d "$JAVA_HOME_PATH" ] || [[ "$JAVA_HOME_PATH" == *"oracle"* ]]; then
    # Look for any OpenJDK directory containing our desired version
    JAVA_HOME_PATH=$(find /usr/lib/jvm -maxdepth 1 -type d \( -name "*openjdk*${JAVA_VERSION}*" -o -name "*java-${JAVA_VERSION}*" \) | grep -v "oracle" | head -n 1)
  fi
  
  # If still not found, search for any OpenJDK directory
  if [ -z "$JAVA_HOME_PATH" ] || [ ! -d "$JAVA_HOME_PATH" ]; then
    JAVA_HOME_PATH=$(find /usr/lib/jvm -maxdepth 1 -type d \( -name "*openjdk*" -o -name "*java-[0-9]*" \) | grep -v "oracle" | head -n 1)
  fi
fi

# Final check - if we have any OpenJDK directory, use it
if [ -z "$JAVA_HOME_PATH" ] || [ ! -d "$JAVA_HOME_PATH" ] || [[ "$JAVA_HOME_PATH" == *"oracle"* ]]; then
  echo "------------------------------------------------------------"
  echo "FATAL: Could not automatically determine OpenJDK home path."
  echo "Available JVM directories found:"
  find /usr/lib/jvm -maxdepth 1 -type d | grep -v "^/usr/lib/jvm$"
  echo "------------------------------------------------------------"
  exit 1
fi

echo "Found OpenJDK at: $JAVA_HOME_PATH"

######################################
#  Update System-wide Configuration  #
######################################
echo ">>> Updating system-wide Java configuration..."

# Create a system-wide Java configuration file
echo ">>> Creating system-wide Java environment file..."
sudo tee /etc/profile.d/jdk.sh > /dev/null << EOF
# OpenJDK Environment
export JAVA_HOME=${JAVA_HOME_PATH}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
sudo chmod +x /etc/profile.d/jdk.sh

######################################
#     Update User Shell Configs      #
######################################
update_bashrc() {
  local bashrc_file="$1"
  local username="$2"

  # If .bashrc doesn't exist, create it with a default comment
  if [ ! -f "$bashrc_file" ]; then
    echo ">>> Creating bashrc for $username at $bashrc_file..."
    sudo touch "$bashrc_file"
    sudo chown "$username:$username" "$bashrc_file" 2>/dev/null || true
    echo "# .bashrc created by setup script" | sudo tee "$bashrc_file" > /dev/null
  fi

  # Remove any previous JAVA_HOME settings to avoid duplicates
  if grep -q "JAVA_HOME" "$bashrc_file"; then
    echo ">>> Removing previous JAVA_HOME settings from $username's bashrc..."
    sudo sed -i '/# === Custom Java & Python Setup ===/d' "$bashrc_file"
    sudo sed -i '/export JAVA_HOME=/d' "$bashrc_file"
    sudo sed -i '/export PATH="\$JAVA_HOME\/bin:\$PATH"/d' "$bashrc_file"
  fi

  # Add new JAVA_HOME settings
  echo ">>> Updating $username's bashrc..."
  sudo tee -a "$bashrc_file" > /dev/null << EOF

# === Custom Java & Python Setup ===
export JAVA_HOME="${JAVA_HOME_PATH}"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF

  echo ">>> Updated $bashrc_file"
}

# Update root user's bashrc
echo ">>> Updating root user's bashrc..."
update_bashrc "/root/.bashrc" "root"

# Update current user's bashrc if not root
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Updating current user's bashrc..."
  update_bashrc "$HOME/.bashrc" "$(whoami)"
fi

# Update all home directories for normal users (UID >= 1000)
echo ">>> Looking for other user bashrc files to update..."
for user_home in /home/*; do
  if [ -d "$user_home" ]; then
    username=$(basename "$user_home")
    user_bashrc="$user_home/.bashrc"

    # Check if this is a regular user (UID >= 1000)
    user_id=$(id -u "$username" 2>/dev/null || echo "0")
    if [ "$user_id" -ge 1000 ]; then
      echo ">>> Found user: $username"
      update_bashrc "$user_bashrc" "$username"
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

# Set Java alternatives to use OpenJDK explicitly
if [ -x "$JAVA_HOME_PATH/bin/java" ]; then
  echo ">>> Setting Java alternatives to use OpenJDK..."
  sudo update-alternatives --set java "$JAVA_HOME_PATH/bin/java" 2>/dev/null || true
  sudo update-alternatives --set javac "$JAVA_HOME_PATH/bin/javac" 2>/dev/null || true
fi

echo -n "➡ Java version: "
java -version
echo -n "➡ Javac version: "
javac -version
echo "➡ JAVA_HOME is set to: $JAVA_HOME_PATH"

# Verify we're using OpenJDK, not Oracle JDK
if java -version 2>&1 | grep -q "OpenJDK"; then
  echo "✓ Confirmed using OpenJDK"
else
  echo "⚠️ Warning: Java does not appear to be using OpenJDK."
  echo "    The system may still be using Oracle JDK or another Java distribution."
  echo "    You may need to manually remove other JDK installations or set alternatives."
fi
echo ""
echo " All done! System is now configured with:"
echo "   → Python $PYTHON_VERSION via python3"
echo "   → OpenJDK $JAVA_VERSION via java"
echo ""
echo " The configuration has been applied in the following ways:"
echo "   1. System-wide via /etc/profile.d/jdk.sh (applies to all users on login)"
echo "   2. Updated .bashrc files for root and other users"
echo "   3. Java alternatives have been set by the package manager"
echo ""
echo " For the changes to take effect, users need to either:"
echo "   - Log out and log back in, or"
echo "   - Run 'source ~/.bashrc' in their terminal"