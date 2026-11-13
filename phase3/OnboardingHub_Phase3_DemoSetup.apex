// ============================================================
// Onboarding Hub — Phase 3 Demo (Execute Anonymous)
// Run AFTER deploying Phase 3 metadata and assigning OnboardingHub_Phase3.
// Sends reminders across channels (Email + In-App real, Slack/SMS simulated unless
// endpoints are configured), generates the design PDF, and logs everything.
// ============================================================

// 1. Find the Lakeside checklist and an open required item
Checklist__c cl = [
    SELECT Id, Contact__c, Contact__r.Email
    FROM Checklist__c
    WHERE Account__r.Name = 'Lakeside Regional Holdings'
    ORDER BY CreatedDate DESC LIMIT 1
];
Checklist_Item__c item = [
    SELECT Id, Title__c
    FROM Checklist_Item__c
    WHERE Checklist__c = :cl.Id AND Status__c != 'Completed'
    ORDER BY Sequence__c ASC NULLS LAST LIMIT 1
];

String to = (cl.Contact__r != null && cl.Contact__r.Email != null)
            ? cl.Contact__r.Email : UserInfo.getUserEmail();

// 2. Fire one notification per channel (callouts first, then insert logs)
List<OnboardingNotifier.Outcome> outs = new List<OnboardingNotifier.Outcome>{
    OnboardingNotifier.dispatch(item, 'Email',  'Reminder: ' + item.Title__c, 'Please complete your onboarding task.', to),
    OnboardingNotifier.dispatch(item, 'In-App', 'Reminder: ' + item.Title__c, 'Please complete your onboarding task.', null),
    OnboardingNotifier.dispatch(item, 'Slack',  'Reminder',                    'Overdue onboarding item for Lakeside.', null),
    OnboardingNotifier.dispatch(item, 'SMS',    'Reminder',                    'Your onboarding task is due.', to)
};
List<Notification_Log__c> logs = new List<Notification_Log__c>();
for (OnboardingNotifier.Outcome o : outs) {
    logs.add(o.logRecord);
    System.debug(o.channel + ' -> ' + o.status + (o.detail == null ? '' : ' (' + o.detail + ')'));
}
insert logs;

// 3. Generate + (email) the design PDF
OnboardingDocGenerator.Result doc = OnboardingDocGenerator.run(cl.Id, to);

System.debug('========================================');
System.debug('PHASE 3 DEMO READY');
System.debug('Notifications logged: ' + logs.size() + ' (see Notification_Log__c)');
System.debug('Document: ' + doc.status + ' | ContentVersion ' + doc.contentVersionId);
System.debug('To schedule daily reminders: OnboardingReminderScheduler.scheduleDaily();');
System.debug('Slack/SMS show "Simulated" until you enable them in Onboarding_Channel_Config (Custom Metadata) + a Remote Site Setting.');
System.debug('========================================');
