# StartTech Infrastructure

Terraform infrastructure for the StartTech application, managed with GitHub Actions CI/CD pipeline.

## Architecture overview

- **Networking**: VPC, public and private subnets across 2 availability zones, internet gateway, NAT gateways, route tables, security groups
- **Compute**: Auto Scaling Group, Application Load Balancer, EC2 launch template, ElastiCache Redis
- **Storage**: S3 bucket for frontend static hosting, CloudFront CDN distribution
- **Monitoring**: CloudWatch log groups, alarms, and dashboard

## Repository structure
