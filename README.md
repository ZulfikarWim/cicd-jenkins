# CI/CD Pipeline: Jenkins + Docker + AWS EC2

> Implementasi CI/CD Pipeline untuk automasi deployment aplikasi Node.js menggunakan Jenkins, Docker, dan AWS EC2.

**Kelompok 6 — Penyediaan dan Automasi Layanan**  
Universitas Brawijaya | Semester Genap 2025/2026  
Dosen Pengampu: Widhi Yahya, S.Kom., M.T., M.Sc., Ph.D.

| Nama | NIM |
|------|-----|
| Asyraf Rizqy Kurnia | 235150201111031 |
| Muhammad Zulfikar Raditya Wimbyarto | 235150201111034 |
| Michael Andro Nathaniel | 235150207111039 |

---

## Daftar Isi

1. [Arsitektur Sistem](#1-arsitektur-sistem)
2. [Tech Stack](#2-tech-stack)
3. [Prasyarat](#3-prasyarat)
4. [Setup Environment](#4-setup-environment)
   - [4.1 Provisioning EC2 Jenkins Server](#41-provisioning-ec2-jenkins-server)
   - [4.2 Instalasi Jenkins](#42-instalasi-jenkins)
   - [4.3 Instalasi Docker di Jenkins Server](#43-instalasi-docker-di-jenkins-server)
   - [4.4 Instalasi Plugin Jenkins](#44-instalasi-plugin-jenkins)
   - [4.5 Setup Credentials](#45-setup-credentials)
   - [4.6 Provisioning EC2 Deploy Target](#46-provisioning-ec2-deploy-target)
   - [4.7 Setup SSH Jenkins ke Deploy Target](#47-setup-ssh-jenkins-ke-deploy-target)
5. [Struktur Repository](#5-struktur-repository)
6. [Menjalankan Pipeline](#6-menjalankan-pipeline)
   - [6.1 Buat Pipeline Job di Jenkins](#61-buat-pipeline-job-di-jenkins)
   - [6.2 Setup GitHub Webhook](#62-setup-github-webhook)
   - [6.3 Trigger Manual](#63-trigger-manual)
7. [Penjelasan Setiap Stage Pipeline](#7-penjelasan-setiap-stage-pipeline)
8. [Hasil Pengujian](#8-hasil-pengujian)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Arsitektur Sistem

```
Developer
    │
    │ git push
    ▼
GitHub Repository ──── webhook trigger ────▶ Jenkins Server (EC2 t2.medium)
                                                        │
                                          ┌─────────────┼─────────────┐
                                          ▼             ▼             ▼
                                       Checkout    Install & Test   Build Image
                                                        │
                                                   (jika gagal)
                                                   pipeline stop
                                                        │
                                                   (jika sukses)
                                                        ▼
                                                  Push to Docker Hub
                                                        │
                                                        ▼
                                                Deploy via SSH
                                                        │
                                                        ▼
                                            Deploy Target (EC2 t2.micro)
                                                        │
                                                        ▼
                                            App running di port 3000
```

| Server | Instance Type | Port | Fungsi |
|--------|--------------|------|--------|
| Jenkins Server | EC2 t2.medium | 8080 | CI/CD orchestrator |
| Deploy Target | EC2 t2.micro | 3000 | Production app server |
| Docker Hub | - | - | Container image registry |

---

## 2. Tech Stack

| Komponen | Tools | Versi |
|----------|-------|-------|
| CI/CD Server | Jenkins | 2.440.x LTS |
| Version Control | GitHub | - |
| Containerisasi | Docker Engine | 24.x |
| Container Registry | Docker Hub | - |
| Jenkins Host | AWS EC2 | t2.medium, Ubuntu 24.04 |
| Deploy Target | AWS EC2 | t2.micro, Ubuntu 24.04 |
| Aplikasi | Node.js + Express | 18.x LTS |
| Testing | Jest + Supertest | 29.x |

---

## 3. Prasyarat

Sebelum memulai setup, pastikan hal-hal berikut sudah tersedia:

- **Akun AWS Academy** — untuk provisioning EC2 instances
- **Akun GitHub** — repository sudah dibuat dengan visibility Public
- **Akun Docker Hub** — sudah terdaftar di [hub.docker.com](https://hub.docker.com)
- **WSL / Terminal** — untuk SSH ke EC2
- **File `.pem`** — key pair AWS yang sudah didownload

---

## 4. Setup Environment

### 4.1 Provisioning EC2 Jenkins Server

1. Login AWS Academy → Launch AWS Learner Lab → Launch AWS Management Console
2. Buka **EC2** → **Launch Instance**
3. Konfigurasi:

| Setting | Value |
|---------|-------|
| Name | `jenkins-server` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance type | `t2.medium` |
| Key pair | Buat baru atau pilih yang sudah ada |

4. **Security Group** — tambahkan inbound rules:

| Port | Protocol | Source | Keperluan |
|------|----------|--------|-----------|
| 22 | TCP | 0.0.0.0/0 | SSH |
| 8080 | TCP | 0.0.0.0/0 | Jenkins UI + Webhook |

5. Klik **Launch Instance**, tunggu status **running**

### 4.2 Instalasi Jenkins

SSH ke EC2 Jenkins Server:

```bash
# Dari WSL/terminal lokal
cp /path/to/jenkins-key.pem ~/jenkins-key.pem
chmod 400 ~/jenkins-key.pem
ssh -i ~/jenkins-key.pem ubuntu@<JENKINS-EC2-IP>
```

Setelah masuk ke EC2, jalankan:

```bash
# Install Java
sudo apt update && sudo apt install -y fontconfig openjdk-21-jre

# Tambah GPG key Jenkins
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

# Tambah repo Jenkins
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Install & jalankan Jenkins
sudo apt update && sudo apt install -y jenkins
sudo systemctl enable --now jenkins

# Verifikasi
sudo systemctl status jenkins
```

> ⚠️ Jika GPG error, gunakan cara alternatif via `.war` file — lihat [Troubleshooting](#9-troubleshooting)

Ambil initial password:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Akses Jenkins di browser: `http://<JENKINS-EC2-IP>:8080`  
Masukkan password, klik **Install suggested plugins**, lalu **Continue as admin**.

### 4.3 Instalasi Docker di Jenkins Server

```bash
sudo apt install -y docker.io
sudo usermod -aG docker jenkins   # wajib agar Jenkins bisa akses Docker
sudo systemctl enable --now docker
sudo systemctl restart jenkins
```

Verifikasi:

```bash
sudo systemctl status docker
```

### 4.4 Instalasi Plugin Jenkins

Masuk ke **Manage Jenkins → Plugins → Available plugins**, install:

- `Git`
- `Docker Pipeline`
- `Credentials Binding`
- `SSH Agent`

Restart Jenkins setelah instalasi selesai, atau akses: `http://<JENKINS-IP>:8080/restart`

### 4.5 Setup Credentials

Buka **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

**Credential 1 — Docker Hub:**

| Field | Value |
|-------|-------|
| Kind | Username with password |
| Username | Username Docker Hub |
| Password | Access Token Docker Hub |
| ID | `dockerhub-creds` |

> Cara buat Access Token: Docker Hub → Account Settings → Security → Personal access tokens → Generate new token (Read & Write)

**Credential 2 — SSH Deploy Target:**

| Field | Value |
|-------|-------|
| Kind | SSH Username with private key |
| Username | `ubuntu` |
| ID | `deploy-ssh-key` |
| Private Key | Enter directly → isi dengan private key Jenkins (lihat langkah 4.7) |

### 4.6 Provisioning EC2 Deploy Target

1. Di AWS Console → EC2 → **Launch Instance**
2. Konfigurasi:

| Setting | Value |
|---------|-------|
| Name | `deploy-target` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance type | `t2.micro` |
| Key pair | Pilih key pair yang sama |

3. Security Group:

| Port | Source | Keperluan |
|------|--------|-----------|
| 22 | 0.0.0.0/0 | SSH |
| 3000 | 0.0.0.0/0 | Akses aplikasi |

4. Install Docker di deploy target:

```bash
ssh -i ~/jenkins-key.pem ubuntu@<DEPLOY-EC2-IP>
sudo apt update && sudo apt install -y docker.io
sudo usermod -aG docker ubuntu
sudo systemctl enable --now docker
```

### 4.7 Setup SSH Jenkins ke Deploy Target

Di EC2 Jenkins Server, jalankan sebagai user jenkins:

```bash
sudo su - jenkins

# Buat SSH key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Lihat public key
cat ~/.ssh/id_rsa.pub
```

Copy output public key, lalu di EC2 Deploy Target:

```bash
echo "<PUBLIC-KEY>" >> ~/.ssh/authorized_keys
```

Test koneksi:

```bash
# Dari Jenkins Server (sebagai user jenkins)
ssh -o StrictHostKeyChecking=no ubuntu@<DEPLOY-EC2-IP> 'echo KONEKSI OK'
```

Harus output: `KONEKSI OK`

Terakhir, copy private key ke Jenkins Credentials (langkah 4.5 Credential 2):

```bash
cat ~/.ssh/id_rsa   # copy seluruh output ini ke Jenkins credentials
```

---

## 5. Struktur Repository

```
cicd-jenkins/
├── app/
│   ├── index.js          # Express app (endpoint / dan /health)
│   ├── index.test.js     # Unit tests (Jest + Supertest)
│   └── package.json      # Dependencies & npm scripts
├── Dockerfile            # Build instruksi container image
└── Jenkinsfile           # Pipeline-as-code definisi CI/CD
```

---

## 6. Menjalankan Pipeline

### 6.1 Buat Pipeline Job di Jenkins

1. Jenkins UI → **New Item**
2. Nama: `cicd-pipeline`, pilih **Pipeline** → OK
3. Di bagian **Build Triggers**: centang **GitHub hook trigger for GITScm polling**
4. Di bagian **Pipeline**:

| Field | Value |
|-------|-------|
| Definition | Pipeline script from SCM |
| SCM | Git |
| Repository URL | `https://github.com/ZulfikarWim/cicd-jenkins.git` |
| Credentials | None (repo public) |
| Branch Specifier | `*/main` |
| Script Path | `Jenkinsfile` |

5. Klik **Save**

### 6.2 Setup GitHub Webhook

Di GitHub repository → **Settings → Webhooks → Add webhook**:

| Field | Value |
|-------|-------|
| Payload URL | `http://<JENKINS-EC2-IP>:8080/github-webhook/` |
| Content type | `application/json` |
| Which events? | Just the push event |
| Active | ✅ |

Klik **Add webhook**.

> ⚠️ Jika menggunakan AWS Academy, IP EC2 berubah setiap session restart. Update Payload URL setiap kali IP berubah.

### 6.3 Trigger Manual

Untuk trigger pipeline secara manual tanpa push:

1. Buka Jenkins → klik job `cicd-pipeline`
2. Klik **Build Now** di menu kiri
3. Monitor progress di **Build History** → klik build → **Console Output**

---

## 7. Penjelasan Setiap Stage Pipeline

Pipeline didefinisikan dalam `Jenkinsfile` dengan 5 stage utama:

### Stage 1 — Checkout
```groovy
stage('Checkout') {
    steps {
        git branch: 'main', url: 'https://github.com/ZulfikarWim/cicd-jenkins.git'
    }
}
```
**Fungsi:** Clone kode terbaru dari branch `main` GitHub ke workspace Jenkins.  
**Output:** Source code tersedia di workspace `/home/jenkins/.jenkins/workspace/cicd-pipeline`

---

### Stage 2 — Install & Test
```groovy
stage('Install & Test') {
    steps {
        dir('app') {
            sh 'npm install'
            sh 'npm test'
        }
    }
}
```
**Fungsi:** Install dependencies Node.js lalu jalankan unit test menggunakan Jest.  
**Fail Fast:** Jika ada test yang gagal, pipeline **langsung berhenti** di stage ini. Stage Build, Push, dan Deploy tidak akan dieksekusi — memastikan kode bermasalah tidak pernah sampai ke server production.

---

### Stage 3 — Build Docker Image
```groovy
stage('Build Docker Image') {
    steps {
        sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
        sh "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest"
    }
}
```
**Fungsi:** Build Docker image dari `Dockerfile` di root repository.  
**Tagging:** Setiap build menghasilkan 2 tag:
- `zulfikarwim/cicd-jenkins:<BUILD_NUMBER>` — tag unik per build (immutable)
- `zulfikarwim/cicd-jenkins:latest` — selalu menunjuk ke build terbaru

---

### Stage 4 — Push to Docker Hub
```groovy
stage('Push to Docker Hub') {
    steps {
        withCredentials([usernamePassword(
            credentialsId: 'dockerhub-creds', ...)]) {
            sh 'echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin'
            sh "docker push ${IMAGE_NAME}:${IMAGE_TAG}"
            sh "docker push ${IMAGE_NAME}:latest"
        }
    }
}
```
**Fungsi:** Login ke Docker Hub menggunakan credentials tersimpan (tidak hardcode), lalu push kedua tag image.  
**Security:** Credentials dikelola Jenkins Credentials Manager — tidak pernah terekspos di log atau Jenkinsfile.

---

### Stage 5 — Deploy
```groovy
stage('Deploy') {
    steps {
        sshagent(['deploy-ssh-key']) {
            sh """
                ssh -o StrictHostKeyChecking=no ubuntu@<DEPLOY-IP> '
                    docker pull zulfikarwim/cicd-jenkins:latest
                    docker stop app 2>/dev/null || true
                    docker rm -f app 2>/dev/null || true
                    docker run -d --name app -p 3000:3000 zulfikarwim/cicd-jenkins:latest
                '
            """
        }
    }
}
```
**Fungsi:** SSH ke EC2 deploy target, pull image terbaru dari Docker Hub, stop & hapus container lama, jalankan container baru.  
**Idempotency:** `|| true` memastikan pipeline tidak gagal meski container belum ada (fresh deployment).  
**Akses App:** Setelah sukses, aplikasi dapat diakses di `http://<DEPLOY-EC2-IP>:3000`

---

## 8. Hasil Pengujian

### Test 1 — Happy Path ✅
**Aksi:** Push kode valid ke branch main  
**Expected:** Pipeline sukses end-to-end, aplikasi running  
**Verifikasi:**
```bash
curl http://<DEPLOY-EC2-IP>:3000
# Output: {"status":"ok","message":"Hello from CI/CD Pipeline!"}

curl http://<DEPLOY-EC2-IP>:3000/health
# Output: {"status":"healthy"}
```

### Test 2 — Failure Test ✅
**Aksi:** Commit unit test yang sengaja gagal  
**Expected:** Pipeline berhenti di stage Install & Test, stage Deploy tidak dieksekusi  
**Hasil:** Build & Deploy stage menampilkan `skipped due to earlier failure(s)`

### Test 3 — Re-run Test ✅
**Aksi:** Jalankan pipeline 2x berturut-turut tanpa ubah kode  
**Expected:** Kedua build sukses dengan hasil identik (idempotency)  
**Catatan:** Menggunakan `options { disableConcurrentBuilds() }` untuk mencegah race condition

### Test 4 — Trigger Test ✅
**Aksi:** Push ke branch main dengan webhook aktif  
**Expected:** Pipeline terpicu otomatis tanpa klik Build Now  
**Verifikasi:** GitHub → Settings → Webhooks → Recent Deliveries → status `200 OK`

---

## 9. Troubleshooting

### Jenkins tidak bisa diakses di port 8080
```bash
# SSH ke Jenkins server, cek status
sudo systemctl status jenkins
sudo systemctl restart jenkins

# Pastikan port 8080 dibuka di Security Group AWS
# EC2 → Security Groups → Inbound rules → port 8080 source 0.0.0.0/0
```

### GPG error saat install Jenkins via apt
Gunakan cara alternatif via `.war` file:
```bash
sudo apt update && sudo apt install -y fontconfig openjdk-21-jre
sudo wget -O /opt/jenkins.war https://get.jenkins.io/war-stable/latest/jenkins.war
sudo useradd -m -s /bin/bash jenkins

sudo tee /etc/systemd/system/jenkins.service > /dev/null <<EOF
[Unit]
Description=Jenkins
After=network.target
[Service]
ExecStart=/usr/bin/java -jar /opt/jenkins.war --httpPort=8080
User=jenkins
Environment=JENKINS_HOME=/home/jenkins/.jenkins
Restart=always
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now jenkins
# Initial password ada di:
sudo cat /home/jenkins/.jenkins/secrets/initialAdminPassword
```

### Permission denied saat SSH dengan file .pem di WSL
```bash
# File .pem di path Windows (/mnt/c/) tidak bisa di-chmod
# Copy ke home directory WSL dulu
cp /mnt/c/Users/<username>/Downloads/jenkins-key.pem ~/jenkins-key.pem
chmod 400 ~/jenkins-key.pem
ssh -i ~/jenkins-key.pem ubuntu@<EC2-IP>
```

### Docker permission denied di Jenkins
```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Webhook tidak trigger pipeline
1. Pastikan port 8080 EC2 Jenkins terbuka di Security Group
2. Cek IP EC2 tidak berubah (AWS Academy session restart → IP bisa berubah)
3. Update Payload URL webhook jika IP berubah:
   - GitHub → Settings → Webhooks → Edit → update IP baru
4. Pastikan job Jenkins dicentang **GitHub hook trigger for GITScm polling**
5. Test redeliver: GitHub → Settings → Webhooks → Recent Deliveries → Redeliver

### IP EC2 berubah setelah AWS Academy session restart
```bash
# 1. Cek IP baru di AWS Console → EC2 → Public IPv4 address
# 2. SSH pakai IP baru
ssh -i ~/jenkins-key.pem ubuntu@<IP-BARU>

# 3. Cek Jenkins masih jalan
sudo systemctl status jenkins
sudo systemctl start jenkins   # jika stopped

# 4. Update webhook URL di GitHub dengan IP baru
# 5. Update IP deploy target di Jenkinsfile jika deploy target juga ganti IP
```

### Container conflict saat deploy (nama /app sudah ada)
```bash
# SSH ke deploy target, hapus manual
ssh -i ~/jenkins-key.pem ubuntu@<DEPLOY-IP>
docker rm -f app
```

### Pipeline berjalan paralel menyebabkan conflict
Pastikan Jenkinsfile memiliki opsi `disableConcurrentBuilds()`:
```groovy
pipeline {
    agent any
    options {
        disableConcurrentBuilds()
    }
    ...
}
```

---

*Kelompok 6 — Penyediaan dan Automasi Layanan — Universitas Brawijaya 2026*