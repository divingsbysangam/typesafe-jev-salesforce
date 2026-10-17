// Demo: show what Jev decided for the most recent demo cases.
for (Case c : [
    SELECT CaseNumber, Subject, Priority, Owner.Name, TS_Triage_Status__c, TS_Department__c,
        TS_Department_Confidence__c, TS_Urgency__c, TS_Refund_Requested__c, TS_Frustration__c,
        TS_Frustration_Confidence__c, TS_Churn_Risk__c, TS_Churn_Risk_Confidence__c, TS_Triage_Reason__c, TS_Model__c
    FROM Case
    WHERE Subject IN ('Villa AC not working', 'Charged twice for spa package', 'Move dinner reservation')
    ORDER BY CreatedDate DESC
    LIMIT 3
]) {
    System.debug(LoggingLevel.ERROR, 'DEMO_ROW ' + JSON.serialize(new Map<String, Object>{
        'case' => c.CaseNumber,
        'subject' => c.Subject,
        'status' => c.TS_Triage_Status__c,
        'department' => c.TS_Department__c,
        'dept_conf' => c.TS_Department_Confidence__c,
        'urgency' => c.TS_Urgency__c,
        'refund' => c.TS_Refund_Requested__c,
        'frustration' => c.TS_Frustration__c,
        'frust_conf' => c.TS_Frustration_Confidence__c,
        'churn' => c.TS_Churn_Risk__c,
        'churn_conf' => c.TS_Churn_Risk_Confidence__c,
        'priority' => c.Priority,
        'owner' => c.Owner.Name,
        'reason' => c.TS_Triage_Reason__c,
        'model' => c.TS_Model__c
    }));
}
