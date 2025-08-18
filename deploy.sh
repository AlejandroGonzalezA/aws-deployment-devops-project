#!/bin/bash
set -e

# AWS Deployment Script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"
DEPLOYMENT_HISTORY_FILE="$SCRIPT_DIR/.deployment-history.json"

CUSTOM_IMAGE=""
ENVIRONMENT=""
ACTION=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image)
            CUSTOM_IMAGE="$2"
            shift 2
            ;;
        --image=*)
            CUSTOM_IMAGE="${1#*=}"
            shift
            ;;
        -*)
            echo "Unknown option $1"
            exit 1
            ;;
        *)
            if [[ -z "$ENVIRONMENT" ]]; then
                ENVIRONMENT="$1"
            elif [[ -z "$ACTION" ]]; then
                ACTION="$1"
            else
                echo "Too many arguments"
                exit 1
            fi
            shift
            ;;
    esac
done

# Set default action
ACTION=${ACTION:-apply}

# Check arguments
if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 <environment> [action] [--image=IMAGE_TAG]"
    echo ""
    echo "Environment: dev, prod"
    echo ""
    echo "Actions:"
    echo "  plan         - Show terraform execution plan"
    echo "  apply        - Deploy infrastructure only (Terraform)"
    echo "  deploy       - Full deployment (Terraform + setup + application)"
    echo "  destroy      - Destroy all infrastructure"
    echo "  setup-env    - Setup environment only (Ansible)"
    echo "  deploy-app   - Deploy application only (Ansible)"
    echo "  update-app   - Update application (default: latest from tfvars, or --image=TAG)"
    echo "  rollback     - Rollback to previous version (default: last deployed, or --image=TAG)"
    echo ""
    echo "Examples:"
    echo "  $0 dev apply                                    # Infrastructure only"
    echo "  $0 dev deploy                                   # Full deployment"
    echo "  $0 dev update-app                               # Update to latest (from tfvars)"
    echo "  $0 dev update-app --image=myapp:v1.2.3          # Update to specific version"
    echo "  $0 dev rollback                                 # Rollback to previous version"
    echo "  $0 dev rollback --image=myapp:v1.1.0            # Rollback to specific version"
    exit 1
fi

# Validate action
valid_actions=("plan" "apply" "deploy" "destroy" "setup-env" "deploy-app" "update-app" "rollback")
if [[ ! " ${valid_actions[@]} " =~ " ${ACTION} " ]]; then
    echo "Error: Invalid action '$ACTION'"
    echo "Valid actions: ${valid_actions[*]}"
    exit 1
fi

# Validate environment
if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    echo "Error: Environment must be 'dev' or 'prod'"
    exit 1
fi

# Check if required tools are installed
for tool in terraform ansible-playbook aws; do
    if ! command -v $tool &> /dev/null; then
        echo "Error: $tool is not installed or not in PATH"
        echo "Please install $tool before running this script"
        exit 1
    fi
done

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured"
    echo "Run 'aws configure' or set AWS environment variables"
    exit 1
fi

# Deployment history management functions
init_deployment_history() {
    if [[ ! -f "$DEPLOYMENT_HISTORY_FILE" ]]; then
        echo '{}' > "$DEPLOYMENT_HISTORY_FILE"
    else
        # Validate existing JSON and fix if corrupted
        if ! jq empty "$DEPLOYMENT_HISTORY_FILE" 2>/dev/null; then
            echo "Warning: Corrupted deployment history file, reinitializing..."
            echo '{}' > "$DEPLOYMENT_HISTORY_FILE"
        fi
    fi
}

get_current_image() {
    local env="$1"
    if [[ -f "$DEPLOYMENT_HISTORY_FILE" ]]; then
        cat "$DEPLOYMENT_HISTORY_FILE" | jq -r ".[\"$env\"].current // null" 2>/dev/null || echo "null"
    else
        echo "null"
    fi
}

get_previous_image() {
    local env="$1"
    if [[ -f "$DEPLOYMENT_HISTORY_FILE" ]]; then
        cat "$DEPLOYMENT_HISTORY_FILE" | jq -r ".[\"$env\"].previous // null" 2>/dev/null || echo "null"
    else
        echo "null"
    fi
}

