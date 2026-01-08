pipeline {
  agent {
    kubernetes {
      cloud 'terralogic-eks-agent'
      namespace 'cloudbees-builds'
      inheritFrom 'jenkins-kaniko-agent'
      defaultContainer 'jnlp'
    }
  }



  environment {
    /* ================= IMAGE ================= */
    IMAGE_NAME = "gkamalakar1006/boardgames"
    IMAGE_TAG  = "${BUILD_NUMBER}"

    /* ================= MAVEN ================= */
    MAVEN_REPO = 'maven-repo'
    MVN_CACHE_NAME = 'mvn-cache'

    /* ================= TRIVY ================= */
    TRIVY_CACHE_DIR = '.trivycache'
    TRIVY_CACHE_NAME = 'trivy-cache'
    TRIVY_DB_REPOSITORY = 'docker.io/aquasec/trivy-db'
    TRIVY_JAVA_DB_REPOSITORY = 'docker.io/aquasec/trivy-java-db'

    /* ================= KANIKO ================= */
    KANIKO_CACHE_DIR = '/workspace/.kaniko-cache'
  }

  stages {

    /* ================= CHECKOUT ================= */

    stage('Checkout') {
      steps {
        git branch: 'main',
            credentialsId: 'github-pat',
            url: 'https://github.com/kamalakar22/board_game.git'
      }
    }

    /* ================= MAVEN ================= */

    stage('Restore Maven Cache') {
      steps {
        sh 'mkdir -p ${MAVEN_REPO}'
        readCache name: "${MVN_CACHE_NAME}"
      }
    }

    stage('Maven Build') {
      steps {
        sh '''
          mvn clean install \
            -Dmaven.repo.local=${MAVEN_REPO}
        '''
      }
    }

    stage('Save Maven Cache') {
      when { expression { !env.CHANGE_ID } }
      steps {
        writeCache(
          name: "${MVN_CACHE_NAME}",
          includes: "${MAVEN_REPO}/**"
        )
      }
    }
    /* ==================SONAR SCAN================ */
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
        sh 'mkdir -p ${TRIVY_CACHE_DIR} trivy-templates'
        readCache name: "${TRIVY_CACHE_NAME}"
      }
    }

    stage('Prepare Trivy Template') {
      steps {
        sh '''
          mkdir -p trivy-templates trivy-reports

          if [ ! -f trivy-templates/html.tpl ]; then
            curl -fsSL \
              https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/html.tpl \
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
              --cache-dir "$TRIVY_CACHE_DIR" \
              --db-repository "$TRIVY_DB_REPOSITORY" \
              --java-db-repository "$TRIVY_JAVA_DB_REPOSITORY" \
              --scanners vuln,license \
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

    /* ================= TRIVY IMAGE ================= */

    stage('Trivy Image Scan (Non-Blocking)') {
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh '''
            trivy image \
              --cache-dir "$TRIVY_CACHE_DIR" \
              --db-repository "$TRIVY_DB_REPOSITORY" \
              --java-db-repository "$TRIVY_JAVA_DB_REPOSITORY" \
              --scanners vuln \
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
            --cache-dir "$TRIVY_CACHE_DIR" \
            --scanners vuln \
            --format cyclonedx \
            --output trivy-reports/source-sbom.json .
        '''
      }
    }

    /* ================= SAVE TRIVY CACHE ================= */

    stage('Save Trivy Cache') {
      when { expression { !env.CHANGE_ID } }
      steps {
        writeCache(
          name: "${TRIVY_CACHE_NAME}",
          includes: """
            ${TRIVY_CACHE_DIR}/**,
            trivy-templates/**
          """
        )
      }
    }
  }

  /* ================= POST ================= */

  post {
    always {
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
