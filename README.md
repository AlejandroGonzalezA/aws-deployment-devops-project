# AWS DevOps Deployment Project

A complete Infrastructure as Code (IaC) solution for deploying Flask applications on AWS using Terraform and Ansible with **zero-downtime deployment** and automatic rollback capabilities.

<div align="center">
  <img src="docs/AWS Infrastructure-EC2_ALB_ASG.png" alt="AWS Infrastructure Architecture" width="800"/>
  <p><em>High-level AWS infrastructure architecture with ALB, Auto Scaling, and RDS</em></p>
</div>

## 🎯 What This Project Does

- **Infrastructure**: Creates VPC, Auto Scaling Groups, ALB, RDS PostgreSQL database on AWS
- **Zero-Downtime**: Application Load Balancer (ALB) + Auto Scaling Groups for rolling deployments without interruptions
- **Dynamic Inventory**: Ansible automatically discovers instances by environment tags
- **Environment Isolation**: Separate dev/prod deployments that never interfere with each other
- **Deployment**: Automatically deploys Flask Docker applications with health checks
- **Rollback**: Automatic rollback on deployment failures with container backup system
- **Security**: Private database subnets, configurable security groups, ALB-only application access
- **Monitoring**: CloudWatch alarms for auto-scaling based on CPU utilization

## 🚀 Quick Start

```bash
# 1. Clone and setup
git clone https://github.com/YOUR_USERNAME/aws-deployment-devops-project.git
cd aws-deployment-devops-project
cp .env.example .env
# Edit .env with your AWS credentials and database password

# 2. Deploy everything
./deploy.sh dev deploy

# 3. Access your application
# URLs will be displayed after successful deployment
```

## Table of Contents

