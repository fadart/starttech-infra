# Runbook

## Deploying infrastructure

### Via pipeline
Push changes to `terraform/**` on the `main` branch. The pipeline will automatically validate and apply.

### Manually
```bash
cd terraform
terraform init
terraform plan -var="key_name=starttech-key"
terraform apply -var="key_name=starttech-key"
```

## Destroying infrastructure
```bash
cd terraform
terraform destroy -var="key_name=starttech-key"
```

## Checking infrastructure outputs
```bash
cd terraform
terraform output
```

## Troubleshooting

### Terraform apply fails
1. Check AWS credentials are valid
2. Check S3 state bucket exists: `aws s3 ls s3://starttech-terraform-state-035`
3. Run `terraform plan` locally to see what changed

### EC2 instances not healthy in ALB
1. Check security group allows port 8080 from ALB
2. SSH into instance via bastion and check app is running:
```bash
ssh -i ~/.ssh/starttech-key.pem ec2-user@<instance-ip>
docker ps
curl localhost:8080/health
```

### CloudFront not serving latest frontend
1. Check S3 sync completed successfully
2. Manually invalidate cache:
```bash
aws cloudfront create-invalidation \
  --distribution-id <distribution-id> \
  --paths "/*"
```

### Redis connection issues
1. Check ElastiCache cluster is available:
```bash
aws elasticache describe-cache-clusters \
  --cache-cluster-id starttech-production-redis
```
2. Check backend security group allows port 6379

### High CPU alarm triggered
1. Check ASG is scaling:
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names starttech-production-asg
```
2. Check CloudWatch logs for errors:
```bash
aws logs tail /starttech/production/backend --follow
```

## Useful commands

### Get ALB DNS name
```bash
terraform output alb_dns_name
```

### Get CloudFront domain
```bash
terraform output cloudfront_domain_name
```

### Get ElastiCache endpoint
```bash
terraform output elasticache_endpoint
```

### View backend logs
```bash
aws logs tail /starttech/production/backend --follow
```

### Force new deployment
```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name starttech-production-asg \
  --preferences '{"MinHealthyPercentage": 50}'
```
