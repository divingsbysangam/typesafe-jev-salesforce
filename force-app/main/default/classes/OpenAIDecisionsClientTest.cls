@IsTest
private class OpenAIDecisionsClientTest {
    private static final String CONTEXT = 'Case_Triage';
    private static final String PNG_DATA_URL = 'data:image/png;base64,iVBORw0KGgo=';

    private static TypeSafeResult ask(TypeSafeMock mock, Object state, Map<String, Object> questions) {
        Test.setMock(HttpCalloutMock.class, mock);
        OpenAIDecisionsClient client = new OpenAIDecisionsClient(OpenAIDecisionsMock.openAIConfig());
        Test.startTest();
        TypeSafeResult result = client.ask(state, questions, CONTEXT, null);
        Test.stopTest();
        return result;
    }

    private static TypeSafeResult askTriage(TypeSafeMock mock) {
        return ask(mock, 'Help!', CaseTriageService.buildQuestions());
    }

    private static Map<String, Object> sentBody(TypeSafeMock mock) {
        return (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
    }

    private static Map<String, Object> sentQuestion(TypeSafeMock mock, String name) {
        for (Object item : (List<Object>) sentBody(mock).get('questions')) {
            Map<String, Object> question = (Map<String, Object>) item;
            if (question.get('name') == name) {
                return question;
            }
        }
        Assert.fail('Question ' + name + ' was not sent');
        return null;
    }

    @IsTest
    static void shouldParseAllAnswerTypes_WhenResponseIs200() {
        TypeSafeResult result = askTriage(new TypeSafeMock(200, OpenAIDecisionsMock.confidentTriage()));

        Assert.isTrue(result.isSuccess, 'Call should succeed');
        Assert.areEqual('Facilities', result.getAnswer('department').choice, 'Choice should be parsed');
        Assert.areEqual(0.85, result.getAnswer('department').probabilities.get('Facilities'), 'Choice probabilities should be keyed by value');
        Assert.areEqual(0.9, result.getAnswer('urgency').noul, 'Predicate probability should land in noul');
        Assert.isNull(result.getAnswer('urgency').confidence, 'Predicates carry no confidence');
        Assert.areEqual(1.2, result.getAnswer('frustration').score, 'Score should be parsed');
        Assert.areEqual(0.6, result.getAnswer('frustration').probabilities.get('1'), 'Score probabilities should be keyed by level index');
        Assert.areEqual('L3', result.getAnswer('frustration').legend.get('3'), 'Score labels should fill the legend');
    }

    @IsTest
    static void shouldFallBackToRequestedModel_WhenResponseHasNoModel() {
        TypeSafeResult result = askTriage(new TypeSafeMock(200, OpenAIDecisionsMock.confidentTriage()));

        Assert.areEqual(OpenAIDecisionsMock.MODEL, result.model, 'Model should fall back to the requested model');
        Assert.areEqual(OpenAIDecisionsMock.INPUT_TOKENS, result.inputTokens, 'Input tokens should be parsed');
        Assert.isNull(result.outputTokens, 'Decisions bills input tokens only');
        Assert.areEqual(OpenAIDecisionsMock.MODEL, result.log.Model__c, 'Log should record the model');
    }

    @IsTest
    static void shouldUseModelFromResponse_WhenPresent() {
        String body = '{"model":"gpt-6-luna-2026-10-01","answers":[{"type":"predicate","name":"q","probability":0.4}]}';

        TypeSafeResult result = ask(
            new TypeSafeMock(200, body),
            'Help!',
            new Map<String, Object>{ 'q' => TypeSafeQuestions.noul('Is it urgent?', null, null) }
        );

        Assert.areEqual('gpt-6-luna-2026-10-01', result.model, 'Model reported by the API should win');
    }

    @IsTest
    static void shouldPostToDecisionsEndpoint_WhenAsking() {
        TypeSafeMock mock = new TypeSafeMock(200, OpenAIDecisionsMock.confidentTriage());

        askTriage(mock);

        Map<String, Object> sent = sentBody(mock);
        Assert.areEqual(OpenAIDecisionsClient.ENDPOINT, mock.lastRequest.getEndpoint(), 'Should call the OpenAI Named Credential');
        Assert.areEqual('POST', mock.lastRequest.getMethod(), 'Should POST');
        Assert.areEqual(OpenAIDecisionsMock.MODEL, sent.get('model'), 'Should send gpt-6-luna');
        Assert.areEqual('Help!', sent.get('input'), 'A string state should be sent as the input text');
        Assert.areEqual(5, ((List<Object>) sent.get('questions')).size(), 'Should send all five triage questions in one request');
    }

    @IsTest
    static void shouldTranslateNoulToPredicate_WhenAsking() {
        TypeSafeMock mock = new TypeSafeMock(200, OpenAIDecisionsMock.confidentTriage());

        askTriage(mock);

        Map<String, Object> urgency = sentQuestion(mock, 'urgency');
        String instructions = (String) urgency.get('instructions');
        Assert.areEqual('predicate', urgency.get('type'), 'Noul should become predicate');
        Assert.isTrue(instructions.contains('True when: States a deadline'), 'True criterion should be folded into instructions');
        Assert.isTrue(instructions.contains('False when: No time pressure'), 'False criterion should be folded into instructions');
    }

    @IsTest
    static void shouldTranslateChoiceCriteria_WhenAsking() {
        TypeSafeMock mock = new TypeSafeMock(200, OpenAIDecisionsMock.confidentTriage());

        askTriage(mock);

        List<Object> choices = (List<Object>) sentQuestion(mock, 'department').get('choices');
        Assert.areEqual(5, choices.size(), 'Every option should become a choice');
        Map<String, Object> first = (Map<String, Object>) choices[0];
        Assert.isNotNull(first.get('value'), 'Each choice should carry a value');
        Assert.isNotNull(first.get('description'), 'Each choice should carry its description');
    }

    @IsTest
    static void shouldSplitScoreLevels_WhenAsking() {
        TypeSafeMock mock = new TypeSafeMock(200, OpenAIDecisionsMock.confidentTriage());

        askTriage(mock);

        List<Object> levels = (List<Object>) sentQuestion(mock, 'frustration').get('levels');
        Map<String, Object> calm = (Map<String, Object>) levels[0];
        Map<String, Object> mild = (Map<String, Object>) levels[1];
        Assert.areEqual(4, levels.size(), 'Every level should be sent');
        Assert.areEqual('Calm', calm.get('label'), 'Label should be the text before the colon');
        Assert.areEqual('neutral or friendly tone', calm.get('description'), 'Description should be the text after the colon');
        Assert.areEqual('Mildly annoyed', mild.get('description'), 'A level without a colon should reuse its label');
    }

    @IsTest
    static void shouldSendJsonText_WhenStateIsMap() {
        TypeSafeMock mock = new TypeSafeMock(200, OpenAIDecisionsMock.confidentTriage());

        ask(mock, new Map<String, Object>{ 'subject' => 'AC broken' }, CaseTriageService.buildQuestions());

        Assert.areEqual('{"subject":"AC broken"}', sentBody(mock).get('input'), 'Structured state should be sent as JSON text');
    }

    @IsTest
    static void shouldSendImageParts_WhenStateIsImageInput() {
        TypeSafeMock mock = new TypeSafeMock(200, OpenAIDecisionsMock.imageCheck(0.9, 2, 0.9));
        OpenAIDecisionsClient.ImageInput input = new OpenAIDecisionsClient.ImageInput('Inspect this.', new List<String>{ PNG_DATA_URL });

        TypeSafeResult result = ask(mock, input, OpenAIImageCheck.buildQuestions());

        List<Object> messages = (List<Object>) sentBody(mock).get('input');
        List<Object> content = (List<Object>) ((Map<String, Object>) messages[0]).get('content');
        Assert.areEqual('user', ((Map<String, Object>) messages[0]).get('role'), 'Image input should be a user message');
        Assert.areEqual('input_text', ((Map<String, Object>) content[0]).get('type'), 'Text part should come first');
        Assert.areEqual(PNG_DATA_URL, ((Map<String, Object>) content[1]).get('image_url'), 'Image should be sent inline');
        Assert.isFalse(result.log.Request__c.contains('iVBORw0KGgo='), 'Image bytes should not be logged');
        Assert.isTrue(result.log.Request__c.contains('base64 chars omitted'), 'Log should note the omitted image');
    }

    @IsTest
    static void shouldThrow_WhenImageIsHostedUrl() {
        try {
            new OpenAIDecisionsClient.ImageInput('x', new List<String>{ 'https://example.com/photo.png' });
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('inline base64'), 'Message should explain the data URL rule');
        }
    }

