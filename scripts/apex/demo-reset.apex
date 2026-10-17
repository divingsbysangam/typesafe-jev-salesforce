// Optional clean slate before recording: removes earlier demo cases (by subject) and demo-run logs.
// Deletes data in the org you run it against. Review before running.
Set<String> demoSubjects = new Set<String>{
    'Villa AC not working', 'Charged twice for spa package', 'Move dinner reservation',
    'Charged twice for March invoice', 'API returning 500 errors - orders blocked', 'Question'
};
List<Case> demoCases = [SELECT Id FROM Case WHERE Subject IN :demoSubjects];
List<TypeSafe_Log__c> demoLogs = [
    SELECT Id FROM TypeSafe_Log__c
    WHERE Context__c IN ('Case_Triage', 'Guardrail_Input', 'Guardrail_Output')
];
delete demoCases;
delete demoLogs;
System.debug(LoggingLevel.ERROR, 'RESET deleted cases=' + demoCases.size() + ' logs=' + demoLogs.size() + ' (latency probe logs kept)');
