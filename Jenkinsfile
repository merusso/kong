pipeline {
    agent none
    options {
        retry(1)
        timeout(time: 3, unit: 'HOURS')
    }
    environment {
        UPDATE_CACHE = "true"
        DOCKER_CREDENTIALS = credentials('dockerhub')
        DOCKER_USERNAME = "${env.DOCKER_CREDENTIALS_USR}"
        DOCKER_PASSWORD = "${env.DOCKER_CREDENTIALS_PSW}"
        DOCKER_CLI_EXPERIMENTAL = "enabled"
        // PULP_PROD and PULP_STAGE are used to do releases
        PULP_HOST_PROD = "https://api.pulp.konnect-prod.konghq.com"
        PULP_PROD = credentials('PULP')
        PULP_HOST_STAGE = "https://api.pulp.konnect-stage.konghq.com"
        PULP_STAGE = credentials('PULP_STAGE')
        DEBUG = 0
    }
    stages {
        stage('Release -- Release Branch Release to Unofficial Asset Stores') {
            when {
                beforeAgent true
                anyOf {
                    branch 'colin-testing';
                }
            }
            parallel {
                stage('Alpine') {
                    agent {
                        node {
                            label 'bionic'
                        }
                    }
                    environment {
                        KONG_SOURCE_LOCATION = "${env.WORKSPACE}"
                        KONG_BUILD_TOOLS_LOCATION = "${env.WORKSPACE}/../kong-build-tools"
                        AWS_ACCESS_KEY = "instanceprofile"
                        CACHE=false
                        PACKAGE_TYPE = "apk"
                        GITHUB_SSH_KEY = credentials('github_bot_ssh_key')
                    }
                    options {
                        retry(2)
                        timeout(time: 2, unit: 'HOURS')
                    }
                    steps {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true'
                        sh 'make setup-kong-build-tools'
                        sh 'curl https://raw.githubusercontent.com/Kong/kong/master/scripts/setup-ci.sh | bash'
                        sh 'make RESTY_IMAGE_BASE=alpine RESTY_IMAGE_TAG=3 KONG_TEST_CONTAINER_TAG="${GIT_BRANCH##*/}-alpine" DOCKER_MACHINE_ARM64_NAME="kong-"`cat /proc/sys/kernel/random/uuid` release-docker-images'
                    }
                }
            }
        }
    }
}
