# ---------------------------------------------------------------------------
# CloudWatch: per-instance status alarms + a dashboard. Alarm state changes
# are routed by EventBridge (see orchestration.tf) to the failover + alert
# Lambdas.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "instance_health" {
  count               = var.target_count
  alarm_name          = "${local.name}-target-${count.index}-unhealthy"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Target ${count.index} failing EC2 status checks"
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = aws_instance.target[count.index].id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rto_breach" {
  alarm_name          = "${local.name}-rto-breach"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RecoveryTimeSeconds"
  namespace           = "ChaosDR"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.rto_target_minutes * 60
  alarm_description   = "Measured recovery time exceeded the RTO target"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title  = "Target CPU Utilization"
          region = var.aws_region
          metrics = [for i in range(var.target_count) :
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.target[i].id]
          ]
          view = "timeSeries", stat = "Average", period = 60
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title   = "Recovery Time (s) vs RTO target"
          region  = var.aws_region
          metrics = [["ChaosDR", "RecoveryTimeSeconds"]]
          view    = "timeSeries", stat = "Maximum", period = 300
          annotations = { horizontal = [{ label = "RTO target", value = var.rto_target_minutes * 60 }] }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title  = "Status Check Failures"
          region = var.aws_region
          metrics = [for i in range(var.target_count) :
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.target[i].id]
          ]
          view = "timeSeries", stat = "Maximum", period = 60
        }
      },
      {
        type = "log", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title  = "FIS experiment log"
          region = var.aws_region
          query  = "SOURCE '${local.fis_log_group}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          view   = "table"
        }
      }
    ]
  })
}
