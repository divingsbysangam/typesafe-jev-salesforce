/**
 * Response-body builders for the OpenAI Decisions API, shaped like the examples in OpenAI's
 * Decisions guide. Pair with TypeSafeMock, which serves any body over HttpCalloutMock.
 *
 * Bodies carry no "model" field (the guide's examples don't show one), so the client falls back
 * to the requested model.
 *
 * @example
 * Test.setMock(HttpCalloutMock.class, new TypeSafeMock(200, OpenAIDecisionsMock.confidentTriage()));
 */
@IsTest
public class OpenAIDecisionsMock {
    public static final String MODEL = 'gpt-6-luna';
    public static final Integer INPUT_TOKENS = 420;

    /**
     * @param answers Decisions answer entries.
     * @return JSON body.
     */
    public static String envelope(List<Object> answers) {
        return JSON.serialize(
            new Map<String, Object>{
                'answers' => answers,
                'usage' => new Map<String, Object>{ 'input_tokens' => INPUT_TOKENS }
            }
        );
    }

    /**
     * @return Predicate answer.
     */
    public static Map<String, Object> predicate(String name, Decimal probability) {
        return new Map<String, Object>{ 'type' => 'predicate', 'name' => name, 'probability' => probability };
    }

    /**
     * @return Choice answer with the winner at 0.85 and 'Other' at 0.15.
     */
    public static Map<String, Object> choice(String name, String choice, Decimal confidence) {
        return new Map<String, Object>{
            'type' => 'choice',
            'name' => name,
            'choice' => choice,
            'probabilities' => new List<Object>{
                new Map<String, Object>{ 'value' => choice, 'probability' => 0.85 },
                new Map<String, Object>{ 'value' => 'Other', 'probability' => 0.15 }
            },
            'confidence' => confidence
        };
    }

    /**
     * @return Score answer on four levels labelled L0-L3.
     */
    public static Map<String, Object> score(String name, Decimal score, Decimal confidence) {
        List<Object> probabilities = new List<Object>();
        List<Decimal> levelProbabilities = new List<Decimal>{ 0.1, 0.6, 0.2, 0.1 };
        for (Integer level = 0; level < levelProbabilities.size(); level++) {
            probabilities.add(
                new Map<String, Object>{
                    'value' => level,
                    'label' => 'L' + level,
                    'probability' => levelProbabilities[level]
                }
            );
        }
        return new Map<String, Object>{
            'type' => 'score',
            'name' => name,
            'score' => score,
            'probabilities' => probabilities,
            'confidence' => confidence
        };
    }

    /**
     * @return Refusal answer.
     */
    public static Map<String, Object> refusal(String name) {
        return new Map<String, Object>{ 'type' => 'refusal', 'name' => name, 'refusal' => 'I can\'t help with that.' };
    }

    /**
     * @return Triage body matching TypeSafeMock.confidentTriage(), in Decisions format.
     */
    public static String confidentTriage() {
        return envelope(
            new List<Object>{
                choice('department', 'Facilities', 0.9),
                predicate('urgency', 0.9),
                predicate('refund_requested', 0.05),
                score('frustration', 1.2, 0.85),
                score('churn_risk', 0.3, 0.9)
            }
        );
    }

    /**
     * @return Guardrail body carrying both input and output hazard names.
     */
    public static String guardrail(Decimal policy, Decimal harm, Decimal pii, Decimal selfHarm, Decimal severity) {
        return envelope(
            new List<Object>{
                predicate('jailbreak', policy),
                predicate('broke_policy', policy),
                predicate('harmful_request', harm),
                predicate('pii_shared', pii),
                predicate('pii_leak', pii),
                predicate('self_harm', selfHarm),
                score('severity', severity, 0.9)
            }
        );
    }

    /**
     * @return Image-check body.
     */
    public static String imageCheck(Decimal visibleDamage, Decimal severity, Decimal severityConfidence) {
        return envelope(
            new List<Object>{
                predicate('visible_damage', visibleDamage),
                score('damage_severity', severity, severityConfidence)
            }
        );
    }

    /**
     * @return An in-memory OpenAI profile (no custom metadata record needed).
     */
    public static TypeSafeConfig openAIConfig() {
        return TypeSafeConfig.fromSetting(new TypeSafe_Setting__mdt(Provider__c = 'OpenAI'));
    }
}
