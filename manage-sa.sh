#!/bin/bash
set -e

gcloud auth login

PROJECT_ID="fiap-adj8-feedback-platform"
KEYS_DIR="$HOME/gcp-keys"

mkdir -p "$KEYS_DIR"

echo "🚀 Criando estrutura IAM profissional..."

############################################
# FUNÇÕES UTILITÁRIAS
############################################
create_sa() {
  NAME=$1
  DISPLAY_NAME=$2
  SA_EMAIL="$NAME@$PROJECT_ID.iam.gserviceaccount.com"

  if gcloud iam service-accounts describe "$SA_EMAIL" --project=$PROJECT_ID >/dev/null 2>&1; then
    echo "ℹ️ SA já existe: $NAME - ignorando criação"
  else
    echo "➕ Criando SA: $NAME"
    gcloud iam service-accounts create $NAME \
      --display-name="$DISPLAY_NAME" \
      --project $PROJECT_ID
  fi

  # Espera até a SA realmente existir (propagação IAM)
  echo "⏳ Aguardando propagação da SA $NAME..."
  for i in {1..10}; do
    if gcloud iam service-accounts describe "$SA_EMAIL" --project=$PROJECT_ID >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
}

add_roles() {
  SA_EMAIL=$1
  shift

  for ROLE in "$@"; do
    echo "🔐 Adicionando role $ROLE em $SA_EMAIL"
    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:$SA_EMAIL" \
      --role="$ROLE" \
      --condition=None \
      --quiet || true
  done
}

create_key() {
  SA_EMAIL=$1
  SA_NAME=$(echo "$SA_EMAIL" | cut -d'@' -f1)
  KEY_FILE="$KEYS_DIR/$SA_NAME-key.json"

  if [ -f "$KEY_FILE" ]; then
    echo "🔑 Key já existe para $SA_NAME - ignorando criação"
  else
    echo "🔑 Criando key para $SA_NAME em $KEY_FILE"
    gcloud iam service-accounts keys create "$KEY_FILE" \
      --iam-account="$SA_EMAIL" \
      --project=$PROJECT_ID
  fi
}

############################################
# 1. SA - INFRA
############################################
create_sa sa-infra "SA Infra - Criação de recursos"

add_roles sa-infra@$PROJECT_ID.iam.gserviceaccount.com \
  roles/cloudsql.admin \
  roles/artifactregistry.admin \
  roles/pubsub.admin \
  roles/cloudscheduler.admin \
  roles/iam.serviceAccountUser \
  roles/resourcemanager.projectIamAdmin \
  roles/serviceusage.serviceUsageAdmin \
  roles/compute.networkAdmin \
  roles/iam.securityAdmin \
  roles/editor

create_key sa-infra@$PROJECT_ID.iam.gserviceaccount.com

############################################
# 2. SA - DEPLOY FEEDBACK APP
############################################
create_sa sa-deploy-feedback-app "SA Deploy - Feedback App"

add_roles sa-deploy-feedback-app@$PROJECT_ID.iam.gserviceaccount.com \
  roles/appengine.deployer \
  roles/artifactregistry.reader \
  roles/appengine.serviceAdmin \
  roles/storage.admin \
  roles/logging.viewer \
  roles/logging.logWriter \
  roles/serviceusage.serviceUsageViewer \
  roles/viewer \
  roles/cloudbuild.builds.editor \
  roles/iam.serviceAccountTokenCreator \
  roles/cloudsql.client \
  roles/secretmanager.secretAccessor


create_key sa-deploy-feedback-app@$PROJECT_ID.iam.gserviceaccount.com

############################################
# 3. SA - DEPLOY NOTIFY ADMIN
############################################
create_sa sa-deploy-notify-admin "SA Deploy - Notify Admin"

add_roles sa-deploy-notify-admin@$PROJECT_ID.iam.gserviceaccount.com \
  roles/cloudfunctions.developer \
  roles/pubsub.admin \
  roles/logging.viewer \
  roles/storage.admin

create_key sa-deploy-notify-admin@$PROJECT_ID.iam.gserviceaccount.com

############################################
# 4. SA - DEPLOY WEEKLY REPORT
############################################
create_sa sa-deploy-weekly-report "SA Deploy - Weekly Report"

add_roles sa-deploy-weekly-report@$PROJECT_ID.iam.gserviceaccount.com \
  roles/cloudfunctions.developer \
  roles/pubsub.admin \
  roles/cloudscheduler.admin \
  roles/logging.viewer \
  roles/storage.admin

create_key sa-deploy-weekly-report@$PROJECT_ID.iam.gserviceaccount.com

############################################
# 5. SA - RUNTIME FEEDBACK APP
############################################
create_sa sa-runtime-feedback-app "SA Runtime - Feedback App"

add_roles sa-runtime-feedback-app@$PROJECT_ID.iam.gserviceaccount.com \
  roles/cloudsql.client \
  roles/pubsub.publisher \
  roles/logging.logWriter

create_key sa-runtime-feedback-app@$PROJECT_ID.iam.gserviceaccount.com

############################################
# 6. SA - RUNTIME NOTIFY ADMIN
############################################
create_sa sa-runtime-notify-admin "SA Runtime - Notify Admin"

add_roles sa-runtime-notify-admin@$PROJECT_ID.iam.gserviceaccount.com \
  roles/pubsub.subscriber \
  roles/logging.logWriter

create_key sa-runtime-notify-admin@$PROJECT_ID.iam.gserviceaccount.com

############################################
# 7. SA - RUNTIME WEEKLY REPORT
############################################
create_sa sa-runtime-weekly-report "SA Runtime - Weekly Report"

add_roles sa-runtime-weekly-report@$PROJECT_ID.iam.gserviceaccount.com \
  roles/pubsub.publisher \
  roles/logging.logWriter

create_key sa-runtime-weekly-report@$PROJECT_ID.iam.gserviceaccount.com

APPENGINE_SA="$PROJECT_ID@appspot.gserviceaccount.com"
DEPLOY_SA="sa-deploy-feedback-app@$PROJECT_ID.iam.gserviceaccount.com"

NOTIFY_DEPLOY_SA="sa-deploy-notify-admin@$PROJECT_ID.iam.gserviceaccount.com"
WEEKLY_REPORT_DEPLOY_SA="sa-deploy-weekly-report@$PROJECT_ID.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

echo "🔗 Permitindo que $DEPLOY_SA atue como $APPENGINE_SA"

gcloud iam service-accounts add-iam-policy-binding "$APPENGINE_SA" \
  --member="serviceAccount:$DEPLOY_SA" \
  --role="roles/iam.serviceAccountUser" \
  --quiet

############################################
# PERMITIR QUE A SA DE DEPLOY NOTIFY SE ASSUMA
############################################

echo "🔗 Permitindo que $NOTIFY_DEPLOY_SA atue como $COMPUTE_SA"

gcloud iam service-accounts add-iam-policy-binding "$COMPUTE_SA" \
  --member="serviceAccount:$NOTIFY_DEPLOY_SA" \
  --role="roles/iam.serviceAccountUser" \
  --quiet


echo "🔗 Permitindo que $WEEKLY_REPORT_DEPLOY_SA atue como $COMPUTE_SA"

gcloud iam service-accounts add-iam-policy-binding "$COMPUTE_SA" \
  --member="serviceAccount:$WEEKLY_REPORT_DEPLOY_SA" \
  --role="roles/iam.serviceAccountUser" \
  --quiet



echo "✅ Todas as Service Accounts e suas keys foram criadas com sucesso!"
echo "📁 Keys armazenadas em: $KEYS_DIR"