// Jenkinsfile

// Define script-level variables to hold our configurations
def config = [:]
def passwords = [:]

pipeline {
    agent any

    environment {
        CONFIG_FILE = "initialization_deployment_config.json"
        PASSWORDS_FILE = "passwords.json" // We'll improve this soon!
        SUDO_COMMANDS_DIR = "sudo_commands"
        JAVA_PYTHON_SCRIPT = "install_java_python.sh"
    }
    

    stages {
        stage('Preparation') {
            steps {
                script {
                    // Step 1: Checkout code from the repository
                    echo "Checking out source code..."
                    checkout scm

                    // Step 2: Load the main configuration file
                    echo "Loading deployment configuration from ${env.CONFIG_FILE}"
                    if (fileExists(env.CONFIG_FILE)) {
                        config = readJSON file: env.CONFIG_FILE
                        echo "Configuration loaded successfully."
                    } else {
                        error "FATAL: Configuration file '${env.CONFIG_FILE}' not found!"
                    }

                    // Step 3: Load the passwords file
                    echo "Loading passwords from ${env.PASSWORDS_FILE}"
                    if (fileExists(env.PASSWORDS_FILE)) {
                        passwords = readJSON file: env.PASSWORDS_FILE
                        echo "Passwords file loaded. (Note: Will be replaced by Jenkins Credentials)"
                    } else {
                        error "FATAL: Passwords file '${env.PASSWORDS_FILE}' not found!"
                    }
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline run finished."
            cleanWs()
        }
        success {
            echo "Pipeline completed successfully!"
        }
        failure {
            echo "Pipeline failed. Please check the logs."
        }
    }
}