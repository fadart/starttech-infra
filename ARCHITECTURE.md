# Architecture
This document describes the system architecture for the StartTech application, 
including infrastructure components, network topology, CI/CD pipeline flow and 
security design. All infrastructure is provisioned with Terraform and deployed 
on AWS.

## Architecture Diagram

```
                        ┌─────────────────────┐
         Users ───────► │     CloudFront       │
                        └──────────┬──────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
         API routes │                             │ Frontend routes
    (/auth, /tasks) │                             │ (everything else)
                    ▼                             ▼
           ┌─────────────┐               ┌─────────────┐
           │     ALB     │               │  S3 Bucket  │
           └──────┬──────┘               │  (React)    │
                  │                      └─────────────┘
     ┌────────────▼─────────────┐
     │     Auto Scaling Group   │
     │  ┌─────────┐ ┌─────────┐ │
     │  │EC2 (AZ1)│ │EC2 (AZ2)│ │
     │  │Go+Docker│ │Go+Docker│ │
     │  └────┬────┘ └────┬────┘ │
     └───────┼───────────┼──────┘
             │           │
     ┌───────▼───┐   ┌───▼────────────┐
     │ElastiCache│   │  MongoDB Atlas  │
     │  Redis    │   │  (Atlas Cloud)  │
     └───────────┘   └────────────────┘
```

## Terraform Breakdown

### Networking
- VPC: Across 2 availability zones`us-east-1a` and `us-east-1b` with public and private subnets
- Public subnets: host the ALB and NAT Gateways
- Private subnets: host EC2 instances and ElastiCache Redis
- Internet Gateway: gives public subnets internet access
- NAT Gateways: allow private instances to reach the internet (e.g. to pull Docker images from ECR)
- Security groups: ALB accepts public traffic, EC2 only accepts traffic from ALB, Redis only accepts traffic from EC2

### Compute
- ALB distributes traffic to EC2 instances, health checks on /health
- Auto Scaling Group runs 2 EC2 instances by default, scales between 1 and 4 based on CPU
- Each EC2 instance runs the backend as a Docker container, pulled from ECR on startup
- ElastiCache Redis handles caching and sessions

### Storage
- S3 bucket: stores compiled React frontend, fully private
- CloudFront: serves both frontend (from S3) and API (proxied to ALB) over HTTPS from a single domain
- Origin Access Control: ensures S3 is only accessible through CloudFront

### Monitoring
- CloudWatch log groups: Collect backend and application logs
- CloudWatch alarms: Trigger scale up above 70% CPU and scale down below 30% CPU
- CloudWatch dashboard: shows EC2 CPU, ALB request, Redis connections and live backend logs

### IAM
- EC2 instances have a least-privilege role scoped to CloudWatch Logs, ECR and SSM parameters

## CI/CD Pipeline Flow

### Infrastructure pipeline
Triggered on push to `main` when files under `terraform/` change.

```
Push to main
     │
     ▼
Validate job
  ├── terraform init
  ├── terraform validate
  └── terraform fmt -check
     │
     ▼
Apply job
  ├── terraform init
  └── terraform apply -auto-approve
```

On a pull request, only Validate and Plan run — no changes are applied.

### Frontend pipeline
Triggered on push to `feature/full-stack` when files under `much-to-do/Client/` change.

```
Install → Lint → Security audit → Build → Deploy to S3 → Invalidate CloudFront
```

### Backend pipeline
Triggered on push to `feature/full-stack` when files under `much-to-do/Server/` change.

```
Tests → staticcheck → govulncheck → Docker build → Trivy scan → Push to ECR → ASG instance refresh → Smoke test
```

## Security

- EC2 instances run in private subnets with no public IP — not directly accessible from the internet
- ALB is the only public entry point for backend traffic
- S3 bucket is fully private — CloudFront uses OAC to access it
- Redis is only accessible from the backend security group on port 6379
- Secrets (MongoDB URI, JWT key) are stored in SSM Parameter Store, never in code
- IAM roles follow least-privilege — EC2 can only access its own SSM parameters
- Terraform state is stored remotely in S3, never committed to git
