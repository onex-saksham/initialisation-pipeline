// Jenkinsfile

// Define script-level variables
def config = [:]
def passwords = [:]
def nodesToProvision = [:]

pipeline {
agent any
    environment {
        CONFIG_FILE = "initialization_deployment_config.json"
        PASSWORDS_FILE = "passwords.json" // We still read this for now
        SUDO_COMMANDS_DIR = "sudo_commands"
        JAVA_PYTHON_SCRIPT = "install_java_python.sh"
        JENKINS_SSH_CREDENTIALS_ID = 'server-ssh-key' 
        PUBLIC_KEY_PATH = '/home/jenkins/.ssh/id_rsa.pub'
    }

    stages {
        stage('Preparation') {
            steps {
                script {
                    echo "Checking out source code..."
                    checkout scm

                    echo "Loading deployment configuration..."
                    if (fileExists(env.CONFIG_FILE)) {
                        config = readJSON file: env.CONFIG_FILE
                    } else {
                        error "FATAL: Configuration file '${env.CONFIG_FILE}' not found!"
                    }

                    echo "Loading passwords file..."
                    if (fileExists(env.PASSWORDS_FILE)) {
                        passwords = readJSON file: env.PASSWORDS_FILE
                    } else {
                        error "FATAL: Passwords file '${env.PASSWORDS_FILE}' not found!"
                    }
                }
            }
        }

        stage('Identify Target Nodes') {
            steps {
                script {
                    echo "Parsing configuration to identify all target nodes..."
                    def excludedKeys = ['releases', 'base_user', 'user', 'deployment_type', 'deployment_path', 'deploy', 'ssh_port']

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
                                    nodesToProvision[ip] = [component: componentName, data: componentData]
                                }
                            }
                        }
                    }

                    if (nodesToProvision.isEmpty()) {
                        error "FATAL: No valid IP addresses found in the configuration file."
                    } else {
                        echo "Plan created. Identified ${nodesToProvision.size()} unique nodes to provision."
                    }
                }
            }
        }

        stage('Provision and Reboot Servers') {
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: env.JENKINS_SSH_CREDENTIALS_ID,
                    keyFileVariable: 'JENKINS_KEY_FILE'
                )]) {
                    script {
                        // Check for required tools and install netcat if missing
                        sh """
                            command -v sshpass >/dev/null 2>&1 || { echo >&2 "sshpass is not installed. Aborting."; exit 1; }
                            command -v nc >/dev/null 2>&1 || { 
                                echo 'netcat (nc) not found, attempting to install it...'
                                sudo apt-get update && sudo apt-get install -y netcat-openbsd
                            }
                        """

                        nodesToProvision.each { ip, details ->
                            echo "--- Starting Provisioning on ${ip} for component: ${details.component} ---"
                            
                            def nodePasswords = passwords[ip]
                            if (!nodePasswords) {
                                error "FATAL: No password configuration found for IP: ${ip}"
                            }
                            def sshPort = config.ssh_port ?: 22
                            def deployUser = nodePasswords.deploy_user
                            def initialHost = "${nodePasswords.root_user}@${ip}"

                            // Step 1: Create a non-root user for Jenkins
                            echo "Step 1: Creating deployment user '${deployUser}' on ${ip}"
                            def createUserScript = """
                                set -e
                                echo "Creating group and user..."
                                sudo groupadd -f ${deployUser}
                                id ${deployUser} &>/dev/null || sudo useradd -m -g ${deployUser} -s /bin/bash ${deployUser}
                                echo "Setting password for ${deployUser}..."
                                echo "${deployUser}:${nodePasswords.deploy_password}" | sudo chpasswd
                                echo "Granting NOPASSWD sudo privileges..."
                                sudo usermod -aG sudo ${deployUser}
                                echo "${deployUser} ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/${deployUser}
                                sudo chmod 440 /etc/sudoers.d/${deployUser}
                                echo "Changing root password..."
                                echo "root:${nodePasswords.new_root_password}" | sudo chpasswd
                                echo "Setting timezone to Asia/Kolkata..."
                                sudo timedatectl set-timezone Asia/Kolkata
                            """
                            withEnv(["REMOTE_SCRIPT=${createUserScript}"]) {
                                sh 'echo "$REMOTE_SCRIPT" | sshpass -p \'' + nodePasswords.root_password + '\' ssh -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + initialHost + ' \'bash -s\''
                            }

                            // Step 2: Distribute the agent's public SSH key
                            echo "Step 2: Distributing local SSH public key to new user on ${ip}"
                            if (!fileExists(env.PUBLIC_KEY_PATH)) {
                                error "FATAL: Public key file not found at ${env.PUBLIC_KEY_PATH} on the Jenkins agent."
                            }
                            def publicKey = readFile(file: env.PUBLIC_KEY_PATH).trim()
                            def setupSshCommand = """
                                set -e
                                mkdir -p ~/.ssh && chmod 700 ~/.ssh
                                touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
                                grep -q -F '${publicKey}' ~/.ssh/authorized_keys || echo '${publicKey}' >> ~/.ssh/authorized_keys
                            """
                            def deployHost = "${deployUser}@${ip}"
                            sh 'echo \'' + setupSshCommand + '\' | sshpass -p \'' + nodePasswords.deploy_password + '\' ssh -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + deployHost + ' \'bash -s\''
                            
                            // Step 3: Verify passwordless SSH access is working
                            echo "Step 3: Verifying passwordless SSH access"
                            sh "ssh -i ${JENKINS_KEY_FILE} -p ${sshPort} -o StrictHostKeyChecking=no ${deployUser}@${ip} 'echo SSH key authentication successful'"
                            
                            // // Step 4: Trigger a reboot to apply all core changes
                            // echo "Step 4: Triggering reboot on ${ip}"
                            // // '|| true' ensures the pipeline doesn't fail when the SSH connection is severed by the reboot
                            // sh "ssh -i ${JENKINS_KEY_FILE} -p ${sshPort} -o StrictHostKeyChecking=no ${deployUser}@${ip} 'sudo reboot' || true"

                            // // Step 5: Wait for the server to come back online
                            // echo "Step 5: Waiting for ${ip} to come back online..."
                            // timeout(time: 5, unit: 'MINUTES') {
                            //     waitUntil {
                            //         try {
                            //             def status = sh(script: "nc -z -w 5 ${ip} ${sshPort}", returnStatus: true)
                            //             return status == 0
                            //         } catch (Exception e) {
                            //             return false
                            //         }
                            //     }
                            // }
                            // echo "Server ${ip} is back online."
                            
                            // sleep 10
                            
                            // echo "--- Finished Provisioning and Reboot on ${ip} ---"
                        }
                    }
                }
            }
        }

        stage('Configure Components') {
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: env.JENKINS_SSH_CREDENTIALS_ID,
                    keyFileVariable: 'JENKINS_KEY_FILE'
                )]) {
                    script {
                        nodesToProvision.each { ip, details ->
                            echo "--- Configuring Component on ${ip} for: ${details.component} ---"

                            def componentData = details.data
                            def componentName = details.component
                            def deployUser = passwords[ip].deploy_user
                            def sshPort = config.ssh_port ?: 22
                            def deployHost = "${deployUser}@${ip}"

                            // Start building the remote script
                            def remoteCommand = '''
                                set -e
                                echo '>>> 1. Disabling automatic unattended upgrades...'
                                sudo systemctl stop unattended-upgrades.service || true
                                sudo systemctl disable unattended-upgrades.service || true
                                echo 'APT::Periodic::Update-Package-Lists "0";' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades
                                echo 'APT::Periodic::Unattended-Upgrade "0";' | sudo tee -a /etc/apt/apt.conf.d/20auto-upgrades
                                
                                echo '>>> 2. Updating package lists...'
                                sudo apt-get update -y
                            '''

                            // Check for storage paths
                            def storagePath = componentData.properties?.storage
                            if (storagePath) {
                                remoteCommand += """
                                    echo '>>> 3. Creating storage directory: ${storagePath}...'
                                    sudo mkdir -p ${storagePath}
                                    sudo chown -R ${deployUser}:${deployUser} ${storagePath}
                                    sudo chmod -R 2775 ${storagePath}
                                """
                            } else {
                                remoteCommand += """
                                    echo '>>> 3. No specific storage path defined. Ensuring /data exists...'
                                    sudo mkdir -p /data
                                    sudo chown ${deployUser}:${deployUser} /data
                                """
                            }
                            
                            // Check for ports to free up
                            def componentPorts = componentData.ports?.values()
                            if (componentPorts) {
                                def portsString = componentPorts.join(' ')
                                remoteCommand += """
                                    echo '>>> 4. Freeing up required network ports...'
                                    for port in ${portsString}; do
                                        if sudo ss -tuln | grep -q ":\$port "; then
                                            echo "Port \$port is in use. Attempting to kill the process..."
                                            sudo fuser -k "\${port}/tcp" || true
                                            sleep 2
                                        fi
                                    done
                                """
                            } else {
                                remoteCommand += "\n echo '>>> 4. No component-specific ports defined to check.'"
                            }

                            // *** NEW SECTION: Add component-specific commands ***
                            remoteCommand += "\n echo '>>> 5. Running component-specific setup for ${componentName}...'"
                            switch (componentName) {
                                case 'backend_job':
                                    remoteCommand += """
                                        sudo apt-get install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev
                                    """
                                    break
                                case 'doris_be':
                                    remoteCommand += '''
                                        echo "Setting vm.max_map_count..."
                                        sudo sh -c 'echo "vm.max_map_count=2000000" > /etc/sysctl.d/60-doris-be.conf'
                                        sudo sysctl --system
                                        
                                        echo "Disabling swap..."
                                        sudo swapoff -a
                                        sudo sed -i '/swap/d' /etc/fstab
                                    '''
                                    break
                                case 'kafka':
                                    remoteCommand += """
                                        sudo apt-get install -y kcat
                                    """
                                    break
                                default:
                                    remoteCommand += "\n echo 'No additional setup required for this component.'"
                                    break
                            }
                            
                            echo "Executing final configuration script on ${ip}..."
                            withEnv(["REMOTE_COMMAND=${remoteCommand}"]) {
                                sh 'echo "$REMOTE_COMMAND" | ssh -i ' + JENKINS_KEY_FILE + ' -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + deployHost + ' \'bash -s\''
                            }
                            
                            echo "--- Finished Component Configuration on ${ip} ---"
                        }
                    }
                }
            }
        }

        // stage('Install Dependencies') {
        //     steps {
        //         withCredentials([sshUserPrivateKey(
        //             credentialsId: env.JENKINS_SSH_CREDENTIALS_ID,
        //             keyFileVariable: 'JENKINS_KEY_FILE'
        //         )]) {
        //             script {
        //                 nodesToProvision.each { ip, details ->
        //                     echo "--- Installing Dependencies on ${ip} for component: ${details.component} ---"

        //                     def componentData = details.data
        //                     def nodePasswords = passwords[ip]
        //                     def javaVersion = componentData.java_version
        //                     def pythonVersion = componentData.python_version
        //                     def deployUser = nodePasswords.deploy_user
        //                     def sshPort = config.ssh_port ?: 22
                            
        //                     if (javaVersion && pythonVersion) {
        //                         echo "Required versions - Java: ${javaVersion}, Python: ${pythonVersion}"
                                
        //                         retry(3) {
        //                             // sleep 15
                                    
        //                             echo "Attempting to connect to ${ip} to install dependencies..."

        //                             def remoteScriptPath = "/tmp/${env.JAVA_PYTHON_SCRIPT}"
        //                             def deployHost = "${deployUser}@${ip}"

        //                             echo "Step 1: Copying '${env.JAVA_PYTHON_SCRIPT}' to ${ip}"
        //                             sh "scp -i ${JENKINS_KEY_FILE} -P ${sshPort} -o StrictHostKeyChecking=no ./${env.JAVA_PYTHON_SCRIPT} ${deployHost}:${remoteScriptPath}"

        //                             echo "Step 2: Executing installation script on ${ip}"
        //                             def remoteCommand = """
        //                                 set -e
        //                                 chmod +x ${remoteScriptPath}
        //                                 sudo ${remoteScriptPath} ${pythonVersion} ${javaVersion}
        //                                 rm ${remoteScriptPath}
        //                             """
        //                             sh 'echo \'' + remoteCommand + '\' | ssh -i ' + JENKINS_KEY_FILE + ' -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + deployHost + ' \'bash -s\''
        //                         }
                                
        //                         echo "Successfully installed dependencies on ${ip}"
        //                     } else {
        //                         echo "Skipping dependency installation for ${details.component} as versions are not specified."
        //                     }
        //                     echo "--- Finished Dependencies on ${ip} ---"
        //                 }
        //             }
        //         }
        //     }
        // }


    }

    post {
        // I've commented out the cleanWs() for now to make debugging easier.
        // We can re-enable it once the pipeline is working.
        // always {
        //     cleanWs()
        // }
        success {
            echo "Pipeline completed successfully!"
        }
        failure {
            echo "Pipeline failed. Please check the logs."
        }
    }
}