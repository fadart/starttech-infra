# Architecture documentation

## System overview

StartTech is a full-stack to-do application deployed on AWS with a complete CI/CD pipeline managed through GitHub Actions and infrastructure provisioned with Terraform.

## Architecture diagram
                      ┌─────────────────┐
                      │   CloudFront    │
                      │      CDN        │
                      └────────┬────────┘
                               │
                      ┌────────▼────────┐
                      │   S3 Bucket     │
                      │ (React Frontend)│
                      └─────────────────┘
Users ──────────────────► Application Load Balancer
│
┌──────────────▼──────────────┐
│      Auto Scaling Group      │
│  ┌──────────┐ ┌──────────┐  │
│  │ EC2 (AZ1)│ │ EC2 (AZ2)│  │
│  │ Golang   │ │ Golang   │  │
│  └────┬─────┘ └────┬─────┘  │
└───────┼────────────┼─────────┘
│            │
┌────────────▼────────────▼────────┐
│                                  │
┌──────────▼──────────┐         ┌─────────────▼──────┐
│   ElastiCache Redis │         │   MongoDB Atlas     │
│   (Caching/Sessions)│         │   (Data persistence)│
└─────────────────────┘         └────────────────────┘


## Components

### Networking
- **VPC**: Isolated network with CIDR `10.0.0.0/16`
- **Public subnets**: Host ALB and NAT gateways across 2 availability zones
- **Private subnets**: Host EC2 instances and ElastiCache across 2 availability zones
- **Internet Gateway**: Provides internet access to public subnets
- **NAT Gateways**: Allow private subnet instances to access the internet
- **Security groups**: Least-privilege rules for ALB, EC2, and Redis

### Compute
- **Auto Scaling Group**: Minimum 1, desired 2, maximum 4 EC2 instances
- **Launch template**: Amazon Linux 2 with Docker and CloudWatch agent
- **Application Load Balancer**: Distributes traffic across EC2 instances
- **Target group**: Health checks on `/health` endpoint port 8080
- **ElastiCache Redis**: Single node cache.t3.micro for caching and sessions

### Storage
- **S3 bucket**: Hosts compiled React static files
- **CloudFront**: CDN distribution with HTTPS redirect and SPA routing support
- **Origin Access Control**: Restricts S3 access to CloudFront only

### Monitoring
- **CloudWatch log groups**: Separate log groups for backend, frontend and application logs
- **CloudWatch alarms**: CPU high (>80%) and CPU low (<20%) for auto scaling
- **CloudWatch dashboard**: Centralised view of EC2 CPU, ALB requests, Redis connections and backend logs

### IAM
- **EC2 instance role**: Least-privilege access to CloudWatch, ECR and SSM
- **Instance profile**: Attached to all EC2 instances in the ASG

## CI/CD pipeline
Push to main (terraform/**)
│
▼
Validate job
├── terraform init
├── terraform validate
└── terraform fmt check
│
▼
Apply job (main branch only)
├── terraform init
└── terraform apply

## Security

- EC2 instances run in private subnets — not directly accessible from the internet
- ALB is the only public entry point for backend traffic
- S3 bucket is private — CloudFront uses OAC to access it
- Redis is only accessible from backend security group
- IAM roles follow least-privilege principle
- Secrets managed via GitHub Actions secrets