- [Prerequisites & Setup](#prerequisites--setup)
  - [System Requirements](#system-requirements)
  - [Tool Installation](#tool-installation)
  - [AWS Setup](#aws-setup)
- [Configuration Overview](#configuration-overview)
- [Deployment Commands](#deployment-commands)
  - [Full Deployment](#full-deployment-recommended)
  - [Step-by-Step Deployment](#step-by-step-deployment)
  - [Application Updates](#application-updates)
  - [Zero Downtime vs Standard Deployment](#zero-downtime-vs-standard-deployment)
- [Monitoring & Auto Scaling](#monitoring--auto-scaling)
- [Verification & Testing](#verification--testing)
- [Rollback & Recovery](#rollback--recovery)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)
- [Customization](#customization)
- [Project Structure](#project-structure)
- [Cleanup](#cleanup)

## Prerequisites & Setup

### System Requirements

- **Operating System**: Linux/macOS (WSL2 for Windows)
- **Python**: 3.8+ (required for Ansible and AWS integration)
- **AWS Account**: With EC2, VPC, RDS permissions

### Tool Installation

#### 1. AWS CLI v2+ Installation

Follow [this](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installation guide.

```bash
# Configure AWS credentials
aws configure
# Enter: Access Key ID, Secret Access Key, region (us-east-1), output format (json)

# Verify installation and credentials
aws --version
aws sts get-caller-identity
```

#### 2. Terraform v1.0+ Installation

Follow [this](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) installation guide.

```bash
# Verify installation
terraform --version
```

#### 3. Ansible Installation with AWS Integration

> **⚠️ CRITICAL**: This step is essential for AWS connectivity. Follow exactly as shown.

**Step 3a: Install pipx (Recommended Method)**
```bash
# Install pipx for isolated Python environments
python3 -m pip install --user pipx
python3 -m pipx ensurepath

# Restart your shell
source ~/.bashrc  # or close/reopen terminal
```

**Step 3b: Install Ansible with AWS Dependencies**
```bash
# Install Ansible in isolated environment
pipx install ansible

# CRITICAL: Install AWS libraries in Ansible's environment
# This prevents "boto3/botocore not found" errors
pipx inject ansible boto3 botocore

# Install AWS collection for dynamic inventory
ansible-galaxy collection install amazon.aws
```

**Step 3c: Verify Installation**
```bash
# Test AWS integration - this confirms everything works
ansible localhost -m amazon.aws.aws_caller_info
# Should return your AWS account info without errors
```

### AWS Setup

#### 1. Create SSH Key Pairs
```bash
# Create SSH key pairs for environments
aws ec2 create-key-pair --key-name myapp-dev-keypair \
  --query 'KeyMaterial' --output text > ~/.ssh/myapp-dev-keypair.pem

aws ec2 create-key-pair --key-name myapp-prod-keypair \
  --query 'KeyMaterial' --output text > ~/.ssh/myapp-prod-keypair.pem

# Set correct permissions
chmod 400 ~/.ssh/myapp-*-keypair.pem
```

#### 2. Configure Environment Variables
```bash
# Copy and edit environment template
cp .env.example .env

# Edit .env with your values:
# TF_VAR_key_pair_name=myapp-dev-keypair
# TF_VAR_db_password=your-secure-password-123

# Source the environment variables
source .env
```

**Recommended**: Use different `.env` files for each environment:
```bash
source .env.dev    # For development
source .env.prod   # For production
```

## Configuration Overview

### Application Configuration
- **Flask App**: Runs on port 5000 with Gunicorn
- **Health Endpoint**: `/health` - returns database status
- **Environment Variables**: Configured for Flask with PostgreSQL

### Environment Files
**Development (`terraform/environments/dev.tfvars`):**
```hcl
docker_image = "alexg18/flask-app-devops-project_app:develop"
ec2_instance_type = "t3.micro"
db_instance_class = "db.t3.micro"

# Network configuration with ALB support
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidr   = "10.0.1.0/24"
public_subnet_2_cidr = "10.0.4.0/24"  # Second subnet for ALB
```

**Production (`terraform/environments/prod.tfvars`):**
```hcl
docker_image = "alexg18/flask-app-devops-project_app:main"
ec2_instance_type = "t3.small"  
db_instance_class = "db.t3.small"

# Network configuration with ALB support
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidr   = "10.1.1.0/24"
public_subnet_2_cidr = "10.1.4.0/24"  # Second subnet for ALB
```

### Application Environment Variables
Automatically configured by deployment:
```bash
FLASK_ENV=development
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<from-terraform>
POSTGRES_DB=myapp
POSTGRES_HOST=<rds-endpoint>
POSTGRES_PORT=5432
PORT=5000
```

## Deployment Commands

The deployment script (`./deploy.sh`) provides comprehensive deployment tracking, automatic rollback capabilities, and environment isolation.

### Script Syntax
```bash
./deploy.sh <environment> <action> [options]

Environments: dev, prod
Actions: plan, apply, deploy, setup-env, deploy-app, update-app, rollback, destroy
Options: --image=TAG (for update-app and rollback actions)
```

### Full Deployment (Recommended)
```bash
# Deploy complete environment (infrastructure + application)
./deploy.sh dev deploy

# Output includes:
# 📱 Application URL (via ALB): http://your-alb-dns-name
# 🔗 Health Check (via ALB): http://your-alb-dns-name/health
# 🖥️  SSH Access: ssh -i ~/.ssh/myapp-dev-keypair.pem ec2-user@YOUR-IP
# 🔍 Direct EC2 Access (debug): http://YOUR-IP:5000
```

### Step-by-Step Deployment
```bash
# 1. Infrastructure only
./deploy.sh dev apply

# 2. Setup environment (Docker, AWS CLI, etc.)
./deploy.sh dev setup-env

# 3. Deploy application
./deploy.sh dev deploy-app
```

### Application Updates

#### Standard Deployment (Fast, brief interruption possible)
```bash
# Update to latest image (from tfvars file)
./deploy.sh dev update-app

# Update to specific image version
./deploy.sh dev update-app --image=alexg18/flask-app-devops-project_app:v1.2.3

# Production updates
./deploy.sh prod update-app --image=alexg18/flask-app-devops-project_app:v2.0.0
```

#### Application Rollback
```bash
# Rollback to previous deployed image
./deploy.sh dev rollback

# Rollback to specific image version
./deploy.sh dev rollback --image=alexg18/flask-app-devops-project_app:v1.1.0
```

### Zero Downtime vs Standard Deployment

#### Standard Deployment (`deploy-app.yml`)
- **Speed**: Fast deployment (1-2 minutes)
- **Downtime**: Brief interruption during container replacement (5-10 seconds)
- **Rollback**: Automatic rollback to backup container on failure
- **Use Case**: Development, testing, non-critical updates

#### Zero Downtime Rolling Deployment (`rolling-deploy.yml`)
```bash
# Use rolling-deploy.yml for true zero downtime via ASG instance refresh
ansible-playbook -i ansible/inventory/aws_ec2.yml ansible/playbooks/rolling-deploy.yml \
  --extra-vars "target_environment=env_prod asg_name=$(terraform output -raw asg_name) docker_image=myapp:v2.0.0"
```
- **Speed**: Slower deployment (5-10 minutes)
- **Downtime**: True zero downtime via ALB + ASG rolling updates
- **Rollback**: ASG-level rollback, maintains 50% healthy instances
- **Use Case**: Production, critical applications

## Monitoring & Auto Scaling

### Quick Instance Status
```bash
# Get current instance count and basic info
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw asg_name) \
  --query 'AutoScalingGroups[0].{DesiredCapacity:DesiredCapacity,MinSize:MinSize,MaxSize:MaxSize,CurrentInstances:length(Instances)}' \
  --output table

# List all instances with their IPs and status
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=$(terraform output -raw asg_name)" \
  --query 'Reservations[*].Instances[*].{InstanceId:InstanceId,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress,State:State.Name,AZ:Placement.AvailabilityZone}' \
  --output table

# Check ALB target health (which instances are receiving traffic)
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --query 'TargetHealthDescriptions[*].{InstanceId:Target.Id,Health:TargetHealth.State,Port:Target.Port}' \
  --output table
```

### Performance Monitoring
```bash
# Monitor current CPU utilization across all instances
aws cloudwatch get-metric-statistics \
  --namespace "AWS/EC2" \
  --metric-name "CPUUtilization" \
  --dimensions Name=AutoScalingGroupName,Value=$(terraform output -raw asg_name) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum \
  --output table

# Check ALB performance metrics
aws cloudwatch get-metric-statistics \
  --namespace "AWS/ApplicationELB" \
  --metric-name "RequestCount" \
  --dimensions Name=LoadBalancer,Value=$(terraform output -raw alb_arn | cut -d'/' -f2-4) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --output table
```

### SSH Access to Instances
```bash
# Get SSH commands for all running instances
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=$(terraform output -raw asg_name)" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress]' \
  --output text | while read instance_id public_ip; do
    echo "ssh -i ~/.ssh/myapp-dev-keypair.pem ec2-user@$public_ip  # Instance: $instance_id"
done
```

## Verification & Testing

### Quick Health Check
```bash
# Test application via Load Balancer
curl http://YOUR-ALB-DNS-NAME/health

# Expected response:
{
  "database": "connected",
  "message": "Application is running correctly", 
  "status": "healthy",
  "timestamp": "2025-XX-XXTXX:XX:XX.XXXXXX"
}
```

### Auto Scaling Verification
```bash
# 1. Check current instance count and capacity
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw asg_name) \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Current:length(Instances)}'

# 2. Verify all instances are healthy in the target group
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`].Target.Id'

# 3. Test load balancing across instances (run multiple times)
for i in {1..5}; do curl -s http://YOUR-ALB-DNS-NAME/health | jq -r .timestamp; done
```

### Complete Infrastructure Verification
```bash
# 1. Check AWS credentials
aws sts get-caller-identity

# 2. Check Terraform state and outputs
cd terraform && terraform output

# 3. Verify Auto Scaling Group configuration
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw asg_name) \
  --query 'AutoScalingGroups[0].{Name:AutoScalingGroupName,LaunchTemplate:LaunchTemplate,VPCZoneIdentifier:VPCZoneIdentifier,HealthCheckType:HealthCheckType}'

# 4. Check CloudWatch alarms are active
aws cloudwatch describe-alarms \
  --alarm-names $(terraform output -raw cloudwatch_alarms | jq -r '.cpu_high_alarm, .cpu_low_alarm') \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}'
```

## Rollback & Recovery

### Deployment History Tracking
The deployment script automatically tracks deployment history in `.deployment-history.json`:
- **Current deployed image** for each environment
- **Previous deployed image** for easy rollback
- **Deployment timestamps** and history
- **Last 10 deployments** per environment

### Automatic Rollback on Failure
- **Container Backup**: Before each deployment, current container is renamed to `myapp-backup-{timestamp}`
- **Health Check Validation**: New container must pass health checks at `/health` endpoint
- **Auto-Recovery**: If health checks fail, system automatically restores backup container
- **No Manual Intervention**: Failed deployments are automatically rolled back

### Environment Isolation Features
- **Dynamic Inventory**: Uses AWS tags to target only specific environment (`env_dev`, `env_prod`)
- **No Cross-Environment Impact**: Deploying to dev never affects prod instances
- **Target Groups**: `target_environment` variable ensures playbooks run on correct instances only

## Troubleshooting

### Auto Scaling Issues

#### Instances Not Scaling Up
```bash
# Check if scaling policies are triggered
aws cloudwatch describe-alarms \
  --alarm-names $(terraform output -raw cloudwatch_alarms | jq -r '.cpu_high_alarm') \
  --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason}'

# Check recent scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name $(terraform output -raw asg_name) \
  --max-items 5
```

#### Instances Unhealthy in Target Group
```bash
# Check which instances are failing health checks
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`]'
```

#### Application Not Responding
```bash
# Check if application is running on instances
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=$(terraform output -raw asg_name)" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress]' \
  --output text | while read instance_id public_ip; do
    echo "Checking $instance_id ($public_ip):"
    curl -s --connect-timeout 5 http://$public_ip:5000/health || echo "  - Application not responding"
done
```

## Architecture

### Infrastructure Components

- **VPC**: Custom Virtual Private Cloud with public and private subnets across 2 Availability Zones
- **Application Load Balancer (ALB)**: Distributes incoming traffic across multiple instances in different AZs
- **Auto Scaling Group (ASG)**: Automatically scales EC2 instances based on CPU utilization
- **Launch Template**: Defines EC2 instance configuration for auto-scaling
- **RDS PostgreSQL**: Managed database with automated backups and multi-AZ deployment
- **Security Groups**: Network-level firewall rules for secure access
- **Internet Gateway**: Provides internet access to public subnets

### Auto Scaling Configuration

- **Development Environment**: 1-4 instances, scales up at 70% CPU, scales down at 30% CPU
- **Production Environment**: 2-10 instances, scales up at 65% CPU, scales down at 25% CPU
- **Health Checks**: ALB performs health checks on `/health` endpoint
- **Rolling Deployments**: New instances are launched and health-checked before old ones are terminated

### Load Balancer Setup
- **Application Load Balancer (ALB)**: Distributes traffic and provides health checks
- **Target Groups**: Automatic health monitoring on `/health` endpoint
- **Multi-AZ Deployment**: ALB spans multiple availability zones for high availability
- **Security**: Application only accessible through ALB, not direct EC2 access
- **Health Checks**: 
  - Path: `/health`
  - Healthy threshold: 2 consecutive successes
  - Unhealthy threshold: 2 consecutive failures
  - Check interval: 30 seconds

### Network Architecture
```
Internet Gateway
       ↓
Application Load Balancer (Multi-AZ)
       ↓
EC2 Instance (Port 5000)
       ↓
RDS PostgreSQL (Private Subnets)
```

### Security Groups
- **ALB Security Group**: Allows HTTP (80) and HTTPS (443) from internet
- **EC2 Security Group**: Allows traffic from ALB on port 5000, SSH from specified CIDRs
- **RDS Security Group**: Allows PostgreSQL (5432) from EC2 security group only

### High Availability Features

- **Multi-AZ Deployment**: Resources span multiple availability zones
- **Load Balancing**: ALB automatically distributes traffic to healthy instances
- **Auto Scaling**: Handles traffic spikes by adding instances automatically
- **Health Monitoring**: Unhealthy instances are automatically replaced
- **Database Backups**: Automated RDS backups with point-in-time recovery

## Customization

### Application Configuration

**Important**: Variables in `deploy-app.yml` have NO defaults and must be provided via `--extra-vars`:
- `docker_image`, `app_port`, `flask_env`, `db_host`, `db_name`, `db_user`, `db_password`: Required

Fixed configuration (modifiable in playbook):
```yaml
vars:
  container_name: myapp
  postgres_port: 5432
  health_check_retries: 5
  health_check_delay: 10
  health_check_timeout: 60
```

### Environment Targeting

All playbooks use `target_environment` for isolation:
```bash
ansible-playbook -i ansible/inventory/aws_ec2.yml ansible/playbooks/deploy-app.yml \
  --extra-vars "target_environment=env_dev docker_image=myapp:v1.0 app_port=5000 ..."
```

### Infrastructure Modifications

Edit Terraform files:
- `terraform/environments/dev.tfvars` - Environment-specific settings
- `terraform/main.tf` - Infrastructure definition
- `terraform/variables.tf` - Add new variables

## Project Structure

```
aws-deployment-devops-project/
├── terraform/
│   ├── main.tf                 # Infrastructure definition (VPC, ASG, ALB, RDS)
│   ├── variables.tf            # Variable declarations
│   ├── outputs.tf              # Output values (ALB DNS, ASG name, etc.)
│   └── environments/
│       ├── dev.tfvars          # Development configuration
│       └── prod.tfvars         # Production configuration
├── ansible/
│   ├── ansible.cfg             # Ansible configuration
│   ├── inventory/
│   │   ├── aws_ec2.yml         # Dynamic EC2 inventory (optimized)
│   │   └── hosts_generated.json # Generated inventory cache
│   └── playbooks/
│       ├── setup-environment.yml  # EC2 setup (Docker only, optimized)
│       ├── deploy-app.yml         # Standard deployment with rollback
│       ├── rollback-app.yml       # Manual rollback with backup discovery
│       └── rolling-deploy.yml     # Zero-downtime ASG rolling deployment
├── deploy.sh                   # Main deployment script
├── .deployment-history.json    # Automatic deployment history tracking
├── .env.example               # Environment variables template
├── .gitignore                 # Git ignore file
└── README.md                  # This documentation
```

## Cleanup

### Destroy Environment
```bash
# Destroy development environment
./deploy.sh dev destroy

# Destroy production environment (requires confirmation)
./deploy.sh prod destroy
```

### Remove SSH Keys
```bash
# Delete AWS key pairs
aws ec2 delete-key-pair --key-name myapp-dev-keypair
aws ec2 delete-key-pair --key-name myapp-prod-keypair

# Remove local key files
rm -f ~/.ssh/myapp-*-keypair.pem
```

---

**🎉 Your AWS DevOps pipeline is ready! Deploy with confidence.**