/**
 * "On this date" -- the attended games that fall on today's month and day, as a Slack digest.
 *
 * The W7 action (Keeping Score parity plan): the retroactive action on the Agentforce surface.
 * Invocable for Agentforce / Flow, plus a Schedulable for the daily push. Data comes straight from
 * the Data 360 DMO the agent already reads (Attended_Games__dlm, SOQL-able in devorg -- see
 * AttendedGamesQuery). Scheduled Flows run as the Automated Process user, which cannot hold a
 * named-credential principal, so the daily push is Apex scheduled under Wax's user
 * (scripts/schedule_on_this_date.apex), not a Scheduled Flow (ruled 2026-09-10).
 */
public with sharing class OnThisDateDigest implements Schedulable {
    public class Request {
        @InvocableVariable(label='Date' description='The date to look up (month and day are used). Defaults to today.')
        public Date onDate;
        @InvocableVariable(label='Post to Slack' description='When true, post the digest to the Keeping Score Slack webhook. Default false: just return the text.')
        public Boolean postToSlack;
    }

    public class Result {
        @InvocableVariable(label='Digest' description='The digest text (Slack mrkdwn).')
        public String digest;
        @InvocableVariable(label='Game Count')
        public Integer gameCount;
        @InvocableVariable(label='Posted')
        public Boolean posted;
        @InvocableVariable(label='Status' description='ok | no_games | not_configured | http_<code> | not_posted')
        public String status;
    }

    @InvocableMethod(label='On This Date digest' description='List the attended games that fall on this month and day, optionally posting the digest to Slack.' callout=true)
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) {
            out.add(runOne(r.onDate == null ? Date.today() : r.onDate, r.postToSlack == true));
        }
        return out;
    }

    /** Schedulable entry: today's digest, posted. */
    public void execute(SchedulableContext ctx) {
        runOne(Date.today(), true);
    }

    public static Result runOne(Date onDate, Boolean post) {
        Result res = new Result();
        List<Attended_Games__dlm> games = new List<Attended_Games__dlm>();
        for (Attended_Games__dlm g : [
            SELECT Wax_Game_ID__c, Game_Date__c, Away_Team__c, Home_Team__c, Venue__c, Game_Type__c
            FROM Attended_Games__dlm
            ORDER BY Game_Date__c
        ]) {
            if (g.Game_Date__c != null && g.Game_Date__c.month() == onDate.month() && g.Game_Date__c.day() == onDate.day()) {
                games.add(g);
            }
        }
        res.gameCount = games.size();
        res.digest = render(onDate, games);
        res.posted = false;
        if (games.isEmpty()) {
            res.status = 'no_games';
            return res;
        }
        if (!post) {
            res.status = 'not_posted';
            return res;
        }
        SlackWebhookPost.Result slack = SlackWebhookPost.postOne(res.digest);
        res.posted = slack.posted;
        res.status = slack.status;
        return res;
    }

    private static String render(Date onDate, List<Attended_Games__dlm> games) {
        String header = ':baseball: *On this date -- ' + monthName(onDate.month()) + ' ' + onDate.day() + '* -- Keeping Score';
        if (games.isEmpty()) {
            return header + '\nNo attended games on this date.';
        }
        List<String> lines = new List<String>{ header };
        for (Attended_Games__dlm g : games) {
            Integer yearsAgo = onDate.year() - g.Game_Date__c.year();
            String ago = yearsAgo == 0 ? 'today' : yearsAgo + (yearsAgo == 1 ? ' year ago' : ' years ago');
            String gameType = String.isBlank(g.Game_Type__c) || g.Game_Type__c == 'Regular Season' ? '' : ' (' + g.Game_Type__c + ')';
            lines.add('- *' + g.Game_Date__c.year() + '* -- ' + g.Away_Team__c + ' at ' + g.Home_Team__c + ', ' + g.Venue__c + gameType + ' -- ' + ago);
        }
        lines.add('_' + games.size() + (games.size() == 1 ? ' game' : ' games') + ' on this date, out of 178._');
        return String.join(lines, '\n');
    }

    private static String monthName(Integer m) {
        return new List<String>{ 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December' }[m - 1];
    }
}
