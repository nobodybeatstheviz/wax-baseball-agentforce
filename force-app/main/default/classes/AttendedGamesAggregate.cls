public with sharing class AttendedGamesAggregate {

    public class Request {
        @InvocableVariable(label='Group By' description='Dimension to group by: home_team, away_team, venue, season, gameType, or state.' required=true)
        public String groupBy;
        @InvocableVariable(label='Team' description='Optional team filter, name or nickname, e.g. "Yankees" matches "New York Yankees"; matches home or away team.')
        public String team;
        @InvocableVariable(label='Season' description='Optional year filter.')
        public Integer season;
    }

    public class GroupCount implements Comparable {
        @InvocableVariable(label='Group Value' description='The value of the grouped dimension.')
        public String groupValue;
        @InvocableVariable(label='Game Count' description='Number of attended games in this group.')
        public Decimal gameCount;

        public Integer compareTo(Object o) {
            GroupCount other = (GroupCount) o;
            if (this.gameCount == other.gameCount) return 0;
            return (this.gameCount > other.gameCount) ? -1 : 1;
        }
    }

    public class Result {
        @InvocableVariable(label='Groups' description='Group counts, ordered from most to fewest.')
        public List<GroupCount> groups;
        @InvocableVariable(label='Has Data' description='Whether any games matched.')
        public Boolean hasData;
    }

    @InvocableMethod(label='Aggregate Attended Games' description='Count attended games grouped by a dimension, ordered from most to fewest.')
    public static List<Result> aggregate(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(runOne(req));
        }
        return results;
    }

    private static Result runOne(Request req) {
        List<Attended_Games__dlm> rows = [
            SELECT Game_Date__c, Away_Team__c, Home_Team__c, Venue__c, City__c, State__c, Game_Type__c
            FROM Attended_Games__dlm
            WITH USER_MODE
            LIMIT 1000
        ];

        String dim = (req.groupBy == null) ? '' : req.groupBy.toLowerCase().trim();
        Map<String, Integer> counts = new Map<String, Integer>();

        for (Attended_Games__dlm g : rows) {
            if (notEmpty(req.team) && !teamMatches(g.Home_Team__c, req.team) && !teamMatches(g.Away_Team__c, req.team)) continue;
            if (req.season != null && (g.Game_Date__c == null || g.Game_Date__c.year() != req.season)) continue;

            String key;
            if (dim == 'home_team') key = g.Home_Team__c;
            else if (dim == 'away_team') key = g.Away_Team__c;
            else if (dim == 'venue') key = g.Venue__c;
            else if (dim == 'state') key = g.State__c;
            else if (dim == 'gametype') key = g.Game_Type__c;
            else if (dim == 'season') key = (g.Game_Date__c == null) ? null : String.valueOf(g.Game_Date__c.year());
            else key = null;

            if (key == null || key == '') key = '(unknown)';
            counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
        }

        List<GroupCount> groups = new List<GroupCount>();
        for (String k : counts.keySet()) {
            GroupCount gc = new GroupCount();
            gc.groupValue = k;
            gc.gameCount = counts.get(k);
            groups.add(gc);
        }
        groups.sort();

        Result res = new Result();
        res.groups = groups;
        res.hasData = !groups.isEmpty();
        return res;
    }

    private static Boolean notEmpty(String s) {
        return s != null && s.trim() != '';
    }

    // Team names in the data are full club names ("New York Yankees") but questions use
    // the nickname ("Yankees"), so team matching is partial.
    private static Boolean teamMatches(String dataValue, String filterValue) {
        return dataValue != null && filterValue != null && dataValue.containsIgnoreCase(filterValue.trim());
    }
}
