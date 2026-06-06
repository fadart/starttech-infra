# IAM role for EC2 instances
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-ec2-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM policy for CloudWatch and ECR access
resource "aws_iam_role_policy" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/${var.project_name}/${var.environment}/*"
      }
    ]
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ALB target group
resource "aws_lb_target_group" "backend" {
  name     = "${var.project_name}-${var.environment}-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ALB listener - HTTP
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# ALB listener - HTTPS (only created when certificate_arn is provided)
resource "aws_lb_listener" "https" {
  count             = var.certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# Launch template
resource "aws_launch_template" "backend" {
  name_prefix   = "${var.project_name}-${var.environment}-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.backend_security_group_id]
  }

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -e

    # Install dependencies
    yum update -y
    yum install -y amazon-cloudwatch-agent docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user

    # Fetch instance metadata
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

    # Start CloudWatch agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s \
      -c ssm:/${var.project_name}/${var.environment}/cloudwatch-config

    # Authenticate to ECR and pull latest backend image
    aws ecr get-login-password --region $REGION | \
      docker login --username AWS --password-stdin $ECR_REGISTRY

    docker pull $ECR_REGISTRY/starttech-backend:latest

    # Fetch secrets from SSM Parameter Store
    MONGO_URI=$(aws ssm get-parameter \
      --name "/${var.project_name}/${var.environment}/mongo-uri" \
      --with-decryption --query Parameter.Value --output text --region $REGION)

    JWT_SECRET=$(aws ssm get-parameter \
      --name "/${var.project_name}/${var.environment}/jwt-secret" \
      --with-decryption --query Parameter.Value --output text --region $REGION)

    # Run backend container with CloudWatch log driver
    docker run -d \
      --name backend \
      --restart always \
      -p 8080:8080 \
      --log-driver awslogs \
      --log-opt awslogs-region=$REGION \
      --log-opt awslogs-group=/${var.project_name}/${var.environment}/backend \
      --log-opt awslogs-stream=$INSTANCE_ID \
      -e PORT=8080 \
      -e MONGO_URI="$MONGO_URI" \
      -e DB_NAME=much_todo_db \
      -e JWT_SECRET_KEY="$JWT_SECRET" \
      -e JWT_EXPIRATION_HOURS=72 \
      -e ENABLE_CACHE=true \
      -e REDIS_ADDR="${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379" \
      -e ALLOWED_ORIGINS="$(aws ssm get-parameter --name '/${var.project_name}/${var.environment}/allowed-origins' --query Parameter.Value --output text --region $REGION 2>/dev/null || echo '*')" \
      -e COOKIE_DOMAINS="da2hzzlrvudt6.cloudfront.net" \
      -e SECURE_COOKIE=false \
      -e LOG_LEVEL=INFO \
      -e LOG_FORMAT=json \
      $ECR_REGISTRY/starttech-backend:latest
  USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-${var.environment}-backend"
      Environment = var.environment
      Project     = var.project_name
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "backend" {
  name                      = "${var.project_name}-${var.environment}-asg"
  desired_capacity          = 2
  min_size                  = 1
  max_size                  = 4
  target_group_arns         = [aws_lb_target_group.backend.arn]
  vpc_zone_identifier       = var.private_subnet_ids
  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-backend"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project_name}-${var.environment}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.backend.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.project_name}-${var.environment}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.backend.name
}

# CloudWatch alarms to trigger scaling policies
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale up when CPU exceeds 70%"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.backend.name
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-cpu-high"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale down when CPU drops below 30%"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.backend.name
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-cpu-low"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ElastiCache subnet group
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-${var.environment}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ElastiCache Redis cluster
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-${var.environment}-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [var.redis_security_group_id]

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis"
    Environment = var.environment
    Project     = var.project_name
  }
}
