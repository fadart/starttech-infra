# StartTech Infrastructure

AWS infrastructure for the StartTech full-stack application, managed entirely with Terraform and deployed via a GitHub Actions CI/CD pipeline.

## Architecture

```
                        ┌─────────────────────────────────────┐
                        │            us-east-1                │
                        │                                     │
         Users ───────► │  CloudFront (da2hzzlrvudt6)        │
                        │     │              │                │
                        │     │ /auth/*      │ default        │
                        │     │ /tasks/*     │                │
                        │     │ /users/*     │                │
                        │     │ /health*     │                │
                        │     ▼              ▼                │
                        │   ALB           S3 Bucket           │
                        │     │         (frontend)            │
                        │     ▼                               │
                        │  ┌──────────────────────┐          │
                        │  │  VPC (10.0.0.0/16)   │          │
                        │  │                      │          │
                        │  │  Public Subnets       │          │
                        │  │  10.0.1.0/24 (us-east-1a)      │
                        │  │  10.0.2.0/24 (us-east-1b)      │
                        │  │        │             │          │
                        │  │     NAT GW        NAT GW        │
                        │  │        │             │          │
                        │  │  Private Subnets      │          │
                        │  │  10.0.3.0/24 (us-east-1a)      │
                        │  │  10.0.4.0/24 (us-east-1b)      │
                        │  │        │                        │
                        │  │   ASG (EC2 t3.micro)            │
                        │  │   Docker: starttech-backend     │
                        │  │        │                        │
                        │  │   ElastiCache Redis             │
                        │  └──────────────────────┘          │
                        │                                     │
                        │  CloudWatch Logs + Dashboard        │
                        └─────────────────────────────────────┘
```

## Repository Structure

```
starttech-infra/
├── .github/
│   └── workflows/
│       └── infrastructure-deploy.yml  # CI/CD pipeline
├── terraform/
│   ├── main.tf                        # Root module, wires all modules together
│   ├── variables.tf                   # Input variables
│   ├── outputs.tf                     # Infrastructure outputs
│   ├── terraform.tfvars.example       # Example variable values
│   └── modules/
│       ├── networking/                # VPC, subnets, NAT, security groups
│       ├── compute/                   # ALB, ASG, EC2, ElastiCache Redis
│       ├── storage/                   # S3, CloudFront
│       └── monitoring/               # CloudWatch logs, dashboard, alarms
├── monitoring/
│   ├── cloudwatch-dashboard.json      # Dashboard widget reference
│   ├── alarm-definitions.json         # Alarm definitions reference
│   └── log-insights-queries.txt       # Useful CloudWatch Logs Insights queries
├── scripts/
│   └── deploy-infrastructure.sh       # Manual deployment script
└── ARCHITECTURE.md
```

## Terraform Modules

### Networking (`modules/networking`)
- VPC with DNS support enabled
- 2 public subnets and 2 private subnets across `us-east-1a` and `us-east-1b`
- Internet Gateway for public subnets
- NAT Gateways (one per AZ) for private subnet outbound traffic
- Security groups for ALB (ports 80/443), EC2 backend (port 8080), and Redis (port 6379)

### Compute (`modules/compute`)
- **ALB** — Internet-facing Application Load Balancer with HTTP listener on port 80; optional HTTPS listener when `certificate_arn` is provided
- **Target Group** — forwards to EC2 on port 8080 with `/health` health check
- **Launch Template** — Amazon Linux 2, installs Docker and CloudWatch agent, pulls backend image from ECR, starts container with secrets from SSM Parameter Store
- **Auto Scaling Group** — min 1, desired 2, max 4 instances; ELB health checks
- **Scaling Policies** — scale up at 70% CPU, scale down at 30% CPU (triggered by CloudWatch alarms)
- **ElastiCache Redis** — `cache.t3.micro`, Redis 7, single node
- **IAM Role** — least-privilege access to CloudWatch Logs, ECR, and SSM parameters scoped to `/${project_name}/${environment}/*`

### Storage (`modules/storage`)
- **S3 Bucket** — private bucket for frontend static files; public access fully blocked
- **CloudFront Distribution** — HTTPS-only, with two origins:
  - S3 origin (default) — serves frontend static files
  - ALB origin — serves API routes (`/auth/*`, `/tasks/*`, `/users/*`, `/health*`, `/swagger/*`) forwarded with cookies and auth headers; caching disabled
- **OAC** — CloudFront Origin Access Control for secure S3 access

### Monitoring (`modules/monitoring`)
- **CloudWatch Log Groups** — `/starttech/production/backend`, `/starttech/production/frontend`, `/starttech/production/application` (30-day retention)
- **SSM Parameter** — `/starttech/production/cloudwatch-config` stores the CloudWatch agent config for Docker log collection
- **CloudWatch Dashboard** — EC2 CPU, ALB request count, Redis connections, backend log stream
- **CloudWatch Alarms** — CPU high (>70%) triggers scale up; CPU low (<30%) triggers scale down

