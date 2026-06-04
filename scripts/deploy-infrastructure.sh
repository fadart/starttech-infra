#!/bin/bash
set -e

echo "==> Initialising Terraform..."
cd terraform
terraform init

echo "==> Validating Terraform configuration..."
terraform validate

echo "==> Planning infrastructure changes..."
terraform plan -out=tfplan

echo "==> Applying infrastructure changes..."
terraform apply tfplan

echo "==> Infrastructure deployment complete."
terraform output
