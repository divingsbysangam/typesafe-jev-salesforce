@IsTest
private class TypeSafeQuestionsTest {
    @IsTest
    static void shouldBuildNoulWithCriteria_WhenDescriptionsGiven() {
        Map<String, Object> question = TypeSafeQuestions.noul('Is it urgent?', 'Yes, urgent', 'Not urgent');

        Map<String, Object> criteria = (Map<String, Object>) question.get('criteria');
        Assert.areEqual('noul', question.get('type'), 'Type should be noul');
        Assert.areEqual('Is it urgent?', question.get('instructions'), 'Instructions should be kept');
        Assert.areEqual('Yes, urgent', criteria.get('true'), 'True criterion should be set');
        Assert.areEqual('Not urgent', criteria.get('false'), 'False criterion should be set');
    }

    @IsTest
    static void shouldOmitNoulCriteria_WhenDescriptionsBlank() {
        Map<String, Object> question = TypeSafeQuestions.noul('Is it urgent?', null, ' ');

        Assert.isFalse(question.containsKey('criteria'), 'Criteria should be omitted when both descriptions are blank');
    }

    @IsTest
    static void shouldBuildChoice_WhenTwoOrMoreOptions() {
        Map<String, String> options = new Map<String, String>{ 'a' => 'Option A', 'b' => null };

        Map<String, Object> question = TypeSafeQuestions.choice('Pick one', options);

        Assert.areEqual('choice', question.get('type'), 'Type should be choice');
        Assert.areEqual(options, question.get('criteria'), 'Options should be the criteria map');
    }

    @IsTest
    static void shouldThrow_WhenChoiceHasOneOption() {
        try {
            TypeSafeQuestions.choice('Pick one', new Map<String, String>{ 'a' => 'Only' });
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('two options'), 'Message should explain the minimum');
        }
    }

    @IsTest
    static void shouldBuildScore_WhenTwoOrMoreLevels() {
        List<String> levels = new List<String>{ 'Calm', 'Angry' };

        Map<String, Object> question = TypeSafeQuestions.score('How angry?', levels);

        Assert.areEqual('score', question.get('type'), 'Type should be score');
        Assert.areEqual(levels, question.get('criteria'), 'Levels should be the criteria list');
    }

    @IsTest
    static void shouldThrow_WhenScoreHasOneLevel() {
        try {
            TypeSafeQuestions.score('How angry?', new List<String>{ 'Calm' });
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('two levels'), 'Message should explain the minimum');
        }
    }

    @IsTest
    static void shouldThrow_WhenInstructionsBlank() {
        try {
            TypeSafeQuestions.noul('', null, null);
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('instructions'), 'Message should mention instructions');
        }
    }
}
