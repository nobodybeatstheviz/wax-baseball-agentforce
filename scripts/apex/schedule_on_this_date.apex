// Schedule the daily "on this date" Slack push at 09:00 org time, under the running user (who must hold
// the Keeping_Score_Slack_Push permission set). Idempotent: aborts an existing job of the same name first.
String jobName = 'Keeping Score - On This Date';
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :jobName]) {
    System.abortJob(ct.Id);
}
Id jobId = System.schedule(jobName, '0 0 9 * * ?', new OnThisDateDigest());
System.debug('SCHEDULED ' + jobName + ' ' + jobId);
