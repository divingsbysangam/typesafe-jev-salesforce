// Demo: what the guarded agent actually did, from org records (newest case filed by the agent).
Case filed = [
    SELECT CaseNumber, Subject, Origin, Priority, Owner.Name, CreatedBy.Name, CreatedDate,
        TS_Triage_Status__c, TS_Department__c, TS_Department_Confidence__c, TS_Urgency__c,
        TS_Frustration__c, TS_Frustration_Confidence__c, TS_Triage_Reason__c
    FROM Case
    WHERE Origin = 'Agentforce'
    ORDER BY CreatedDate DESC
    LIMIT 1
];
System.debug(LoggingLevel.ERROR, 'AGENT_CASE ' + JSON.serialize(new Map<String, Object>{
    'case' => filed.CaseNumber, 'subject' => filed.Subject, 'origin' => filed.Origin,
    'createdBy' => filed.CreatedBy.Name, 'status' => filed.TS_Triage_Status__c,
    'department' => filed.TS_Department__c, 'dept_conf' => filed.TS_Department_Confidence__c,
    'urgency' => filed.TS_Urgency__c, 'frustration' => filed.TS_Frustration__c,
    'frust_conf' => filed.TS_Frustration_Confidence__c, 'priority' => filed.Priority,
    'owner' => filed.Owner.Name, 'reason' => filed.TS_Triage_Reason__c
}));

for (TypeSafe_Log__c log : [
    SELECT Name, Context__c, Outcome__c, Latency_Ms__c, Status_Code__c, CreatedBy.Name
    FROM TypeSafe_Log__c
    WHERE CreatedDate >= :filed.CreatedDate.addMinutes(-3)
    ORDER BY CreatedDate
]) {
    System.debug(LoggingLevel.ERROR, 'AGENT_LOG ' + log.Name + ' | ' + log.Context__c + ' | ' + log.Outcome__c +
        ' | HTTP ' + log.Status_Code__c + ' | ' + log.Latency_Ms__c + 'ms | by ' + log.CreatedBy.Name);
}
