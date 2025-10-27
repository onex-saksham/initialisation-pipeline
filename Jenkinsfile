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
        // This is the ID of the SSH private key stored in Jenkins Credentials
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

        stage('Provision Servers') {
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: env.JENKINS_SSH_CREDENTIALS_ID,
                    keyFileVariable: 'JENKINS_KEY_FILE'
                )]) {
                    script {
                        sh 'command -v sshpass >/dev/null 2>&1 || { echo >&2 "sshpass is not installed. Aborting."; exit 1; }'

                        nodesToProvision.each { ip, details ->
                            echo "--- Starting Provisioning on ${ip} for component: ${details.component} ---"
                            
                            def nodePasswords = passwords[ip]
                            if (!nodePasswords) {
                                error "FATAL: No password configuration found for IP: ${ip}"
                            }

                            def initialHost = "${nodePasswords.root_user}@${ip}"
                            def sshPort = config.ssh_port ?: 22

                            echo "Step 1: Creating deployment user '${nodePasswords.deploy_user}' on ${ip}"
                            def createUserScript = """
                                set -e
                                echo "Creating group and user..."
                                sudo groupadd -f ${nodePasswords.deploy_user}
                                id ${nodePasswords.deploy_user} &>/dev/null || sudo useradd -m -g ${nodePasswords.deploy_user} -s /bin/bash ${nodePasswords.deploy_user}
                                echo "Setting password for ${nodePasswords.deploy_user}..."
                                echo "${nodePasswords.deploy_user}:${nodePasswords.deploy_password}" | sudo chpasswd
                                echo "Granting NOPASSWD sudo privileges..."
                                sudo usermod -aG sudo ${nodePasswords.deploy_user}
                                echo "${nodePasswords.deploy_user} ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/${nodePasswords.deploy_user}
                                sudo chmod 440 /etc/sudoers.d/${nodePasswords.deploy_user}
                                echo "Changing root password..."
                                echo "root:${nodePasswords.new_root_password}" | sudo chpasswd
                                echo "Setting timezone to Asia/Kolkata..."
                                sudo timedatectl set-timezone Asia/Kolkata
                            """
                            
                            withEnv(["REMOTE_SCRIPT=${createUserScript}"]) {
                                sh 'echo "$REMOTE_SCRIPT" | sshpass -p \'' + nodePasswords.root_password + '\' ssh -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + initialHost + ' \'bash -s\''
                            }

                            // *** THE FIX: Read local public key and distribute it manually ***
                            echo "Step 2: Distributing local SSH public key to new user on ${ip}"

                            // 1. Read the public key from the Jenkins agent's filesystem
                            def publicKey = readFile(env.PUBLIC_KEY_PATH).trim()

                            // 2. Prepare the remote command to add the key securely
                            def deployHost = "${nodePasswords.deploy_user}@${ip}"
                            def setupSshCommand = """
                                set -e
                                echo 'Setting up SSH directory and authorized_keys...'
                                mkdir -p ~/.ssh
                                chmod 700 ~/.ssh
                                touch ~/.ssh/authorized_keys
                                chmod 600 ~/.ssh/authorized_keys
                                echo 'Adding public key...'
                                # Use grep to prevent adding a duplicate key
                                grep -q -F "$PUBLIC_KEY" ~/.ssh/authorized_keys || echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
                            """

                            // 3. Execute the command on the remote host using the deploy_user's password
                            withEnv(["PUBLIC_KEY=${publicKey}", "SETUP_COMMAND=${setupSshCommand}"]) {
                                sh 'echo "$SETUP_COMMAND" | sshpass -p \'' + nodePasswords.deploy_password + '\' ssh -p ' + sshPort + ' -o StrictHostKeyChecking=no ' + deployHost + ' \'bash -s\''
                            }

                            echo "Step 3: Verifying passwordless SSH access"
                            def deployUser = nodePasswords.deploy_user
                            // This verification now uses the private key from credentials, which matches the public key we just installed
                            sh "ssh -i ${JENKINS_KEY_FILE} -p ${sshPort} -o StrictHostKeyChecking=no ${deployUser}@${ip} 'echo SSH key authentication successful'"
                            
                            echo "--- Finished Provisioning on ${ip} ---"
                        }
                    }
                }
            }
        }
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