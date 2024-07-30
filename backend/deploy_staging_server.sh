#!/bin/bash

# This script is used to deploy the server to Google Cloud Run.
# It automatically imports secrets from Google Cloud Secret Manager based on labels.
# It also handles the service key and .gitignore modifications.
# Now includes an auto-update feature with config preservation.

# Author @VindicoRory

# ===========================================
# CONFIGURATION SECTION - MODIFY VALUES HERE
# ===========================================

# Google Cloud Run Configuration
PROJECT_ID="your-project-id-here"        # Your Google Cloud Project ID
DEPLOYMENT_NAME="your-deployment-name"   # Name of your Cloud Run service
DEPLOYMENT_REGION="europe-west1"         # Region for deployment (e.g., europe-west1)

# Deployment Source Configuration
SOURCE_PATH="."                          # Path to the source code (. for current directory)

# Environment Configuration
ENVIRONMENT="staging"                    # Environment (e.g., staging, production)
SECRET_LABEL="env=$ENVIRONMENT"          # Label for selecting secrets

# Optional Configuration
SERVICE_KEY_NAME=""                      # Firebase Service Key Name (if applicable)

# ===========================================
# END OF CONFIGURATION SECTION
# ===========================================

# --- Auto-update Configuration ---
REPO_URL="https://raw.githubusercontent.com/yourusername/yourrepository/main"
SCRIPT_NAME="$(basename "$0")"
VERSION="1.0.0"

# List of configuration variables to preserve during updates
CONFIG_VARS=(
    "PROJECT_ID"
    "DEPLOYMENT_NAME"
    "DEPLOYMENT_REGION"
    "SOURCE_PATH"
    "ENVIRONMENT"
    "SECRET_LABEL"
    "SERVICE_KEY_NAME"
)

# Function to extract configuration
extract_config() {
    local config_file="/tmp/${SCRIPT_NAME}_config"
    for var in "${CONFIG_VARS[@]}"; do
        if [ -n "${!var}" ]; then
            echo "${var}='${!var}'" >> "$config_file"
        fi
    done
}

# Function to apply configuration
apply_config() {
    local config_file="/tmp/${SCRIPT_NAME}_config"
    if [ -f "$config_file" ]; then
        source "$config_file"
        rm "$config_file"
    fi
}

# Function to check for updates
check_for_updates() {
    log_message "${YELLOW}🔄 Checking for updates...${NC}"
    local tmp_file="/tmp/$SCRIPT_NAME"
    if curl -sSL "$REPO_URL/$SCRIPT_NAME" -o "$tmp_file"; then
        if [ -f "$tmp_file" ]; then
            remote_version=$(grep "^VERSION=" "$tmp_file" | cut -d'"' -f2)
            if [ "$VERSION" != "$remote_version" ]; then
                log_message "${GREEN}✅ Update available: $remote_version${NC}"
                read -p "Do you want to update? (y/n): " update_confirm
                if [[ $update_confirm == [Yy] ]]; then
                    extract_config
                    mv "$tmp_file" "$0"
                    chmod +x "$0"
                    log_message "${GREEN}✅ Script updated. Restarting with preserved config...${NC}"
                    exec "$0" "$@"
                else
                    log_message "${YELLOW}⚠️ Update skipped.${NC}"
                fi
            else
                log_message "${GREEN}✅ Script is up to date.${NC}"
            fi
        fi
    else
        log_message "${RED}❌ Failed to check for updates.${NC}"
    fi
}

# Define color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    echo -e "$1"
}

# Function to convert string to uppercase
to_uppercase() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Function to fetch secrets based on label and generate secret flags
fetch_secrets() {
    local secret_flags=""
    local secrets=$(gcloud secrets list --filter="labels.$SECRET_LABEL" --format="value(name)")

    if [ -z "$secrets" ]; then
        log_message "${YELLOW}⚠️ No secrets found with label $SECRET_LABEL${NC}"
        return
    fi

    local env_prefix=$(to_uppercase "${ENVIRONMENT}")
    for secret in $secrets; do
        # Remove the environment prefix and underscore
        local secret_name=$(echo "$secret" | sed "s/^${env_prefix}_//")
        secret_flags+="--set-secrets=${secret_name}=${secret}:latest "
    done
    echo $secret_flags
}

