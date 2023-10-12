variable "region" {
  type    = string
  default = "us-east-1"
}
variable "vpc_id" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
  default = "ecs_cluster"
}

variable "instance_type" {
  type = string
  default = "t2.micro"
}

variable "ecr_repository_name" {
  type = string
  default = "frontend-service1"
}

variable "subnets" {
  type = any
}
variable "min_size" {
  default = 1
  type = number
}
variable "max_size" {
  default = 2
  type = number
}

data "aws_ami" "ecs_optimized" {
  most_recent = true
  filter {
    name   = "name"
    values = ["*amazon-ecs-optimized*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["amazon"]
}

