provider "aws" {
  region     = var.region
}

resource "aws_ecr_repository" "ecr_repository" {
  name = var.ecr_repository_name
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.ecs_cluster_name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "ecs_cluster_cp" {
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.provider_aws.name]
}

resource "aws_launch_configuration" "ecs_launch_config" {
  name_prefix                 = "ecs-launch-configuration"
  image_id                    = data.aws_ami.ecs_optimized.id
  instance_type               = var.instance_type
  security_groups             = [aws_security_group.ecs_security_group.id]
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance_profile.name
  associate_public_ip_address = true
  user_data                   = <<-EOF
                                #!/bin/bash
                                echo ECS_CLUSTER=${var.ecs_cluster_name} >> /etc/ecs/ecs.config
                                EOF
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                 = "ecs-autoscaling-group"
  launch_configuration = aws_launch_configuration.ecs_launch_config.id
  vpc_zone_identifier  = [var.subnets]
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.min_size
  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "provider_aws" {
  depends_on = [aws_ecs_cluster.ecs_cluster]
  name       = "provider_aws_ec2"
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
    managed_termination_protection = "DISABLED"
    managed_scaling {
      maximum_scaling_step_size = var.max_size
      minimum_scaling_step_size = var.min_size
      status                    = "ENABLED"
      target_capacity           = var.min_size
    }
  }
}

resource "aws_security_group" "ecs_security_group" {
  vpc_id      = var.vpc_id
  name        = "ecs-security-group"
  description = "ECS Security Group"
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ecs_execution_role" {
  name               = "ecs_execution_role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ecs_alb_creator_policy" {
  name        = "ecs-alb-creator-policy"
  description = "Policy to create ALBs"
  policy      = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action = [
          "ec2:Describe*",
          "ec2:CreateLoadBalancer",
          "ec2:CreateTargetGroup",
          "ec2:RegisterTargets",
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_alb_creator_attachment" {
  policy_arn = aws_iam_policy.ecs_alb_creator_policy.arn
  role       = aws_iam_role.ecs_execution_role.name
}

resource "aws_iam_policy" "ecs_task_policy" {
  name   = "ecs_task_policy"
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:GetLifecyclePolicy",
          "ecr:GetLifecyclePolicyPreview",
          "ecr:GetRepositoryPolicy",
          "ecr:ListTagsForResource",
          "ecs:CreateCluster",
          "ecs:DeregisterContainerInstance",
          "ecs:DiscoverPollEndpoint",
          "ecs:Poll",
          "ecs:RegisterContainerInstance",
          "ecs:StartTelemetrySession",
          "ecs:Submit*",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "ecr:GetAuthorizationToken"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "ecs_execution_role_task_attachment" {
  name       = "ecs_execution_role_task_attachment"
  roles      = [aws_iam_role.ecs_execution_role.name]
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}

resource "aws_iam_policy_attachment" "ecs_instance_attachment" {
  name       = "ecs-instance-attachment"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  roles      = [aws_iam_role.ecs_execution_role.name]
}

resource "aws_iam_policy_attachment" "ecs_instance_attachment2" {
  name       = "ecs-instance-attachment2"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
  roles      = [aws_iam_role.ecs_execution_role.name]
}

resource "aws_iam_policy_attachment" "ecs_attachment" {
  name       = "ecs-attachment"
  roles      = [aws_iam_role.ecs_execution_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_policy_attachment" "ecs_execution_role_attachment" {
  name       = "ecs_execution_role_attachment"
  roles      = [aws_iam_role.ecs_execution_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "ecs_instance_policy" {
  name        = "ecs-instance-policy"
  description = "Policy for ECS Instance Role"
  policy      = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "ecs:*"
          ],
          "Resource" : "*"
        }
      ]
    })
}

resource "aws_iam_policy_attachment" "ecs_instance_police_attachment" {
  name       = "ecs-instance-attachment"
  policy_arn = aws_iam_policy.ecs_instance_policy.arn
  roles      = [aws_iam_role.ecs_execution_role.name]
}


resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-instance-profile"
  role = aws_iam_role.ecs_execution_role.name
}

