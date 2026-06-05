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
          metrics = [
            ["AWS/EC2", "CPUUtilization"]
          ]
          period  = 300
          stat    = "Average"
          region  = "us-east-1"
          title   = "EC2 CPU Utilisation"
          view    = "timeSeries"
          stacked = false
          annotations = {
            alarms = []
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount"]
          ]
          period  = 300
          stat    = "Sum"
          region  = "us-east-1"
          title   = "ALB Request Count"
          view    = "timeSeries"
          stacked = false
          annotations = {
            alarms = []
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ElastiCache", "CurrConnections"]
          ]
          period  = 300
          stat    = "Average"
          region  = "us-east-1"
          title   = "Redis Connections"
          view    = "timeSeries"
          stacked = false
          annotations = {
            alarms = []
          }
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '/starttech/production/backend' | fields @timestamp, @message | sort @timestamp desc | limit 20"
          region = "us-east-1"
          title  = "Recent backend logs"
          view   = "table"
        }
      }
    ]
  })
}
