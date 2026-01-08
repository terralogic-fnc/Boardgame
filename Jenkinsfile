pipeline {
  agent {
    kubernetes {
      cloud 'terralogic-eks-agent'
      namespace 'cloudbees-builds'
      inheritFrom 'jenkins-kaniko-agent'
      defaultContainer 'jnlp'
    }
  }

  options {
    skipDefaultCheckout true
    disableConcurrentBuilds()
    durabilityHint('PERFORMANCE_OPTIMIZED')
  }

  environment {
    /* ================= MAVEN ================= */
    MAVEN_REPO     = 'maven-repo'
    MVN_CACHE_NAME = 'mvn-cache'

    /* ================= TRIVY ================= */
    TRIVY_CACHE_DIR          = '.trivycache'
    TRIVY_DB_REPOSITORY      = 'docker.io/aquasec/trivy-db'
    TRIVY_JAVA_DB_REPOSITORY = 'docker.io/aquasec/trivy-java-db'

    /* ================= KANIKO ================= */
    KANIKO_CACHE_DIR = '/workspace/.kaniko-cache'
  }

  stages {

    /* ================= SCM CHECKOUT ================= */
    stage('Checkout') {
      steps {
        checkout([
          $class: 'GitSCM',
          branches: [[name: "${branchName}"]],
          userRemoteConfigs: [[
            url: "${repoUrl}",
            credentialsId: "${gitCredentials}"
          ]]
        ])
      }
    }

    /* ================= DERIVE IMAGE NAME ================= */
    stage('Derive Image Name') {
      steps {
        script {
          def repo = sh(
            script: "basename -s .git ${repoUrl}",
            returnStdout: true
          ).trim()

          env.IMAGE_NAME = "docker.io/gkamalakar1006/${repo}"
          env.IMAGE_TAG  = "${BUILD_NUMBER}"

          echo "Image to build: ${env.IMAGE_NAME}:${env.IMAGE_TAG}"
        }
      }
    }

    /* ================= RESTORE MAVEN CACHE ================= */
    stage('Restore Maven Cache') {
      steps {
        sh "mkdir -p ${MAVEN_REPO}"
        readCache name: "${MVN_CACHE_NAME}"
      }
    }

    /* ================= MAVEN BUILD ================= */
    stage('Maven Build') {
      steps {
        sh """
          mvn clean install \
            -Dmaven.repo.local=${MAVEN_REPO} \
            -DskipTests
        """
      }
    }

    /* ================= SAVE MAVEN CACHE ================= */
    stage('Save Maven Cache') {
      steps {
        writeCache(
          name: "${MVN_CACHE_NAME}",
          includes: "${MAVEN_REPO}/**"
        )
      }
    }

    /* ================= SONARQUBE SCAN ================= */
    stage('SonarQube Scan') {
      steps {
        withSonarQubeEnv('sonar-server') {
          sh """
            mvn \
              -Dmaven.repo.local=${MAVEN_REPO} \
              org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
              -Dsonar.projectKey=${sonarProjectKey} \
              -Dsonar.projectName=${sonarProjectKey}
          """
        }
      }
    }

    /* ================= KANIKO BUILD & PUSH ================= */
    stage('Kaniko Build & Push') {
      steps {
        container('kaniko') {
          sh '''
            mkdir -p "$KANIKO_CACHE_DIR"

            /kaniko/executor \
              --context /workspace \
              --dockerfile Dockerfile \
              --destination ${IMAGE_NAME}:${IMAGE_TAG} \
              --destination ${IMAGE_NAME}:latest \
              --cache=true \
              --cache-dir="$KANIKO_CACHE_DIR"
          '''
        }
      }
    }

    /* ================= ARGO CD DEPLOY (GITOPS) ================= */
    stage('Argo CD Deploy (GitOps)') {
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'gitops-github-token',
            usernameVariable: 'GIT_USER',
            passwordVariable: 'GIT_TOKEN'
          )
        ]) {
          sh '''
            set -e
            echo "Updating GitOps repository for Argo CD deployment"

            rm -rf argo-deploy
            git clone https://${GIT_USER}:${GIT_TOKEN}@github.com/kamalakar22/argo-deploy.git
            cd argo-deploy

            sed -i "s|image: .*|image: ${IMAGE_NAME}:${IMAGE_TAG}|g" manifests/deployment-service.yaml

            git config user.email "jenkins@cloudbees.local"
            git config user.name "jenkins"

            git add manifests/deployment-service.yaml
            git commit -m "Deploy ${IMAGE_NAME}:${IMAGE_TAG} (Build #${BUILD_NUMBER})"
            git push origin main

            echo "GitOps repo updated. Argo CD will auto-sync."
          '''
        }
      }
    }
  }

  /* ================= POST ================= */
  post {
    always {
      // Avoid archive warnings when Trivy is disabled
      sh 'mkdir -p trivy-reports || true'

      archiveArtifacts allowEmptyArchive: true, artifacts: '''
        trivy-reports/*.html,
        trivy-reports/*.json
      '''

      echo "Build #: ${BUILD_NUMBER}"
      echo "Result  : ${currentBuild.currentResult}"

      deleteDir()
    }
  }
}
