// Demo: ask the same five triage questions to Jev and to OpenAI Decisions (gpt-6-luna), side by side.
// Uses the "Default" (TypeSafe) and "OpenAI" TypeSafe_Setting__mdt profiles directly, so it works
// whichever profile is active. 3 samples x 2 providers = 6 callouts; each is saved as a TypeSafe_Log__c.
List<List<String>> samples = new List<List<String>>{
    new List<String>{ 'Villa AC not working', 'The air conditioning in villa 12 has been broken since last night. We have a toddler and it is 31 degrees. Please send someone now.' },
    new List<String>{ 'Charged twice for spa package', 'I was charged twice for the couples spa package. I want the duplicate charge refunded. This is the second time I am writing.' },
    new List<String>{ 'Move dinner reservation', 'Could we move our dinner at the beach grill from 7pm to 8pm on Saturday? Thanks!' }
};
Map<String, TypeSafeConfig> profiles = new Map<String, TypeSafeConfig>{
    'jev' => TypeSafeConfig.forProfile(TypeSafeConfig.PROFILE_DEFAULT),
    'openai' => TypeSafeConfig.forProfile(TypeSafeConfig.PROFILE_OPENAI)
};
Map<String, Object> questions = CaseTriageService.buildQuestions();
List<TypeSafe_Log__c> logs = new List<TypeSafe_Log__c>();

for (List<String> sample : samples) {
    Map<String, Object> state = new Map<String, Object>{ 'subject' => sample[0], 'description' => sample[1], 'channel' => 'Email' };
    for (String providerKey : profiles.keySet()) {
        TypeSafeConfig config = profiles.get(providerKey);
        TypeSafeResult result = DecisionProviders.forConfig(config).ask(state, questions, CaseTriageService.CONTEXT, null);
        result.log.Outcome__c = 'compare:' + providerKey;
        logs.add(result.log);
        Map<String, Object> row = new Map<String, Object>{
            'subject' => sample[0], 'provider' => providerKey, 'model' => result.model,
            'latency_ms' => result.latencyMs, 'input_tokens' => result.inputTokens, 'ok' => result.isSuccess,
            'error' => result.errorMessage
        };
        if (result.isSuccess) {
            try {
                row.put('department', result.getAnswer('department').choice);
                row.put('dept_conf', result.getAnswer('department').confidence);
                row.put('urgency', result.getAnswer('urgency').noul);
                row.put('refund', result.getAnswer('refund_requested').noul);
                row.put('frustration', result.getAnswer('frustration').score);
                row.put('churn', result.getAnswer('churn_risk').score);
            } catch (TypeSafeException e) {
                row.put('error', e.getMessage());
            }
        }
        System.debug(LoggingLevel.ERROR, 'COMPARE_ROW ' + JSON.serialize(row));
    }
}
TypeSafeLogger.save(logs);
