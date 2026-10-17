/**
 * Builders for the three TypeSafe question types. Each returns the JSON-ready map for one entry
 * in the request's "questions" map.
 *
 * @example
 * Map<String, Object> questions = new Map<String, Object>{
 *     'is_urgent' => TypeSafeQuestions.noul('Does this convey urgency?', 'Explicitly time-sensitive', 'No urgency expressed'),
 *     'frustration' => TypeSafeQuestions.score('How frustrated is the customer?', new List<String>{ 'Calm', 'Frustrated', 'Very angry' })
 * };
 */
public with sharing class TypeSafeQuestions {
    private TypeSafeQuestions() {
    }

    /**
     * Yes/no question. The answer is the probability (0-1) that the answer is yes.
     * @param instructions The yes/no question.
     * @param whenTrue What a yes means (optional).
     * @param whenFalse What a no means (optional).
     * @return Question map.
     * @throws TypeSafeException When instructions are blank.
     */
    public static Map<String, Object> noul(String instructions, String whenTrue, String whenFalse) {
        Map<String, Object> question = base('noul', instructions);
        Map<String, Object> criteria = new Map<String, Object>();
        if (String.isNotBlank(whenTrue)) {
            criteria.put('true', whenTrue);
        }
        if (String.isNotBlank(whenFalse)) {
            criteria.put('false', whenFalse);
        }
        if (!criteria.isEmpty()) {
            question.put('criteria', criteria);
        }
        return question;
    }

    /**
     * Pick one option from a set. Map values are rubric descriptions; null means no extra detail.
     * @param instructions What the model should decide.
     * @param options Option key to description.
     * @return Question map.
     * @throws TypeSafeException When instructions are blank or fewer than two options are given.
     */
    public static Map<String, Object> choice(String instructions, Map<String, String> options) {
        if (options == null || options.size() < 2) {
            throw new TypeSafeException('A choice question needs at least two options.');
        }
        Map<String, Object> question = base('choice', instructions);
        question.put('criteria', options);
        return question;
    }

    /**
     * Rate the state on ordered levels. Level 0 is the first entry.
     * @param instructions What the model should rate.
     * @param levels Ordered level descriptions, lowest first.
     * @return Question map.
     * @throws TypeSafeException When instructions are blank or fewer than two levels are given.
     */
    public static Map<String, Object> score(String instructions, List<String> levels) {
        if (levels == null || levels.size() < 2) {
            throw new TypeSafeException('A score question needs at least two levels.');
        }
        Map<String, Object> question = base('score', instructions);
        question.put('criteria', levels);
        return question;
    }

    private static Map<String, Object> base(String type, String instructions) {
        if (String.isBlank(instructions)) {
            throw new TypeSafeException('Question instructions are required.');
        }
        return new Map<String, Object>{ 'type' => type, 'instructions' => instructions };
    }
}
