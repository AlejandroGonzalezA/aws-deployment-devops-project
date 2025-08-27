# Production Environment Configuration

# Project Settings
project_name = "flask-webapp"
environment  = "prod"

# Network Configuration
vpc_cidr                = "10.1.0.0/16"
public_subnet_cidr      = "10.1.1.0/24"
public_subnet_2_cidr    = "10.1.4.0/24"
private_subnet_1_cidr   = "10.1.2.0/24"
private_subnet_2_cidr   = "10.1.3.0/24"
allowed_ssh_cidr        = ["0.0.0.0/0"]  # IMPORTANT: Replace with your actual IP (e.g., "1.2.3.4/32") for security

# Infrastructure Configuration
ec2_instance_type    = "t3.small"
docker_image         = "alexg18/flask-app-devops-project_app:main"      # Your production Docker image
db_instance_class    = "db.t3.small"
db_allocated_storage = 50

# Auto Scaling Configuration
min_instances              = 2
max_instances              = 10
desired_instances          = 3
scale_up_cpu_threshold     = 65
scale_down_cpu_threshold   = 25

# Storage Configuration
root_volume_size = 50  # Larger disk space for production workloads

# Health Check Configuration - Stricter for production
health_check_grace_period        = 300   # 5 minutes grace period
health_check_timeout             = 10    # 10 seconds timeout
health_check_interval            = 30    # Check every 30 seconds
health_check_unhealthy_threshold = 2     # 2 failed checks before unhealthy
