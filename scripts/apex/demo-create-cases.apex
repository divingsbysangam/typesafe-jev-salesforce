// Demo: three resort cases. The Case trigger marks them Pending and queues live Jev triage.
List<Case> cases = new List<Case>{
    new Case(Subject = 'Villa AC not working', Description = 'The air conditioning in villa 12 stopped working last night and my kids could not sleep at all. Please send someone to fix it today.', Origin = 'Web'),
    new Case(Subject = 'Charged twice for spa package', Description = 'I was charged twice for the couples spa package. This is the second time I am writing about it and nobody has replied. Refund the duplicate charge today or we will never book Coral Cloud again.', Origin = 'Email'),
    new Case(Subject = 'Move dinner reservation', Description = 'Hi! Could we move our dinner reservation at the Beach Grill tomorrow from 7pm to 8pm? Thanks so much.', Origin = 'Phone')
};
insert cases;
List<String> ids = new List<String>();
for (Case c : cases) {
    ids.add(c.Id);
}
System.debug(LoggingLevel.ERROR, 'DEMO_CASES ' + String.join(ids, ','));
