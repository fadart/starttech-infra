# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/${var.project_name}/${var.environment}/backend"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-backend-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/${var.project_name}/${var.environment}/frontend"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-frontend-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/${var.project_name}/${var.environment}/application"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-application-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU Utilization"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount"]
          ]
        }
      }
    ]
  })
}
