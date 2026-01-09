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
    IMAGE_TAG  = "${GIT_COMMIT.take(6)}"

    MAVEN_REPO     = 'maven-repo'
    MVN_CACHE_NAME = 'mvn-cache'

    TRIVY_CACHE_DIR          = '.trivycache'
    TRIVY_CACHE_NAME         = 'trivy-cache'
    TRIVY_DB_REPOSITORY      = 'docker.io/aquasec/trivy-db'
    TRIVY_JAVA_DB_REPOSITORY = 'docker.io/aquasec/trivy-java-db'

    KANIKO_CACHE_DIR = '/workspace/.kaniko-cache'
  }

  stages {

    stage('Info') {
      steps {
        echo "Branch : ${BRANCH_NAME}"
        echo "Commit : ${GIT_COMMIT}"
        echo "Image  : ${IMAGE_NAME}:${IMAGE_TAG}"
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

    /* ================= SONAR ================= */

    stage('SonarQube Scan') {
      steps {
        withSonarQubeEnv('sonar-server') {
          sh '''
          echo "=== SONARQUBE SCAN ==="
            mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
              -Dmaven.repo.local=${MAVEN_REPO} \
              -Dsonar.projectKey=board_game \
              -Dsonar.projectName=board_game
          '''
        }
      }
    }

    /* ================= TRIVY FS ================= */

    stage('Restore Trivy Cache') {
      steps {
        sh 'mkdir -p ${TRIVY_CACHE_DIR} trivy-templates trivy-reports'
        readCache name: TRIVY_CACHE_NAME
      }
    }

    stage('Prepare Trivy Template') {
      steps {
        sh '''
          if [ ! -f trivy-templates/html.tpl ]; then
            curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/html.tpl \
              -o trivy-templates/html.tpl
          fi
        '''
      }
    }

    stage('Trivy FS Scan (Non-Blocking)') {
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
          '''
        }
      }
    }

    /* ================= KANIKO ================= */

    stage('Kaniko Build & Push') {
      when { branch 'main' }
      steps {
        container('kaniko') {
          sh '''
            mkdir -p ${KANIKO_CACHE_DIR}
            /kaniko/executor \
              --context /workspace \
              --dockerfile Dockerfile \
              --destination ${IMAGE_NAME}:${IMAGE_TAG} \
              --destination ${IMAGE_NAME}:latest \
              --cache=true \
              --cache-dir ${KANIKO_CACHE_DIR}
          '''
        }
      }
    }

    /* ================= TRIVY IMAGE ================= */

    stage('Trivy Image Scan (Non-Blocking)') {
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
              ${IMAGE_NAME}:${IMAGE_TAG}
          '''
        }
      }
    }

    /* ================= SBOM ================= */

    stage('Generate SBOM (CycloneDX)') {
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

    stage('Argo CD Deploy (GitOps)') {
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
            git clone https://${GIT_USER}:${GIT_TOKEN}@github.com/terralogic-fnc/deploy-to-argocd.git
            cd argo-deploy

            sed -i "s|image: .*|image: ${IMAGE_NAME}:${IMAGE_TAG}|g" manifests/deployment-service.yaml

            git config user.email "jenkins@cloudbees.local"
            git config user.name "jenkins"

            git commit -am "Deploy ${IMAGE_NAME}:${IMAGE_TAG}"
            git push origin main
          '''
        }
      }
    }

    /* ================= SAVE TRIVY CACHE ================= */

    stage('Save Trivy Cache') {
      when { expression { !env.CHANGE_ID } }
      steps {
        writeCache(
          name: TRIVY_CACHE_NAME,
          includes: "${TRIVY_CACHE_DIR}/**,trivy-templates/**"
        )
      }
    }
  }

  post {
    always {
      archiveArtifacts allowEmptyArchive: true, artifacts: '''
        trivy-reports/*.html,
        trivy-reports/*.json
      '''
      echo "Result: ${currentBuild.currentResult}"
      deleteDir()
    }
  }
}
