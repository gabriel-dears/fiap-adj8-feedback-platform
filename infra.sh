#!/bin/bash
set -e

PROJECT_ID="fiap-adj8-feedback-platform"
REGION="us-central1"
INSTANCE_NAME="feedback-db-instance"
DB_NAME="feedback_db"
DB_USER="fiap_user"
DB_PASSWORD="pass"
ARTIFACT_REPO="feedback-app"
SA_KEY_PATH="$HOME/gcp-keys/sa-infra-key.json"

echo "🚀 Inicializando infraestrutura base do projeto..."

##############################
# 1. Autenticar usando SA INFRA
##############################
if [ ! -f "$SA_KEY_PATH" ]; then
  echo "❌ Key da SA Infra não encontrada em $SA_KEY_PATH"
  exit 1
fi

echo "🔐 Autenticando com Service Account de Infra..."
gcloud auth activate-service-account --key-file="$SA_KEY_PATH"
gcloud config set project "$PROJECT_ID"

############################################
# ✅ HABILITAR APIS OBRIGATÓRIAS
############################################

echo "🔧 Habilitando APIs necessárias para o projeto..."

gcloud services enable appengine.googleapis.com
gcloud services enable appengineflex.googleapis.com
gcloud services enable servicemanagement.googleapis.com
gcloud services enable serviceusage.googleapis.com
gcloud services enable cloudbuild.googleapis.com

echo "✅ APIs habilitadas com sucesso"

##############################
# 2. Criar Cloud SQL Instance
##############################
if ! gcloud sql instances describe "$INSTANCE_NAME" >/dev/null 2>&1; then
  echo "🐘 Criando Cloud SQL Instance..."
  gcloud sql instances create "$INSTANCE_NAME" \
    --database-version=POSTGRES_16 \
    --region="$REGION" \
    --edition=ENTERPRISE \
    --tier=db-g1-small \
    --storage-size=10GB \
    --storage-type=SSD
else
  echo "✅ Cloud SQL Instance já existe"
fi

##############################
# 3. Criar Database
##############################
if ! gcloud sql databases describe "$DB_NAME" --instance="$INSTANCE_NAME" >/dev/null 2>&1; then
  echo "📦 Criando database $DB_NAME"
  gcloud sql databases create "$DB_NAME" --instance="$INSTANCE_NAME"
else
  echo "✅ Database já existe"
fi

##############################
# 4. Criar usuário do banco
##############################
if ! gcloud sql users list --instance="$INSTANCE_NAME" | grep -q "$DB_USER"; then
  echo "👤 Criando usuário $DB_USER"
  gcloud sql users create "$DB_USER" \
    --instance="$INSTANCE_NAME" \
    --password="$DB_PASSWORD"
else
  echo "✅ Usuário do banco já existe"
fi

##############################
# 5. Configurar Docker Auth
##############################
echo "🔧 Configurando Docker para Artifact Registry"
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

##############################
# 6. Criar Artifact Registry
##############################
if ! gcloud artifacts repositories describe "$ARTIFACT_REPO" --location="$REGION" >/dev/null 2>&1; then
  echo "📦 Criando Artifact Registry $ARTIFACT_REPO"
  gcloud artifacts repositories create "$ARTIFACT_REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Repositório para a imagem Docker do feedback-app"
else
  echo "✅ Artifact Registry já existe"
fi

##############################
# 7. Criar App Engine
##############################
if ! gcloud app describe >/dev/null 2>&1; then
  echo "🌍 Criando App Engine"
  gcloud app create --region="$REGION"
else
  echo "✅ App Engine já existe"
fi

##############################
# FINAL
##############################

echo "🎉 Infraestrutura criada com sucesso usando SA Infra!"
