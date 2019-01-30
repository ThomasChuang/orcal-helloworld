#!/usr/bin/env groovy

// deployment:
// if branch isn't 'master'
//   - run tests
//   - build container image with tag=<branch_name>
//   - push created image to registry
// if branch is 'master' and parameter DEPLOY_PROD=false
//   - run tests
//   - build container image with tag=<semver> (e.g. v1.2.3)
//   - push image to registry
//   - deploy image to development cluster
//   - create new tag=<semver> in git and push it to repo
// if branch is 'master' and parameter DEPLOY_PROD=true
//   - deploy image created previously and tagged with <semver> to prod clusters.
//     by default latest tag will be deployed, but it's possible to select previous tag,
//     see environment RELEASE_VERSION for more details
// also see parameters description for more info on deploy logic.
//
// kubernetes credentials:
// names of jenkins credential must align with naming of
// app environment configuration files (src/conf/) prefixed with 'kubeconfig-' 
// example:
//     app environment config name:     'production-sg' (src/conf/production-sg.json)
//     jenkins kubeconfig secret name:  'kubeconfig-production-sg'
// jenkins credentials should contain string with base64 encoded kubeconfig.

pipeline {
    agent {
        node { label 'container-host' }
    }
    
    options {
        timeout(time: 1, unit: 'HOURS')
        retry(0)
        quietPeriod(0)
        buildDiscarder(logRotator(numToKeepStr: '30', daysToKeepStr: '90'))
        timestamps()
        ansiColor('xterm')
    }

    parameters {
        booleanParam(
            name: 'DEPLOY_PROD',
            defaultValue: false,
            description: 'set to true to deploy app to production environments')

        string(
            name: 'PROD_ENVIRONMENTS',
            defaultValue: 'production-sg production-my production-id production-ph production-th production-tw production-au',
            description: '''
                space separated list of production environments.
                this parameter only affects deployment, when DEPLOY_PROD=true.
            ''')

        string(
            name: 'RELEASE_VERSION',
            defaultValue: '',
            description: '''
                this parameter affects only master branch builds
                if DEPLOY_PROD=false and RELEASE_VERSION=''        - create new tag by incrementing minor version of previous tag
                if DEPLOY_PROD=false and RELEASE_VERSION='v1.2.3'  - create new tag 'v1.2.3'

                if DEPLOY_PROD=true and RELEASE_VERSION=''         - use latest tag to deploy to prod environments
                if DEPLOY_PROD=true and RELEASE_VERSION='v1.2.3'   - deploy 'v1.2.3' to prod environments (image for v1.2.3 must exist)
            ''')

        string(
            name: 'HELM_ARGS',
            defaultValue: '',
            description: 'additional arguments passed to "helm template" command')

        string(
            name: 'GITHUB_CREDENTIALS',
            defaultValue: 'shopback-ci-ssh-key',
            description: 'name of jenkins credentials (ssh key) used to pull submodule and push release tag to app github repo')

        string(
            name: 'JENKINS_AWS_KEYS',
            defaultValue: 'jenkins-aws-keys',
            description: 'name of jenkins credentials which contains AWS access/secret keys (required for kubectl iam-authenticator)')
    }

    environment {
        // container image name stucture: orgname/appname:tag
        // this var represents 'orgname' part
        REGISTRY_ORG = 'shopbackcom'

        // extract app name from repo url, e.g. git@github.com:shopback/foobar.git -> foobar
        APP_NAME = sh(
            script: '''#!/bin/bash -e
                echo ${GIT_URL} | awk -F '/' '{s=$2; FS="."; split(s, a); print a[1]}'
            ''',
            returnStdout: true
        ).trim()
    }

    stages {
        stage("Prepare workspace") {
            steps {
                // update submodule and fetch tags
                sshagent (credentials: [params.GITHUB_CREDENTIALS]) {
                    sh('''#!/bin/bash -e
                        git submodule update --init
                        git submodule status
                        git fetch --tags
                    ''')
                }

                // save release version in file to reuse it in further steps
                // it holds semver value used to tag releases and images in master branch, e.g. v1.2.3
                sh('''#!/bin/bash -e
                    LATEST_TAG=$(git tag --sort="v:refname" | awk '/^v[0-9].*$/ {v=$1} END {print v}')

                    # determine release version if input parameter is empty, otherwise use from input
                    if [[ "$DEPLOY_PROD" == "true" && -z "$RELEASE_VERSION" ]]; then
                        RELEASE_VERSION="$LATEST_TAG"
                    elif [[ "$DEPLOY_PROD" != "true" && -z "$RELEASE_VERSION" ]]; then
                        if [[ -z "$LATEST_TAG" ]]; then
                            # no previous tags, create initial
                            RELEASE_VERSION="v0.0.1"
                        else
                            # increment latest existing tag
                            RELEASE_VERSION=$(echo "$LATEST_TAG" | awk -F '.' '{printf("%s.%s.%s", $1, $2, $3 + 1)}')
                        fi
                    fi

                    echo "$RELEASE_VERSION" > RELEASE_VERSION 
                ''')

                // print build parameters
                sh('''#!/bin/bash
                    echo "
                    GIT_URL:             $GIT_URL
                    GIT_BRANCH:          $GIT_BRANCH
                    GIT_COMMIT:          $GIT_COMMIT
                    APP_NAME:            $APP_NAME
                    REGISTRY_ORG:        $REGISTRY_ORG
                    RELEASE_VERSION:     $(cat RELEASE_VERSION)
                    DEPLOY_PROD:         $DEPLOY_PROD
                    PROD_ENVIRONMENTS:   $PROD_ENVIRONMENTS
                    GITHUB_CREDENTIALS:  $GITHUB_CREDENTIALS
                    JENKINS_AWS_KEYS:    $JENKINS_AWS_KEYS"
                ''')
            }
        }

        stage("Build image and run tests") {
            when {
                environment name: 'DEPLOY_PROD', value: 'false'
            }
            steps {
                // run tests
                sh('deploy/scripts/test.sh')

                // build image and push it to registry
                sh('''#!/bin/bash -e
                    IMG_REPO="${REGISTRY_ORG}/${APP_NAME}"
                    if [[ "$GIT_BRANCH" == "master" ]]; then
                        IMG_TAG=$(cat RELEASE_VERSION)
                    else
                        IMG_TAG="${GIT_BRANCH}"
                    fi
                    sudo docker build -t ${IMG_REPO}:${IMG_TAG} .
                    sudo docker push ${IMG_REPO}:${IMG_TAG}
                ''')
            }
        }

        stage("Push new tag to git repo") {
            when {
                branch 'master'
                environment name: 'DEPLOY_PROD', value: 'false'
            }
            steps {
                sshagent (credentials: [params.GITHUB_CREDENTIALS]) {
                    sh('''#!/bin/bash -e
                        git tag -f $(cat RELEASE_VERSION)
                        git push -f --tag
                    ''')
                }
            }
        }

        stage("Deploy to development cluster") {
            when {
                branch 'master'
                environment name: 'DEPLOY_PROD', value: 'false'
            }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: params.JENKINS_AWS_KEYS,
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'),
                    string(
                        credentialsId: 'kubeconfig-development',
                        variable: 'KUBECONFIG_DEVELOPMENT')
                ]) {
                    sh('''#!/bin/bash -e
                        RELEASE_VERSION=$(cat RELEASE_VERSION)

                        cd deploy/helm
                        echo "$KUBECONFIG_DEVELOPMENT" | base64 -d > kubeconfig
                        export KUBECONFIG=kubeconfig

                        sk deploy development \
                            --set org=${REGISTRY_ORG} \
                            --set app=${APP_NAME} \
                            --set tag=${RELEASE_VERSION} ${HELM_ARGS}

                        sleep 10
                        sk status development

                        rm -f kubeconfig
                    ''')
                }
            }
        }

        stage("Deploy to production") {
            when {
                branch 'master'
                environment name: 'DEPLOY_PROD', value: 'true'
            }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: params.JENKINS_AWS_KEYS,
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'),
                    string(
                        credentialsId: 'kubeconfig-production-sg',
                        variable: 'KUBECONFIG_PRODUCTION_SG'),
                    string(
                        credentialsId: 'kubeconfig-production-id',
                        variable: 'KUBECONFIG_PRODUCTION_ID'),
                    string(
                        credentialsId: 'kubeconfig-production-th',
                        variable: 'KUBECONFIG_PRODUCTION_TH'),
                    string(
                        credentialsId: 'kubeconfig-production-tw',
                        variable: 'KUBECONFIG_PRODUCTION_TW')
                ]) {
                    sh('''#!/bin/bash -e
                        RELEASE_VERSION=$(cat RELEASE_VERSION)

                        echo -e "\nenvironments:\n$(echo ${PROD_ENVIRONMENTS} | tr ' ' '\n')\n"

                        cd deploy/helm
                        export KUBECONFIG=kubeconfig

                        for E in ${PROD_ENVIRONMENTS}; do
                            echo -e "\n\\e[34m===== deploying to $E =====\\e[39m"
                            if [[ ! -f "../environments/$E.yaml" ]]; then
                                echo -e "\\e[33m===== values file 'deploy/environments/$E.yaml' not found, skipping deploy =====\\e[39m"
                                continue
                            fi
                            KUBECONFIG_CONTENT_VAR="KUBECONFIG_$(echo $E | awk '{gsub("-", "_", $0); print toupper($0)}')"
                            echo "${!KUBECONFIG_CONTENT_VAR}" | base64 -d > kubeconfig

                            sk deploy $E \
                                --set org=${REGISTRY_ORG} \
                                --set app=${APP_NAME} \
                                --set tag=${RELEASE_VERSION} ${HELM_ARGS}

                            sleep 10
                            sk status $E

                            echo -e "\n\\e[32m===== deploy to $E finished =====\\e[39m"
                        done

                        rm -f kubeconfig
                    ''')
                }
            }
        }
    }

    post {
        success {
            cleanWs()
        }
    }
}
