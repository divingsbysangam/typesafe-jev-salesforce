/**
 * Tunable settings for Jev decisions, loaded from the TypeSafe_Setting__mdt "Default" record.
 * Every threshold the triage and guardrail code branches on lives here, so a business change
 * is a metadata edit rather than a code or prompt change. Missing values fall back to the
 * defaults below.
 *
 * Each TypeSafe_Setting__mdt record is a profile: one provider (TypeSafe Jev or OpenAI
 * Decisions), its model and its own thresholds, because probabilities from different models need
 * separately calibrated cut-offs. Default.Active_Profile__c names the profile everything uses;
 * blank means the Default record itself.
 */
public with sharing class TypeSafeConfig {
    public static final String PROFILE_DEFAULT = 'Default';
    public static final String PROFILE_OPENAI = 'OpenAI';
    public static final String OPENAI_DEFAULT_MODEL = 'gpt-6-luna';
    private static final String PROVIDER_OPENAI_VALUE = 'OpenAI';
    private static final Integer MAX_TIMEOUT_MS = 120000;

    /** Decision API behind a profile. */
    public enum ProviderType {
        TYPESAFE,
        OPENAI
    }

    public String profile = PROFILE_DEFAULT;
    public ProviderType provider = ProviderType.TYPESAFE;
    public String model = 'jev-latest';
    public Integer timeoutMs = 10000;
    /** Choice/Score answers below this confidence go to human review. */
    public Decimal confidenceMin = 0.7;
    /** Noul probability at or above which a signal triggers review. Nouls carry no confidence. */
    public Decimal noulReviewThreshold = 0.35;
    /** Noul probability at or above which a signal triggers its configured action. */
    public Decimal noulActionThreshold = 0.7;
    /** Guardrail severity score at or above which a review escalates to a block. */
    public Decimal severityBlock = 2.0;

    @TestVisible
    private static TypeSafeConfig cached;

    /**
     * @return The active configuration, cached for the transaction.
     */
    public static TypeSafeConfig current() {
        if (cached == null) {
            TypeSafe_Setting__mdt defaultSetting = TypeSafe_Setting__mdt.getInstance(PROFILE_DEFAULT);
            String activeProfile = defaultSetting?.Active_Profile__c;
            cached = String.isBlank(activeProfile) || activeProfile == PROFILE_DEFAULT
                ? fromSetting(defaultSetting)
                : forProfile(activeProfile);
        }
        return cached;
    }

    /**
     * Loads a named profile, whether or not it is active (e.g. to compare providers side by side).
     * @param profileName TypeSafe_Setting__mdt DeveloperName.
     * @return The profile's configuration.
     * @throws TypeSafeException When no such record exists.
     */
    public static TypeSafeConfig forProfile(String profileName) {
        TypeSafe_Setting__mdt setting = String.isBlank(profileName) ? null : TypeSafe_Setting__mdt.getInstance(profileName);
        if (setting == null) {
            throw new TypeSafeException('No TypeSafe_Setting__mdt profile named "' + profileName + '".');
        }
        return fromSetting(setting);
    }

    @TestVisible
    private static TypeSafeConfig fromSetting(TypeSafe_Setting__mdt setting) {
        TypeSafeConfig config = new TypeSafeConfig();
        if (setting == null) {
            return config;
        }
        config.profile = setting.DeveloperName ?? config.profile;
        config.provider = PROVIDER_OPENAI_VALUE.equalsIgnoreCase(setting.Provider__c) ? ProviderType.OPENAI : ProviderType.TYPESAFE;
        String providerDefaultModel = config.provider == ProviderType.OPENAI ? OPENAI_DEFAULT_MODEL : config.model;
        config.model = String.isBlank(setting.Model__c) ? providerDefaultModel : setting.Model__c;
        if (setting.Timeout_Ms__c != null) {
            config.timeoutMs = Math.min(Math.max(setting.Timeout_Ms__c.intValue(), 1), MAX_TIMEOUT_MS);
        }
        config.confidenceMin = setting.Confidence_Min__c ?? config.confidenceMin;
        config.noulReviewThreshold = setting.Noul_Review_Threshold__c ?? config.noulReviewThreshold;
        config.noulActionThreshold = setting.Noul_Action_Threshold__c ?? config.noulActionThreshold;
        config.severityBlock = setting.Severity_Block__c ?? config.severityBlock;
        return config;
    }
}
