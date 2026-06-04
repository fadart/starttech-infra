output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.compute.alb_dns_name
}

output "frontend_bucket_name" {
  description = "S3 bucket name for frontend"
  value       = module.storage.frontend_bucket_name
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.storage.cloudfront_domain_name
}

output "elasticache_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = module.compute.elasticache_endpoint
}
