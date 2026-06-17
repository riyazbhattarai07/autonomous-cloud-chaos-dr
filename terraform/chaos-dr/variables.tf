variable "aws_region" {
  description = "Primary AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Logical secondary region label used for the failover demo."
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment tag (demo/dev/prod)."
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "chaos-dr"
}

variable "instance_type" {
  description = "EC2 instance type for chaos targets. t3.micro is free-tier eligible."
  type        = string
  default     = "t3.micro"
}

variable "target_count" {
  description = "Number of chaos target instances (spread across AZs)."
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "rto_target_minutes" {
  description = "Recovery Time Objective target, in minutes (used for alarms/reporting)."
  type        = number
  default     = 2
}

variable "domain_name" {
  description = "Hosted-zone domain for the Route 53 failover demo. Leave empty to skip Route 53 resources."
  type        = string
  default     = ""
}

variable "schedule_expression" {
  description = "EventBridge schedule for the weekly chaos run."
  type        = string
  default     = "cron(0 2 ? * SUN *)"
}

variable "health_check_path" {
  description = "HTTP path the target serves for health checks."
  type        = string
  default     = "/health"
}
