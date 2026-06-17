#!/usr/bin/env bash
# Very rough monthly estimate IF the stack is left running 24/7.
# The intended operating model is deploy -> demo -> destroy, in which case
# real cost is a few dollars per demo.
cat << 'TXT'
Rough monthly estimate (us-east-1, on-demand, stack left running 24/7):

  2x t3.micro            ~$15/mo   (free-tier eligible first 12 months)
  Route 53 hosted zone    $0.50/mo
  2x health checks        ~$1/mo
  CloudWatch alarms/logs  ~$2-5/mo
  FIS                     usage-based, cents per run
  Lambda / SNS / SQS      effectively $0 at demo volume
  ----------------------------------------
  Total if left on        ~$20-25/mo

  Total for a 2-hour demo then destroy:   a few dollars.

NOTE: no NAT gateway and no Route 53 ARC cluster, by design.
Always confirm live pricing on the AWS pricing pages.
TXT
