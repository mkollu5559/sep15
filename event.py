import boto3
import json
import os
import re
import traceback

s3 = boto3.client("s3")

TARGET_BUCKET = os.environ["BUCKET_NAME"]
CONFIG_BUCKET = os.environ["CONFIG_BUCKET"]
CONFIG_KEY = os.environ["CONFIG_KEY"]   # eventnotification/events.json

STATE_KEY = "eventnotification/state/latest_successful_version.json"
BACKUP_PREFIX = "eventnotification/backup/"
DEFAULT_EVENTS = ["s3:ObjectCreated:*"]


# --------------------------
# GET LATEST SUCCESSFUL VERSION
# --------------------------
def get_latest_successful_version():
    try:
        obj = s3.get_object(Bucket=CONFIG_BUCKET, Key=STATE_KEY)
        data = json.loads(obj["Body"].read().decode("utf-8"))
        return data.get("latest_version", 0)
    except:
        return 0


# --------------------------
# SET LATEST SUCCESSFUL VERSION
# --------------------------
def set_latest_successful_version(v):
    s3.put_object(
        Bucket=CONFIG_BUCKET,
        Key=STATE_KEY,
        Body=json.dumps({"latest_version": v}, indent=2)
    )


def lambda_handler(event, context):
    try:
        # --------------------------------------------------------
        # LOAD INPUT CONFIG (events.json)
        # --------------------------------------------------------
        cfg = s3.get_object(Bucket=CONFIG_BUCKET, Key=CONFIG_KEY)
        cfg_data = json.loads(cfg["Body"].read().decode("utf-8"))
        incoming = cfg_data["events_list"]

        # --------------------------------------------------------
        # LOAD CURRENT NOTIFICATIONS FROM TARGET BUCKET
        # --------------------------------------------------------
        curr = s3.get_bucket_notification_configuration(Bucket=TARGET_BUCKET)
        lambda_cfg = curr.get("LambdaFunctionConfigurations", [])

        # --------------------------------------------------------
        # DETERMINE BACKUP VERSION
        # --------------------------------------------------------
        current_version = get_latest_successful_version()
        next_version = current_version + 1
        backup_file = f"{BACKUP_PREFIX}event-v{next_version}.json"

        # --------------------------------------------------------
        # WRITE BACKUP FILE
        # --------------------------------------------------------
        s3.put_object(
            Bucket=CONFIG_BUCKET,
            Key=backup_file,
            Body=json.dumps(curr, indent=2)
        )

        # SAVE FOR ROLLBACK
        full_backup = json.loads(json.dumps(curr))

        success = []
        failed = []

        # --------------------------------------------------------
        # PROCESS EACH EVENT
        # --------------------------------------------------------
        for ev in incoming:
            action = ev.get("action", "add").lower()
            op_backup = json.loads(json.dumps(lambda_cfg))

            try:
                # suffix
                suffix_data = ev.get("suffix")
                suffix_rules = []
                if suffix_data:
                    if isinstance(suffix_data, str):
                        suffix_rules.append({"Name": "suffix", "Value": suffix_data})
                    else:
                        for s in suffix_data:
                            suffix_rules.append({"Name": "suffix", "Value": s})

                # filters
                filter_rules = [{"Name": "prefix", "Value": ev["prefix"]}]
                filter_rules.extend(suffix_rules)

                # ADD
                if action == "add":
                    lambda_cfg.append({
                        "Id": ev["id"],
                        "LambdaFunctionArn": ev["lambda_arn"],
                        "Events": ev.get("events", DEFAULT_EVENTS),
                        "Filter": {"Key": {"FilterRules": filter_rules}}
                    })

                # UPDATE
                elif action == "update":
                    lambda_cfg = [c for c in lambda_cfg if c["Id"] != ev["id"]]
                    lambda_cfg.append({
                        "Id": ev["id"],
                        "LambdaFunctionArn": ev["lambda_arn"],
                        "Events": ev.get("events", DEFAULT_EVENTS),
                        "Filter": {"Key": {"FilterRules": filter_rules}}
                    })

                # DELETE
                elif action == "delete":
                    lambda_cfg = [c for c in lambda_cfg if c["Id"] != ev["id"]]

                # APPLY TO S3
                curr["LambdaFunctionConfigurations"] = lambda_cfg
                s3.put_bucket_notification_configuration(
                    Bucket=TARGET_BUCKET,
                    NotificationConfiguration=curr
                )

                success.append({"id": ev["id"], "action": action})

            except Exception as e:
                # rollback only this item
                lambda_cfg = op_backup
                curr["LambdaFunctionConfigurations"] = lambda_cfg
                failed.append({"id": ev["id"], "action": action, "error": str(e)})

        # --------------------------------------------------------
        # IF NO FAILURES → MARK VERSION AS SUCCESSFUL
        # --------------------------------------------------------
        if len(failed) == 0:
            set_latest_successful_version(next_version)

        return {
            "status": "completed",
            "backup_file": backup_file,
            "success": success,
            "failed": failed
        }

    except Exception as e:
        # fatal rollback
        s3.put_bucket_notification_configuration(
            Bucket=TARGET_BUCKET,
            NotificationConfiguration=full_backup
        )
        return {
            "status": "fatal_error",
            "error": str(e),
            "trace": traceback.format_exc()
        }
