public with sharing class KeepingScoreQuery {

    private static final String MODEL_ID = '2SMdL0000001xSfWAI';
    private static final String GATEWAY = '/services/data/v66.0/semantic-engine/gateway';

    public class Request {
        @InvocableVariable(label='Metrics' description='Comma-separated list of metrics to include: homeRuns, runs, hallOfFamers, gamesAndStadiums. Set only the ones the user asked about.')
        public String metrics;
        @InvocableVariable(label='Team Win Rate' description='Team code to compute attended win rate for, e.g. "NYA" for the Yankees. Leave blank to skip.')
        public String winRateTeam;
    }

    public class Result {
        @InvocableVariable(label='Home Runs Witnessed' description='Total home runs witnessed, or null if not requested.')
        public Decimal homeRunsWitnessed;
        @InvocableVariable(label='Runs Witnessed' description='Total runs witnessed, or null if not requested.')
        public Decimal runsWitnessed;
        @InvocableVariable(label='Hall of Famers Seen' description='Count of distinct Hall of Famers seen, or null if not requested.')
        public Decimal hallOfFamersSeen;
        @InvocableVariable(label='Games Attended' description='Total games attended, or null if not requested.')
        public Decimal gamesAttended;
        @InvocableVariable(label='Unique Stadiums' description='Distinct stadiums visited, or null if not requested.')
        public Decimal uniqueStadiums;
        @InvocableVariable(label='Win Rate Team' description='The team code the win rate was computed for, echoed back.')
        public String winRateTeam;
        @InvocableVariable(label='Team Wins Attended' description='Wins for winRateTeam in attended games, or null.')
        public Decimal teamWinsAttended;
        @InvocableVariable(label='Team Games Decided' description='Decided games for winRateTeam in attended games, or null.')
        public Decimal teamGamesDecided;
        @InvocableVariable(label='Has Data' description='Whether at least one requested metric was returned.')
        public Boolean hasData;
    }

    @InvocableMethod(label='Query Keeping Score Metrics' description='Return governed metrics (home runs, runs, Hall of Famers seen, games/stadiums, team win rate) from the Keeping Score semantic data model. Set only the fields the user asked about.')
    public static List<Result> query(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(runOne(req));
        }
        return results;
    }

    // The SDM's join graph only spans tables that share a relationship path (see
    // CODING/wax_baseball_datacloud_deploy README "join-graph semantics" — confirmed
    // live 2026-09-01: Home_Runs_Witnessed + Hall_of_Famers_Seen in one query throws
    // NO_PATH_ERROR because Plays and HOF_Sightings don't join to each other directly).
    // Same-table metrics DO combine (Home_Runs_Witnessed + Runs_Witnessed, both on
    // Plays, returned together in one call). So each requested group is its own
    // gateway call rather than one combined query.
    private static Result runOne(Request req) {
        Result res = new Result();
        res.hasData = false;

        Set<String> wanted = new Set<String>();
        if (req.metrics != null) {
            for (String m : req.metrics.split(',')) {
                wanted.add(m.trim().toLowerCase());
            }
        }

        Boolean wantsPlays = wanted.contains('homeruns') || wanted.contains('runs');
        if (wantsPlays) {
            List<Object> fields = new List<Object>();
            if (wanted.contains('homeruns')) fields.add(semanticField('Home_Runs_Witnessed', 'hr'));
            if (wanted.contains('runs')) fields.add(semanticField('Runs_Witnessed', 'runs'));
            List<Object> rows = runQuery(fields);
            if (!rows.isEmpty()) {
                List<Object> values = (List<Object>) ((Map<String, Object>) rows[0]).get('values');
                Integer i = 0;
                if (wanted.contains('homeruns')) { res.homeRunsWitnessed = asDecimal(values[i]); i++; res.hasData = true; }
                if (wanted.contains('runs')) { res.runsWitnessed = asDecimal(values[i]); i++; res.hasData = true; }
            }
        }

        if (wanted.contains('halloffamers')) {
            List<Object> rows = runQuery(new List<Object>{ semanticField('Hall_of_Famers_Seen', 'hof') });
            if (!rows.isEmpty()) {
                List<Object> values = (List<Object>) ((Map<String, Object>) rows[0]).get('values');
                res.hallOfFamersSeen = asDecimal(values[0]);
                res.hasData = true;
            }
        }

        if (wanted.contains('gamesandstadiums')) {
            List<Object> rows = runQuery(new List<Object>{
                semanticField('Games_Attended', 'games'),
                semanticField('Unique_Stadiums', 'stadiums')
            });
            if (!rows.isEmpty()) {
                List<Object> values = (List<Object>) ((Map<String, Object>) rows[0]).get('values');
                res.gamesAttended = asDecimal(values[0]);
                res.uniqueStadiums = asDecimal(values[1]);
                res.hasData = true;
            }
        }

        if (req.winRateTeam != null && req.winRateTeam.trim() != '') {
            String team = req.winRateTeam.trim();
            List<Object> rows = runQuery(new List<Object>{
                tableField('Attended_Team_Games', 'team_id', 'team'),
                semanticField('Team_Wins_Attended', 'wins'),
                semanticField('Team_Games_Decided', 'decided')
            });
            for (Object rowObj : rows) {
                List<Object> values = (List<Object>) ((Map<String, Object>) rowObj).get('values');
                if (values != null && values.size() >= 3 && values[0] instanceof String
                        && ((String) values[0]).equalsIgnoreCase(team)) {
                    res.winRateTeam = (String) values[0];
                    res.teamWinsAttended = asDecimal(values[1]);
                    res.teamGamesDecided = asDecimal(values[2]);
                    res.hasData = true;
                    break;
                }
            }
        }

        return res;
    }

    // One gateway call for one group of same-table fields. Returns the raw
    // `rows` array (each row a Map with a "values" list), or an empty list on
    // any failure — callers treat "no rows" the same as "field not requested".
    private static List<Object> runQuery(List<Object> fields) {
        Map<String, Object> structuredQuery = new Map<String, Object>{
            'fields' => fields,
            'options' => new Map<String, Object>{ 'limitOptions' => new Map<String, Object>{ 'limit' => 100 } }
        };
        Map<String, Object> body = new Map<String, Object>{
            'semanticModelId' => MODEL_ID,
            'structuredSemanticQuery' => structuredQuery
        };

        String sid = UserInfo.getSessionId();
        System.debug(LoggingLevel.ERROR, 'KeepingScoreQuery runAs=' + UserInfo.getUserName()
            + ' sessionIdBlank=' + String.isBlank(sid) + ' sessionIdLen=' + (sid == null ? -1 : sid.length()));

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(Url.getOrgDomainUrl().toExternalForm() + GATEWAY);
        httpReq.setMethod('POST');
        httpReq.setHeader('Content-Type', 'application/json');
        httpReq.setHeader('Authorization', 'Bearer ' + sid);
        httpReq.setBody(JSON.serialize(body));
        httpReq.setTimeout(20000);

        HttpResponse httpRes;
        try {
            httpRes = new Http().send(httpReq);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'KeepingScoreQuery callout exception: ' + e.getMessage());
            return new List<Object>();
        }
        if (httpRes.getStatusCode() != 200 && httpRes.getStatusCode() != 201) {
            System.debug(LoggingLevel.ERROR, 'KeepingScoreQuery non-2xx: ' + httpRes.getStatusCode() + ' ' + httpRes.getBody());
            return new List<Object>();
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());
        if (parsed.get('status') != 'SUCCESS') {
            System.debug(LoggingLevel.ERROR, 'KeepingScoreQuery non-SUCCESS status: ' + httpRes.getBody());
            return new List<Object>();
        }
        Map<String, Object> queryResults = (Map<String, Object>) parsed.get('queryResults');
        Map<String, Object> queryData = (Map<String, Object>) queryResults.get('queryData');
        List<Object> rows = (List<Object>) queryData.get('rows');
        return rows == null ? new List<Object>() : rows;
    }

    private static Decimal asDecimal(Object v) {
        if (v == null) return null;
        return Decimal.valueOf(String.valueOf(v));
    }

    private static Map<String, Object> semanticField(String name, String alias) {
        return new Map<String, Object>{
            'expression' => new Map<String, Object>{ 'semanticField' => new Map<String, Object>{ 'name' => name } },
            'alias' => alias
        };
    }

    private static Map<String, Object> tableField(String tableName, String name, String alias) {
        return new Map<String, Object>{
            'rowGrouping' => true,
            'expression' => new Map<String, Object>{ 'tableField' => new Map<String, Object>{ 'name' => name, 'tableName' => tableName } },
            'alias' => alias
        };
    }
}
