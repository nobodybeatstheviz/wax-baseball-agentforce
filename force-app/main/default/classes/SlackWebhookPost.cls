/**
 * Posts a message to a Slack incoming webhook through the Slack_Webhook named credential.
 *
 * Why this shape (ruled 2026-09-10, the W7 Slack push): native Salesforce-to-Slack needs a paid
 * workspace and org-side provisioning devorg doesn't have (measured 2026-09-01, re-measured on the
 * partner org 2026-09-09). An incoming webhook works on a free workspace. The webhook URL's path IS
 * the secret, so it lives in the protected custom setting Keeping_Score_Settings__c
 * (set by scripts/set_slack_webhook.py, never in source); the named credential holds only the host.
 */
public with sharing class SlackWebhookPost {
    public class Request {
        @InvocableVariable(label='Text' description='Message text (Slack mrkdwn).' required=true)
        public String text;
    }

    public class Result {
        @InvocableVariable(label='Posted')
        public Boolean posted;
        @InvocableVariable(label='Status' description='ok | not_configured | http_<code>')
        public String status;
    }

    @InvocableMethod(label='Post to Slack' description='Post a message to the Keeping Score Slack incoming webhook.' callout=true)
    public static List<Result> post(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) {
            out.add(postOne(r.text));
        }
        return out;
    }

    public static Result postOne(String text) {
        Result res = new Result();
        String path = webhookPath();
        if (String.isBlank(path)) {
            res.posted = false;
            res.status = 'not_configured';
            return res;
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Slack_Webhook' + path);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, Object>{ 'text' => text }));
        HttpResponse resp = new Http().send(req);
        res.posted = resp.getStatusCode() == 200;
        res.status = res.posted ? 'ok' : 'http_' + resp.getStatusCode();
        if (!res.posted) {
            System.debug(LoggingLevel.ERROR, 'Slack webhook failed: HTTP ' + resp.getStatusCode() + ' ' + resp.getBody());
        }
        return res;
    }

    /** "/services/T.../B.../xxx" from the protected custom setting; blank when not configured. */
    public static String webhookPath() {
        Keeping_Score_Settings__c s = Keeping_Score_Settings__c.getInstance('Default');
        return s == null ? null : s.Slack_Webhook_Path__c;
    }
}
