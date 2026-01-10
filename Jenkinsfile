pipeline {
  agent {
    kubernetes {
      cloud 'terralogic-eks-agent'
      inheritFrom 'jenkins-kaniko-agent'
      defaultContainer 'jnlp'
    }
  }

  options {
    disableConcurrentBuilds()
    durabilityHint('PERFORMANCE_OPTIMIZED')
  }

  environment {
    IMAGE_NAME = "gkamalakar1006/boardgames"

    MAVEN_REPO     = 'maven-repo'
    MVN_CACHE_NAME = 'mvn-cache'


    EMAIL_RECIPIENTS = 'aws-fnc@terralogic.com,kamalakar.reddy@terralogic.com'
  }

  stages {

    /* ================= INIT ================= */

    stage('Init') {
      steps {
        script {
          env.IMAGE_TAG = env.GIT_COMMIT.substring(0, 6)
        }
        echo "Branch     : ${BRANCH_NAME}"
        echo "Commit     : ${GIT_COMMIT}"
        echo "Image Tag  : ${IMAGE_TAG}"
        echo "Full Image : ${IMAGE_NAME}:${IMAGE_TAG}"
      }
    }

    /* ================= MAVEN ================= */

    stage('Restore Maven Cache') {
      steps {
        sh 'mkdir -p ${MAVEN_REPO}'
        readCache name: MVN_CACHE_NAME
      }
    }

    stage('Maven Build') {
      steps {
        sh 'mvn clean install -Dmaven.repo.local=${MAVEN_REPO}'
      }
    }

    stage('Save Maven Cache') {
      when { branch 'main' }
      steps {
        writeCache name: MVN_CACHE_NAME, includes: "${MAVEN_REPO}/**"
      }
    }

    /* ================= SONAR ================= */

    stage('SonarQube Scan') {
      steps {
        withSonarQubeEnv('sonar-server') {
          sh """
            mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
              -Dmaven.repo.local=${MAVEN_REPO} \
              -Dsonar.projectKey=board_game \
              -Dsonar.projectName=board_game
          """
        }
      }
    }

    /* ================= DOCKER BUILD ================= */

    stage('Kaniko Build & Push') {
      when { branch 'main' }
      steps {
        container('kaniko') {
          sh """
            mkdir -p ${KANIKO_CACHE_DIR}

            /kaniko/executor \
              --context /workspace \
              --dockerfile Dockerfile \
              --destination ${IMAGE_NAME}:${IMAGE_TAG} \
              --destination ${IMAGE_NAME}:latest 
    

          """
        }
      }
    }

    /* ================= GITOPS DEPLOY ================= */

    stage('Update Argo CD Repo (Rollout Trigger)') {
      when { branch 'main' }
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'gitops-token',
            usernameVariable: 'GIT_USER',
            passwordVariable: 'GIT_TOKEN'
          )
        ]) {
          sh """
            echo "Cloning GitOps repo"
            git clone https://${GIT_USER}:${GIT_TOKEN}@github.com/terralogic-fnc/boardgame-argo-rollouts.git

            cd boardgame-argo-rollouts/boardgame

            echo "Updating image tag to ${IMAGE_TAG}"
            sed -i 's|tag:.*|tag: \"${IMAGE_TAG}\"|g' values.yaml

            git status

            git config user.email "jenkins@cloudbees.local"
            git config user.name "jenkins"

            git commit -am "Rollout boardgame image ${IMAGE_TAG}" || echo "No changes to commit"
            git push origin main
          """
        }
      }
    }
  }

  post {
    success {
      emailext(
        to: "${EMAIL_RECIPIENTS}",
        subject: "✅ SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        body: """
        <h3>CI + GitOps Rollout Triggered</h3>
        <p><b>Image:</b> ${IMAGE_NAME}:${IMAGE_TAG}</p>
        <p>Argo CD will sync and Argo Rollouts will perform canary deployment.</p>
        """
      )
    }

    failure {
      emailext(
        to: "${EMAIL_RECIPIENTS}",
        subject: "❌ FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        body: """
        <h3>Pipeline Failed</h3>
        <p><b>Status:</b> ${currentBuild.currentResult}</p>
        """
      )
    }

    always {
      deleteDir()
    }
  }
}
