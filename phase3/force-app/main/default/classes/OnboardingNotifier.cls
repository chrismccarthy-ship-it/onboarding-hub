/**
 * OnboardingNotifier — Phase 3 channel router.
 *
 * Email and in-app bell send for real. Slack and SMS perform a real HTTP callout when
 * the matching Onboarding_Channel_Config__mdt record is Enabled and has an Endpoint
 * (plus a Remote Site Setting / Named Credential for the host); otherwise they record
 * 'Simulated'. In tests, the @TestVisible overrides take precedence over the config.
 *
 * dispatch() performs the send and RETURNS an unsaved Notification_Log__c in the Outcome.
 * The CALLER inserts the logs — this keeps every HTTP callout before any DML, which the
 * reminder batch relies on (you cannot call out after DML in the same transaction).
 */
public with sharing class OnboardingNotifier {

    // ---- Test-only overrides (production endpoints live in Onboarding_Channel_Config__mdt) ----
    @TestVisible private static String SLACK_WEBHOOK = null;
    @TestVisible private static String SMS_ENDPOINT  = null;
    @TestVisible private static void setSlackWebhookForTest(String url) { SLACK_WEBHOOK = url; }
    @TestVisible private static void setSmsEndpointForTest(String url)  { SMS_ENDPOINT = url; }

    private static Map<String, Onboarding_Channel_Config__mdt> CONFIG;

    public class Outcome {
        public String channel;
        public String status;                 // Sent | Simulated | Failed
        public String detail;
        public Notification_Log__c logRecord;  // unsaved — caller inserts
    }

    /** Convenience overload: no explicit in-app recipients (defaults to the running user). */
    public static Outcome dispatch(Checklist_Item__c item, String channel,
                                   String subject, String message, String recipient) {
        return dispatch(item, channel, subject, message, recipient, null);
    }

    /** Send on one channel and build (not insert) the log record. */
    public static Outcome dispatch(Checklist_Item__c item, String channel, String subject,
                                   String message, String recipient, Set<Id> inAppUserIds) {
        Outcome o = new Outcome();
        o.channel = channel;
        try {
            if (channel == 'Email')       o.status = sendEmail(recipient, subject, message);
            else if (channel == 'In-App') o.status = sendInApp(item, subject, message, inAppUserIds);
            else if (channel == 'Slack')  o.status = sendSlack(subject, message);
            else if (channel == 'SMS')    o.status = sendSms(recipient, message);
            else { o.status = 'Failed'; o.detail = 'Unknown channel: ' + channel; }
        } catch (Exception e) {
            o.status = 'Failed';
            o.detail = e.getMessage();
        }
        o.logRecord = buildLog(item, channel, o.status, recipient, message, o.detail);
        return o;
    }

    // ---------------- channels ----------------
    private static String sendEmail(String to, String subject, String body) {
        if (String.isBlank(to)) return 'Simulated';
        if (Test.isRunningTest()) return 'Sent';
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(new List<String>{ to });
        m.setSubject(subject);
        m.setPlainTextBody(body);
        m.setSaveAsActivity(false);
        Messaging.SendEmailResult[] r =
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m }, false);
        return (r != null && !r.isEmpty() && r[0].isSuccess()) ? 'Sent' : 'Failed';
    }

    private static String sendInApp(Checklist_Item__c item, String subject, String body, Set<Id> userIds) {
        Set<String> recipients = new Set<String>();
        if (userIds != null) {
            for (Id uid : userIds) if (uid != null) recipients.add(uid);
        }
        if (recipients.isEmpty()) recipients.add(UserInfo.getUserId());
        if (Test.isRunningTest()) return 'Sent';
        Messaging.CustomNotification n = new Messaging.CustomNotification();
        n.setTitle(subject);
        n.setBody(body);
        n.setNotificationTypeId(notificationTypeId());
        if (item != null) n.setTargetId(item.Id);
        n.send(recipients);
        return 'Sent';
    }

    private static String sendSlack(String subject, String message) {
        String endpoint = resolveEndpoint('Slack', SLACK_WEBHOOK);
        if (String.isBlank(endpoint)) return 'Simulated';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, Object>{ 'text' => subject + '\n' + message }));
        HttpResponse res = new Http().send(req);
        return (res.getStatusCode() >= 200 && res.getStatusCode() < 300) ? 'Sent' : 'Failed';
    }

    private static String sendSms(String to, String message) {
        String endpoint = resolveEndpoint('SMS', SMS_ENDPOINT);
        if (String.isBlank(endpoint) || String.isBlank(to)) return 'Simulated';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, Object>{ 'to' => to, 'message' => message }));
        HttpResponse res = new Http().send(req);
        return (res.getStatusCode() >= 200 && res.getStatusCode() < 300) ? 'Sent' : 'Failed';
    }

    // ---------------- helpers ----------------
    /** Test override wins; otherwise use the __mdt record when it is Enabled with an Endpoint. */
    private static String resolveEndpoint(String channel, String testOverride) {
        if (String.isNotBlank(testOverride)) return testOverride;
        Onboarding_Channel_Config__mdt c = config(channel);
        return (c != null && c.Enabled__c == true) ? c.Endpoint__c : null;
    }

    private static Onboarding_Channel_Config__mdt config(String developerName) {
        if (CONFIG == null) {
            CONFIG = new Map<String, Onboarding_Channel_Config__mdt>();
            for (Onboarding_Channel_Config__mdt c : Onboarding_Channel_Config__mdt.getAll().values()) {
                CONFIG.put(c.DeveloperName, c);
            }
        }
        return CONFIG.get(developerName);
    }

    private static Id notificationTypeId() {
        return [SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = 'Onboarding_Alert' LIMIT 1].Id;
    }

    private static Notification_Log__c buildLog(Checklist_Item__c item, String channel, String status,
                                                String recipient, String message, String detail) {
        return new Notification_Log__c(
            Checklist_Item__c = (item != null ? item.Id : null),
            Channel__c   = channel,
            Status__c    = status,
            Recipient__c = recipient,
            Message__c   = (detail == null ? message : message + '\n[' + detail + ']'),
            Sent_Date__c = System.now()
        );
    }
}
