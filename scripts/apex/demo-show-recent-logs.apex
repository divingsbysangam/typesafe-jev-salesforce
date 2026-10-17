// Demo: did Jev run at all in the last few minutes? Shows every TypeSafe call since the cutoff.
Datetime since = System.now().addMinutes(-5);
Integer count = 0;
for (TypeSafe_Log__c log : [
    SELECT Name, Context__c, Outcome__c, Latency_Ms__c, CreatedBy.Name, CreatedDate
    FROM TypeSafe_Log__c
    WHERE CreatedDate >= :since
    ORDER BY CreatedDate
]) {
    count++;
    System.debug(LoggingLevel.ERROR, 'RECENT_LOG ' + log.Name + ' | ' + log.Context__c + ' | ' + log.Outcome__c +
        ' | ' + log.Latency_Ms__c + 'ms | by ' + log.CreatedBy.Name + ' | ' + log.CreatedDate.format('HH:mm:ss'));
}
System.debug(LoggingLevel.ERROR, 'RECENT_COUNT ' + count + ' TypeSafe calls in the last 5 minutes');
