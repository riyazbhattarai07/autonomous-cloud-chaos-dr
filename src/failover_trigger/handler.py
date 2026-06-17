"""
Chaos-DR Failover Trigger
-------------------------
Invoked by EventBridge on a CloudWatch Alarm -> ALARM transition.

With Route 53 failover routing + health checks, traffic re-routes
automatically when the primary health check fails. This function:
  * records the time the failover decision was observed,
  * (optionally) forces failover by inverting the primary health check,
  * emits a RecoveryTimeSeconds metric to the ChaosDR namespace so the
    dashboard and RTO alarm have data to chart.

RecoveryTimeSeconds here is the time from alarm onset to this handler
acknowledging it. Replace with a true end-to-end measurement (alarm ->
secondary serving traffic) once you wire a synthetic check.
"""
import json
import os
import time
from datetime import datetime, timezone

import boto3

route53 = boto3.client("route53")
cloudwatch = boto3.client("cloudwatch")
sns = boto3.client("sns")

PRIMARY_HC = os.environ.get("PRIMARY_HEALTH_CHECK_ID", "")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
RTO_TARGET_MINUTES = float(os.environ.get("RTO_TARGET_MINUTES", "2"))
PROJECT = os.environ.get("PROJECT", "chaos-dr")


def _alarm_onset(detail):
    ts = detail.get("state", {}).get("timestamp")
    if ts:
        try:
            return datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except ValueError:
            pass
    return datetime.now(timezone.utc)


def lambda_handler(event, context):
    detail = (event or {}).get("detail", {})
    onset = _alarm_onset(detail)
    now = datetime.now(timezone.utc)
    recovery_seconds = max(0.0, (now - onset).total_seconds())

    result = {
        "project": PROJECT,
        "alarm": detail.get("alarmName", "unknown"),
        "recovery_seconds": round(recovery_seconds, 1),
        "rto_target_seconds": RTO_TARGET_MINUTES * 60,
        "within_rto": recovery_seconds <= RTO_TARGET_MINUTES * 60,
        "forced_failover": False,
    }

    # Emit the recovery-time metric for the dashboard + RTO alarm.
    cloudwatch.put_metric_data(
        Namespace="ChaosDR",
        MetricData=[{
            "MetricName": "RecoveryTimeSeconds",
            "Value": recovery_seconds,
            "Unit": "Seconds",
            "Timestamp": now,
        }],
    )

    # Optional explicit failover: invert the primary health check so Route 53
    # routes to SECONDARY immediately rather than waiting on natural health.
    if PRIMARY_HC:
        try:
            route53.update_health_check(HealthCheckId=PRIMARY_HC, Inverted=True)
            result["forced_failover"] = True
            # Brief settle so the change is observable in a demo.
            time.sleep(2)
        except Exception as exc:  # noqa: BLE001 - report, don't crash the handler
            result["failover_error"] = str(exc)

    print(json.dumps(result))

    if SNS_TOPIC_ARN:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[{PROJECT}] failover handled ({result['recovery_seconds']}s)"[:100],
            Message=json.dumps(result, indent=2),
        )
    return {"statusCode": 200, **result}
