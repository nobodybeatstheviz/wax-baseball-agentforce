public with sharing class AttendedGamesQuery {

    public class Request {
        @InvocableVariable(label='Team' description='Team name or nickname, e.g. "Yankees" matches "New York Yankees"; matches either the home or away team.')
        public String team;
        @InvocableVariable(label='Season' description='The year of the game, e.g. 2008.')
        public Integer season;
        @InvocableVariable(label='Venue' description='Ballpark name.')
        public String venue;
        @InvocableVariable(label='City' description='City the game was in.')
        public String city;
        @InvocableVariable(label='State' description='Two-letter state code.')
        public String state;
        @InvocableVariable(label='Game Type' description='Game type, e.g. Regular Season.')
        public String gameType;
    }

    public class GameInfo {
        @InvocableVariable(label='Wax Game ID' description='Unique attended-game id.')
        public String waxGameId;
        @InvocableVariable(label='Game Date' description='Date of the game.')
        public Date gameDate;
        @InvocableVariable(label='Away Team' description='Away team.')
        public String awayTeam;
        @InvocableVariable(label='Home Team' description='Home team.')
        public String homeTeam;
        @InvocableVariable(label='Venue' description='Ballpark.')
        public String venue;
        @InvocableVariable(label='City' description='City.')
        public String city;
        @InvocableVariable(label='State' description='State.')
        public String state;
        @InvocableVariable(label='Game Type' description='Game type.')
        public String gameType;
    }

    public class Result {
        @InvocableVariable(label='Games' description='Matching attended games (up to 25).')
        public List<GameInfo> games;
        @InvocableVariable(label='Match Count' description='Total number of matching games.')
        public Decimal matchCount;
        @InvocableVariable(label='Has Data' description='Whether any games matched.')
        public Boolean hasData;
    }

    @InvocableMethod(label='Query Attended Games' description='Return attended games matching optional filters (team matches home or away), with a total match count.')
    public static List<Result> query(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(runOne(req));
        }
        return results;
    }

    private static Result runOne(Request req) {
        // Reference data is small (178 rows): query all, filter in Apex for robustness against DMO SOQL quirks.
        List<Attended_Games__dlm> rows = [
            SELECT Wax_Game_ID__c, Game_Date__c, Away_Team__c, Home_Team__c,
                   Venue__c, City__c, State__c, Game_Type__c
            FROM Attended_Games__dlm
            WITH USER_MODE
            ORDER BY Game_Date__c
            LIMIT 1000
        ];

        List<GameInfo> matches = new List<GameInfo>();
        for (Attended_Games__dlm g : rows) {
            if (notEmpty(req.team) && !teamMatches(g.Home_Team__c, req.team) && !teamMatches(g.Away_Team__c, req.team)) continue;
            if (notEmpty(req.venue) && !eq(g.Venue__c, req.venue)) continue;
            if (notEmpty(req.city) && !eq(g.City__c, req.city)) continue;
            if (notEmpty(req.state) && !eq(g.State__c, req.state)) continue;
            if (notEmpty(req.gameType) && !eq(g.Game_Type__c, req.gameType)) continue;
            if (req.season != null && (g.Game_Date__c == null || g.Game_Date__c.year() != req.season)) continue;

            GameInfo gi = new GameInfo();
            gi.waxGameId = g.Wax_Game_ID__c;
            gi.gameDate = g.Game_Date__c;
            gi.awayTeam = g.Away_Team__c;
            gi.homeTeam = g.Home_Team__c;
            gi.venue = g.Venue__c;
            gi.city = g.City__c;
            gi.state = g.State__c;
            gi.gameType = g.Game_Type__c;
            matches.add(gi);
        }

        Result res = new Result();
        res.matchCount = matches.size();
        res.hasData = !matches.isEmpty();

        // Cap the returned list so the agent's context stays manageable; matchCount keeps the true total.
        List<GameInfo> capped = new List<GameInfo>();
        for (Integer i = 0; i < matches.size() && i < 25; i++) {
            capped.add(matches[i]);
        }
        res.games = capped;
        return res;
    }

    private static Boolean notEmpty(String s) {
        return s != null && s.trim() != '';
    }

    private static Boolean eq(String a, String b) {
        return a != null && b != null && a.equalsIgnoreCase(b.trim());
    }

    // Team names in the data are full club names ("New York Yankees") but questions use
    // the nickname ("Yankees"), so team matching is partial where other filters are exact.
    private static Boolean teamMatches(String dataValue, String filterValue) {
        return dataValue != null && filterValue != null && dataValue.containsIgnoreCase(filterValue.trim());
    }
}
