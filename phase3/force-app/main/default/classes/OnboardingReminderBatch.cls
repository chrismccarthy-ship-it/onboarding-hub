/**
 * OnboardingReminderBatch — finds required, portal-visible items that are overdue or due soon
 * and dispatches reminders through OnboardingNotifier, with an escalation ladder:
 *   level 0 = reminder (upcoming), 1 = overdue nudge, 2+ = escalate (also pings the
 *   checklist's Onboarding Specialist in-app; falls back to the checklist owner).
 *
 * A quiet-period guard (quietDays) suppresses items reminded within the last N days, so an
 * overdue item is not pinged on every run. Counters (Reminder_Count__c, Last_Reminder_Date__c,
 * Escalation_Level__c) are maintained per run.
 *
 * All HTTP callouts happen before the DML at the end of execute() — required by the platform.
 */
public with sharing class OnboardingReminderBatch
        implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    public Integer dueWindowDays = 3;   // remind for items due within N days (or already overdue)
    public Integer quietDays     = 2;   // do not re-remind an item reminded within the last N days
    public Integer processed     = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date cutoff = Date.today().addDays(dueWindowDays);
        Datetime quietCutoff = System.now().addDays(-quietDays);
        return Database.getQueryLocator([
            SELECT Id, Title__c, Status__c, Due_Date__c, Required__c, Visible_In_Portal__c,
                   Reminder_Count__c, Reminder_Channel__c, Escalation_Level__c, Last_Reminder_Date__c,
                   Checklist__c, Checklist__r.Contact__c, Checklist__r.Contact__r.Email,
                   Checklist__r.Onboarding_Specialist__c, Checklist__r.OwnerId
            FROM Checklist_Item__c
            WHERE Status__c != 'Completed'
              AND Required__c = true
              AND Visible_In_Portal__c = true
              AND Due_Date__c != null
              AND Due_Date__c <= :cutoff
              AND (Last_Reminder_Date__c = null OR Last_Reminder_Date__c < :quietCutoff)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Checklist_Item__c> scope) {
        List<Notification_Log__c> logs = new List<Notification_Log__c>();
        List<Checklist_Item__c> toUpdate = new List<Checklist_Item__c>();
        Date today = Date.today();

        for (Checklist_Item__c item : scope) {
            Integer count = (item.Reminder_Count__c == null) ? 0 : Integer.valueOf(item.Reminder_Count__c);
            Boolean overdue = item.Due_Date__c < today;
            Integer level = overdue ? Math.min(count, 2) : 0;

            String channel = String.isNotBlank(item.Reminder_Channel__c) ? item.Reminder_Channel__c : 'Email';
            String recipient = (item.Checklist__r != null && item.Checklist__r.Contact__r != null)
                               ? item.Checklist__r.Contact__r.Email : null;
            String subject = (overdue ? 'Overdue: ' : 'Reminder: ') + item.Title__c;

            // client-facing reminder on the item's channel
            logs.add(OnboardingNotifier.dispatch(item, channel, subject, buildBody(item, overdue, level), recipient).logRecord);

            // escalation: ping the specialist (or owner) in-app
            if (level >= 2) {
                Set<Id> escalateTo = new Set<Id>();
                if (item.Checklist__r != null) {
                    if (item.Checklist__r.Onboarding_Specialist__c != null) escalateTo.add(item.Checklist__r.Onboarding_Specialist__c);
                    else if (item.Checklist__r.OwnerId != null)             escalateTo.add(item.Checklist__r.OwnerId);
                }
                logs.add(OnboardingNotifier.dispatch(
                    item, 'In-App', 'Escalation: ' + item.Title__c,
                    'Overdue after ' + count + ' reminders with no completion — please follow up with the client.',
                    null, escalateTo).logRecord);
            }

            item.Reminder_Count__c = count + 1;
            item.Last_Reminder_Date__c = System.now();
            item.Escalation_Level__c = level;
            toUpdate.add(item);
            processed++;
        }

        if (!logs.isEmpty())     insert logs;
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('OnboardingReminderBatch processed ' + processed + ' item(s).');
    }

    private String buildBody(Checklist_Item__c item, Boolean overdue, Integer level) {
        String due = (item.Due_Date__c == null) ? '' : ' (due ' + item.Due_Date__c.format() + ')';
        if (level >= 2) return 'Final notice: "' + item.Title__c + '"' + due + ' remains outstanding. Please complete it to avoid delays to your onboarding.';
        if (overdue)    return 'Your onboarding task "' + item.Title__c + '"' + due + ' is overdue. Please complete it at your earliest convenience.';
        return 'A quick reminder that "' + item.Title__c + '"' + due + ' is coming up. Thank you!';
    }
}
