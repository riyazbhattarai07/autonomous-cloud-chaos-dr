"""
Chaos-DR Alert Handler
----------------------
Invoked by EventBridge on CloudWatch Alarm state changes (state -> ALARM).
Normalises the alarm payload and fans it out to SNS for human notification.
"""
import json
import os
import boto3

sns = boto3.client("sns")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
PROJECT = os.environ.get("PROJECT", "chaos-dr")


def lambda_handler(event, context):
    detail = (event or {}).get("detail", {})
    alarm = detail.get("alarmName", "unknown-alarm")
    state = detail.get("state", {}).get("value", "UNKNOWN")
    reason = detail.get("state", {}).get("reason", "")

    summary = {
        "project": PROJECT,
        "alarm": alarm,
        "state": state,
        "reason": reason,
    }
    print(json.dumps(summary))

    if SNS_TOPIC_ARN and state == "ALARM":
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[{PROJECT}] ALARM: {alarm}"[:100],
            Message=json.dumps(summary, indent=2),
        )
    return {"statusCode": 200, **summary}
