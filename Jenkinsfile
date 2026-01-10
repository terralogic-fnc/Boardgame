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
    /* ================= IMAGE CONFIG ================= */
    IMAGE_NAME = "gkamalakar1006/boardgames"

    /* ================= MAVEN CACHE ================= */
    MAVEN_REPO     = 'maven-repo'
    MVN_CACHE_NAME = 'mvn-cache'

    /* ================= TRIVY CACHE ================= */
    TRIVY_CACHE_DIR          = '.trivycache'
    TRIVY_CACHE_NAME         = 'trivy-cache'
    TRIVY_DB_REPOSITORY      = 'docker.io/aquasec/trivy-db'
    TRIVY_JAVA_DB_REPOSITORY = 'docker.io/aquasec/trivy-java-db'

    /* ================= KANIKO ================= */
    KANIKO_CACHE_DIR = '/workspace/.kaniko-cache'

    EMAIL_RECIPIENTS = 'aws-fnc@terralogic.com,kamalakar.reddy@terralogic.com,harshavardhan.s@terralogic.com'
  }

  stages {

    /* =================================================
       INIT: DEFINE TAG STRATEGY
       - CI tag  : build-<BUILD_NUMBER> (ALL branches)
       - Release : <commit-6> (ONLY main)
       ================================================= */
    stage('Init') {
      steps {
        script {
          env.CI_IMAGE_TAG      = "build-${BUILD_NUMBER}"
          env.RELEASE_IMAGE_TAG = GIT_COMMIT.take(6)
        }

        echo "Branch             : ${BRANCH_NAME}"
        echo "CI Image Tag       : ${CI_IMAGE_TAG}"
        echo "Release Image Tag  : ${RELEASE_IMAGE_TAG}"
      }
    }

    /* ================= MAVEN BUILD ================= */

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
      when { expression { !env.CHANGE_ID } }
      steps {
        writeCache name: MVN_CACHE_NAME, includes: "${MAVEN_REPO}/**"
      }
    }

    /* ================= SONAR ================= */

    stage('SonarQube Scan') {
      steps {
        withSonarQubeEnv('sonar-server') {
          sh '''
            mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
              -Dmaven.repo.local=${MAVEN_REPO} \
              -Dsonar.projectKey=board_game \
              -Dsonar.projectName=board_game
          '''
        }
      }
    }

    /* =================================================
       BUILD & PUSH IMAGE FOR ALL BRANCHES
       Tag: build-<BUILD_NUMBER>
       ================================================= */
    stage('Kaniko Build & Push (CI Image)') {
      steps {
        container('kaniko') {
          sh '''
            mkdir -p ${KANIKO_CACHE_DIR}

            /kaniko/executor \
              --context /workspace \
              --dockerfile Dockerfile \
              --destination ${IMAGE_NAME}:${CI_IMAGE_TAG} \
              --cache=true \
              --cache-dir ${KANIKO_CACHE_DIR}
          '''
        }
      }
    }

    /* =================================================
       BUILD RELEASE IMAGE ONLY ON MAIN
       Tag: <commit-6>
       ================================================= */
    stage('Kaniko Build & Push (Release Image)') {
      when { branch 'main' }
      steps {
        container('kaniko') {
          sh '''
            /kaniko/executor \
              --context /workspace \
              --dockerfile Dockerfile \
              --destination ${IMAGE_NAME}:${RELEASE_IMAGE_TAG} \
              --destination ${IMAGE_NAME}:latest \
              --cache=true \
              --cache-dir ${KANIKO_CACHE_DIR}
          '''
        }
      }
    }

    /* ================= TRIVY FS (MAIN ONLY) ================= */

    stage('Trivy FS Scan (Main Only)') {
      when { branch 'main' }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh '''
            trivy fs \
              --cache-dir ${TRIVY_CACHE_DIR} \
              --db-repository ${TRIVY_DB_REPOSITORY} \
              --java-db-repository ${TRIVY_JAVA_DB_REPOSITORY} \
              --severity LOW,MEDIUM,HIGH,CRITICAL \
              --ignore-unfixed .
          '''
        }
      }
    }

    /* ================= TRIVY IMAGE (MAIN ONLY) ================= */

    stage('Trivy Image Scan (Main Only)') {
      when { branch 'main' }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh '''
            trivy image \
              --cache-dir ${TRIVY_CACHE_DIR} \
              --severity LOW,MEDIUM,HIGH,CRITICAL \
              --ignore-unfixed \
              ${IMAGE_NAME}:${RELEASE_IMAGE_TAG}
          '''
        }
      }
    }

    /* ================= SBOM (MAIN ONLY) ================= */

    stage('Generate SBOM (Main Only)') {
      when { branch 'main' }
      steps {
        sh '''
          trivy fs \
            --cache-dir ${TRIVY_CACHE_DIR} \
            --format cyclonedx \
            --output trivy-reports/source-sbom.json .
        '''
      }
    }
    /* ================= ARGO CD ================= */
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
          sh '''
            git clone https://${GIT_USER}:${GIT_TOKEN}@github.com/terralogic-fnc/boardgame-argo-rollouts.git
            cd boardgame-argo-rollouts/boardgame

            sed -i 's|tag:.*|tag: "'${IMAGE_TAG}'"|g' values.yaml

            git config user.email "jenkins@cloudbees.local"
            git config user.name "jenkins"

            git commit -am "Rollout boardgame image ${IMAGE_TAG}" || echo "No changes to commit"
            git push origin main
          '''
        }
      }
    }
  }

  /* ================= POST ================= */

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
        <h3>Build Failed</h3>
        <p><b>Status:</b> ${currentBuild.currentResult}</p>
        <p><a href="${env.BUILD_URL}">Check Console Output</a></p>
        """
      )
    }

    always {
      archiveArtifacts allowEmptyArchive: true, artifacts: '''
        trivy-reports/*.html,
        trivy-reports/*.json
      '''
      deleteDir()
    }
  }
}
