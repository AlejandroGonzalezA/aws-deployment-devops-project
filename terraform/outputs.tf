# Infrastructure Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "public_subnet_2_id" {
  description = "ID of the second public subnet"
  value       = aws_subnet.public_2.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

# EC2 Auto Scaling Group Outputs
output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.arn
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.app.id
}

output "asg_capacity" {
  description = "Auto Scaling Group capacity settings"
  value = {
    min_size         = aws_autoscaling_group.app.min_size
    max_size         = aws_autoscaling_group.app.max_size
    desired_capacity = aws_autoscaling_group.app.desired_capacity
  }
}

# Database Outputs
output "rds_instance_id" {
  description = "ID of the RDS instance"
  value       = aws_db_instance.postgres.id
}

output "rds_endpoint" {
  description = "RDS instance endpoint (PRIVATE - only accessible from VPC)"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.postgres.port
}

output "rds_address" {
  description = "RDS instance address (without port)"
  value       = aws_db_instance.postgres.address
}

# Application Access
output "app_url" {
  description = "Public URL to access the application via Load Balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "docker_image" {
  description = "Docker image configured for this environment"
  value       = var.docker_image
}

# SSH Access
output "ssh_command" {
  description = "SSH commands to connect to ASG instances (use specific instance IPs)"
  value       = "Use 'aws ec2 describe-instances' to get instance IPs, then ssh -i ${var.key_pair_name}.pem ec2-user@INSTANCE-IP"
  sensitive   = true
}

# Security Information
output "ec2_security_group_id" {
  description = "ID of the EC2 security group"
  value       = aws_security_group.ec2.id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

# Load Balancer Information
output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.app.arn
}

output "target_group_health" {
  description = "Health check configuration"
  value = {
    path                = aws_lb_target_group.app.health_check[0].path
    healthy_threshold   = aws_lb_target_group.app.health_check[0].healthy_threshold
    unhealthy_threshold = aws_lb_target_group.app.health_check[0].unhealthy_threshold
    timeout             = aws_lb_target_group.app.health_check[0].timeout
    interval            = aws_lb_target_group.app.health_check[0].interval
  }
}

# Network Configuration Summary
output "network_summary" {
  description = "Summary of network configuration"
  value = {
    vpc_cidr         = aws_vpc.main.cidr_block
    public_subnet    = aws_subnet.public.cidr_block
    public_subnet_2  = aws_subnet.public_2.cidr_block
    private_subnet_1 = aws_subnet.private_1.cidr_block
    private_subnet_2 = aws_subnet.private_2.cidr_block
    availability_zones = [
      aws_subnet.public.availability_zone,
      aws_subnet.public_2.availability_zone,
      aws_subnet.private_1.availability_zone,
      aws_subnet.private_2.availability_zone
    ]
  }
}

# Database Connection Information (for application configuration)
output "database_connection_info" {
  description = "Database connection information for application configuration"
  value = {
    host     = aws_db_instance.postgres.endpoint
    port     = aws_db_instance.postgres.port
    database = aws_db_instance.postgres.db_name
    username = aws_db_instance.postgres.username
    # Password is intentionally omitted for security
  }
  sensitive = true
}

# Security Note
output "security_note" {
  description = "Important security information"
  value       = "🔒 RDS is deployed in PRIVATE subnets only - accessible only from EC2 instances within the VPC"
}

# Auto Scaling Configuration
output "scaling_policies" {
  description = "Auto Scaling policies and thresholds"
  value = {
    scale_up_policy_arn    = aws_autoscaling_policy.scale_up.arn
    scale_down_policy_arn  = aws_autoscaling_policy.scale_down.arn
    cpu_high_alarm_arn     = aws_cloudwatch_metric_alarm.cpu_high.arn
    cpu_low_alarm_arn      = aws_cloudwatch_metric_alarm.cpu_low.arn
    scale_up_threshold     = var.scale_up_cpu_threshold
    scale_down_threshold   = var.scale_down_cpu_threshold
  }
}

# CloudWatch Alarms
output "cloudwatch_alarms" {
  description = "CloudWatch alarm details"
  value = {
    cpu_high_alarm = aws_cloudwatch_metric_alarm.cpu_high.alarm_name
    cpu_low_alarm  = aws_cloudwatch_metric_alarm.cpu_low.alarm_name
  }
}