# Function to comment out specific lines in .gitignore
comment_out_gitignore_entries() {
    local gitignore_file=".gitignore"

    # Check if the .gitignore file exists
    if [ ! -f "$gitignore_file" ]; then
        log_message "${RED}❌ Error: .gitignore file not found.${NC}"
        exit 1
    fi

    # Lines to be commented out
    local lines_to_comment=(".npmrc" "$SERVICE_KEY_NAME")

    for line in "${lines_to_comment[@]}"; do
        # Comment out the line if it's not already commented
        sed -i '' "/^$line/ s/^/#/" $gitignore_file
    done

    log_message "${GREEN}✅ .gitignore entries commented out.${NC}"
}

# Function to uncomment specific lines in .gitignore
uncomment_gitignore_entries() {
    local gitignore_file=".gitignore"

    # Check if the .gitignore file exists
    if [ ! -f "$gitignore_file" ]; then
        log_message "${RED}❌ Error: .gitignore file not found.${NC}"
        exit 1
    fi

    # Lines to be uncommented
    local lines_to_uncomment=(".npmrc" "$SERVICE_KEY_NAME")

    for line in "${lines_to_uncomment[@]}"; do
        # Uncomment the line if it's commented
        sed -i '' "/^#$line/ s/^#//" $gitignore_file
    done

    log_message "${GREEN}✅ .gitignore entries uncommented.${NC}"
}

# Function to update the Dockerfile with the correct environment setting
update_dockerfile_env() {
    local dockerfile_path="./Dockerfile"

    # Check if the Dockerfile exists
    if [ ! -f "$dockerfile_path" ]; then
        log_message "${RED}❌ Error: Dockerfile not found.${NC}"
        exit 1
    fi

    # macOS compatible sed command to replace the --env setting in the Dockerfile
    sed -i '' "s/--env=[a-z]*/--env=$ENVIRONMENT/g" "$dockerfile_path"

    if [ $? -eq 0 ]; then
        log_message "${GREEN}✅ Dockerfile updated to use --env=$ENVIRONMENT${NC}"
    else
        log_message "${RED}❌ Failed to update Dockerfile.${NC}"
    fi
}

# Parse command line arguments
SKIP_CONFIRMATION=false
while getopts ":y" opt; do
  case $opt in
    y)
      SKIP_CONFIRMATION=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# --- Main Script Execution ---

# Check for updates
check_for_updates "$@"

echo -e "${YELLOW}🚀 Starting Deployment Process... ${RED}($ENVIRONMENT) ${NC}"

# Confirmation before Deployment
if [ "$SKIP_CONFIRMATION" = false ]; then
    read -p "🤔 Are you sure you want to deploy '$DEPLOYMENT_NAME' to '$PROJECT_ID'? (y/n): " confirmation
    if [[ $confirmation != [Yy] ]]; then
        log_message "${YELLOW}🛑 Deployment cancelled by user.${NC}"
        exit 0
    fi
fi

# Update the Dockerfile with the correct environment
update_dockerfile_env

# Call the function to comment out .gitignore entries
comment_out_gitignore_entries

# Setting Project to the specified ID
log_message "🔨 Setting Project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# Verify Project Setting
currentProjectID=$(gcloud config get-value project)
if [ "$currentProjectID" != "$PROJECT_ID" ]; then
    log_message "${RED}❌ Error: Project ID mismatch. Expected: ${PROJECT_ID}, Found: ${currentProjectID}.${NC}"
    exit 1
fi
log_message "${GREEN}✅ Project ID verified: $currentProjectID${NC}"

# Fetch secrets and get secret flags
SECRET_FLAGS=$(fetch_secrets)

# Print out the secret flags (for debugging, remove in production)
log_message "${YELLOW}🔒 Secret Flags: $SECRET_FLAGS${NC}"

# Deployment
log_message "${YELLOW}🚢 Deploying $DEPLOYMENT_NAME to Cloud Run...${NC}"
gcloud run deploy $DEPLOYMENT_NAME \
  --source $SOURCE_PATH \
  --platform managed \
  --region $DEPLOYMENT_REGION \
  --allow-unauthenticated \
  $(echo $SECRET_FLAGS)

# Check the result of the deployment
if [ $? -eq 0 ]; then
    log_message "${GREEN}✅ Deployment of $DEPLOYMENT_NAME Successful!${NC}"
else
    log_message "${RED}❌ Deployment of $DEPLOYMENT_NAME Failed.${NC}"
fi

# Uncomment lines after the deployment process has finished
uncomment_gitignore_entries

# Remove service_key and .npmrc files from git cache
git rm --cached $SERVICE_KEY_NAME .npmrc >> /dev/null 2>&1

# --- Script End ---
