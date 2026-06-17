# Autonomous Cloud Chaos & Disaster Recovery

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-2088FF?style=for-the-badge&logo=githubactions&logoColor=white)

An event-driven chaos-engineering and multi-region failover platform on AWS, defined entirely as infrastructure-as-code. It schedules and runs failure experiments with AWS Fault Injection Simulator, orchestrates automated recovery through Lambda and EventBridge, and shifts traffic between regions using Route 53 health-check failover routing — all deployed through a GitHub Actions pipeline.

**Personal project.** I built this to learn how resilience engineering and automated DR are wired together on AWS: chaos experiments, failover paths, and SLO measurement. It is deliberately designed to be **deployed, demonstrated, and torn down** — and engineered to be cheap enough that a full demo costs a few dollars, not a few thousand.

> 💡 **Design note — why not Route 53 Application Recovery Controller (ARC)?**
> ARC is AWS's premium failover control plane, and it's billed **~$2.50/hour per cluster regardless of whether a failover ever runs** — over $1,800/month if left standing. For a project whose entire point is to be spun up, demonstrated, and destroyed, that cost model is wrong. This build uses **standard Route 53 health-check failover routing** to achieve the same observable behavior — traffic moving from an unhealthy region to a healthy one — for roughly **$0.50 per health check per month**. ARC earns its price in regulated, high-stakes production environments that need a manual override control plane; matching the recovery mechanism to the actual blast radius and budget is itself part of the engineering.

---

## What it does

- **Injects controlled failure** — 8 FIS experiment templates covering CPU, memory, disk I/O, network latency, packet loss, network isolation, instance termination, and a combined multi-fault scenario.
- **Recovers automatically** — a Lambda + EventBridge orchestration layer reacts to CloudWatch alarms, flips Route 53 failover records to the healthy region, and invokes SSM automation, with a dead-letter queue catching failed invocations.
- **Measures resilience** — recovery-time tracking and SLO-compliance reporting against defined targets, surfaced on a CloudWatch dashboard.
- **Ships through CI/CD** — a multi-stage GitHub Actions pipeline validates, scans, plans, deploys, and verifies the infrastructure.

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
        ┌──────────┐   ┌────────────┐   ┌──────────────┐
        │  AWS FIS │   │ CloudWatch │   │  Route 53    │
        │ 8 templates  │ metrics/SNS│   │ health-check │
        │          │   │            │   │  failover    │
        └────┬─────┘   └────────────┘   └─────┬────────┘
             └────────────────┬───────────────┘
                              ▼
                ┌─────────────────────────────┐
                │  EC2 Chaos Targets (2 AZs)  │
                │  t3.micro · SSM-managed     │
                │  No NAT — VPC endpoints      │
                └─────────────────────────────┘
```

## Component matrix

| Layer | Service | Purpose |
|---|---|---|
| Orchestration | EventBridge | Event routing & scheduling |
| Automation | Lambda | Experiment execution & recovery |
| Fault injection | AWS FIS | Chaos experiment execution (8 templates) |
| Failover | Route 53 | Health-check failover routing |
| Monitoring | CloudWatch | Metrics, alarms, dashboard |
| Network/compute | VPC, EC2, IAM, VPC endpoints | Targets & isolation (no NAT) |
| IaC | Terraform | Infrastructure definition |
| CI/CD | GitHub Actions | Automated delivery |

## 🚀 Deploy

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
environment        = "demo"
project_name       = "chaos-dr"
rto_target_minutes = 2
secondary_region   = "us-west-2"
instance_type      = "t3.micro"
EOF

# 4. Deploy
terraform init -backend-config="bucket=terraform-state-chaos-dr-$(whoami)"
terraform plan -out=tfplan
terraform apply tfplan

# 5. Package & deploy the Lambda functions
cd ../.. && ./scripts/deploy-lambda-functions.sh
```

**Tear it down when you're done** — this is the intended operating model:

```bash
terraform destroy
```

