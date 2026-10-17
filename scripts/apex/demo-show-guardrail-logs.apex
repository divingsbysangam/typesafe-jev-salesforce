// Demo: the audit trail for the guardrail run. Newest guardrail checks first.
for (TypeSafe_Log__c log : [
    SELECT Name, Context__c, Outcome__c, Status_Code__c, Latency_Ms__c, Input_Tokens__c, Model__c, CreatedBy.Name, CreatedDate
    FROM TypeSafe_Log__c
    WHERE Context__c IN ('Guardrail_Input', 'Guardrail_Output')
    ORDER BY CreatedDate DESC
    LIMIT 10
]) {
    System.debug(LoggingLevel.ERROR, 'LOG_ROW ' + JSON.serialize(new Map<String, Object>{
        'name' => log.Name,
        'context' => log.Context__c,
        'outcome' => log.Outcome__c,
        'http' => log.Status_Code__c,
        'ms' => log.Latency_Ms__c,
        'tokens' => log.Input_Tokens__c,
        'model' => log.Model__c,
        'by' => log.CreatedBy.Name
    }));
}
