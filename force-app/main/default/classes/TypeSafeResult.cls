/**
 * Outcome of one TypeSafe call: the typed answers plus everything needed for the audit log.
 * A failed call has isSuccess = false and an errorMessage; it is not thrown.
 */
public class TypeSafeResult {
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 429, 503, 529 };

    public Boolean isSuccess = false;
    public Integer statusCode;
    public Long latencyMs;
    public String model;
    public Integer inputTokens;
    public Integer outputTokens;
    public String rawResponse;
    public String errorMessage;
    public Map<String, TypeSafeAnswer> answers = new Map<String, TypeSafeAnswer>();
    /** Unsaved audit record for this call. Callers set Outcome__c, then save via TypeSafeLogger. */
    public TypeSafe_Log__c log;

    /**
     * @param questionId The key used in the request's questions map.
     * @return The typed answer.
     * @throws TypeSafeException When the response has no answer under that key, or the model
     *         refused it (OpenAI Decisions), so every caller fails safe the same way.
     */
    public TypeSafeAnswer getAnswer(String questionId) {
        TypeSafeAnswer answer = answers.get(questionId);
        if (answer == null) {
            throw new TypeSafeException('No answer returned for question "' + questionId + '".');
        }
        if (answer.isRefusal()) {
            throw new TypeSafeException(
                'Model refused to answer "' + questionId + '"' +
                (String.isBlank(answer.refusal) ? '.' : ': ' + answer.refusal)
            );
        }
        return answer;
    }

    /**
     * @return True for rate-limit/overload responses, which should be retried with backoff.
     */
    public Boolean isRetryable() {
        return !isSuccess && statusCode != null && RETRYABLE_STATUS_CODES.contains(statusCode);
    }
}
