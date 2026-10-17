/**
 * Service Cloud case triage with Jev. For each case, one TypeSafe request asks five questions in
 * parallel (department Choice, urgency and refund Nouls, frustration and churn Scores). Jev
 * returns the answers; the thresholds in TypeSafeConfig then decide the priority and whether the
 * case can be routed automatically or needs a human. Queue assignment happens in the
 * TypeSafe_Case_Routing flow, which branches on the typed fields written here. The same questions
 * run on OpenAI Decisions (gpt-6-luna) when the active TypeSafe_Setting__mdt profile says so.
 *
 * Runs WITHOUT SHARING and in SYSTEM_MODE on purpose: triage is back-end automation started by
 * the Case trigger, and the user who created a case often cannot see it afterwards (Email-to-Case,
 * Web-to-Case, assignment rules moving it to a queue). No user input selects records here: the
 * job only reads Subject/Description/Origin and writes the TS_* fields and Priority on the exact
 * case Ids the trigger handed over. Not exposed to Flow, LWC or the API.
 */
public without sharing class CaseTriageService {
    public static final String CONTEXT = 'Case_Triage';
    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_AUTO_ROUTED = 'Auto_Routed';
    public static final String STATUS_NEEDS_REVIEW = 'Needs_Review';
    public static final String STATUS_ERROR = 'Error';

    @TestVisible
    private static final String Q_DEPARTMENT = 'department';
    @TestVisible
    private static final String Q_URGENCY = 'urgency';
    @TestVisible
    private static final String Q_REFUND = 'refund_requested';
    @TestVisible
    private static final String Q_FRUSTRATION = 'frustration';
    @TestVisible
    private static final String Q_CHURN = 'churn_risk';

    private static final String DEPARTMENT_BILLING = 'Billing';
    private static final Decimal HIGH_SCORE_LEVEL = 2;
    private static final Decimal MEDIUM_SCORE_LEVEL = 1;
    private static final Integer MAX_REASON = 255;

    /**
     * Calls Jev once per case, writes the typed answers and routing decision to each case, and
     * saves one audit log per call. Rate-limited calls are left untouched when retry is allowed.
     * @param caseIds Cases to triage (at most 100 per transaction because of the callout limit).
     * @param allowRetry When false, rate-limited cases are marked Error instead of returned.
     * @return Ids of cases that hit a rate limit and should be retried later.
     */
    public static Set<Id> triage(Set<Id> caseIds, Boolean allowRetry) {
        Set<Id> retryableIds = new Set<Id>();
        List<Case> cases = CaseSelector.selectForTriage(caseIds);
        if (cases.isEmpty()) {
            return retryableIds;
        }
        TypeSafeConfig config = TypeSafeConfig.current();
        IDecisionProvider client = DecisionProviders.forConfig(config);
        Map<String, Object> questions = buildQuestions();

        List<Case> updates = new List<Case>();
        List<TypeSafe_Log__c> logs = new List<TypeSafe_Log__c>();
        for (Case source : cases) {
            TypeSafeResult result = client.ask(buildState(source), questions, CONTEXT, source.Id);
            logs.add(result.log);
            if (result.isRetryable() && allowRetry == true) {
                result.log.Outcome__c = 'retry_scheduled';
                retryableIds.add(source.Id);
                continue;
            }
            Case decided = decide(source, result, config);
            result.log.Outcome__c = decided.TS_Triage_Status__c;
            updates.add(decided);
        }
        // All callouts are done; DML is safe from here on.
        TypeSafeLogger.save(logs, AccessLevel.SYSTEM_MODE);
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.SYSTEM_MODE);
        }
        return retryableIds;
    }

    /**
     * Marks cases as failed so they don't sit in Pending forever.
     * @param caseIds Cases to mark.
     * @param reason Short failure reason.
     */
    public static void markError(Set<Id> caseIds, String reason) {
        if (caseIds == null || caseIds.isEmpty()) {
            return;
        }
        List<Case> updates = new List<Case>();
        for (Id caseId : caseIds) {
            updates.add(
                new Case(
                    Id = caseId,
                    TS_Triage_Status__c = STATUS_ERROR,
                    TS_Triage_Reason__c = reason?.abbreviate(MAX_REASON)
                )
            );
        }
        Database.update(updates, AccessLevel.SYSTEM_MODE);
    }

    /**
     * The five triage questions, asked in one request. Criteria spell out boundary cases because
     * Jev reads instructions literally.
     * @return Question id to question map.
     */
    public static Map<String, Object> buildQuestions() {
        return new Map<String, Object>{
            Q_DEPARTMENT => TypeSafeQuestions.choice(
                'Which Coral Cloud Resorts team should own this guest case?',
                new Map<String, String>{
                    'Facilities' => 'Anything broken or not working in the room, villa or grounds: air conditioning, plumbing, power, Wi-Fi, cleanliness, noise, maintenance',
                    'Reservations' => 'Booking, changing or cancelling stays, activities, spa or dining reservations, dates, room types, late checkout',
                    'Guest_Services' => 'On-site help and experience: concierge requests, lost items, transport, complaints about staff or service, special occasions',
                    'Billing' => 'Charges, invoices, deposits, refunds, payment problems, pricing on an existing booking',
                    'Other' => 'Anything that does not clearly belong to one of the teams above'
                }
            ),
            Q_URGENCY => TypeSafeQuestions.noul(
                'Does the customer say this is time-sensitive or is blocking their work right now?',
                'States a deadline, an outage, or that work or revenue is blocked now',
                'No time pressure is stated'
            ),
            Q_REFUND => TypeSafeQuestions.noul(
                'Does the customer ask for a refund, a credit, or their money back?',
                'Explicitly asks for money back or a credit',
                'Does not ask for money back or a credit'
            ),
            Q_FRUSTRATION => TypeSafeQuestions.score(
                'How frustrated is the customer?',
                new List<String>{
                    'Calm: neutral or friendly tone',
                    'Mildly annoyed',
                    'Frustrated: clear dissatisfaction or mentions repeated contact',
                    'Furious: angry, hostile, or shouting'
                }
            ),
            Q_CHURN => TypeSafeQuestions.score(
                'Based only on what they wrote, how likely is this customer to leave?',
                new List<String>{
                    'None: no sign of leaving',
                    'Low: general disappointment',
                    'Elevated: mentions competitors or questions whether the product is worth it',
                    'Explicit: says they will cancel or leave'
                }
            )
        };
    }

    /**
     * Converts Jev's answers into case field values and a routing decision.
     * @param source The case that was evaluated.
     * @param result The TypeSafe result for that case.
     * @param config Thresholds.
     * @return A case sObject holding only the fields to update.
     */
    @TestVisible
    private static Case decide(Case source, TypeSafeResult result, TypeSafeConfig config) {
        Case updated = new Case(Id = source.Id);
        if (!result.isSuccess) {
            return withError(updated, result.errorMessage);
        }
        try {
            TypeSafeAnswer department = result.getAnswer(Q_DEPARTMENT);
            TypeSafeAnswer urgency = result.getAnswer(Q_URGENCY);
            TypeSafeAnswer refund = result.getAnswer(Q_REFUND);
            TypeSafeAnswer frustration = result.getAnswer(Q_FRUSTRATION);
            TypeSafeAnswer churn = result.getAnswer(Q_CHURN);

            updated.TS_Department__c = department.choice;
            updated.TS_Department_Confidence__c = department.confidence;
            updated.TS_Urgency__c = urgency.noul;
            updated.TS_Refund_Requested__c = refund.noul;
            updated.TS_Frustration__c = frustration.score;
            updated.TS_Frustration_Confidence__c = frustration.confidence;
            updated.TS_Churn_Risk__c = churn.score;
            updated.TS_Churn_Risk_Confidence__c = churn.confidence;
            updated.TS_Model__c = result.model;
            updated.Priority = derivePriority(urgency.noul, frustration.score, churn.score, config);

            List<String> reviewReasons = new List<String>();
            addIfUncertain(reviewReasons, 'department', department.confidence, config);
            addIfUncertain(reviewReasons, 'frustration', frustration.confidence, config);
            addIfUncertain(reviewReasons, 'churn risk', churn.confidence, config);
            if ((refund.noul ?? 0) >= config.noulActionThreshold && department.choice != DEPARTMENT_BILLING) {
                reviewReasons.add('refund requested but routed to ' + department.choice);
            }

            updated.TS_Triage_Status__c = reviewReasons.isEmpty() ? STATUS_AUTO_ROUTED : STATUS_NEEDS_REVIEW;
            updated.TS_Triage_Reason__c = reviewReasons.isEmpty()
                ? 'All answers above thresholds'
                : String.join(reviewReasons, '; ').abbreviate(MAX_REASON);
        } catch (TypeSafeException e) {
            return withError(new Case(Id = source.Id), e.getMessage());
        }
        return updated;
    }

    @TestVisible
    private static String derivePriority(Decimal urgency, Decimal frustration, Decimal churn, TypeSafeConfig config) {
        Decimal urgencyValue = urgency ?? 0;
        Decimal frustrationValue = frustration ?? 0;
        Decimal churnValue = churn ?? 0;
        if (
            urgencyValue >= config.noulActionThreshold ||
            frustrationValue >= HIGH_SCORE_LEVEL ||
            churnValue >= HIGH_SCORE_LEVEL
        ) {
            return 'High';
        }
        if (urgencyValue >= config.noulReviewThreshold || frustrationValue >= MEDIUM_SCORE_LEVEL) {
            return 'Medium';
        }
        return 'Low';
    }

    private static void addIfUncertain(List<String> reasons, String label, Decimal confidence, TypeSafeConfig config) {
        Decimal value = confidence ?? 0;
        if (value < config.confidenceMin) {
            reasons.add(label + ' confidence ' + value.setScale(2));
        }
    }

    private static Map<String, Object> buildState(Case source) {
        // Only the fields the questions need: large irrelevant state lowers Jev's accuracy.
        return new Map<String, Object>{
            'subject' => source.Subject ?? '',
            'description' => source.Description ?? '',
            'channel' => source.Origin ?? ''
        };
    }

    private static Case withError(Case updated, String message) {
        updated.TS_Triage_Status__c = STATUS_ERROR;
        updated.TS_Triage_Reason__c = (message ?? 'Unknown TypeSafe error').abbreviate(MAX_REASON);
        return updated;
    }
}
