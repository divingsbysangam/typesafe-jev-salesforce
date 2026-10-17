/**
 * HTTP client for the OpenAI Decisions API (POST /v1/decisions, model gpt-6-luna). Auth comes from
 * the OpenAI Named Credential, so no key is ever in code.
 *
 * It speaks the same contract as TypeSafeClient (see IDecisionProvider), so triage and the
 * guardrail run unchanged on either vendor. The translation both ways:
 *
 *   TypeSafeQuestions (map keyed by id)      ->  Decisions request (array, each with a name)
 *   noul  {criteria: {true, false}}          ->  predicate, criteria folded into instructions
 *   choice {criteria: {option: description}} ->  choice {choices: [{value, description}]}
 *   score {criteria: ["Label: description"]} ->  score {levels: [{label, description}]}
 *
 *   Decisions answers (array)                ->  TypeSafeAnswer keyed by name
 *   predicate.probability                    ->  .noul
 *   choice/score probabilities [{value, p}]  ->  .probabilities (score labels also go to .legend)
 *   refusal                                  ->  .type = 'refusal'; TypeSafeResult.getAnswer() throws
 *
 * Images must be inline base64 data URLs (the API rejects hosted URLs and file ids); pass an
 * ImageInput as the state. Image bytes are left out of the audit log.
 *
 * @example
 * IDecisionProvider client = new OpenAIDecisionsClient(TypeSafeConfig.forProfile('OpenAI'));
 * TypeSafeResult result = client.ask('I was charged twice for my order.', questions, 'Case_Triage', caseId);
 */
