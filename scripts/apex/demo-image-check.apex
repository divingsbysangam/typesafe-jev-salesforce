// Demo: OpenAI Decisions image check. Attach a photo (PNG/JPG, under 2 MB) to a case first, then
// put its case number below. Writes TS Visible Damage / TS Damage Severity on the case.
String caseNumber = '00001234';
Case target = [SELECT Id FROM Case WHERE CaseNumber = :caseNumber WITH USER_MODE LIMIT 1];
OpenAIImageCheck.Request request = new OpenAIImageCheck.Request();
request.caseId = target.Id;
OpenAIImageCheck.Response response = OpenAIImageCheck.check(new List<OpenAIImageCheck.Request>{ request })[0];
System.debug(LoggingLevel.ERROR, 'IMAGE_ROW ' + JSON.serialize(new Map<String, Object>{
    'case' => caseNumber,
    'file' => response.fileName,
    'visible_damage' => response.visibleDamage,
    'severity' => response.damageSeverity,
    'severity_conf' => response.damageSeverityConfidence,
    'needs_review' => response.needsReview,
    'case_updated' => response.caseUpdated,
    'model' => response.model,
    'latency_ms' => response.latencyMs,
    'ok' => response.isSuccess,
    'error' => response.errorMessage
}));
