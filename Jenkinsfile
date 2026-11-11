// ============================================================
//  Jenkinsfile  -  Cyberwing.pk 3-tier CI/CD (Azure lab)
//  4 stages: Checkout -> Build -> Push -> Deploy
//  Pipeline as Code: pipeline bhi git mein version hoti hai
// ============================================================
pipeline {
  agent any

  options {
    timestamps()                                  // har log line par waqt
    buildDiscarder(logRotator(numToKeepStr: '10'))
    disableConcurrentBuilds()                     // aik waqt mein aik build
    timeout(time: 25, unit: 'MINUTES')
  }

  environment {
    PROJECT     = 'cyberwing'
    DEPLOY_DIR  = '/opt/cyberwing'
    // dockerhub-creds (Username with password) -> DHCRED_USR / DHCRED_PSW
    DHCRED      = credentials('dockerhub-creds')
    DB_NAME     = 'guestbook'
    DB_USER     = credentials('db-user')
    DB_PASSWORD = credentials('db-password')
    DB_ROOT_PASSWORD = credentials('db-root-password')
    GRAFANA_PASSWORD = credentials('grafana-password')
  }

  stages {

    // ---------- Stage 1: code uthao ----------
    stage('1. Checkout') {
      steps {
        echo "Build #${env.BUILD_NUMBER} shuru"
        checkout scm
        sh 'echo "Commit: $(git log -1 --pretty=%h) $(git log -1 --pretty=%s)"'
      }
    }

    // ---------- Stage 2: images banao ----------
    stage('2. Build') {
      steps {
        sh '''
          set -eu
          echo "Frontend image ban rahi hai..."
          docker build -t "$DHCRED_USR/cyberwing-frontend:$BUILD_NUMBER" ./frontend

          echo "Backend image ban rahi hai..."
          docker build -t "$DHCRED_USR/cyberwing-backend:$BUILD_NUMBER" ./backend

          docker images | grep -E "cyberwing-(frontend|backend)" || true
        '''
      }
    }

    // ---------- Stage 3: Docker Hub par push ----------
    stage('3. Push') {
      steps {
        sh '''
          set -eu
          echo "$DHCRED_PSW" | docker login -u "$DHCRED_USR" --password-stdin

          docker push "$DHCRED_USR/cyberwing-backend:$BUILD_NUMBER"
          docker push "$DHCRED_USR/cyberwing-frontend:$BUILD_NUMBER"

          docker tag "$DHCRED_USR/cyberwing-backend:$BUILD_NUMBER"  "$DHCRED_USR/cyberwing-backend:latest"
          docker tag "$DHCRED_USR/cyberwing-frontend:$BUILD_NUMBER" "$DHCRED_USR/cyberwing-frontend:latest"
          docker push "$DHCRED_USR/cyberwing-backend:latest"
          docker push "$DHCRED_USR/cyberwing-frontend:latest"

          docker logout
        '''
      }
    }

    // ---------- Stage 4: server par deploy ----------
    stage('4. Deploy') {
      steps {
        sh '''
          set -eu

          # 1) Deploy folder mein files rakho
          mkdir -p "$DEPLOY_DIR"
          cp docker-compose.yml docker-compose.monitoring.yml "$DEPLOY_DIR"/
          cp -r nginx database monitoring "$DEPLOY_DIR"/

          cd "$DEPLOY_DIR"

          # 2) Is machine ka public IP (Azure IMDS se) - Grafana link ke liye
          PUBLIC_IP=$(curl -s --max-time 5 -H Metadata:true \
            "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" || true)
          PUBLIC_IP=${PUBLIC_IP:-localhost}
          echo "Server ka public IP: $PUBLIC_IP"

          # 3) .env khud banao (secrets Jenkins credentials se)
          cat > .env <<EOF
DOCKERHUB_USER=$DHCRED_USR
IMAGE_TAG=$BUILD_NUMBER
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD
GRAFANA_PASSWORD=$GRAFANA_PASSWORD
GRAFANA_ROOT_URL=http://$PUBLIC_IP:3000
EOF
          chgrp docker .env || true
          chmod 640 .env

          # 4) Naye images pull karo + app update karo
          echo "$DHCRED_PSW" | docker login -u "$DHCRED_USR" --password-stdin
          docker compose pull
          docker compose up -d --remove-orphans

          # 5) Monitoring stack (pehli dafa up, baad mein update)
          docker compose -f docker-compose.monitoring.yml up -d

          # 6) Saaf-safai: purani images hatao (disk na bhare)
          docker image prune -f
          docker logout

          echo "Deploy mukammal."
        '''

        // 7) Smoke test: app asal mein zinda hai?
        sh '''
          echo "Health check ka intezar (max 90s)..."
          i=0
          while [ $i -lt 30 ]; do
            if curl -fsS http://localhost/api/health | grep -q '"status":"ok"'; then
              echo "SUCCESS: nginx + backend + database teeno theek hain"
              exit 0
            fi
            i=$((i+1))
            sleep 3
          done
          echo "FAILED: Health check pass nahi hua"
          docker ps -a
          docker compose -f /opt/cyberwing/docker-compose.yml logs --tail 60 backend || true
          exit 1
        '''
      }
    }
  }

  post {
    success {
      echo "✅ Deploy kamyab! App: http://<SERVER-IP>/  (build #${env.BUILD_NUMBER})"
    }
    failure {
      echo "❌ Build fail - logs dekhein (docker compose logs backend)"
    }
    always {
      sh 'docker image prune -f || true'
    }
  }
}
