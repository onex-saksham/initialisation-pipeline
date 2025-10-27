// Jenkinsfile

// Define script-level variables to hold our configurations
def config = [:]
def passwords = [:]
def nodesToProvision = [:] // New map to hold the provisioning plan

pipeline {
    agent any

    environment {
        CONFIG_FILE = "initialization_deployment_config.json"
        PASSWORDS_FILE = "passwords.json"
        SUDO_COMMANDS_DIR = "sudo_commands"
        JAVA_PYTHON_SCRIPT = "install_java_python.sh"
    }

    stages {
        stage('Preparation') {
            steps {
                script {
                    echo "Checking out source code..."
                    checkout scm

                    echo "Loading deployment configuration from ${env.CONFIG_FILE}"
                    if (fileExists(env.CONFIG_FILE)) {
                        config = readJSON file: env.CONFIG_FILE
                    } else {
                        error "FATAL: Configuration file '${env.CONFIG_FILE}' not found!"
                    }

                    echo "Loading passwords from ${env.PASSWORDS_FILE}"
                    if (fileExists(env.PASSWORDS_FILE)) {
                        passwords = readJSON file: env.PASSWORDS_FILE
                    } else {
                        error "FATAL: Passwords file '${env.PASSWORDS_FILE}' not found!"
                    }
                }
            }
        }

        // NEW STAGE
        stage('Identify Target Nodes') {
            steps {
                script {
                    echo "Parsing configuration to identify all target nodes..."
                    // These are the top-level keys in the JSON that are not actual components
                    def excludedKeys = ['releases', 'base_user', 'user', 'deployment_type', 'deployment_path', 'deploy', 'ssh_port']

                    // Iterate over each component in the config file
                    config.each { componentName, componentData ->
                        if (!(componentName in excludedKeys) && (componentData instanceof Map)) {
                            def ips = []
                            // Check for 'node_ip' or 'broker_ip' keys, which hold the IPs
                            ['node_ip', 'broker_ip'].each { key ->
                                if (componentData.containsKey(key)) {
                                    def ipValue = componentData[key]
                                    // Add the IP(s) to our list, whether it's a single string or a list of strings
                                    ips.addAll(ipValue instanceof List ? ipValue : [ipValue])
                                }
                            }

                            // For each unique IP, add it to our plan
                            ips.unique().each { ip ->
                                if (ip && ip instanceof String && !ip.startsWith('_')) { // Basic validation
                                    echo "Found node: ${ip} for component: ${componentName}"
                                    nodesToProvision[ip] = [component: componentName, data: componentData]
                                }
                            }
                        }
                    }

                    if (nodesToProvision.isEmpty()) {
                        error "FATAL: No valid IP addresses found in the configuration file to provision."
                    } else {
                        echo "Plan created. Identified ${nodesToProvision.size()} unique nodes to provision."
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