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
    IMAGE_NAME = "gkamalakar1006/board_games_new"

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
          env.BRANCH_NAME_ONLY = env.GIT_BRANCH
            .replaceFirst(/^origin\//, '')
            .replaceFirst(/^refs\/heads\//, '')

          env.SHORT_COMMIT = sh(
            script: "git rev-parse --short=6 HEAD",
            returnStdout: true
          ).trim()

          // Image tagging rule
          if (env.BRANCH_NAME_ONLY == 'main') {
            env.IMAGE_TAG = env.SHORT_COMMIT
          } else {
            env.IMAGE_TAG = env.BUILD_NUMBER
          }

          echo "Branch     : ${env.BRANCH_NAME_ONLY}"
          echo "Commit SHA: ${env.SHORT_COMMIT}"
          echo "Image Tag : ${env.IMAGE_TAG}"
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
      when {
        anyOf {
          expression { env.BRANCH_NAME_ONLY.startsWith('feature-') }
          expression { env.BRANCH_NAME_ONLY.startsWith('fix-') }
          branch 'main'
        }
      }
      steps {
        sh '''
          mvn clean install \
            -Dmaven.repo.local=${MAVEN_REPO}
        '''
      }
    }

    stage('Save Maven Cache') {
      when { branch 'main' }
      steps {
        writeCache(
          name: "${MVN_CACHE_NAME}",
          includes: "${MAVEN_REPO}/**"
        )
      }
    }

    /* ================= KANIKO BUILD ================= */
    stage('Kaniko Build & Push') {
      when {
        anyOf {
          expression { env.BRANCH_NAME_ONLY.startsWith('feature-') }
          expression { env.BRANCH_NAME_ONLY.startsWith('fix-') }
          branch 'main'
        }
      }
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
  }

  post {
    always {
      echo "Build Result: ${currentBuild.currentResult}"
      deleteDir()
    }
  }
}
