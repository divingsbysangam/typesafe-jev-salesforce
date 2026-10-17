/**
 * A typed-decision API the triage, guardrail and probe code can call without knowing which
 * vendor answers. Implementations: TypeSafeClient (Jev, /v1/systemone) and OpenAIDecisionsClient
 * (gpt-6-luna, /v1/decisions). Pick one with DecisionProviders.forConfig().
 *
 * Contract shared by every implementation:
 * - questions are built with TypeSafeQuestions (noul / choice / score), keyed by question id;
 * - answers come back as TypeSafeAnswer under the same ids (a yes/no answer's probability is in .noul);
 * - HTTP and network failures are returned on the result (isSuccess = false), never thrown;
 * - result.log is an unsaved TypeSafe_Log__c, so callers can finish every callout before any DML.
 */
public interface IDecisionProvider {
    /**
     * @param state Text, Map or List to evaluate (OpenAIDecisionsClient also takes an ImageInput).
     * @param questions Question id to question map (see TypeSafeQuestions).
     * @param context TypeSafe_Log__c.Context__c value for the audit record.
     * @param recordId Related Salesforce record, may be null.
     * @return Result with typed answers, or isSuccess = false and an errorMessage.
     * @throws TypeSafeException When state or questions are missing or malformed.
     */
    TypeSafeResult ask(Object state, Map<String, Object> questions, String context, Id recordId);
}
