"""Store the Slack incoming-webhook path in the protected custom setting (the secret never touches source).

Usage: python scripts/set_slack_webhook.py https://hooks.slack.com/services/T.../B.../xxx [org-alias]
Creates or updates the Keeping_Score_Settings__c record named 'Default'. Prints nothing secret.
"""
import json
import os
import subprocess
import sys
from urllib.parse import urlparse

if len(sys.argv) < 2:
    sys.exit(__doc__)
url = sys.argv[1].strip()
org = sys.argv[2] if len(sys.argv) > 2 else "devorg"
u = urlparse(url)
if u.netloc != "hooks.slack.com" or not u.path.startswith("/services/"):
    sys.exit("that is not a Slack incoming webhook URL")
path = u.path


def sf(*args):
    out = subprocess.run(["sf", *args, "--json"], capture_output=True, text=True, shell=(os.name == "nt"))
    t = out.stdout
    return json.loads(t[t.index("{"):])


q = sf("data", "query", "-o", org, "-q", "SELECT Id FROM Keeping_Score_Settings__c WHERE Name = 'Default'")
records = q.get("result", {}).get("records", [])
if records:
    r = sf("data", "update", "record", "-o", org, "-s", "Keeping_Score_Settings__c", "-i", records[0]["Id"],
           "-v", f"Slack_Webhook_Path__c='{path}'")
    print("updated Default:", r.get("status"))
else:
    r = sf("data", "create", "record", "-o", org, "-s", "Keeping_Score_Settings__c",
           "-v", f"Name='Default' Slack_Webhook_Path__c='{path}'")
    print("created Default:", r.get("status"))
print("webhook path stored (length", len(path), ") -- test with: sf apex run -o", org, "-f scripts/apex/test_slack_push.apex")
