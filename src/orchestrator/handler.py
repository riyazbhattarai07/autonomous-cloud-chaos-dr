"""
Chaos-DR Orchestrator
---------------------
Entry point for running chaos experiments. Invoked by:
  * EventBridge schedule  -> {"action": "run_experiment", "experiment_type": "cpu-stress"}
  * manual `aws lambda invoke` for ad-hoc runs / listing templates

Actions:
  list_templates   -> return the configured experiment_type -> template_id map
  run_experiment   -> start the FIS experiment for the given experiment_type
"""
import json
import os
import boto3

fis = boto3.client("fis")
sns = boto3.client("sns")

TEMPLATES = json.loads(os.environ.get("EXPERIMENT_TEMPLATES", "{}"))
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
PROJECT = os.environ.get("PROJECT", "chaos-dr")


def _notify(subject, message):
    if SNS_TOPIC_ARN:
        sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)


def lambda_handler(event, context):
    action = (event or {}).get("action", "list_templates")
    print(json.dumps({"received_action": action, "event": event}))

    if action == "list_templates":
        return {"statusCode": 200, "templates": TEMPLATES}

    if action == "run_experiment":
        experiment_type = event.get("experiment_type")
        template_id = TEMPLATES.get(experiment_type)
        if not template_id:
            return {
                "statusCode": 400,
                "error": f"unknown experiment_type '{experiment_type}'",
                "available": list(TEMPLATES.keys()),
            }

        resp = fis.start_experiment(
            experimentTemplateId=template_id,
            tags={"Project": PROJECT, "TriggeredBy": "orchestrator"},
        )
        experiment_id = resp["experiment"]["id"]
        msg = f"Started FIS experiment '{experiment_type}' (id={experiment_id})"
        print(msg)
        _notify(f"[{PROJECT}] chaos experiment started", msg)
        return {"statusCode": 200, "experiment_id": experiment_id, "experiment_type": experiment_type}

    return {"statusCode": 400, "error": f"unknown action '{action}'"}
