/**
 * HttpCalloutMock for the TypeSafe API, with builders for realistic response bodies.
 */
@IsTest
public class TypeSafeMock implements HttpCalloutMock {
    public static final String MODEL = 'jev-1.13.0';

    public Integer statusCode;
    public String body;
    public Boolean throwCalloutException = false;
    public Integer callCount = 0;
    public HttpRequest lastRequest;

    /**
     * @param statusCode HTTP status to return.
     * @param body Response body.
     */
    public TypeSafeMock(Integer statusCode, String body) {
        this.statusCode = statusCode;
        this.body = body;
    }

    /**
     * @return A mock whose every call throws CalloutException (e.g. a timeout).
     */
    public static TypeSafeMock failing() {
        TypeSafeMock mock = new TypeSafeMock(0, null);
        mock.throwCalloutException = true;
        return mock;
    }

    /**
     * @param request The outgoing request.
     * @return The canned response.
     */
    public HttpResponse respond(HttpRequest request) {
        callCount++;
        lastRequest = request;
        if (throwCalloutException) {
            throw new CalloutException('Read timed out');
        }
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setHeader('Content-Type', 'application/json');
        response.setBody(body ?? '');
        return response;
    }

    /**
     * Wraps answers in the TypeSafe response envelope.
     * @param answers Question id to answer map.
     * @return JSON body.
     */
    public static String envelope(Map<String, Object> answers) {
        return JSON.serialize(
            new Map<String, Object>{
                'model' => MODEL,
                'answers' => answers,
                'usage' => new Map<String, Object>{ 'input_tokens' => 312, 'output_tokens' => 48 }
            }
        );
    }

    /**
     * @param probability Probability of yes.
     * @return Noul answer.
     */
    public static Map<String, Object> noul(Decimal probability) {
        return new Map<String, Object>{ 'type' => 'noul', 'noul' => probability };
    }

    /**
     * @param choice Winning option.
     * @param confidence Confidence.
     * @return Choice answer with the winner at 0.85.
     */
    public static Map<String, Object> choice(String choice, Decimal confidence) {
        return new Map<String, Object>{
            'type' => 'choice',
            'choice' => choice,
            'probabilities' => new Map<String, Object>{ choice => 0.85, 'Other' => 0.15 },
            'confidence' => confidence
        };
    }

    /**
     * @param score Probability-weighted score.
     * @param confidence Confidence.
     * @return Score answer on a four-level legend.
     */
    public static Map<String, Object> score(Decimal score, Decimal confidence) {
        return new Map<String, Object>{
            'type' => 'score',
            'score' => score,
            'legend' => new Map<String, Object>{ '0' => 'L0', '1' => 'L1', '2' => 'L2', '3' => 'L3' },
            'probabilities' => new Map<String, Object>{ '0' => 0.1, '1' => 0.6, '2' => 0.2, '3' => 0.1 },
            'confidence' => confidence
        };
    }

    /**
     * @return A triage response where every answer is confident and nothing needs review.
     */
    public static String confidentTriage() {
        return triage('Facilities', 0.9, 0.9, 0.05, 1.2, 0.85, 0.3, 0.9);
    }

    /**
     * @return Triage response body.
     */
    public static String triage(
        String department,
        Decimal departmentConfidence,
        Decimal urgency,
        Decimal refund,
        Decimal frustration,
        Decimal frustrationConfidence,
        Decimal churn,
        Decimal churnConfidence
    ) {
        return envelope(
            new Map<String, Object>{
                'department' => choice(department, departmentConfidence),
                'urgency' => noul(urgency),
                'refund_requested' => noul(refund),
                'frustration' => score(frustration, frustrationConfidence),
                'churn_risk' => score(churn, churnConfidence)
            }
        );
    }

    /**
     * @return Guardrail response body carrying both input and output hazard keys.
     */
    public static String guardrail(Decimal policy, Decimal harm, Decimal pii, Decimal selfHarm, Decimal severity) {
        return envelope(
            new Map<String, Object>{
                'jailbreak' => noul(policy),
                'broke_policy' => noul(policy),
                'harmful_request' => noul(harm),
                'pii_shared' => noul(pii),
                'pii_leak' => noul(pii),
                'self_harm' => noul(selfHarm),
                'severity' => score(severity, 0.9)
            }
        );
    }
}
