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
    disableConcurrentBuilds()
    timeout(time: 60, unit: 'MINUTES')
  }

  environment {
    /* ================= IMAGE ================= */
    IMAGE_NAME = "gkamalakar1006/board_games_neww"

    /* ================= MAVEN ================= */
    MAVEN_REPO = 'maven-repo'
    MVN_CACHE_NAME = 'mvn-cache'
  }

  stages {

    /* ================= CHECKOUT ================= */
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.BRANCH_NAME_ONLY = sh(
            script: "git rev-parse --abbrev-ref HEAD",
            returnStdout: true
          ).trim()

          env.SHORT_COMMIT = sh(
            script: "git rev-parse --short=6 HEAD",
            returnStdout: true
          ).trim()

          env.IMAGE_TAG = env.SHORT_COMMIT

          echo "Branch     : ${env.BRANCH_NAME_ONLY}"
          echo "Commit SHA : ${env.SHORT_COMMIT}"
          echo "Image Tag  : ${env.IMAGE_TAG}"
        }
      }
    }

    /* ================= MAVEN CACHE ================= */
    stage('Restore Maven Cache') {
      steps {
        sh 'mkdir -p ${MAVEN_REPO}'
        readCache name: "${MVN_CACHE_NAME}"
      }
    }

    /* ================= MAVEN BUILD ================= */
    stage('Maven Build') {
      steps {
        sh '''
          mvn clean install \
            -Dmaven.repo.local=${MAVEN_REPO}
        '''
      }
    }

    stage('Save Maven Cache') {
      steps {
        writeCache(
          name: "${MVN_CACHE_NAME}",
          includes: "${MAVEN_REPO}/**"
        )
      }
    }

    /* ================= KANIKO BUILD ================= */
    stage('Kaniko Build & Push') {
      steps {
        container('kaniko') {
          sh '''
            /kaniko/executor \
              --context /workspace \
              --dockerfile Dockerfile \
              --destination ${IMAGE_NAME}:${IMAGE_TAG} \
              --destination ${IMAGE_NAME}:latest \
              --cache=true
          '''
        }
      }
    }

    /* ================= REGISTER BUILD ARTIFACT ================= */
    stage('Register Build Artifact') {
      steps {
        script {
          echo "Registering Docker image metadata to CloudBees Platform"

          registerBuildArtifactMetadata(
            name: "board-games-backend",
            url: "docker.io/${IMAGE_NAME}:${IMAGE_TAG}",
            version: "${IMAGE_TAG}",
            label: "main,ci",
            type: "docker"
          )
        }
      }
    }
  }

  post {
    always {
      echo "Build Result: ${currentBuild.currentResult}"
      deleteDir()
    }
  }
}
