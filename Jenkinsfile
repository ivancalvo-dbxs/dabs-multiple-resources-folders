// Deploys the bundle to the production target only.
// Only resources-prod/ files are part of the production target, so dev resources are never deployed from here.
pipeline {
    agent any

    parameters {
        string(name: 'CATALOG', defaultValue: 'ivancalvo_playground_catalog', description: 'Catalog passed to the bundle as BUNDLE_VAR_catalog')
    }

    environment {
        DATABRICKS_CLI_VERSION   = '1.19.0'
        DATABRICKS_HOST          = 'https://fevm-ivancalvo-playground.cloud.databricks.com'
        DATABRICKS_CLIENT_ID     = credentials('databricks-client-id')
        DATABRICKS_CLIENT_SECRET = credentials('databricks-client-secret')
        BUNDLE_VAR_catalog       = "${params.CATALOG}"
    }

    stages {
        stage('Install Databricks CLI') {
            steps {
                // The official install.sh needs sudo on Linux, so download the pinned release into the workspace.
                sh '''
                    curl -fsSL -o cli.zip "https://github.com/databricks/cli/releases/download/v${DATABRICKS_CLI_VERSION}/databricks_cli_${DATABRICKS_CLI_VERSION}_linux_amd64.zip"
                    unzip -o -q cli.zip databricks -d bin
                    rm cli.zip
                    bin/databricks --version
                '''
            }
        }

        stage('Validate') {
            steps {
                sh 'bin/databricks bundle validate --target production'
            }
        }

        stage('Deploy') {
            steps {
                sh 'bin/databricks bundle deploy --target production'
            }
        }
    }
}
