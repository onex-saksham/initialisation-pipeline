def config = [:]
def passwords = [:]
def nodesToProvision = [:]

def PASSWORDS_FILE = "passwords.json"
def JAVA_PYTHON_SCRIPT = "install_java_python.sh"
def VAULT_CREDENTIAL_ID = 'vault-approle-credential' 
def PUBLIC_KEY_PATH = '/home/jenkins/.ssh/jenkins_new_key.pub'
def JENKINS_KEY_FILE = "jenkins_key_from_vault.pem"

// The entire pipeline runs on a node (agent)
node {
    try {
        stage('Preparation') {
            echo "🔍 Checking out source code from SCM..."
            checkout scm

            // Detect changed files between commits
            def changedFilesRaw = sh(script: "git diff --name-only HEAD~1 HEAD", returnStdout: true).trim()
            if (!changedFilesRaw) {
                error "No changed files detected between commits."
            }
            def changedFiles = changedFilesRaw.split('\n')
            echo "Changed files: ${changedFiles}"

            // Find all subdirectories under 'config/'
            def configDirsRaw = sh(script: "ls -d config/*/ 2>/dev/null || true", returnStdout: true).trim()
            if (!configDirsRaw) {
                error "No environment directories found under config/."
            }

            def configDirs = configDirsRaw.split('\n')
                .collect { it.replaceAll('config/', '').replaceAll('/', '') }
                .findAll { it }
            echo "Detected environment directories: ${configDirs}"

            // Validate directory names (only letters, numbers, hyphen, underscore)
            def invalidDirs = configDirs.findAll { !it.matches('^[A-Za-z0-9_-]+$') }
            if (invalidDirs) {
                error "Invalid environment directory names detected: ${invalidDirs}. Please rename them using only letters, numbers, hyphens, or underscores."
            }

            // Try to detect which env was modified
            def changedEnvs = configDirs.findAll { envDir ->
                changedFiles.any { it.startsWith("config/${envDir}/") }
            }

            if (changedEnvs.size() == 0) {
                error "No environment-specific config directory modified. Skipping pipeline."
            } else if (changedEnvs.size() > 1) {
                error "Multiple environment directories modified in one commit: ${changedEnvs}. Please modify only one environment per pipeline run."
            }

            def envDir = changedEnvs[0]
            echo "Using environment: ${envDir.toUpperCase()}"
            env.ENVIRONMENT = envDir

            // Load configuration file
            def configFilePath = "config/${envDir}/initialization_config.json"
            if (!fileExists(configFilePath)) {
                error "Config file not found at ${configFilePath}"
            }

            def configContent = readFile(configFilePath).trim()
            if (!configContent) {
                error "Configuration file at ${configFilePath} is empty!"
            }

            // Try parsing JSON (catch malformed)
            try {
                config = readJSON text: configContent
            } catch (Exception e) {
                error "Malformed JSON in ${configFilePath}: ${e.message}"
            }

            echo "Loaded configuration from ${configFilePath}"
            env.CONFIG = config // Keep using env var for config for compatibility with later stages if needed

            // Load passwords file (if provided)
            // echo "Loading passwords file from ${PASSWORDS_FILE}..."
            // if (fileExists(PASSWORDS_FILE)) {
            //     passwords = readJSON file: PASSWORDS_FILE
            // } else {
            //     error "Passwords file '${PASSWORDS_FILE}' not found!"
            // }

            // echo "Preparation stage completed successfully."
        }
        stage('Fetch Passwords from Vault') {
            echo "Fetching passwords.json from Vault..."

            def vaultPath = "secret/initialization/nodes/${env.ENVIRONMENT}/passwords.json"
            def passwordsData = ""

            // Fetch the KV v2 secret (it’s stored under `data` inside Vault)
            withVault([configuration: VAULT_CREDENTIAL_ID, vaultSecrets: [[
                path: vaultPath,
                engineVersion: 2,
                secretValues: [[envVar: 'VAULT_PASSWORDS_JSON', vaultKey: 'data']]
            ]]]) {
                passwordsData = env.VAULT_PASSWORDS_JSON
            }

            if (!passwordsData?.trim()) {
                error "Failed to fetch passwords from Vault path: ${vaultPath}"
            }

            echo "Successfully pulled secret from Vault. Writing to ${PASSWORDS_FILE}..."

            // Convert Groovy map string to proper JSON and save locally
            def jsonData
            try {
                jsonData = readJSON text: passwordsData
            } catch (ignored) {
                // If Vault returned map-style text like "map[key:value]", convert it safely
                passwordsData = passwordsData
                    .replaceAll('map\\[', '{')
                    .replaceAll('\\]', '}')
                    .replaceAll(' ([A-Za-z0-9_]+):', '"$1":')
                    .replaceAll(':([A-Za-z0-9_]+)', ':"$1"')
                jsonData = readJSON text: passwordsData
            }

            // Write formatted JSON to local file for compatibility with existing logic
            writeFile file: PASSWORDS_FILE, text: groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(jsonData))
            echo "passwords.json written locally."
        }


        stage('Fetch SSH Key from Vault') {
            echo "Fetching Jenkins SSH private key from Vault..."
            def vaultConfig = [vaultCredentialId: VAULT_CREDENTIAL_ID]
            def secretsToFetch = [
                [path: 'secret/initialization/jenkins/ssh_key', engineVersion: 2, secretValues: [
                    [envVar: 'SSH_PRIVATE_KEY_CONTENT', vaultKey: 'ssh-key']
                ]]
            ]

            withVault([configuration: vaultConfig, vaultSecrets: secretsToFetch]) {
                writeFile(file: JENKINS_KEY_FILE, text: env.SSH_PRIVATE_KEY_CONTENT)
                sh "chmod 600 ${JENKINS_KEY_FILE}"
            }
            echo "SSH key stored locally at ${JENKINS_KEY_FILE}"
        }


        stage('Identify Target Nodes and Dependencies') {
            echo "Parsing configuration to build deployment plan..."
            def excludedKeys = ['deployment_type', 'ssh_port']

            config.each { componentName, componentData ->
                if (!(componentName in excludedKeys) && (componentData instanceof Map)) {
                    def ips = []
                    ['node_ip', 'broker_ip'].each { key ->
                        if (componentData.containsKey(key)) {
                            def ipValue = componentData[key]
                            ips.addAll(ipValue instanceof List ? ipValue : [ipValue])
                        }
                    }
                    ips.unique().each { ip ->
                        if (ip && ip instanceof String && !ip.startsWith('_')) {
                            if (!nodesToProvision.containsKey(ip)) {
                                nodesToProvision[ip] = []
                            }
                            nodesToProvision[ip].add([component: componentName, data: componentData])
                        }
                    }
                }
            }

            if (nodesToProvision.isEmpty()) {
                error "FATAL: No valid IP addresses found in the configuration file."
            } else {
                echo "Plan created. Identified ${nodesToProvision.size()} unique nodes to provision."
                nodesToProvision.each { ip, componentList ->
                    echo " -> Node ${ip} will host: ${componentList.collect { it.component }.join(', ')}"
                }
            }

            echo "\nBuilding dependency installation plan..."
            // We'll rename this to dependencyPlan for clarity in the next stage
            dependencyPlan = [:] 
            nodesToProvision.each { ip, componentList ->
                def javaVersions = new HashSet<String>()
                def pythonVersions = new HashSet<String>()

                componentList.each { componentDetails ->
                    if (componentDetails.data.java_version) {
                        javaVersions.add(componentDetails.data.java_version)
                    }
                    if (componentDetails.data.python_version) {
                        pythonVersions.add(componentDetails.data.python_version)
                    }
                }
                
                // Only add an entry if there are dependencies to install
                if (!javaVersions.isEmpty() || !pythonVersions.isEmpty()) {
                    dependencyPlan[ip] = [java: javaVersions.toList(), python: pythonVersions.toList()]
                }
            }

            echo "Dependency plan created:"
            dependencyPlan.each { ip, versions ->
                echo " -> Node ${ip} requires Java: ${versions.java}, Python: ${versions.python}"
            }
        }

        stage('Provision and Reboot Servers') {            
                sh """
                    command -v sshpass >/dev/null 2>&1 || { echo >&2 "sshpass is not installed. Aborting."; exit 1; }
                    command -v nc >/dev/null 2>&1 || {
                        echo 'netcat (nc) not found on agent, attempting to install it...'
                        sudo apt-get update && sudo apt-get install -y netcat-openbsd
                    }
                """

                nodesToProvision.each { ip, componentList ->
                    echo "--- Starting Provisioning on ${ip} ---"
                    
                    def nodePasswords = passwords[ip]
                    if (!nodePasswords) {
                        error "FATAL: No password configuration found for IP: ${ip}"
                    }
                    def sshPort = config.ssh_port ?: 22
                    def deployUser = nodePasswords.deploy_user
                    def initialUser = nodePasswords.root_user
                    def initialPass = nodePasswords.root_password
                    def initialHost = "${initialUser}@${ip}"

                    // Step 1: Create a non-root user for Jenkins (runs once per server)
                    echo "Step 1: Creating deployment user '${deployUser}' on ${ip}"
                    
                    def createUserScript = """
                        set -e
                        echo "Creating group and user..."
                        echo '${initialPass}' | sudo -S groupadd -f ${deployUser}
                        echo '${initialPass}' | sudo -S id ${deployUser} &>/dev/null || sudo -S useradd -m -g ${deployUser} -s /bin/bash ${deployUser}                        
                        echo "Setting password for ${deployUser}..."
                        echo '${initialPass}' | sudo -S sh -c 'echo "${deployUser}:${nodePasswords.deploy_password}" | chpasswd'                        
                        echo "Granting NOPASSWD sudo privileges..."
                        echo '${initialPass}' | sudo -S usermod -aG sudo ${deployUser}
                        echo '${initialPass}' | sudo -S sh -c 'echo "${deployUser} ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/${deployUser}'
                        echo '${initialPass}' | sudo -S chmod 440 /etc/sudoers.d/${deployUser}
                        echo "Enabling user services to run after logout..."
                        echo '${initialPass}' | sudo -S loginctl enable-linger ${deployUser}
                        echo "Creating directories for systemd user services..."
                        echo '${initialPass}' | sudo -S mkdir -p /home/${deployUser}/.config/systemd/user
                        echo '${initialPass}' | sudo -S chown -R ${deployUser}:${deployUser} /home/${deployUser}/.config
                        echo '${initialPass}' | sudo -S chmod 755 /home/${deployUser}/.config                        
                        echo "Setting secure permissions on home directory..."
                        echo '${initialPass}' | sudo -S chmod 750 /home/${deployUser}                        
                        echo "Changing root password..."
                        echo '${initialPass}' | sudo -S sh -c 'echo "root:${nodePasswords.new_root_password}" | chpasswd'                        
                        echo "Setting timezone to Asia/Kolkata..."
                        echo '${initialPass}' | sudo -S timedatectl set-timezone Asia/Kolkata
                    """
                    withEnv(["REMOTE_SCRIPT=${createUserScript}"]) {
                        sh 'echo "$REMOTE_SCRIPT" | sshpass -p \'' + initialPass + '\' ssh -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + initialHost + ' \'bash -s\''
                    }

                    // Step 2: Distribute the agent's public SSH key (runs once per server)
                    echo "Step 2: Distributing local SSH public key to new user on ${ip}"
                    if (!fileExists(PUBLIC_KEY_PATH)) {
                        error "FATAL: Public key file not found at ${PUBLIC_KEY_PATH} on the Jenkins agent."
                    }
                    def publicKey = readFile(file: PUBLIC_KEY_PATH).trim()
                    def setupSshCommand = """
                        set -e
                        echo 'Setting up SSH directory and authorized_keys file...'
                        mkdir -p ~/.ssh && chmod 700 ~/.ssh
                        touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
                        echo 'Adding public key to authorized_keys...'
                        grep -q -F "${publicKey}" ~/.ssh/authorized_keys || echo '${publicKey}' >> ~/.ssh/authorized_keys
                    """
                    def deployHost = "${deployUser}@${ip}"
                    sh 'echo \'' + setupSshCommand + '\' | sshpass -p \'' + nodePasswords.deploy_password + '\' ssh -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + deployHost + ' \'bash -s\''
                    
                    // Step 3: Verify passwordless SSH access is working
                    echo "Step 3: Verifying passwordless SSH access"
                    sh "ssh -i ${JENKINS_KEY_FILE} -p ${sshPort} -o StrictHostKeyChecking=no ${deployUser}@${ip} 'echo SSH key authentication successful'"
                    
                    // Step 4: Trigger a reboot to apply all core changes
                    // echo "Step 4: Triggering reboot on ${ip}"
                    // sh "ssh -i ${JENKINS_KEY_FILE} -p ${sshPort} -o StrictHostKeyChecking=no ${deployUser}@${ip} 'sudo reboot' || true"

                    // // Step 5: Wait for the server to come back online
                    // echo "Step 5: Waiting for ${ip} to come back online..."
                    // timeout(time: 5, unit: 'MINUTES') {
                    //     waitUntil {
                    //         try {
                    //             def status = sh(script: "nc -z -w 5 ${ip} ${sshPort}", returnStatus: true)
                    //             return status == 0
                    //         } catch (Exception e) { return false }
                    //     }
                    // }
                    // echo "Server ${ip} is back online."
                    // sleep 10
                    
                    // echo "--- Finished Provisioning and Reboot on ${ip} ---"
                
            }
        }

        stage('Configure Components') {
            
                // Outer loop: Iterate through each server ONCE.
                nodesToProvision.each { ip, componentList ->
                    echo "--- Configuring ALL Components on ${ip} ---"
                    def deployUser = passwords[ip].deploy_user
                    def sshPort = config.ssh_port ?: 22
                    def deployHost = "${deployUser}@${ip}"

                    // Start with the base script that runs for every server.
                    def remoteCommand = '''
                        set -e
                        echo '>>> Disabling automatic unattended upgrades...'
                        sudo systemctl stop unattended-upgrades.service || true
                        sudo systemctl disable unattended-upgrades.service || true
                        echo 'APT::Periodic::Update-Package-Lists "0";' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades
                        echo 'APT::Periodic::Unattended-Upgrade "0";' | sudo tee -a /etc/apt/apt.conf.d/20auto-upgrades
                        echo '>>> Updating package lists...'
                        sudo apt-get update -y || true
                    '''

                    // Inner loop: Iterate through EACH component planned for this IP.
                    componentList.each { componentDetails ->
                        def componentName = componentDetails.component
                        def componentData = componentDetails.data
                        echo " -> Adding configuration for component: ${componentName}"

                        // Append storage directory commands if they exist
                        def storagePath = componentData.properties?.storage
                        if (storagePath) {
                            remoteCommand += """
                                echo 'Creating storage directory: ${storagePath}...'
                                sudo mkdir -p ${storagePath}
                                sudo chown -R ${deployUser}:${deployUser} ${storagePath}
                                sudo chmod -R 2775 ${storagePath}
                            """
                        }                        

                        switch (componentName) {
                            case 'backend_job':
                                remoteCommand += "echo 'Installing build-essential for backend_job...' && export DEBIAN_FRONTEND=noninteractive && sudo apt-get install -y build-essential libpcre3-dev zlib1g-dev libssl-dev\n"
                                break
                            case 'doris_be':
                                remoteCommand += '''
                                    echo 'Applying doris_be kernel settings...'
                                    sudo sh -c 'echo "vm.max_map_count=2000000" > /etc/sysctl.d/60-doris-be.conf'
                                    sudo sysctl --system
                                    echo 'Disabling swap...'
                                    sudo swapoff -a && sudo sed -i '/swap/d' /etc/fstab
                                '''
                                break
                            case 'kafka':
                                remoteCommand += "echo 'Installing kcat for kafka...' && sudo apt-get install -y kcat\n"
                                break
                        }
                    }
                    
                    echo "Executing final combined configuration script on ${ip}..."
                    withEnv(["REMOTE_COMMAND=${remoteCommand}"]) {
                        sh 'echo "$REMOTE_COMMAND" | ssh -i ' + JENKINS_KEY_FILE + ' -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + deployHost + ' \'bash -s\''
                    }
                    echo "--- Finished All Component Configurations on ${ip} ---"
                
            }
        }

        stage('Install Dependencies') {
            dependencyPlan.each { ip, versions ->
                echo "--- Installing Dependencies on ${ip} ---"
                
                def requiredJava = versions.java
                def requiredPython = versions.python

                def deployUser = passwords[ip].deploy_user
                def sshPort = config.ssh_port ?: 22
                def deployHost = "${deployUser}@${ip}"

                retry(3) {
                    sleep(10)
                    echo "Attempting to connect to ${ip}..."
                    def remoteScriptPath = "/tmp/${JAVA_PYTHON_SCRIPT}"
                    def remoteLogPath = "/tmp/install_dependencies.log"

                    sh "scp -i ${JENKINS_KEY_FILE} -P ${sshPort} -o StrictHostKeyChecking=no ./${JAVA_PYTHON_SCRIPT} ${deployHost}:${remoteScriptPath}"

                    def pythonVersionsString = requiredPython.join(' ')
                    def javaVersionsString = requiredJava.join(' ')

                    def remoteCommand = """
                        set -e
                        chmod +x ${remoteScriptPath}
                        # IMPORTANT: Your install_java_python.sh script MUST handle these arguments
                        sudo ${remoteScriptPath} "${pythonVersionsString}" "${javaVersionsString}" > ${remoteLogPath} 2>&1
                        echo "\\n--- Displaying last 30 lines of installation log ---"
                        tail -n 30 ${remoteLogPath}
                        echo "--- End of installation log tail ---"
                    """
                    sh 'echo \'' + remoteCommand + '\' | ssh -i ' + JENKINS_KEY_FILE + ' -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + deployHost + ' \'bash -s\''

                    def localLogFile = "install_log_${ip}.log"
                    sh "scp -i ${JENKINS_KEY_FILE} -P ${sshPort} -o StrictHostKeyChecking=no ${deployHost}:${remoteLogPath} ./${localLogFile}"
                    archiveArtifacts artifacts: localLogFile, allowEmptyArchive: true

                    sh "ssh -i ${JENKINS_KEY_FILE} -p ${sshPort} -o StrictHostKeyChecking=no ${deployHost} 'rm -f ${remoteScriptPath} ${remoteLogPath}'"
                }
                echo "Successfully installed dependencies on ${ip}"
            }
        }

        stage('Configure Inter-Service SSH') {
            if (nodesToProvision.size() <= 1) {
                echo "Skipping inter-service SSH configuration for single-node deployment."
                return // Exits the stage cleanly
            }

            echo "--- Starting Inter-Service SSH Configuration ---"

            // **FIX 1: Correctly and efficiently find all unique IPs first.**
            def apiIps = nodesToProvision.findAll { ip, componentList ->
                componentList.any { it.component == 'api' }
            }.keySet()

            def backendIps = nodesToProvision.findAll { ip, componentList ->
                componentList.any { it.component == 'backend_job' }
            }.keySet()

            if (apiIps.isEmpty() || backendIps.isEmpty()) {
                echo "Warning: Missing 'api' or 'backend_job' components in the plan. Skipping SSH setup."
                return
            }
            
            echo "Found API nodes: ${apiIps}"
            echo "Found Backend nodes: ${backendIps}"

            // For each API node, generate a key and distribute it to all backend nodes
            apiIps.each { apiIp ->
                echo "Configuring API node at ${apiIp}..."
                def apiDeployUser = passwords[apiIp].deploy_user
                def apiDeployHost = "${apiDeployUser}@${apiIp}"
                def sshPort = config.ssh_port ?: 22

                // Step 1: Ensure sshpass is installed on the API node
                // **FIX 2: Corrected the installSshpass command for clarity and reliability**
                def installSshpass = "command -v sshpass >/dev/null 2>&1 || { echo 'sshpass not found, installing...'; sudo apt-get update && sudo apt-get install -y sshpass; }"
                sh 'echo \'' + installSshpass + '\' | ssh -i ' + JENKINS_KEY_FILE + ' -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + apiDeployHost + ' \'bash -s\''

                // Step 2: Generate/retrieve SSH key from the API node
                def getKeyCommand = """
                    set -e
                    if [ ! -f ~/.ssh/id_rsa.pub ]; then
                        echo 'Generating new SSH key on API node...'
                        ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa
                    fi
                    cat ~/.ssh/id_rsa.pub
                """
                def apiPublicKey = sh(script: 'echo \'' + getKeyCommand + '\' | ssh -i ' + JENKINS_KEY_FILE + ' -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + apiDeployHost + ' \'bash -s\'', returnStdout: true).trim()

                if (!apiPublicKey) {
                    error "FATAL: Failed to get public key from API node ${apiIp}"
                }

                // Step 3: Distribute the API node's public key to every backend node
                backendIps.each { backendIp ->
                    // Don't copy key to self if an API node is also a backend node
                    if (apiIp == backendIp) {
                        echo " -> Skipping key distribution from ${apiIp} to itself."
                        return
                    }

                    echo " -> Distributing key from ${apiIp} to backend node ${backendIp}"
                    def backendDeployUser = passwords[backendIp].deploy_user
                    def backendDeployPass = passwords[backendIp].deploy_password

                    def distributeKeyCommand = "sshpass -p '${backendDeployPass}' ssh-copy-id -p ${sshPort} -o StrictHostKeyChecking=no ${backendDeployUser}@${backendIp}"
                    sh 'echo \'' + distributeKeyCommand + '\' | ssh -i ' + JENKINS_KEY_FILE + ' -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + apiDeployHost + ' \'bash -s\''

                    // Step 4: Verify connection from API to Backend
                    def verifyCommand = "ssh -p ${sshPort} -o StrictHostKeyChecking=no ${backendDeployUser}@${backendIp} 'echo Successfully connected from API to Backend'"
                    sh 'echo \'' + verifyCommand + '\' | ssh -i ' + JENKINS_KEY_FILE + ' -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + apiDeployHost + ' \'bash -s\''
                }
            }
            echo "--- Finished Inter-Service SSH Configuration ---"
        }
    } catch (err) {
        echo "Pipeline failed. Please check the logs and build artifacts."
        currentBuild.result = 'FAILURE'
        throw err 
    } finally {
        // This 'finally' block replaces the 'always' post-condition
        if (currentBuild.result == null || currentBuild.result == 'SUCCESS') {
            // This 'if' block replaces the 'success' post-condition
            echo "Pipeline completed successfully!"
        }
        
        // echo "Pipeline run finished. Cleaning up workspace..."
        // cleanWs()
    }
}