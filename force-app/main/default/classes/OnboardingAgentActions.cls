/**
 * OnboardingAgentActions
 * Invocable methods so an Agentforce Service Agent can read checklist status
 * and complete items on behalf of a client or employee during a conversation.
 */
public with sharing class OnboardingAgentActions {

    // ──────────────────────────────────────────────
    // GET CHECKLIST STATUS  (Agentforce-callable)
    // ──────────────────────────────────────────────
    public class StatusRequest {
        @InvocableVariable(label='Checklist Id' required=true)
        public Id checklistId;
    }

    public class StatusResponse {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Progress Percent') public Decimal progressPercent;
        @InvocableVariable(label='Next Item') public String nextItem;
        @InvocableVariable(label='Overdue Items') public String overdueItems;
    }

    @InvocableMethod(label='Get Onboarding Checklist Status' description='Returns progress, next item, and overdue items for a checklist.')
    public static List<StatusResponse> getChecklistStatus(List<StatusRequest> requests) {
        List<StatusResponse> responses = new List<StatusResponse>();
        Date today = Date.today();

        for (StatusRequest req : requests) {
            StatusResponse resp = new StatusResponse();

            List<Checklist__c> cls = [
                SELECT Id, Name, Status__c, Progress_Percent__c, Checklist_Type__c,
                       Account__r.Name, Contact__r.Name
                FROM Checklist__c
                WHERE Id = :req.checklistId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (cls.isEmpty()) {
                resp.summary = 'Checklist not found.';
                resp.progressPercent = 0;
                responses.add(resp);
                continue;
            }

            Checklist__c cl = cls[0];
            resp.progressPercent = (cl.Progress_Percent__c != null) ? cl.Progress_Percent__c : 0;

            List<Checklist_Item__c> items = [
                SELECT Id, Title__c, Status__c, Due_Date__c, Required__c, Sequence__c
                FROM Checklist_Item__c
                WHERE Checklist__c = :req.checklistId
                WITH SECURITY_ENFORCED
                ORDER BY Sequence__c ASC NULLS LAST
            ];

            String nextOpen = null;
            List<String> overdue = new List<String>();
            Integer completed = 0;

            for (Checklist_Item__c item : items) {
                if (item.Status__c == 'Completed') {
                    completed++;
                } else if (nextOpen == null) {
                    nextOpen = item.Title__c;
                }
                if (item.Due_Date__c != null && item.Due_Date__c < today && item.Status__c != 'Completed') {
                    overdue.add(item.Title__c);
                }
            }

            resp.nextItem = (nextOpen != null) ? nextOpen : 'All items complete';
            resp.overdueItems = overdue.isEmpty() ? 'None' : String.join(overdue, '; ');
            resp.summary = 'Checklist ' + cl.Name + ' is ' + resp.progressPercent + '% complete (' +
                           completed + ' of ' + items.size() + ' items). Status: ' + cl.Status__c + '.';

            responses.add(resp);
        }
        return responses;
    }

    // ──────────────────────────────────────────────
    // COMPLETE A CHECKLIST ITEM  (Agentforce-callable)
    // ──────────────────────────────────────────────
    public class CompleteRequest {
        @InvocableVariable(label='Checklist Item Id' required=true)
        public Id itemId;
    }

    public class CompleteResponse {
        @InvocableVariable(label='Result') public String result;
    }

    @InvocableMethod(label='Complete Onboarding Item' description='Marks a checklist item as completed.')
    public static List<CompleteResponse> completeItem(List<CompleteRequest> requests) {
        List<CompleteResponse> responses = new List<CompleteResponse>();
        for (CompleteRequest req : requests) {
            CompleteResponse resp = new CompleteResponse();
            try {
                OnboardingDashboardController.completeItem(req.itemId);
                resp.result = 'Item marked complete.';
            } catch (Exception e) {
                resp.result = 'Error: ' + e.getMessage();
            }
            responses.add(resp);
        }
        return responses;
    }
}
