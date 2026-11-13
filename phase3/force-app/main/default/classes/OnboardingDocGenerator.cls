/**
 * OnboardingDocGenerator — renders the onboarding design/sign-off document as a PDF
 * (via the OnboardingDesignDoc Visualforce page), saves it to the checklist as a File,
 * and emails it to the client. Invocable so the "Generate & Send" action / a Flow / an
 * Agentforce action can call it.
 */
public with sharing class OnboardingDocGenerator {

    public class Request {
        @InvocableVariable(required=true label='Checklist Id') public Id checklistId;
        @InvocableVariable(label='Recipient Email') public String recipientEmail;
    }
    public class Result {
        @InvocableVariable public String status;
        @InvocableVariable public Id contentVersionId;
    }

    @InvocableMethod(label='Generate & Send Onboarding Document'
        description='Renders the onboarding design/sign-off PDF, saves it to the checklist, and emails it to the client.')
    public static List<Result> generate(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) results.add(run(r.checklistId, r.recipientEmail));
        return results;
    }

    public static Result run(Id checklistId, String recipientEmail) {
        Result res = new Result();

        // 1. render the PDF (guarded in tests — getContentAsPDF is not available there)
        Blob pdf;
        if (Test.isRunningTest()) {
            pdf = Blob.valueOf('TEST-PDF');
        } else {
            PageReference p = Page.OnboardingDesignDoc;
            p.getParameters().put('id', checklistId);
            pdf = p.getContentAsPDF();
        }

        // 2. save as a File linked to the checklist
        ContentVersion cv = new ContentVersion(
            Title = 'Onboarding Design Document',
            PathOnClient = 'Onboarding_Design_Document.pdf',
            VersionData = pdf,
            FirstPublishLocationId = checklistId
        );
        insert cv;
        res.contentVersionId = cv.Id;

        // 3. email it to the client
        if (String.isNotBlank(recipientEmail) && !Test.isRunningTest()) {
            Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
            att.setFileName('Onboarding_Design_Document.pdf');
            att.setBody(pdf);
            att.setContentType('application/pdf');

            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setToAddresses(new List<String>{ recipientEmail });
            m.setSubject('Your onboarding design document');
            m.setPlainTextBody('Attached is the design / sign-off document for your onboarding. Please review and sign.');
            m.setFileAttachments(new List<Messaging.EmailFileAttachment>{ att });
            m.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m }, false);
            res.status = 'Generated and emailed';
        } else {
            res.status = 'Generated';
        }
        return res;
    }
}