## 🧪 Chaos experiments

Eight FIS experiment templates, triggered on a schedule or on demand:

| # | Experiment | Duration | Target | Validates |
|---|---|---|---|---|
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
```

## 🔄 CI/CD pipeline (GitHub Actions)

| Stage | Trigger | What it does |
|---|---|---|
| Validate | Every push | `terraform fmt -check`, `terraform validate` |
| Security | Every push | TFLint + Checkov, SARIF upload to GitHub Security |
| Plan | Pull requests | `terraform plan` + cost diff posted as a PR comment |
| Deploy | Merge to main | `terraform apply`, Lambda updates |
| Verify | Post-deploy | EC2 / FIS template / Lambda smoke checks |

Authentication uses **GitHub OIDC federation** — no long-lived AWS keys in the repo.

## 💰 Cost

This version is built to be cheap. The expensive enterprise control plane (ARC) is intentionally replaced with standard Route 53 failover routing, and NAT gateways are replaced with VPC endpoints.

| Component | Approx. cost | Notes |
|---|---|---|
| Route 53 health checks | ~$0.50 / check / month | Replaces the ~$1,800/mo ARC cluster |
| 2× t3.micro (chaos targets) | Free-tier eligible* | ~$17/mo on-demand after free tier |
| VPC interface endpoints | ~$7 each / month | Only while deployed; no NAT, no egress charges |
| FIS | Per action-minute | Cents per experiment run |
| Lambda · CloudWatch · SNS | Usage-based | A few dollars/month at demo volume |

\*First 12 months of an AWS account. A full deploy → demo → destroy cycle typically costs a **few dollars total**. Always verify current pricing on the AWS pricing pages; rates vary by region and change over time.

## 🎯 Design objectives

These are the targets the system is built to validate — **design goals, not measured production results.** Replace them with your own numbers once you've run the experiments end-to-end, and capture the dashboard as evidence.

| Objective | Target | How it's measured |
|---|---|---|
| Recovery time (RTO) | < 2 min | Orchestrator times termination → failover → health restore |
| Failover success | ≥ 99% | Tracked per experiment run via recovery monitor |
| Experiment coverage | 5+ types | 8 templates implemented |

## 🔐 Security

- Private subnets for Lambda and EC2 targets; security groups scoped to least privilege.
- No internet egress path — instances reach AWS services through VPC endpoints (`ssm`, `ssmmessages`, `ec2messages`, `monitoring`).
- IAM roles with minimal, service-scoped permissions; no static credentials (GitHub OIDC).
- S3 state and EBS volumes encrypted at rest.
- CloudTrail and VPC Flow Logs enabled for audit.
- TFLint + Checkov in CI, with SARIF results surfaced in GitHub Security.
- `main` protected by required status checks and review.

## 🧠 What this project demonstrates

- **Resilience engineering** — chaos experiment design, failure-mode coverage, and SLO/RTO definition.
- **Automated failover** — Route 53 health-check routing with an automated, Lambda-driven recovery path.
- **Event-driven automation** — EventBridge + Lambda orchestration with a DLQ and SSM automation hooks.
- **Infrastructure as code** — Terraform with remote state, locking, and CI-driven delivery.
- **Cost-aware architecture** — choosing the right recovery mechanism for the blast radius and budget, and knowing precisely when a premium control plane like ARC is and isn't worth its hourly bill.

## 🛣️ Roadmap

- Slack / PagerDuty alert integration
- Optional ARC module for users who need a true manual override control plane
- EKS and RDS failover chaos experiments

## 📁 Project structure

```
autonomous-cloud-chaos-dr/
├── .github/workflows/
├── terraform/chaos-dr/
│   ├── main.tf
│   ├── terraform.tfvars
│   └── outputs.tf
├── src/
│   ├── lambda-orchestrator.py
│   ├── lambda-alert-handler.py
│   └── requirements.txt
├── scripts/
├── docs/
├── README.md
├── LICENSE
└── .gitignore
```
