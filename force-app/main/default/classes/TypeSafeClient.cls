/**
 * HTTP client for the TypeSafe System One endpoint (Jev). Auth comes from the TypeSafe Named
 * Credential, so no key is ever in code.
 *
 * The client never throws on HTTP or network failure: it returns a TypeSafeResult with
 * isSuccess = false and an unsaved TypeSafe_Log__c. That keeps callers free to make every
 * callout first and do all DML afterwards (Salesforce blocks callouts after uncommitted DML).
 *
 * @example
 * TypeSafeClient client = new TypeSafeClient(TypeSafeConfig.current());
 * TypeSafeResult result = client.ask('Help! My payouts have been failing for 3 days.', questions, 'Case_Triage', caseId);
 * if (result.isSuccess) {
 *     Decimal urgency = result.getAnswer('is_urgent').noul;
 * }
 * TypeSafeLogger.save(new List<TypeSafe_Log__c>{ result.log });
 */
public with sharing class TypeSafeClient implements IDecisionProvider {
    @TestVisible
    private static final String ENDPOINT = 'callout:TypeSafe/v1/systemone';
    private static final Integer MAX_ERROR_BODY_IN_MESSAGE = 1000;

    private final TypeSafeConfig config;

    /**
     * @param config Model and timeout settings.
     */
    public TypeSafeClient(TypeSafeConfig config) {
        this.config = config ?? TypeSafeConfig.current();
    }

    /**
     * Evaluate one state against a map of typed questions in a single call.
     * @param state String, Map or List describing what to evaluate. Send only the fields the questions need.
     * @param questions Question id to question map (see TypeSafeQuestions).
     * @param context TypeSafe_Log__c.Context__c value for the audit record.
     * @param recordId Related Salesforce record, may be null.
     * @return Result with typed answers, or isSuccess = false and an errorMessage.
     * @throws TypeSafeException When state or questions are missing (programming error, not a runtime failure).
     */
    public TypeSafeResult ask(Object state, Map<String, Object> questions, String context, Id recordId) {
        if (state == null) {
            throw new TypeSafeException('state is required.');
        }
        if (questions == null || questions.isEmpty()) {
            throw new TypeSafeException('At least one question is required.');
        }
        String requestBody = JSON.serialize(
            new Map<String, Object>{ 'state' => state, 'model' => config.model, 'questions' => questions }
        );

        TypeSafeResult result = new TypeSafeResult();
        Long startedAt = System.currentTimeMillis();
        try {
            HttpResponse response = new Http().send(buildRequest(requestBody));
            result.latencyMs = System.currentTimeMillis() - startedAt;
            result.statusCode = response.getStatusCode();
            result.rawResponse = response.getBody();
            if (result.statusCode >= 200 && result.statusCode < 300) {
                parseInto(result);
            } else {
                result.errorMessage =
                    'HTTP ' + result.statusCode + ': ' + result.rawResponse?.abbreviate(MAX_ERROR_BODY_IN_MESSAGE);
            }
        } catch (CalloutException e) {
            result.latencyMs = System.currentTimeMillis() - startedAt;
            result.errorMessage = 'Callout failed: ' + e.getMessage();
        } catch (JSONException e) {
            result.errorMessage = 'Response was not valid JSON: ' + e.getMessage();
        } catch (TypeSafeException e) {
            result.errorMessage = 'Unexpected response shape: ' + e.getMessage();
        }
        result.log = TypeSafeLogger.buildLog(result, requestBody, context, recordId);
        return result;
    }

    private HttpRequest buildRequest(String body) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(config.timeoutMs);
        request.setBody(body);
        return request;
    }

    private static void parseInto(TypeSafeResult result) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(result.rawResponse);
        Map<String, Object> rawAnswers = (Map<String, Object>) root.get('answers');
        if (rawAnswers == null) {
            throw new TypeSafeException('Response has no answers.');
        }
        for (String questionId : rawAnswers.keySet()) {
            result.answers.put(questionId, TypeSafeAnswer.fromMap((Map<String, Object>) rawAnswers.get(questionId)));
        }
        result.model = (String) root.get('model');
        Map<String, Object> usage = (Map<String, Object>) root.get('usage');
        if (usage != null) {
            result.inputTokens = toInteger(usage.get('input_tokens'));
            result.outputTokens = toInteger(usage.get('output_tokens'));
        }
        result.isSuccess = true;
    }

    private static Integer toInteger(Object value) {
        return value == null ? null : Integer.valueOf(value);
    }
}
