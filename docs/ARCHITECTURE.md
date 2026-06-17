# Architecture

## Flow

1. **EventBridge** triggers experiments — on a weekly schedule, or on demand via
   the orchestrator Lambda.
2. **Orchestrator Lambda** calls `fis:StartExperiment` for the requested
   experiment type using the template IDs passed in as an environment variable.
3. **AWS FIS** runs the fault. SSM-based faults (CPU/memory/disk/latency/packet
   loss/isolation) use AWS-managed `AWSFIS-Run-*` documents; instance
   termination uses the native EC2 action.
4. **CloudWatch alarms** watch EC2 status checks and a custom
   `ChaosDR/RecoveryTimeSeconds` metric.
5. On an alarm → `ALARM` transition, **EventBridge** fans out to two Lambdas:
   - **alert-handler** → publishes a normalised alert to SNS.
   - **failover-trigger** → records recovery time, optionally inverts the
     primary Route 53 health check to force failover, and emits the recovery
     metric.
6. **Route 53** failover routing (PRIMARY/SECONDARY records + health checks)
   shifts traffic to the healthy target automatically.
7. Failed async Lambda invocations land in the **SQS dead-letter queue**.

## Why Route 53 failover instead of ARC

Route 53 Application Recovery Controller is billed ~$2.50/hour per cluster
whether or not a failover ever runs. For a deploy → demo → destroy project,
standard health-check failover routing achieves the same observable behaviour
for roughly $0.50 per health check per month. ARC earns its cost in regulated,
high-stakes production environments needing a manual override control plane —
matching the mechanism to the blast radius and budget is part of the design.

## Network

Public subnets + Internet Gateway only — no NAT gateway. This keeps recurring
network cost at $0 while letting Route 53 public health checks reach the
targets and giving instances egress for SSM/FIS/CloudWatch. For a hardened
variant, move targets to private subnets and add VPC interface endpoints
(`ssm`, `ssmmessages`, `ec2messages`, `monitoring`) instead.