## CI/CD Pipeline

The infrastructure pipeline (`.github/workflows/infrastructure-deploy.yml`) runs on every push to `main` that changes files under `terraform/`.

```
Pull Request → Validate → Plan (shows diff)
Push to main → Validate → Apply (deploys changes)
```

| Job | Trigger | Steps |
|-----|---------|-------|
| Validate | PR + push | `terraform init` → `validate` → `fmt -check` |
| Plan | PR only | `terraform init` → `plan` |
| Apply | Push to main | `terraform init` → `apply -auto-approve` |

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS credentials for Terraform |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for Terraform |
| `EC2_KEY_NAME` | EC2 key pair name for SSH access |

## Prerequisites

- [Terraform](https://www.terraform.io/) >= 1.0
- AWS CLI configured with appropriate permissions
- S3 bucket `starttech-terraform-state-035` for remote state (already exists)
- EC2 key pair created in `us-east-1`

## Remote State

Terraform state is stored remotely in S3 with the following configuration:

```hcl
backend "s3" {
  bucket = "starttech-terraform-state-035"
  key    = "starttech/terraform.tfstate"
  region = "us-east-1"
}
```

**Never commit `.tfstate` files to git.** The `.gitignore` excludes all state files.

## Deploying

### Via CI/CD (recommended)
Push changes to `main` — the pipeline handles the rest.

### Manually

```bash
# Copy and fill in your variable values
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Run the deployment script
./scripts/deploy-infrastructure.sh
```

Or step by step:

```bash
cd terraform
terraform init
terraform plan -var="key_name=your-key-pair"
terraform apply -var="key_name=your-key-pair"
```

## SSM Parameters (must be created manually before first deploy)

The EC2 instances fetch these at startup to configure the backend container:

```bash
# MongoDB Atlas connection string
aws ssm put-parameter \
  --name "/starttech/production/mongo-uri" \
  --value "mongodb+srv://user:pass@cluster.mongodb.net/much_todo_db" \
  --type SecureString --region us-east-1

# JWT signing secret
aws ssm put-parameter \
  --name "/starttech/production/jwt-secret" \
  --value "your-long-random-secret" \
  --type SecureString --region us-east-1

# CORS allowed origins
aws ssm put-parameter \
  --name "/starttech/production/allowed-origins" \
  --value "https://da2hzzlrvudt6.cloudfront.net" \
  --type String --region us-east-1
```

## Terraform Outputs

After a successful apply:

| Output | Description |
|--------|-------------|
| `alb_dns_name` | ALB DNS name for backend API |
| `cloudfront_domain_name` | CloudFront URL for the frontend |
| `frontend_bucket_name` | S3 bucket name for frontend assets |
| `elasticache_endpoint` | Redis endpoint for the backend |
| `vpc_id` | VPC ID |

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `us-east-1` |
| `project_name` | Project name prefix | `starttech` |
| `environment` | Environment name | `production` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `availability_zones` | AZs to deploy into | `["us-east-1a", "us-east-1b"]` |
| `public_subnets` | Public subnet CIDRs | `["10.0.1.0/24", "10.0.2.0/24"]` |
| `private_subnets` | Private subnet CIDRs | `["10.0.3.0/24", "10.0.4.0/24"]` |
| `ami_id` | AMI ID for EC2 instances | `ami-0c02fb55956c7d316` |
| `instance_type` | EC2 instance type | `t3.micro` |
| `key_name` | EC2 key pair name | *(required)* |
| `certificate_arn` | ACM certificate ARN for HTTPS | `""` (HTTPS disabled) |

## Monitoring

### CloudWatch Log Groups
| Log Group | Purpose |
|-----------|---------|
| `/starttech/production/backend` | Backend container stdout/stderr via Docker awslogs driver |
| `/starttech/production/frontend` | Frontend access logs |
| `/starttech/production/application` | EC2 system logs |

### Useful Log Insights Queries

```
# Recent backend errors
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50

# Authentication failures
fields @timestamp, @message
| filter @message like /unauthorized/ or @message like /401/
| sort @timestamp desc
| limit 50

# Slow requests (over 1 second)
fields @timestamp, @message
| parse @message '"latency":*,' as latency
| filter latency > 1000
| sort latency desc
| limit 20
```

## Security

- EC2 instances run in **private subnets** with no public IP
- All secrets stored in **SSM Parameter Store** (SecureString), never in code
- IAM role uses **least-privilege** — SSM access scoped to project path only
- S3 bucket has **all public access blocked**; served exclusively via CloudFront OAC
- No `.tfstate` or `.tfvars` files committed to git
