# Deployment

## Prerequisites
- Terraform >= 1.5, AWS CLI >= 2.0, configured credentials
- An S3 bucket + DynamoDB lock table for remote state

## Steps

```bash
# 1. Backend
aws s3api create-bucket --bucket terraform-state-chaos-dr-$(whoami) --region us-east-1
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# 2. Configure
cd terraform/chaos-dr
cp terraform.tfvars.example terraform.tfvars # edit as needed

# 3. Deploy
terraform init -backend-config="bucket=terraform-state-chaos-dr-$(whoami)"
terraform plan -out=tfplan
terraform apply tfplan

# 4. (Re)deploy Lambda code
cd ../.. && ./scripts/deploy-lambda-functions.sh

# 5. Verify
./scripts/test-infrastructure.sh
```

## Run a chaos experiment
```bash
./scripts/run-experiment.sh cpu-stress
aws logs tail /aws/fis/chaos-dr-experiments --follow
```

## Tear down (do this after every demo)
```bash
cd terraform/chaos-dr && terraform destroy
```

## CI/CD secrets
The GitHub Actions workflows expect repo secrets:
- `AWS_PLAN_ROLE_ARN`, `AWS_DEPLOY_ROLE_ARN` — IAM roles trusted for GitHub OIDC
- `TF_STATE_BUCKET` — the remote-state bucket name
