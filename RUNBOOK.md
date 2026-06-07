# Runbook

This is a guide for operating and troubleshooting the StartTech infrastructure.

---

## Deploying infrastructure

The easiest way is to push a change to `terraform/**` on the `main` branch. The pipeline picks it up and runs apply automatically.

To deploy manually:
```bash
cd terraform
terraform init
terraform plan -var="key_name=starttech-key"
terraform apply -var="key_name=starttech-key"
```

To destroy all infrastructure:
```bash
cd terraform
terraform destroy -var="key_name=starttech-key"
```

---

## Testing and verification of infrastructure

### Verify infrastructure is running
```bash
terraform output
```

### Test backend health
```bash
curl https://<cloudfront-domain>/health
```
Expected response: `{"cache":"disabled","database":"ok"}`

### Test frontend
Open `https://<cloudfront-domain>` in a browser. You should see the MuchToDo login page.

### Verify EC2 instances are healthy
```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names starttech-production-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text) \
  --query 'TargetHealthDescriptions[*].{ID:Target.Id,Health:TargetHealth.State}' \
  --output table
```

### Verify CloudWatch logs are flowing
```bash
aws logs tail /starttech/production/backend --follow
```

### Verify ECR has latest image
```bash
aws ecr describe-images \
  --repository-name starttech-backend \
  --query 'imageDetails[*].{Tag:imageTags[0],Date:imagePushedAt}' \
  --output table
```

---

## Common issues and how to fix them

### Backend returns 502

This means the ALB is running but the EC2 instances are unhealthy — usually because the backend container failed to start.

First, check the logs:
```bash
aws logs tail /starttech/production/backend --follow
```

If the logs show errors about missing SSM parameters, make sure these exist in AWS:
```bash
aws ssm get-parameter --name "/starttech/production/mongo-uri" --region us-east-1
aws ssm get-parameter --name "/starttech/production/jwt-secret" --region us-east-1
aws ssm get-parameter --name "/starttech/production/allowed-origins" --region us-east-1
```

Once the parameters are in place, restart the instances:
```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name starttech-production-asg \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 120}'
```

### Frontend shows AccessDenied

Check if the files are in S3:
```bash
aws s3 ls s3://starttech-production-frontend
```

If the bucket is empty, re-run the frontend pipeline from GitHub Actions.

### Frontend is showing an old version

Invalidate the CloudFront cache:
```bash
aws cloudfront create-invalidation \
  --distribution-id <your-distribution-id> \
  --paths "/*"
```

### Terraform apply fails

Check your AWS credentials are working:
```bash
aws sts get-caller-identity
```

Check the state bucket exists:
```bash
aws s3 ls s3://starttech-terraform-state-035
```

Then run `terraform plan` locally to see which resource is failing.

### High CPU alert triggered

The ASG should automatically scale up. To check if it did:
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names starttech-production-asg \
  --query 'AutoScalingGroups[0].Instances[*].HealthStatus'
```

Check logs to understand why CPU spiked:
```bash
aws logs tail /starttech/production/backend --follow
```

### No logs appearing in CloudWatch

The CloudWatch agent config is stored in SSM. Check it exists:
```bash
aws ssm get-parameter --name "/starttech/production/cloudwatch-config" --region us-east-1
```

If it's missing, run `terraform apply` to recreate it, then do an instance refresh.

---

## Useful commands

View backend logs:
```bash
aws logs tail /starttech/production/backend --follow
```

View EC2 system logs:
```bash
aws logs tail /starttech/production/application --follow
```

Check how many instances are running:
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names starttech-production-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Running:Instances[*].HealthStatus}'
```

Force a new backend deployment:
```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name starttech-production-asg \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 120}'
```

Get all infrastructure URLs and endpoints:
```bash
cd terraform && terraform output
```