save_deployment() {
    local env="$1"
    local new_image="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    init_deployment_history
    
    # Get current image to save as previous
    local current_image=$(get_current_image "$env")
    
    # Create deployment entry with proper JSON handling using jq
    local deployment_entry
    if [[ "$current_image" == "null" ]] || [[ -z "$current_image" ]]; then
        deployment_entry=$(jq -n \
            --arg current "$new_image" \
            --arg timestamp "$timestamp" \
            '{current: $current, previous: null, last_deployment: $timestamp, deployments: []}')
    else
        deployment_entry=$(jq -n \
            --arg current "$new_image" \
            --arg previous "$current_image" \
            --arg timestamp "$timestamp" \
            '{current: $current, previous: $previous, last_deployment: $timestamp, deployments: []}')
    fi
    
    # If history exists, preserve deployment history and update
    if [[ -f "$DEPLOYMENT_HISTORY_FILE" ]] && [[ $(cat "$DEPLOYMENT_HISTORY_FILE") != "{}" ]]; then
        # Get existing deployments array
        local existing_deployments=$(cat "$DEPLOYMENT_HISTORY_FILE" | jq ".[\"$env\"].deployments // []" 2>/dev/null || echo "[]")
        
        # Add new deployment to history - using jq to ensure proper JSON
        local new_deployment=$(jq -n \
            --arg image "$new_image" \
            --arg timestamp "$timestamp" \
            --arg action "deploy" \
            '{image: $image, timestamp: $timestamp, action: $action}')
        
        # Update the deployments array (keep last 10 deployments)
        local updated_deployments=$(echo "$existing_deployments" | jq --argjson new "$new_deployment" '. + [$new] | if length > 10 then .[1:] else . end')
        
        # Update the deployment entry with history
        deployment_entry=$(echo "$deployment_entry" | jq --argjson deployments "$updated_deployments" '.deployments = $deployments')
    fi
    
    # Update the history file using jq for safe JSON manipulation
    local updated_history
    if [[ -f "$DEPLOYMENT_HISTORY_FILE" ]]; then
        updated_history=$(cat "$DEPLOYMENT_HISTORY_FILE" | jq --argjson entry "$deployment_entry" --arg env "$env" '.[$env] = $entry')
    else
        updated_history=$(jq -n --argjson entry "$deployment_entry" --arg env "$env" '{($env): $entry}')
    fi
    echo "$updated_history" > "$DEPLOYMENT_HISTORY_FILE"
    
    echo "📝 Deployment recorded: $new_image"
}

get_image_from_tfvars() {
    local env="$1"
    local tfvars_file="$TERRAFORM_DIR/environments/${env}.tfvars"
    
    if [[ -f "$tfvars_file" ]]; then
        grep -E '^docker_image\s*=' "$tfvars_file" | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' '
    else
        echo ""
    fi
}

determine_target_image() {
    local env="$1"
    local action="$2"
    local custom_image="$3"
    
    if [[ -n "$custom_image" ]]; then
        echo "$custom_image"
        return
    fi
    
    case "$action" in
        "update-app")
            # Default to latest image from tfvars
            local latest_image=$(get_image_from_tfvars "$env")
            if [[ -n "$latest_image" ]]; then
                echo "$latest_image"
            else
                echo "Error: Could not determine latest image from $env.tfvars"
                exit 1
            fi
            ;;
        "rollback")
            # Default to previous deployed image
            local previous_image=$(get_previous_image "$env")
            if [[ "$previous_image" != "null" && -n "$previous_image" ]]; then
                echo "$previous_image"
            else
                echo "Error: No previous deployment found for rollback. Use --image=TAG to specify target image."
                exit 1
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# Check required environment variables (sensitive only)
required_vars=(
    "TF_VAR_key_pair_name"
    "TF_VAR_db_password"
)

echo "Checking environment variables..."
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "Error: $var is not set"
        echo "Source your .env file first: source .env"
        exit 1
    fi
done

# Function to run Ansible playbooks
run_ansible() {
    local playbook=$1
    local description=$2
    local extra_vars=${3:-""}
    
    echo "$description"
    cd "$ANSIBLE_DIR"
    
    # Update inventory first
    echo "Refreshing Ansible inventory..."
    ansible-inventory -i inventory/aws_ec2.yml --list > inventory/hosts_generated.json
    
    # Run the playbook with extra vars if provided
    local target_env="env_$ENVIRONMENT"
    if [[ -n "$extra_vars" ]]; then
        ansible-playbook -i inventory/aws_ec2.yml "playbooks/$playbook" --extra-vars "target_environment=$target_env $extra_vars"
    else
        ansible-playbook -i inventory/aws_ec2.yml "playbooks/$playbook" --extra-vars "target_environment=$target_env"
    fi
    
    # Return to terraform directory for subsequent terraform commands
    cd "$TERRAFORM_DIR"
}

cd "$TERRAFORM_DIR"

