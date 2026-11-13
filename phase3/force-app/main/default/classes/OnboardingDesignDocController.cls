/**
 * OnboardingDesignDocController — backs the OnboardingDesignDoc Visualforce page (rendered as PDF).
 * Reads the checklist id from the ?id= page parameter.
 */
public with sharing class OnboardingDesignDocController {

    public Checklist__c checklist { get; private set; }
    public List<Checklist_Item__c> items { get; private set; }

    public OnboardingDesignDocController() {
        load(ApexPages.currentPage().getParameters().get('id'));
    }

    private void load(Id cid) {
        items = new List<Checklist_Item__c>();
        if (cid == null) return;
        List<Checklist__c> cls = [
            SELECT Id, Name, Legal_Entity_Name__c, DBA_Name__c, Business_Address__c,
                   Tax_ID__c, Date_of_Incorporation__c, Progress_Percent__c, Status__c,
                   Dashboard_Config_Name__c
            FROM Checklist__c WHERE Id = :cid LIMIT 1
        ];
        if (cls.isEmpty()) return;
        checklist = cls[0];
        items = [
            SELECT Id, Title__c, Status__c, Category__c, Due_Date__c, Required__c
            FROM Checklist_Item__c
            WHERE Checklist__c = :cid
            ORDER BY Sequence__c ASC NULLS LAST, Name ASC
        ];
    }
}
