// The Slack push, end to end. Two dates with known attended games, then today.
// Without the webhook configured (scripts/set_slack_webhook.py) the digest still renders and status is not_configured.
for (Date d : new List<Date>{ Date.newInstance(2026, 10, 16), Date.newInstance(2026, 10, 5), Date.today() }) {
    OnThisDateDigest.Result r = OnThisDateDigest.runOne(d, true);
    System.debug('DATE=' + d + ' GAMES=' + r.gameCount + ' STATUS=' + r.status + ' POSTED=' + r.posted);
    System.debug('DIGEST=\n' + r.digest);
}
