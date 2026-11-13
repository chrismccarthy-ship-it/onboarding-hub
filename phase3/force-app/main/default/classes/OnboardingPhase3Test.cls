@isTest
private class OnboardingPhase3Test {

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'Lakeside Regional Holdings');
        insert a;
        Contact c = new Contact(LastName = 'Doe', Email = 'client@example.com', AccountId = a.Id);
        insert c;

        Checklist__c cl = new Checklist__c(
            Account__c = a.Id, Contact__c = c.Id,
            Checklist_Type__c = 'Onboarding', Status__c = 'In Progress',
            Dashboard_Config_Name__c = 'Citi',
            Legal_Entity_Name__c = 'Lakeside Regional Holdings, Inc.'
        );
        insert cl;

        insert new List<Checklist_Item__c>{
            new Checklist_Item__c(Checklist__c = cl.Id, Title__c = 'Overdue Item', Sequence__c = 1,
                Status__c = 'Not Started', Required__c = true, Visible_In_Portal__c = true,
                Due_Date__c = Date.today().addDays(-5), Reminder_Channel__c = 'Email', Reminder_Count__c = 2),
            new Checklist_Item__c(Checklist__c = cl.Id, Title__c = 'Due Soon Item', Sequence__c = 2,
                Status__c = 'Not Started', Required__c = true, Visible_In_Portal__c = true,
                Due_Date__c = Date.today().addDays(1), Reminder_Channel__c = 'Slack'),
            // reminded 1 hour ago -> inside the 2-day quiet window -> must be suppressed
            new Checklist_Item__c(Checklist__c = cl.Id, Title__c = 'Recently Reminded', Sequence__c = 3,
                Status__c = 'Not Started', Required__c = true, Visible_In_Portal__c = true,
                Due_Date__c = Date.today().addDays(-3), Reminder_Channel__c = 'Email',
                Reminder_Count__c = 5, Last_Reminder_Date__c = System.now().addHours(-1))
        };
    }

    @isTest
    static void testReminderBatch() {
        Test.startTest();
        Database.executeBatch(new OnboardingReminderBatch(), 50);
        Test.stopTest();
        System.assert([SELECT COUNT() FROM Notification_Log__c] > 0, 'Logs should be created');
    }

    @isTest
    static void testQuietPeriodSuppresses() {
        Test.startTest();
        Database.executeBatch(new OnboardingReminderBatch(), 50);
        Test.stopTest();
        Checklist_Item__c recent = [SELECT Reminder_Count__c FROM Checklist_Item__c WHERE Title__c = 'Recently Reminded' LIMIT 1];
        System.assertEquals(5, recent.Reminder_Count__c, 'Item reminded within the quiet window must not be re-reminded');
    }

    @isTest
    static void testEscalationTimestamps() {
        Test.startTest();
        Database.executeBatch(new OnboardingReminderBatch(), 50);
        Test.stopTest();
        Checklist_Item__c overdue = [SELECT Reminder_Count__c, Escalation_Level__c, Last_Reminder_Date__c
                                     FROM Checklist_Item__c WHERE Title__c = 'Overdue Item' LIMIT 1];
        System.assertEquals(3, overdue.Reminder_Count__c, 'Reminder count should increment');
        System.assertEquals(2, overdue.Escalation_Level__c, 'Overdue item with 2 prior reminders should be at escalation level 2');
        System.assertNotEquals(null, overdue.Last_Reminder_Date__c);
    }

    @isTest
    static void testScheduler() {
        Test.startTest();
        String jobId = OnboardingReminderScheduler.scheduleDaily();
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Scheduler should return a job id');
    }

    @isTest
    static void testNotifierSimulatedChannels() {
        Checklist_Item__c it = [SELECT Id, Title__c FROM Checklist_Item__c LIMIT 1];
        Test.startTest();
        OnboardingNotifier.Outcome email = OnboardingNotifier.dispatch(it, 'Email', 's', 'b', 'x@y.com');
        OnboardingNotifier.Outcome inapp = OnboardingNotifier.dispatch(it, 'In-App', 's', 'b', null);
        OnboardingNotifier.Outcome slack = OnboardingNotifier.dispatch(it, 'Slack', 's', 'b', null); // config disabled -> Simulated
        OnboardingNotifier.Outcome sms   = OnboardingNotifier.dispatch(it, 'SMS', 's', 'b', '+15551234567');
        insert new List<Notification_Log__c>{ email.logRecord, inapp.logRecord, slack.logRecord, sms.logRecord };
        Test.stopTest();
        System.assertEquals('Sent', email.status);
        System.assertEquals('Sent', inapp.status);
        System.assertEquals('Simulated', slack.status);
        System.assertEquals('Simulated', sms.status);
    }

    @isTest
    static void testNotifierSlackRealCallout() {
        Test.setMock(HttpCalloutMock.class, new OkMock());
        OnboardingNotifier.setSlackWebhookForTest('https://hooks.slack.com/services/TEST');
        Checklist_Item__c it = [SELECT Id, Title__c FROM Checklist_Item__c LIMIT 1];
        Test.startTest();
        OnboardingNotifier.Outcome o = OnboardingNotifier.dispatch(it, 'Slack', 'Subject', 'Body', null);
        insert o.logRecord;
        Test.stopTest();
        System.assertEquals('Sent', o.status, 'Mocked Slack callout should report Sent');
    }

    @isTest
    static void testDocGenerator() {
        Checklist__c cl = [SELECT Id FROM Checklist__c LIMIT 1];
        Test.startTest();
        OnboardingDocGenerator.Result r = OnboardingDocGenerator.run(cl.Id, 'client@example.com');
        OnboardingDocGenerator.Request req = new OnboardingDocGenerator.Request();
        req.checklistId = cl.Id;
        OnboardingDocGenerator.generate(new List<OnboardingDocGenerator.Request>{ req });
        Test.stopTest();
        System.assertNotEquals(null, r.contentVersionId, 'A file should be created');
    }

    private class OkMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('ok');
            return res;
        }
    }
}
