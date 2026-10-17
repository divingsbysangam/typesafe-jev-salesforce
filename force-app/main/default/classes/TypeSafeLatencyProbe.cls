/**
 * Measures TypeSafe latency from inside the org, where callouts actually originate (the org's
 * Salesforce data center, not the developer's laptop). Run from Anonymous Apex; every call is
 * saved as a TypeSafe_Log__c with Context = Latency_Probe so you can report on it.
 *
 * The first call includes TLS setup, so it is reported separately as the cold call.
 *
 * @example
 * System.debug(TypeSafeLatencyProbe.run(20).toText());
 */
public with sharing class TypeSafeLatencyProbe {
    public static final String CONTEXT = 'Latency_Probe';
    @TestVisible
    private static final Integer MAX_CALLS = 50;
    private static final String SAMPLE_STATE = 'Help! My payouts have been failing for 3 days and my customers are angry.';

    /**
     * @param callCount Number of sequential calls (1-50; each counts against the 100-callout limit).
     * @return Latency summary.
     */
    public static Summary run(Integer callCount) {
        Integer calls = Math.min(Math.max(callCount ?? 1, 1), MAX_CALLS);
        IDecisionProvider client = DecisionProviders.forConfig(TypeSafeConfig.current());
        Map<String, Object> questions = sampleQuestions();

        Summary summary = new Summary();
        summary.instanceName = [SELECT InstanceName FROM Organization WITH USER_MODE LIMIT 1]?.InstanceName;
        List<TypeSafe_Log__c> logs = new List<TypeSafe_Log__c>();
        List<Long> warmLatencies = new List<Long>();
        for (Integer i = 0; i < calls; i++) {
            TypeSafeResult result = client.ask(SAMPLE_STATE, questions, CONTEXT, null);
            result.log.Outcome__c = 'call ' + (i + 1) + (i == 0 ? ' (cold)' : '');
            logs.add(result.log);
            summary.calls++;
            if (!result.isSuccess) {
                summary.lastError = result.errorMessage;
                continue;
            }
            summary.successes++;
            summary.model = result.model;
            if (i == 0) {
                summary.coldMs = result.latencyMs;
            } else {
                warmLatencies.add(result.latencyMs);
            }
        }
        TypeSafeLogger.save(logs);
        summary.setWarmStats(warmLatencies);
        return summary;
    }

    private static Map<String, Object> sampleQuestions() {
        return new Map<String, Object>{
            'is_urgent' => TypeSafeQuestions.noul('Does this convey urgency?', 'Explicitly time-sensitive', 'No urgency expressed'),
            'department' => TypeSafeQuestions.choice(
                'Which team should handle this?',
                new Map<String, String>{
                    'billing' => 'Payments, invoicing, refunds',
                    'technical' => 'Bugs, outages, integrations',
                    'sales' => 'Pricing, upgrades, new accounts'
                }
            ),
            'frustration' => TypeSafeQuestions.score(
                'How frustrated is the customer?',
                new List<String>{ 'Calm', 'Frustrated', 'Very angry' }
            )
        };
    }

    /**
     * Latency results. Warm stats exclude the first (cold) call.
     */
    public class Summary {
        public Integer calls = 0;
        public Integer successes = 0;
        public String instanceName;
        public String model;
        public Long coldMs;
        public Long minMs;
        public Long p50Ms;
        public Long p95Ms;
        public Long maxMs;
        public String lastError;

        /**
         * @param latencies Warm-call latencies in ms.
         */
        public void setWarmStats(List<Long> latencies) {
            if (latencies.isEmpty()) {
                return;
            }
            List<Long> sorted = latencies.clone();
            sorted.sort();
            minMs = sorted[0];
            maxMs = sorted[sorted.size() - 1];
            p50Ms = percentile(sorted, 0.50);
            p95Ms = percentile(sorted, 0.95);
        }

        private Long percentile(List<Long> sorted, Decimal fraction) {
            Integer index = Math.ceil(fraction * sorted.size()).intValue() - 1;
            return sorted[Math.min(Math.max(index, 0), sorted.size() - 1)];
        }

        /**
         * @return One-line summary for the debug log.
         */
        public String toText() {
            return 'TypeSafe latency from instance ' + instanceName + ' (' + model + '): ' +
                successes + '/' + calls + ' ok | cold ' + coldMs + 'ms | warm min ' + minMs +
                'ms, p50 ' + p50Ms + 'ms, p95 ' + p95Ms + 'ms, max ' + maxMs + 'ms' +
                (lastError == null ? '' : ' | last error: ' + lastError);
        }
    }
}
