# Troubleshooting

**FIS SSM actions fail immediately** — confirm the instance shows up in Fleet
Manager (SSM agent registered). The instance role needs
`AmazonSSMManagedInstanceCore`, and the instance needs egress (it has it via
the IGW in this design).

**Route 53 health check always unhealthy** — the health responder listens on
:80 and the security group allows :80 from `0.0.0.0/0`. Check the instance is
running the `health.service` unit (`systemctl status health`).

**`terraform destroy` leaves an instance** — FIS termination experiments delete
instances out from under Terraform state. Run `terraform apply` to reconcile,
or `terraform state rm` the stale instance, then destroy.

**Lambda invocation lands in the DLQ** — check the function's CloudWatch logs;
the message attributes on the SQS message include the error.
