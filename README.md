# StartTech Infrastructure

AWS infrastructure for the StartTech full-stack application, managed entirely with Terraform and deployed via a GitHub Actions CI/CD pipeline.

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full system architecture documentation.

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

## Terraform Breakdown
See [ARCHITECTURE.md](./ARCHITECTURE.md#terraform-breakdown) for the breakdown of Terraform Modules


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
| `AWS_ACCESS_KEY_ID` | AWS access key for Terraform |
| `AWS_SECRET_ACCESS_KEY` | AWS secret for Terraform |
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

## Security

- EC2 instances run in **private subnets** with no public IP - not directly accessible from the internet
- ALB is the only public entry point for backend traffic
- All secrets stored in **SSM Parameter Store**, never in code
- IAM role uses **least-privilege** — SSM access scoped to project path only
- S3 bucket has **all public access blocked**; served exclusively via CloudFront OAC
- No `.tfstate` or `.tfvars` files committed to git
