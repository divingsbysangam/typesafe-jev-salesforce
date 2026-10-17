/**
 * Persists TypeSafe audit records. Call it once, after all callouts in the transaction are done.
 */
public with sharing class TypeSafeLogger {
    private static final Integer MAX_LONG_TEXT = 131072;
    private static final Integer MAX_ERROR_TEXT = 32768;

    private TypeSafeLogger() {
    }

    /**
     * Builds the unsaved audit record for one decision call. Shared by every IDecisionProvider.
     * @param result The call outcome.
     * @param requestBody Body to keep for the audit trail (redact anything that should not be stored).
     * @param context TypeSafe_Log__c.Context__c value.
     * @param recordId Related Salesforce record, may be null.
     * @return Unsaved log.
     */
    public static TypeSafe_Log__c buildLog(TypeSafeResult result, String requestBody, String context, Id recordId) {
        return new TypeSafe_Log__c(
            Context__c = context,
            Record_Id__c = recordId,
            Model__c = result.model,
            Success__c = result.isSuccess,
            Status_Code__c = result.statusCode,
            Latency_Ms__c = result.latencyMs,
            Input_Tokens__c = result.inputTokens,
            Output_Tokens__c = result.outputTokens,
            Request__c = requestBody?.abbreviate(MAX_LONG_TEXT),
            Response__c = result.rawResponse?.abbreviate(MAX_LONG_TEXT),
            Error__c = result.errorMessage?.abbreviate(MAX_ERROR_TEXT)
        );
    }

    /**
     * Saves in user mode: the caller needs the TypeSafe_User permission set.
     * @param logs Unsaved logs (nulls are skipped).
     * @return The inserted logs, with Ids.
     */
    public static List<TypeSafe_Log__c> save(List<TypeSafe_Log__c> logs) {
        return save(logs, AccessLevel.USER_MODE);
    }

    /**
     * @param logs Unsaved logs (nulls are skipped).
     * @param mode USER_MODE for user-invoked actions, SYSTEM_MODE for back-end automation.
     * @return The inserted logs, with Ids.
     */
    public static List<TypeSafe_Log__c> save(List<TypeSafe_Log__c> logs, AccessLevel mode) {
        List<TypeSafe_Log__c> toInsert = new List<TypeSafe_Log__c>();
        for (TypeSafe_Log__c log : logs ?? new List<TypeSafe_Log__c>()) {
            if (log != null) {
                toInsert.add(log);
            }
        }
        if (toInsert.isEmpty()) {
            return toInsert;
        }
        if (mode == AccessLevel.SYSTEM_MODE) {
            Database.insert(toInsert, AccessLevel.SYSTEM_MODE);
        } else {
            Database.insert(toInsert, AccessLevel.USER_MODE);
        }
        return toInsert;
    }
}
