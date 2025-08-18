# Development Environment Configuration

# Project Settings
project_name = "flask-webapp"
environment  = "dev"

# Network Configuration
vpc_cidr                = "10.0.0.0/16"
public_subnet_cidr      = "10.0.1.0/24"
public_subnet_2_cidr    = "10.0.4.0/24"
private_subnet_1_cidr   = "10.0.2.0/24"
private_subnet_2_cidr   = "10.0.3.0/24"
allowed_ssh_cidr        = ["0.0.0.0/0"]  # Restrict this to your IP for security

# Infrastructure Configuration
ec2_instance_type    = "t3.micro"
docker_image         = "alexg18/flask-app-devops-project_app:develop"
db_instance_class    = "db.t3.micro"
db_allocated_storage = 20

# Auto Scaling Configuration
min_instances              = 1
max_instances              = 4
desired_instances          = 2
scale_up_cpu_threshold     = 70
scale_down_cpu_threshold   = 30
