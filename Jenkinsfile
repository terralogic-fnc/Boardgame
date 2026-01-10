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

    /* ================= KANIKO ================= */

    stage('Kaniko Build & Push') {
      when { branch 'main' }
      steps {
        container('kaniko') {
          sh """
            /kaniko/executor \
              --context /workspace \
              --dockerfile Dockerfile \
              --destination ${IMAGE_NAME}:${IMAGE_TAG} \
              --destination ${IMAGE_NAME}:latest
          """
        }
      }
    }

    /* ================= ARGO CD (GITOPS) ================= */

    stage('Update Argo CD Repo (Trigger Rollout)') {
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
        <h3>Image Built & Rollout Triggered</h3>
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
