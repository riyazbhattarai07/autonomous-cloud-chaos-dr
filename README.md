# 🔥 Autonomous Cloud Chaos & Disaster Recovery System
 
[![Terraform](https://img.shields.io/badge/Terraform-1.5+-623CE4?style=flat-square&logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-FIS%20%7C%20Route53%20ARC-FF9900?style=flat-square&logo=amazon-aws)](https://aws.amazon.com/)
[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088F0?style=flat-square&logo=github-actions)](https://github.com/features/actions)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
 
An event-driven chaos engineering and multi-region disaster-recovery platform on AWS, defined entirely as infrastructure-as-code. It schedules and runs failure experiments with AWS Fault Injection Simulator, orchestrates automated recovery through Lambda and EventBridge, and coordinates cross-region failover via Route 53 Application Recovery Controller — with the whole stack deployed through a GitHub Actions pipeline.
 
> **Personal project.** I built this to explore how resilience engineering and automated DR are wired together on AWS — chaos experiments, failover control planes, and SLO measurement. It's designed to be deployed, demonstrated, and torn down (see the [cost note](#-cost) — this stack is not cheap to leave running).
 
---
 
## What it does
 
- **Injects controlled failure** — 8 FIS experiment templates covering CPU, memory, disk I/O, network latency, packet loss, network isolation, instance termination, and a combined multi-fault scenario.
- **Recovers automatically** — a Lambda + EventBridge orchestration layer reacts to CloudWatch alarms, triggers Route 53 ARC routing-control failover, and invokes SSM automation, with a dead-letter queue catching failed invocations.
- **Measures resilience** — recovery-time tracking and daily SLO compliance reporting against defined targets, surfaced on a CloudWatch dashboard.
- **Ships through CI/CD** — a multi-stage GitHub Actions pipeline validates, scans, plans, deploys, and verifies the infrastructure.
---
 
## 📊 Architecture
 
```
        ┌─────────────┐                    ┌──────────────┐
        │ Schedule    │                    │  CloudWatch  │
        │ (Sun 02:00) │                    │   Alarms     │
        └──────┬──────┘                    └──────┬───────┘
               └──────────────┬───────────────────┘
                              ▼
                     ┌──────────────────┐
                     │   EventBridge    │
                     │  (Event Router)  │
                     └────────┬─────────┘
              ┌───────────────┼────────────────┐
              ▼               ▼                ▼
        ┌──────────┐    ┌──────────┐    ┌────────────┐
        │Orchestr- │    │  Alert   │    │  Failover  │
        │ ator λ   │    │ Handler λ│    │ Trigger λ  │
        └────┬─────┘    └────┬─────┘    └─────┬──────┘
             ▼               ▼                ▼
        ┌──────────┐   ┌────────────┐   ┌────────────┐
        │  AWS FIS │   │ CloudWatch │   │ Route 53   │
        │ 8 templates  │ metrics/SNS│   │    ARC     │
        └────┬─────┘   └────────────┘   └─────┬──────┘
             └────────────────┬───────────────┘
                              ▼
                ┌─────────────────────────────┐
                │  EC2 Chaos Targets (3 AZs)  │
                │  Multi-AZ · SSM-managed     │
                │  CloudWatch agent metrics   │
                └─────────────────────────────┘
```
 
### Component matrix
 
| Layer | Service | Purpose | Scale |
|-------|---------|---------|-------|
| Orchestration | EventBridge | Event routing & scheduling | 6 rules |
| Automation | Lambda | Experiment execution & recovery | 5 functions |
| Fault injection | AWS FIS | Chaos experiment execution | 8 templates |
| Failover | Route 53 ARC | Multi-region routing control | 3 regions |
| Monitoring | CloudWatch | Metrics, alarms, dashboard | 30+ alarms |
| Network/compute | VPC, EC2, IAM | Targets & isolation | 3 instances, 3 AZs |
| IaC | Terraform | Infrastructure definition | ~760 lines |
| CI/CD | GitHub Actions | Automated delivery | 5 workflows |
 
---
 
## 🚀 Deploy
 
> ⚠️ Read the [cost note](#-cost) first. The Route 53 ARC cluster bills by the hour whether or not a failover ever runs.
 
**Prerequisites:** Terraform ≥ 1.5, AWS CLI ≥ 2.0, configured AWS credentials.
 
```bash
# 1. Clone
git clone https://github.com/riyazbhattarai07/autonomous-cloud-chaos-dr.git
cd autonomous-cloud-chaos-dr
 
# 2. Create the Terraform backend (S3 state + DynamoDB lock)
aws s3api create-bucket \
  --bucket terraform-state-chaos-dr-$(whoami) --region us-east-1
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
 
# 3. Configure
cd terraform/chaos-dr
cat > terraform.tfvars << 'EOF'
aws_region         = "us-east-1"
environment        = "prod"
project_name       = "chaos-dr"
rto_target_minutes = 2
secondary_regions  = ["us-west-2", "eu-west-1"]
EOF
 
# 4. Deploy
terraform init -backend-config="bucket=terraform-state-chaos-dr-$(whoami)"
terraform plan -out=tfplan
terraform apply tfplan
 
# 5. Package & deploy the Lambda functions
cd ../.. && ./scripts/deploy-lambda-functions.sh
```
 
**Tear it down when you're done** — this is the single most important operational step for this project:
 
```bash
terraform destroy
```
 
### Verify
 
```bash
terraform output dashboard_url
 
aws lambda invoke \
  --function-name chaos-dr-orchestrator \
  --payload '{"action":"list_templates"}' response.json
 
aws ec2 describe-instances \
  --filters "Name=tag:ChaosTarget,Values=true" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]'
```
 
---
 
## 🧪 Chaos experiments
 
Eight FIS experiment templates, triggered on a schedule or on demand:
 
| # | Experiment | Duration | Target | Validates |
|---|-----------|----------|--------|-----------|
| 1 | CPU stress | 5 min | 2 instances | Compute saturation |
| 2 | Network latency | 10 min | All | Degraded connectivity |
| 3 | Memory stress | 5 min | 2 instances | OOM behavior |
| 4 | Instance termination | 2 min | 1 instance | Failover path |
| 5 | Packet loss | 10 min | All | Lossy networks |
| 6 | Disk I/O stress | 5 min | 2 instances | Storage bottlenecks |
| 7 | Network isolation | 5 min | 1 instance | Partition tolerance |
| 8 | Combined chaos | 10 min | All | Multi-fault scenarios |
 
```bash
# Run one experiment
aws lambda invoke \
  --function-name chaos-dr-orchestrator \
  --payload '{"action":"run_experiment","experiment_type":"cpu-stress"}' \
  response.json
 
# Follow it
aws logs tail /aws/fis/chaos-dr-experiments --follow
aws fis describe-experiments --query 'experiments[0]'
```
 
---
 
## 🔄 CI/CD pipeline (GitHub Actions)
 
| Stage | Trigger | What it does |
|-------|---------|--------------|
| **Validate** | Every push | `terraform fmt -check`, `terraform validate` |
| **Security** | Every push | TFLint + Checkov, SARIF upload to GitHub Security |
| **Plan** | Pull requests | `terraform plan` + cost diff posted as a PR comment |
| **Deploy** | Merge to `main` | `terraform apply`, Lambda updates |
| **Verify** | Post-deploy | EC2 / FIS template / Lambda smoke checks |
 
Authentication uses GitHub OIDC federation — no long-lived AWS keys in the repo.
 
---
 
## 💰 Cost
 
**This stack is expensive to leave running, and the reason is Route 53 ARC.** An ARC cluster is billed per hour regardless of whether a failover ever happens:
 
| Component | Rate | If left running 24/7 |
|-----------|------|----------------------|
| **Route 53 ARC cluster** | **~$2.50 / hour** | **~$1,825 / month** |
| ARC readiness checks | ~$0.045 / hour each | ~$33–100 / month |
| 3× NAT Gateway | ~$0.045 / hour each | ~$96 / month + data |
| 3× t3.medium (on-demand) | ~$0.0416 / hour each | ~$90 / month |
| FIS | per action-minute | small, usage-driven |
| Lambda · CloudWatch · SNS | usage-based | ~$20–50 / month |
| **Total if left on** | | **well over $2,000 / month** |
 
The practical operating model is **deploy → demo → `terraform destroy`**. A two-hour demonstration of the ARC cluster, instances, and NAT gateways costs only a few dollars; the bill only becomes a problem if the cluster is left standing. That trade-off — extreme-reliability tooling that's costed by the hour — is itself one of the design lessons of the project.
 
> Always verify current pricing on the [AWS pricing pages](https://aws.amazon.com/application-recovery-controller/pricing/); rates vary by region and change over time.
 
---
 
## 🎯 Design objectives
 
These are the targets the system is built to validate. They are **design goals, not measured production results** — replace them with your own numbers once you've run the experiments end-to-end, and capture the dashboard as evidence.
 
| Objective | Target | How it's measured |
|-----------|--------|-------------------|
| Recovery time (RTO) | < 2 min | Orchestrator times termination → ARC failover → health restore |
| Failover success | ≥ 99% | Tracked per experiment run via recovery monitor |
| Application availability | ≥ 99.9% | Synthetic health checks across regions |
| Experiment coverage | 5+ types | 8 templates implemented |
 
---
 
## 🔐 Security
 
- Private subnets for Lambda and EC2 targets; security groups scoped to least privilege.
- IAM roles with minimal, service-scoped permissions; no static credentials (GitHub OIDC).
- S3 state and EBS volumes encrypted at rest (AES-256).
- CloudTrail and VPC Flow Logs enabled for audit.
- TFLint + Checkov in CI, with SARIF results surfaced in GitHub Security.
- `main` protected by required status checks and review.
---
 
## 📁 Project structure
 
```
autonomous-cloud-chaos-dr/
├── .github/workflows/
│   ├── terraform-validate.yml
│   ├── terraform-plan.yml
│   ├── terraform-deploy.yml
│   └── lambda-deploy.yml
├── terraform/chaos-dr/
│   ├── main.tf                 # ~760 lines, all infrastructure
│   ├── terraform.tfvars
│   └── outputs.tf
├── src/
│   ├── lambda-orchestrator.py
│   ├── lambda-alert-handler.py
│   └── requirements.txt
├── scripts/
│   ├── deploy-lambda-functions.sh
│   ├── test-infrastructure.sh
│   └── cost-estimate.sh
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEPLOYMENT.md
│   ├── TROUBLESHOOTING.md
│   └── COST.md
├── tests/{unit,integration,performance}/
├── README.md
├── LICENSE
└── .gitignore
```
 
---
 
## 🛣️ Roadmap
 
- Slack / PagerDuty alert integration
- QuickSight analytics on experiment history
- EKS (Kubernetes) and RDS failover chaos experiments
- Multi-account support
---
 
## 🧠 What this project demonstrates
 
- **Resilience engineering** — chaos experiment design, failure-mode coverage, and SLO/RTO definition.
- **Multi-region DR** — Route 53 ARC routing controls, readiness checks, and an automated failover path.
- **Event-driven automation** — EventBridge + Lambda orchestration with a DLQ and SSM automation hooks.
- **Infrastructure as code** — Terraform with remote state, locking, and CI-driven delivery.
- **Cost-aware architecture** — understanding why a high-reliability control plane is billed by the hour and designing the operating model around it.
---
 
## 📄 License
 
MIT — see [LICENSE](LICENSE).
 
---
 
## 📞 Contact
 
**Riyaz Bhattarai (Arthur)** — Calgary, AB · open to relocation within Canada
 
[![Email](https://img.shields.io/badge/Email-EA4335?style=for-the-badge&logo=gmail&logoColor=white)](mailto:riyabhattarai07@gmail.com)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/riyaz-bhattarai-836ab6323/)
[![Portfolio](https://img.shields.io/badge/Portfolio-000000?style=for-the-badge&logo=vercel&logoColor=white)](https://portfolio-ajpn.vercel.app/)
[![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/riyazbhattarai07)
