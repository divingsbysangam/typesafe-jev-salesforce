// Live TypeSafe latency probe from inside the org. Saves one TypeSafe_Log__c per call.
TypeSafeLatencyProbe.Summary summary = TypeSafeLatencyProbe.run(20);
System.debug(LoggingLevel.ERROR, 'PROBE_RESULT ' + summary.toText());