public with sharing class OpenAIDecisionsClient implements IDecisionProvider {
    @TestVisible
    private static final String ENDPOINT = 'callout:OpenAI/v1/decisions';
    private static final Integer MAX_ERROR_BODY_IN_MESSAGE = 1000;
    private static final String DATA_URL_PREFIX = 'data:image/';
    private static final String BASE64_MARKER = ';base64,';
    private static final String LEVEL_SEPARATOR = ':';

    private final TypeSafeConfig config;

    /**
     * @param config Model and timeout settings; null means the active profile.
     */
    public OpenAIDecisionsClient(TypeSafeConfig config) {
        this.config = config ?? TypeSafeConfig.current();
    }

    /**
     * Evaluate one input against typed questions in a single call.
     * @param state String, Map/List (sent as JSON text) or ImageInput.
     * @param questions Question id to question map (see TypeSafeQuestions).
     * @param context TypeSafe_Log__c.Context__c value for the audit record.
     * @param recordId Related Salesforce record, may be null.
     * @return Result with typed answers, or isSuccess = false and an errorMessage.
     * @throws TypeSafeException When state or questions are missing, or a question type is unsupported.
     */
    public TypeSafeResult ask(Object state, Map<String, Object> questions, String context, Id recordId) {
        if (state == null) {
            throw new TypeSafeException('state is required.');
        }
        if (questions == null || questions.isEmpty()) {
            throw new TypeSafeException('At least one question is required.');
        }
        List<Object> decisionQuestions = toDecisionQuestions(questions);
        String requestBody = serializeRequest(toInput(state, false), decisionQuestions);
        String loggedBody = state instanceof ImageInput
            ? serializeRequest(toInput(state, true), decisionQuestions)
            : requestBody;

        TypeSafeResult result = new TypeSafeResult();
        Long startedAt = System.currentTimeMillis();
        try {
            HttpResponse response = new Http().send(buildRequest(requestBody));
            result.latencyMs = System.currentTimeMillis() - startedAt;
            result.statusCode = response.getStatusCode();
            result.rawResponse = response.getBody();
            if (result.statusCode >= 200 && result.statusCode < 300) {
                parseInto(result, config.model);
            } else {
                result.errorMessage =
                    'HTTP ' + result.statusCode + ': ' + result.rawResponse?.abbreviate(MAX_ERROR_BODY_IN_MESSAGE);
            }
        } catch (CalloutException e) {
            result.latencyMs = System.currentTimeMillis() - startedAt;
            result.errorMessage = 'Callout failed: ' + e.getMessage();
        } catch (JSONException e) {
            result.errorMessage = 'Response was not valid JSON: ' + e.getMessage();
        } catch (TypeException e) {
            result.errorMessage = 'Unexpected response shape: ' + e.getMessage();
        } catch (TypeSafeException e) {
            result.errorMessage = 'Unexpected response shape: ' + e.getMessage();
        }
        result.log = TypeSafeLogger.buildLog(result, loggedBody, context, recordId);
        return result;
    }

    private String serializeRequest(Object input, List<Object> decisionQuestions) {
        return JSON.serialize(
            new Map<String, Object>{ 'model' => config.model, 'input' => input, 'questions' => decisionQuestions }
        );
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

    private static Object toInput(Object state, Boolean redactImages) {
        if (state instanceof String) {
            return state;
        }
        if (!(state instanceof ImageInput)) {
            // Decisions takes text, so structured state is sent as compact JSON.
            return JSON.serialize(state);
        }
        ImageInput image = (ImageInput) state;
        List<Object> content = new List<Object>();
        if (String.isNotBlank(image.text)) {
            content.add(new Map<String, Object>{ 'type' => 'input_text', 'text' => image.text });
        }
        for (String dataUrl : image.imageDataUrls) {
            content.add(
                new Map<String, Object>{
                    'type' => 'input_image',
                    'image_url' => redactImages ? redact(dataUrl) : dataUrl
                }
            );
        }
        return new List<Object>{ new Map<String, Object>{ 'role' => 'user', 'content' => content } };
    }

    private static String redact(String dataUrl) {
        return dataUrl.substringBefore(BASE64_MARKER) + BASE64_MARKER + '<' +
            dataUrl.substringAfter(BASE64_MARKER).length() + ' base64 chars omitted>';
    }

    @TestVisible
    private static List<Object> toDecisionQuestions(Map<String, Object> questions) {
        // Round-trip through JSON so typed builder maps (Map<String, String>, List<String>) read uniformly.
        Map<String, Object> normalized = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(questions));
        List<Object> translated = new List<Object>();
        for (String name : normalized.keySet()) {
            translated.add(toDecisionQuestion(name, (Map<String, Object>) normalized.get(name)));
        }
        return translated;
    }

    private static Map<String, Object> toDecisionQuestion(String name, Map<String, Object> question) {
        String type = (String) question?.get('type');
        String instructions = (String) question?.get('instructions');
        Object criteria = question?.get('criteria');
        Map<String, Object> translated = new Map<String, Object>{ 'name' => name };
        switch on type {
            when 'noul' {
                translated.put('type', 'predicate');
                translated.put('instructions', withPredicateCriteria(instructions, (Map<String, Object>) criteria));
            }
            when 'choice' {
                translated.put('type', 'choice');
                translated.put('instructions', instructions);
                translated.put('choices', toChoices((Map<String, Object>) criteria));
            }
            when 'score' {
                translated.put('type', 'score');
                translated.put('instructions', instructions);
                translated.put('levels', toLevels((List<Object>) criteria));
            }
            when else {
                throw new TypeSafeException('Unsupported question type "' + type + '" for "' + name + '".');
            }
        }
        return translated;
    }

    private static String withPredicateCriteria(String instructions, Map<String, Object> criteria) {
        if (criteria == null) {
            return instructions;
        }
        String combined = instructions;
        if (criteria.get('true') != null) {
            combined += '\nTrue when: ' + criteria.get('true');
        }
        if (criteria.get('false') != null) {
            combined += '\nFalse when: ' + criteria.get('false');
        }
        return combined;
    }

    private static List<Object> toChoices(Map<String, Object> options) {
        List<Object> choices = new List<Object>();
        for (String value : options.keySet()) {
            Map<String, Object> choice = new Map<String, Object>{ 'value' => value };
            String description = (String) options.get(value);
            if (String.isNotBlank(description)) {
                choice.put('description', description);
            }
            choices.add(choice);
        }
        return choices;
    }

    private static List<Object> toLevels(List<Object> rawLevels) {
        List<Object> levels = new List<Object>();
        for (Object rawLevel : rawLevels) {
            // TypeSafe levels are written "Label: description"; Decisions wants the two apart.
            String text = String.valueOf(rawLevel);
            String label = text.contains(LEVEL_SEPARATOR) ? text.substringBefore(LEVEL_SEPARATOR).trim() : text;
            String description = text.contains(LEVEL_SEPARATOR) ? text.substringAfter(LEVEL_SEPARATOR).trim() : '';
            levels.add(
                new Map<String, Object>{
                    'label' => label,
                    'description' => String.isBlank(description) ? label : description
                }
            );
        }
        return levels;
    }

    private static void parseInto(TypeSafeResult result, String requestedModel) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(result.rawResponse);
        List<Object> rawAnswers = (List<Object>) root.get('answers');
        if (rawAnswers == null) {
            throw new TypeSafeException('Response has no answers.');
        }
        for (Object item : rawAnswers) {
            Map<String, Object> raw = (Map<String, Object>) item;
            String name = (String) raw?.get('name');
            if (String.isBlank(name)) {
                throw new TypeSafeException('Answer is missing its name.');
            }
            result.answers.put(name, toAnswer(raw));
        }
        result.model = (String) root.get('model') ?? requestedModel;
        Map<String, Object> usage = (Map<String, Object>) root.get('usage');
        if (usage != null) {
            result.inputTokens = toInteger(usage.get('input_tokens'));
            result.outputTokens = toInteger(usage.get('output_tokens'));
        }
        result.isSuccess = true;
    }

    private static TypeSafeAnswer toAnswer(Map<String, Object> raw) {
        String type = (String) raw.get('type');
        if (type == null) {
            throw new TypeSafeException('Answer is missing its type.');
        }
        TypeSafeAnswer answer = new TypeSafeAnswer();
        answer.type = type;
        answer.confidence = toDecimal(raw.get('confidence'));
        switch on type {
            when 'predicate' {
                answer.noul = toDecimal(raw.get('probability'));
            }
            when 'choice' {
                answer.choice = (String) raw.get('choice');
                readProbabilities(answer, (List<Object>) raw.get('probabilities'), false);
            }
            when 'score' {
                answer.score = toDecimal(raw.get('score'));
                readProbabilities(answer, (List<Object>) raw.get('probabilities'), true);
            }
            when 'refusal' {
                answer.refusal = String.valueOf(raw.get('refusal') ?? raw.get('message') ?? '');
            }
        }
        return answer;
    }

    private static void readProbabilities(TypeSafeAnswer answer, List<Object> rawProbabilities, Boolean withLegend) {
        for (Object item : rawProbabilities ?? new List<Object>()) {
            Map<String, Object> entry = (Map<String, Object>) item;
            String key = String.valueOf(entry.get('value'));
            answer.probabilities.put(key, toDecimal(entry.get('probability')));
            if (withLegend && entry.get('label') != null) {
                answer.legend.put(key, String.valueOf(entry.get('label')));
            }
        }
    }

    private static Decimal toDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }

    private static Integer toInteger(Object value) {
        return value == null ? null : Integer.valueOf(value);
    }

    /**
     * Text plus one or more images for a single Decisions request.
     */
    public class ImageInput {
        public final String text;
        public final List<String> imageDataUrls;

        /**
         * @param text Optional instructions or context sent before the images.
         * @param imageDataUrls Inline base64 data URLs (data:image/png;base64,...).
         * @throws TypeSafeException When no image is given or an image is not an inline data URL.
         */
        public ImageInput(String text, List<String> imageDataUrls) {
            if (imageDataUrls == null || imageDataUrls.isEmpty()) {
                throw new TypeSafeException('At least one image is required.');
            }
            for (String dataUrl : imageDataUrls) {
                if (dataUrl == null || !dataUrl.startsWith(DATA_URL_PREFIX) || !dataUrl.contains(BASE64_MARKER)) {
                    throw new TypeSafeException(
                        'Images must be inline base64 data URLs (data:image/...;base64,...); hosted URLs are not supported.'
                    );
                }
            }
            this.text = text;
            this.imageDataUrls = imageDataUrls;
        }
    }

    /**
     * @param mimeType Image MIME type, e.g. image/png.
     * @param data Image bytes.
     * @return Inline data URL for ImageInput.
     */
    public static String toDataUrl(String mimeType, Blob data) {
        return 'data:' + mimeType + BASE64_MARKER + EncodingUtil.base64Encode(data);
    }
}