case $ACTION in
    plan)
        echo "Planning infrastructure for $ENVIRONMENT..."
        terraform init -backend-config="key=terraform-$ENVIRONMENT.tfstate"
        terraform plan -var-file="environments/$ENVIRONMENT.tfvars"
        ;;
    apply)
        echo "Deploying infrastructure for $ENVIRONMENT..."
        terraform init -backend-config="key=terraform-$ENVIRONMENT.tfstate"
        terraform apply -auto-approve -var-file="environments/$ENVIRONMENT.tfvars"
        
        echo ""
        echo "=== Infrastructure Outputs ==="
        terraform output
        ;;
    deploy)
        echo "Full deployment for $ENVIRONMENT (infrastructure + application)..."
        terraform init -backend-config="key=terraform-$ENVIRONMENT.tfstate"
        terraform apply -auto-approve -var-file="environments/$ENVIRONMENT.tfvars"
        
        echo ""
        echo "=== Infrastructure Outputs ==="
        terraform output
        
        # Get ALB DNS for application access
        ALB_DNS=$(terraform output -raw alb_dns_name)
        ASG_NAME=$(terraform output -raw asg_name)
        echo ""
        echo "🔗 ALB DNS Name: $ALB_DNS"
        echo "� Auto Scaling Group: $ASG_NAME"
        
        # Extract Docker image from tfvars for Ansible
        DOCKER_IMAGE=$(grep '^docker_image[[:space:]]*=' "environments/$ENVIRONMENT.tfvars" | cut -d'"' -f2)
        if [[ -z "$DOCKER_IMAGE" ]]; then
            echo "Warning: docker_image not found in tfvars, using default"
            DOCKER_IMAGE="nginx:latest"
        fi
        
        # Get database configuration from Terraform outputs
        DB_HOST=$(terraform output -raw rds_address 2>/dev/null || echo "localhost")
        DB_USER="postgres"
        DB_NAME="myapp"
        
        # Database password from environment variable
        DB_PASSWORD="$TF_VAR_db_password"
        
        echo ""
        run_ansible "setup-environment.yml" "Setting up environment..."
        # Determine Flask environment based on deployment environment
        FLASK_ENV=$([[ "$ENVIRONMENT" == "prod" ]] && echo "production" || echo "development")
        
        run_ansible "deploy-app.yml" "Deploying application..." "docker_image=$DOCKER_IMAGE app_port=5000 flask_env=$FLASK_ENV db_host=$DB_HOST db_name=$DB_NAME db_user=$DB_USER db_password=$DB_PASSWORD"
        
        # Save deployment to history
        save_deployment "$ENVIRONMENT" "$DOCKER_IMAGE"
        
        echo ""
        echo "🎉 Deployment Complete!"
        echo "📱 Application URL (via ALB): http://$ALB_DNS"
        echo "🔗 Health Check (via ALB): http://$ALB_DNS/health"
        echo "� Auto Scaling Group: $ASG_NAME"
        echo "� Scaling Status: Use 'aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME' to check instances"
        ;;
    destroy)
        if [[ "$ENVIRONMENT" == "prod" ]]; then
            echo "WARNING: You are about to destroy PRODUCTION infrastructure!"
            echo "This will permanently delete all resources and data."
            read -p "Type 'yes' to confirm destruction of production: " confirm
            if [[ "$confirm" != "yes" ]]; then
                echo "Destruction cancelled"
                exit 1
            fi
        fi
        
        echo "Destroying infrastructure for $ENVIRONMENT..."
        terraform init -backend-config="key=terraform-$ENVIRONMENT.tfstate"
        terraform destroy -auto-approve -var-file="environments/$ENVIRONMENT.tfvars"
        ;;
    setup-env)
        run_ansible "setup-environment.yml" "Setting up environment for $ENVIRONMENT..."
        ;;
    deploy-app)
        # Extract Docker image from tfvars for Ansible
        DOCKER_IMAGE=$(grep '^docker_image[[:space:]]*=' "environments/$ENVIRONMENT.tfvars" | cut -d'"' -f2)
        if [[ -z "$DOCKER_IMAGE" ]]; then
            echo "Warning: docker_image not found in tfvars, using default"
            DOCKER_IMAGE="nginx:latest"
        fi
        
        # Get database configuration from Terraform outputs
        DB_HOST=$(terraform output -raw rds_address 2>/dev/null || echo "localhost")
        DB_USER="postgres"
        DB_NAME="myapp"
        DB_PASSWORD="$TF_VAR_db_password"
        
        # Get ALB DNS
        ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "unknown")
        
        # Determine Flask environment based on deployment environment
        FLASK_ENV=$([[ "$ENVIRONMENT" == "prod" ]] && echo "production" || echo "development")
        
        run_ansible "deploy-app.yml" "Deploying application for $ENVIRONMENT..." "docker_image=$DOCKER_IMAGE app_port=5000 flask_env=$FLASK_ENV db_host=$DB_HOST db_name=$DB_NAME db_user=$DB_USER db_password=$DB_PASSWORD"
        
        # Save deployment to history
        save_deployment "$ENVIRONMENT" "$DOCKER_IMAGE"
        
        echo ""
        echo "🎉 Application Deployment Complete!"
        echo "📱 Application URL (via ALB): http://$ALB_DNS"
        echo "🔗 Health Check (via ALB): http://$ALB_DNS/health"
        ;;
    update-app)
        # Determine target image (custom or latest from tfvars)
        TARGET_IMAGE=$(determine_target_image "$ENVIRONMENT" "update-app" "$CUSTOM_IMAGE")
        
        echo "Updating application for $ENVIRONMENT..."
        if [[ -n "$CUSTOM_IMAGE" ]]; then
            echo "🎯 Target image: $TARGET_IMAGE (custom)"
        else
            echo "🎯 Target image: $TARGET_IMAGE (latest from tfvars)"
        fi
        
        # Get database configuration from Terraform outputs
        DB_HOST=$(terraform output -raw rds_address 2>/dev/null || echo "localhost")
        DB_USER="postgres"
        DB_NAME="myapp"
        DB_PASSWORD="$TF_VAR_db_password"
        
        # Get ALB DNS
        ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "unknown")
        
        # Determine Flask environment based on deployment environment
        FLASK_ENV=$([[ "$ENVIRONMENT" == "prod" ]] && echo "production" || echo "development")
        
        run_ansible "deploy-app.yml" "Updating application for $ENVIRONMENT..." "docker_image=$TARGET_IMAGE app_port=5000 flask_env=$FLASK_ENV db_host=$DB_HOST db_name=$DB_NAME db_user=$DB_USER db_password=$DB_PASSWORD"
        
        # Save deployment to history
        save_deployment "$ENVIRONMENT" "$TARGET_IMAGE"
        
        echo ""
        echo "🎉 Application Update Complete!"
        echo "📱 Application URL (via ALB): http://$ALB_DNS"
        echo "🔗 Health Check (via ALB): http://$ALB_DNS/health"
        ;;
    rollback)
        # Determine target image (custom or previous deployed)
        TARGET_IMAGE=$(determine_target_image "$ENVIRONMENT" "rollback" "$CUSTOM_IMAGE")
        
        echo "Rolling back application for $ENVIRONMENT..."
        if [[ -n "$CUSTOM_IMAGE" ]]; then
            echo "🎯 Target image: $TARGET_IMAGE (custom)"
        else
            echo "🎯 Target image: $TARGET_IMAGE (previous deployment)"
        fi
        
        # Get database configuration from Terraform outputs
        DB_HOST=$(terraform output -raw rds_address 2>/dev/null || echo "localhost")
        DB_USER="postgres"
        DB_NAME="myapp"
        DB_PASSWORD="$TF_VAR_db_password"
        
        # Get ALB DNS
        ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "unknown")
        
        # Choose rollback method based on whether custom image is specified
        if [[ -n "$CUSTOM_IMAGE" ]]; then
            # Rollback to specific image using rollback-app.yml
            run_ansible "rollback-app.yml" "Rolling back application for $ENVIRONMENT..." "rollback_image=$TARGET_IMAGE flask_env=production db_host=$DB_HOST db_name=$DB_NAME db_user=$DB_USER db_password=$DB_PASSWORD"
        else
            # Rollback to backup container using rollback-app.yml
            run_ansible "rollback-app.yml" "Rolling back application for $ENVIRONMENT..." "flask_env=production db_host=$DB_HOST db_name=$DB_NAME db_user=$DB_USER db_password=$DB_PASSWORD"
        fi
        
        # Save rollback to history
        save_deployment "$ENVIRONMENT" "$TARGET_IMAGE"
        
        echo ""
        echo "🎉 Application Rollback Complete!"
        echo "📱 Application URL (via ALB): http://$ALB_DNS"
        echo "🔗 Health Check (via ALB): http://$ALB_DNS/health"
        ;;
    *)
        echo "Invalid action: $ACTION"
        echo "Valid actions: plan, apply, deploy, destroy, setup-env, deploy-app, update-app, rollback"
        exit 1
        ;;
esac

echo "Done!"