    @IsTest
    static void shouldThrow_WhenNoImageGiven() {
        try {
            new OpenAIDecisionsClient.ImageInput('x', new List<String>());
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('At least one image'), 'Message should ask for an image');
        }
    }

    @IsTest
    static void shouldBuildDataUrl_WhenGivenBytes() {
        String dataUrl = OpenAIDecisionsClient.toDataUrl('image/png', Blob.valueOf('abc'));

        Assert.areEqual('data:image/png;base64,YWJj', dataUrl, 'Data URL should carry MIME type and base64 bytes');
    }

    @IsTest
    static void shouldThrowOnGetAnswer_WhenModelRefuses() {
        String body = OpenAIDecisionsMock.envelope(new List<Object>{ OpenAIDecisionsMock.refusal('q') });
        TypeSafeResult result = ask(
            new TypeSafeMock(200, body),
            'Help!',
            new Map<String, Object>{ 'q' => TypeSafeQuestions.noul('Is it urgent?', null, null) }
        );

        Assert.isTrue(result.isSuccess, 'A refusal is a valid response');
        Assert.isTrue(result.answers.get('q').isRefusal(), 'Answer should be marked as a refusal');
        try {
            result.getAnswer('q');
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('refused to answer "q"'), 'Message should name the refused question');
        }
    }

    @IsTest
    static void shouldReportError_WhenResponseIs400() {
        TypeSafeResult result = askTriage(new TypeSafeMock(400, '{"error":{"message":"Unknown model"}}'));

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isFalse(result.isRetryable(), 'A bad request should not be retried');
        Assert.isTrue(result.errorMessage.startsWith('HTTP 400'), 'Error should carry the status');
        Assert.isFalse(result.log.Success__c, 'Log should record failure');
    }

    @IsTest
    static void shouldBeRetryable_WhenResponseIs429() {
        TypeSafeResult result = askTriage(new TypeSafeMock(429, '{"error":{"message":"Rate limit"}}'));

        Assert.isTrue(result.isRetryable(), 'A rate limit should be retryable');
    }

    @IsTest
    static void shouldReportError_WhenCalloutThrows() {
        TypeSafeResult result = askTriage(TypeSafeMock.failing());

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isTrue(result.errorMessage.startsWith('Callout failed'), 'Error should describe the callout failure');
        Assert.isNotNull(result.log, 'A log should still be built');
    }

    @IsTest
    static void shouldReportError_WhenBodyIsNotJson() {
        TypeSafeResult result = askTriage(new TypeSafeMock(200, '<html>gateway</html>'));

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isTrue(result.errorMessage.contains('not valid JSON'), 'Error should describe the parse failure');
    }

    @IsTest
    static void shouldReportError_WhenAnswersMissing() {
        TypeSafeResult result = askTriage(new TypeSafeMock(200, '{"usage":{"input_tokens":1}}'));

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isTrue(result.errorMessage.contains('no answers'), 'Error should describe the missing answers');
    }

    @IsTest
    static void shouldReportError_WhenAnswersIsNotAList() {
        TypeSafeResult result = askTriage(new TypeSafeMock(200, '{"answers":{"urgency":{"type":"predicate"}}}'));

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isTrue(result.errorMessage.startsWith('Unexpected response shape'), 'Error should describe the bad shape');
    }

    @IsTest
    static void shouldReportError_WhenAnswerHasNoName() {
        TypeSafeResult result = askTriage(new TypeSafeMock(200, '{"answers":[{"type":"predicate","probability":0.5}]}'));

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isTrue(result.errorMessage.contains('missing its name'), 'Error should describe the unnamed answer');
    }

    @IsTest
    static void shouldReportError_WhenAnswerHasNoType() {
        TypeSafeResult result = askTriage(new TypeSafeMock(200, '{"answers":[{"name":"urgency","probability":0.5}]}'));

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isTrue(result.errorMessage.contains('missing its type'), 'Error should describe the untyped answer');
    }

    @IsTest
    static void shouldThrow_WhenQuestionTypeUnsupported() {
        Map<String, Object> questions = new Map<String, Object>{
            'q' => new Map<String, Object>{ 'type' => 'ranking', 'instructions' => 'Rank these' }
        };
        try {
            new OpenAIDecisionsClient(OpenAIDecisionsMock.openAIConfig()).ask('Help!', questions, CONTEXT, null);
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('Unsupported question type "ranking"'), 'Message should name the bad type');
        }
    }

    @IsTest
    static void shouldThrow_WhenStateIsNull() {
        try {
            new OpenAIDecisionsClient(OpenAIDecisionsMock.openAIConfig()).ask(null, CaseTriageService.buildQuestions(), CONTEXT, null);
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('state'), 'Message should mention state');
        }
    }

    @IsTest
    static void shouldThrow_WhenQuestionsEmpty() {
        try {
            new OpenAIDecisionsClient(OpenAIDecisionsMock.openAIConfig()).ask('Help!', new Map<String, Object>(), CONTEXT, null);
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('question'), 'Message should mention questions');
        }
    }
}
