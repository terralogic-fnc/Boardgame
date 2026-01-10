pipeline {
  agent {
    kubernetes {
      cloud 'terralogic-eks-agent'
      inheritFrom 'jenkins-kaniko-agent'
      defaultContainer 'jnlp'
    }
  }

  options {
    
    durabilityHint('PERFORMANCE_OPTIMIZED')
  }

  environment {
    /* ================= IMAGE ================= */
    IMAGE_NAME = "gkamalakar1006/boardgames"

    /* ================= MAVEN ================= */
    MAVEN_REPO     = 'maven-repo'
    MVN_CACHE_NAME = 'mvn-cache'

    /* ================= TRIVY ================= */
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
       INIT – TAG STRATEGY
       ================================================= */
    stage('Init') {
      steps {
        script {
          // CI image tag for ALL branches
          env.CI_IMAGE_TAG = "build-${BUILD_NUMBER}"

          // Release image tag ONLY for main (merge commit)
          if (env.BRANCH_NAME == 'main') {
            env.RELEASE_IMAGE_TAG = GIT_COMMIT.take(6)
          } else {
            env.RELEASE_IMAGE_TAG = ''
          }
        }

        echo "Branch            : ${BRANCH_NAME}"
        echo "CI Image Tag      : ${CI_IMAGE_TAG}"
        echo "Release Image Tag : ${env.RELEASE_IMAGE_TAG ?: 'N/A'}"
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
      when { expression { !env.CHANGE_ID } }
      steps {
        writeCache name: MVN_CACHE_NAME, includes: "${MAVEN_REPO}/**"
      }
    }

    /* =================================================
       TRIVY FS – MAIN ONLY (MOVED ABOVE SONAR)
       ================================================= */

    stage('Restore Trivy Cache') {
      when { branch 'main' }
      steps {
        sh 'mkdir -p ${TRIVY_CACHE_DIR} trivy-templates trivy-reports'
        readCache name: TRIVY_CACHE_NAME
      }
    }

    stage('Prepare Trivy Template') {
      when { branch 'main' }
      steps {
        sh '''
          if [ ! -f trivy-templates/html.tpl ]; then
            curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/html.tpl \
              -o trivy-templates/html.tpl
          fi
        '''
      }
    }

    stage('Trivy FS Scan') {
      when { branch 'main' }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh '''
            trivy fs \
              --cache-dir ${TRIVY_CACHE_DIR} \
              --db-repository ${TRIVY_DB_REPOSITORY} \
              --java-db-repository ${TRIVY_JAVA_DB_REPOSITORY} \
              --severity LOW,MEDIUM,HIGH,CRITICAL \
              --ignore-unfixed \
              --format template \
              --template @trivy-templates/html.tpl \
              --output trivy-reports/fs-vuln.html .
			  > /dev/null 2>&1
          '''
        }
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
       BUILD & PUSH CI IMAGE – ALL BRANCHES
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
       BUILD & PUSH RELEASE IMAGE – MAIN ONLY
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

    /* ================= TRIVY IMAGE (MAIN ONLY) ================= */

    stage('Trivy Image Scan') {
      when { branch 'main' }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh '''
            trivy image \
              --cache-dir ${TRIVY_CACHE_DIR} \
              --severity LOW,MEDIUM,HIGH,CRITICAL \
              --ignore-unfixed \
              --format template \
              --template @trivy-templates/html.tpl \
              --output trivy-reports/image-vuln.html \
              ${IMAGE_NAME}:${RELEASE_IMAGE_TAG}
          '''
        }
      }
    }

    /* ================= SBOM (MAIN ONLY) ================= */

    stage('Generate SBOM') {
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

    stage('Save Trivy Cache') {
      when { branch 'main' }
      steps {
        writeCache name: TRIVY_CACHE_NAME, includes: "${TRIVY_CACHE_DIR}/**"
      }
    }

    /* ================= ARGO CD GITOPS ================= */

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

            sed -i "s|tag:.*|tag: ${RELEASE_IMAGE_TAG}|g" values.yaml

            git config user.email "jenkins@cloudbees.local"
            git config user.name "jenkins"

            git commit -am "Deploy boardgame ${RELEASE_IMAGE_TAG}" || echo "No changes"
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
        <h3>Pipeline Succeeded</h3>
        <p><b>Branch:</b> ${BRANCH_NAME}</p>
        <p><b>CI Image:</b> ${IMAGE_NAME}:${CI_IMAGE_TAG}</p>
        ${BRANCH_NAME == 'main' ? "<p><b>Release Image:</b> ${IMAGE_NAME}:${RELEASE_IMAGE_TAG}</p>" : ""}
        <p><a href="${env.BUILD_URL}">View Build</a></p>
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
