pipeline {
  agent {
    kubernetes {
      cloud 'eks-agent'
      inheritFrom 'jenkins-kaniko-agent'
      defaultContainer 'jnlp'
    }
  }

  environment {
    IMAGE_NAME = "kamalakar2210/board_games"
    IMAGE_TAG  = "${BUILD_NUMBER}"

    ARGO_REPO = "github.com/kamalakar22/argo-deploy.git"
    ARGO_DIR  = "argo-deploy"
    MANIFESTS = "manifests"

    /* =========================
       SHARED CACHE (PVC)
       ========================= */
    MAVEN_OPTS      = "-Dmaven.repo.local=/cache/maven"
    TRIVY_CACHE_DIR = "/cache/trivy"
  }

  /*
   * IMPORTANT:
   * - Concurrency is ENABLED by default
   * - DO NOT add disableConcurrentBuilds()
   */
  options {
    timestamps()
  }

  stages {

    /* =========================
       Verify Agent & Cache
       ========================= */
    stage('Verify Agent') {
      steps {
        sh '''
          echo "User:"
          whoami

          echo "Java & Maven:"
          mvn -v

          echo "Trivy:"
          trivy --version || true

          echo "Cache contents:"
          ls -lah /cache || true
        '''
      }
    }

    /* =========================
       Maven Build (ONCE)
       ========================= */
    stage('Maven Build') {
      steps {
        sh '''
          echo "=== MAVEN BUILD ==="
          mvn clean package -DskipTests
        '''
      }
    }

    /* =========================
       SonarQube Scan
       ========================= */
    stage('SonarQube Scan') {
      steps {
        withSonarQubeEnv('sonarqube') {
          sh '''
            echo "=== SONAR ANALYSIS ==="

            mvn -DskipTests \
              -Dsonar.projectKey=board-game \
              -Dsonar.projectName=board-game \
              -Dsonar.java.binaries=target/classes \
              org.sonarsource.scanner.maven:sonar-maven-plugin:5.5.0.6356:sonar
          '''
        }
      }
    }

    /* =========================
       Trivy FS Scan & SBOM
       ========================= */
    stage('Trivy FS Scan & SBOM') {
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh '''
            mkdir -p trivy-reports sbom

            trivy fs \
              --cache-dir ${TRIVY_CACHE_DIR} \
              --scanners vuln \
              --format table \
              --output trivy-reports/fs-vuln.txt .

            trivy fs \
              --cache-dir ${TRIVY_CACHE_DIR} \
              --scanners vuln,license \
              --format cyclonedx \
              --output sbom/sbom-fs.json .
          '''
        }
      }
    }

    /* =========================
       Kaniko Build & Push
       ========================= */
    stage('Kaniko Build & Push') {
      steps {
        container('kaniko') {
          sh '''
            echo "Preparing Kaniko cache..."
            mkdir -p /cache/kaniko

            /kaniko/executor \
              --context /workspace \
              --dockerfile Dockerfile \
              --destination ${IMAGE_NAME}:${IMAGE_TAG} \
              --destination ${IMAGE_NAME}:latest \
              --cache=true \
              --cache-dir=/cache/kaniko
          '''
        }
      }
    }

    /* =========================
       Update Argo Rollout
       (LOCKED – SAFE)
       ========================= */
    stage('Update Argo Rollout') {
      options {
        lock(resource: 'board-game-rollout')
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'github-pat',
          usernameVariable: 'GIT_USER',
          passwordVariable: 'GIT_TOKEN'
        )]) {
          sh '''
            rm -rf ${ARGO_DIR}
            git clone https://${GIT_USER}:${GIT_TOKEN}@${ARGO_REPO}
            cd ${ARGO_DIR}/${MANIFESTS}

            echo "Updating rollout image to ${IMAGE_NAME}:${IMAGE_TAG}"

            sed -i "s|image: ${IMAGE_NAME}:.*|image: ${IMAGE_NAME}:${IMAGE_TAG}|g" rollout.yaml

            git config user.name "Jenkins CI"
            git config user.email "jenkins@ci.local"
            git add rollout.yaml
            git commit -m "canary: update to ${IMAGE_TAG}" || true
            git push origin main
          '''
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts allowEmptyArchive: true, artifacts: '''
        trivy-reports/*,
        sbom/*.json
      '''
      echo "Pipeline result: ${currentBuild.currentResult}"
    }
  }
}
