/**
 * Picks the decision API for a configuration profile. The active profile is set on the
 * TypeSafe_Setting__mdt "Default" record (Active_Profile__c), so switching Jev <-> OpenAI is a
 * metadata edit, not a code change.
 *
 * @example
 * IDecisionProvider client = DecisionProviders.forConfig(TypeSafeConfig.current());
 */
public with sharing class DecisionProviders {
    private DecisionProviders() {
    }

    /**
     * @param config Profile to build a client for; null means the active profile.
     * @return OpenAIDecisionsClient for an OpenAI profile, otherwise TypeSafeClient.
     */
    public static IDecisionProvider forConfig(TypeSafeConfig config) {
        TypeSafeConfig resolved = config ?? TypeSafeConfig.current();
        if (resolved.provider == TypeSafeConfig.ProviderType.OPENAI) {
            return new OpenAIDecisionsClient(resolved);
        }
        return new TypeSafeClient(resolved);
    }
}
