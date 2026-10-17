/**
 * One typed answer from TypeSafe. Which fields are populated depends on the type:
 * noul -> noul; choice -> choice, probabilities, confidence;
 * score -> score, legend, probabilities, confidence. Noul answers never carry a confidence.
 * OpenAI Decisions answers use the same fields: a predicate's probability is stored in noul, and
 * a refusal (OpenAI only) has type 'refusal' and the model's message in refusal.
 */
public class TypeSafeAnswer {
    public static final String TYPE_REFUSAL = 'refusal';

    public String type;
    public String refusal;
    public String choice;
    public Decimal noul;
    public Decimal score;
    public Decimal confidence;
    public Map<String, Decimal> probabilities = new Map<String, Decimal>();
    public Map<String, String> legend = new Map<String, String>();

    /**
     * @param raw One entry of the response "answers" map, from JSON.deserializeUntyped.
     * @return The parsed answer.
     * @throws TypeSafeException When the entry has no type.
     */
    public static TypeSafeAnswer fromMap(Map<String, Object> raw) {
        if (raw == null || raw.get('type') == null) {
            throw new TypeSafeException('Answer is missing its type.');
        }
        TypeSafeAnswer answer = new TypeSafeAnswer();
        answer.type = (String) raw.get('type');
        answer.choice = (String) raw.get('choice');
        answer.noul = toDecimal(raw.get('noul'));
        answer.score = toDecimal(raw.get('score'));
        answer.confidence = toDecimal(raw.get('confidence'));

        Map<String, Object> rawProbabilities = (Map<String, Object>) raw.get('probabilities');
        if (rawProbabilities != null) {
            for (String option : rawProbabilities.keySet()) {
                answer.probabilities.put(option, toDecimal(rawProbabilities.get(option)));
            }
        }
        Map<String, Object> rawLegend = (Map<String, Object>) raw.get('legend');
        if (rawLegend != null) {
            for (String level : rawLegend.keySet()) {
                answer.legend.put(level, String.valueOf(rawLegend.get(level)));
            }
        }
        return answer;
    }

    /**
     * @return True when the model declined to answer this question.
     */
    public Boolean isRefusal() {
        return type == TYPE_REFUSAL;
    }

    private static Decimal toDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }
}
