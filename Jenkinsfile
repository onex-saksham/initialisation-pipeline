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
        JENKINS_ROOT_CREDENTIALS_ID = 'server-root-credentials'
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

                            // Define the remote server for the initial password-based connection
                            def initialRemote = [
                                host: ip,
                                user: nodePasswords.root_user,
                                port: config.ssh_port ?: 22,
                                allowAnyHosts: true,
                                credentialsId: env.JENKINS_ROOT_CREDENTIALS_ID // Use the new credential
                            ]

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
                            
                            // *** THE FIX: Use sshScript for reliable remote execution ***
                            sshScript remote: initialRemote, script: createUserScript

                            echo "Step 2: Distributing Jenkins SSH key to new user on ${ip}"
                            def deployHost = "${nodePasswords.deploy_user}@${ip}"
                            
                            // We still use sshpass here as it's a simple way to use the deploy_password
                            sh """
                                sshpass -p '${nodePasswords.deploy_password}' ssh-copy-id -i ${JENKINS_KEY_FILE} -p ${initialRemote.port} -o StrictHostKeyChecking=no ${deployHost}
                            """

                            echo "Step 3: Verifying passwordless SSH access with the 'SSH Pipeline Steps' plugin"
                            
                            // Define the remote for the final key-based verification
                            def finalRemote = [
                                host: ip,
                                user: nodePasswords.deploy_user,
                                port: initialRemote.port,
                                allowAnyHosts: true,
                                credentialsId: env.JENKINS_SSH_CREDENTIALS_ID // The SSH key credential
                            ]

                            sshCommand remote: finalRemote, command: "echo 'SSH key authentication successful via sshCommand'"
                            
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