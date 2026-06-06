/**
 * OnboardingDashboardController
 * Service layer for the white-label onboarding dashboard LWC.
 * Methods are cacheable for LWC wire adapters and exposed for Experience Cloud (guest/portal) use.
 */
public with sharing class OnboardingDashboardController {

    // ──────────────────────────────────────────────
    // WRAPPER CLASSES
    // ──────────────────────────────────────────────
    public class DashboardData {
        @AuraEnabled public Checklist__c checklist;
        @AuraEnabled public BrandConfig brand;
        @AuraEnabled public List<ItemWrapper> items;
        @AuraEnabled public Decimal progressPercent;
        @AuraEnabled public Integer itemsTotal;
        @AuraEnabled public Integer itemsComplete;
    }

    public class ItemWrapper {
        @AuraEnabled public Checklist_Item__c item;
        @AuraEnabled public List<Checklist_Item_Step__c> steps;
        @AuraEnabled public Boolean isOverdue;
        @AuraEnabled public Decimal stepProgress;
    }

    public class BrandConfig {
        @AuraEnabled public String configName;
        @AuraEnabled public String logoUrl;
        @AuraEnabled public String dashboardTitle;
        @AuraEnabled public String primaryColor;
        @AuraEnabled public String secondaryColor;
        @AuraEnabled public String accentColor;
        @AuraEnabled public String headerLabel;
        @AuraEnabled public String progressLabel;
        @AuraEnabled public String itemsLabel;
        @AuraEnabled public String detailsLabel;
        @AuraEnabled public Boolean showHeader;
        @AuraEnabled public Boolean showProgress;
        @AuraEnabled public Boolean showBusinessDetails;
        @AuraEnabled public Boolean isInternal;
    }

    // ──────────────────────────────────────────────
    // MAIN ENTRY POINT — used by the LWC wire
    // ──────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboard(Id checklistId, String configName, Boolean isInternal) {
        DashboardData data = new DashboardData();

        // 1. Load the checklist with all configured fields
        List<Checklist__c> checklists = [
            SELECT Id, Name, RecordType.DeveloperName, Checklist_Type__c, Client_Segment__c,
                   Status__c, Start_Date__c, Target_Completion_Date__c, Progress_Percent__c,
                   Preferred_Communication__c, Dashboard_Config_Name__c,
                   Account__c, Account__r.Name, Contact__c, Contact__r.Name,
                   Employee_User__c, Employee_User__r.Name,
                   Onboarding_Specialist__c, Onboarding_Specialist__r.Name,
                   Sales_Rep__c, Sales_Rep__r.Name,
                   DBA_Name__c, Legal_Entity_Name__c, Business_Address__c, Tax_ID__c, Date_of_Incorporation__c,
                   Items_Total__c, Items_Complete__c
            FROM Checklist__c
            WHERE Id = :checklistId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (checklists.isEmpty()) {
            throw new AuraHandledException('Checklist not found or you do not have access.');
        }
        data.checklist = checklists[0];

        // 2. Resolve branding — explicit param wins, else checklist's stored config, else default
        String resolvedConfig = String.isNotBlank(configName)
            ? configName
            : (String.isNotBlank(data.checklist.Dashboard_Config_Name__c) ? data.checklist.Dashboard_Config_Name__c : 'Default');
        data.brand = getBrandConfig(resolvedConfig, isInternal);

        // 3. Load items (filter by portal visibility when external)
        Boolean internalView = (isInternal == true);
        List<Checklist_Item__c> itemRecords = [
            SELECT Id, Name, Title__c, Description__c, Internal_Notes__c, Sequence__c,
                   Required__c, Due_Date__c, Signature_Required__c, Signature_Captured__c,
                   Status__c, Category__c, Reminder_Count__c, Last_Reminder_Date__c, Reminder_Channel__c,
                   Requires_Document__c, Document_Count__c, AI_Analysis_Enabled__c, AI_Analysis_Status__c,
                   Document_Generation_Enabled__c, Steps_Total__c, Steps_Complete__c,
                   Completed_Date__c, Visible_In_Portal__c
            FROM Checklist_Item__c
            WHERE Checklist__c = :checklistId
            WITH SECURITY_ENFORCED
            ORDER BY Sequence__c ASC NULLS LAST, Name ASC
        ];

        // 4. Load all steps in one query, group by item
        Map<Id, List<Checklist_Item_Step__c>> stepsByItem = new Map<Id, List<Checklist_Item_Step__c>>();
        for (Checklist_Item_Step__c step : [
            SELECT Id, Name, Title__c, Description__c, Sequence__c, Status__c, Completed_Date__c, Checklist_Item__c
            FROM Checklist_Item_Step__c
            WHERE Checklist_Item__r.Checklist__c = :checklistId
            WITH SECURITY_ENFORCED
            ORDER BY Sequence__c ASC NULLS LAST, Name ASC
        ]) {
            if (!stepsByItem.containsKey(step.Checklist_Item__c)) {
                stepsByItem.put(step.Checklist_Item__c, new List<Checklist_Item_Step__c>());
            }
            stepsByItem.get(step.Checklist_Item__c).add(step);
        }

        // 5. Build wrappers
        data.items = new List<ItemWrapper>();
        Integer total = 0;
        Integer complete = 0;
        Date today = Date.today();

        for (Checklist_Item__c item : itemRecords) {
            if (!internalView && item.Visible_In_Portal__c == false) {
                continue; // hide non-portal items on Experience Cloud
            }
            ItemWrapper w = new ItemWrapper();
            w.item = item;
            w.steps = stepsByItem.containsKey(item.Id) ? stepsByItem.get(item.Id) : new List<Checklist_Item_Step__c>();
            w.isOverdue = (item.Due_Date__c != null && item.Due_Date__c < today && item.Status__c != 'Completed');

            if (item.Steps_Total__c != null && item.Steps_Total__c > 0) {
                w.stepProgress = (item.Steps_Complete__c == null ? 0 : item.Steps_Complete__c) / item.Steps_Total__c * 100;
            } else {
                w.stepProgress = (item.Status__c == 'Completed') ? 100 : 0;
            }

            total++;
            if (item.Status__c == 'Completed') complete++;
            data.items.add(w);
        }

        data.itemsTotal = total;
        data.itemsComplete = complete;
        data.progressPercent = (total > 0) ? (Decimal.valueOf(complete) / total * 100).setScale(1) : 0;

        return data;
    }

    // ──────────────────────────────────────────────
    // BRAND CONFIG LOADER
    // ──────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static BrandConfig getBrandConfig(String configName, Boolean isInternal) {
        BrandConfig bc = new BrandConfig();

        List<Dashboard_Config__c> configs = [
            SELECT Name, Logo_URL__c, Dashboard_Title__c, Primary_Color__c, Secondary_Color__c, Accent_Color__c,
                   Header_Section_Label__c, Progress_Section_Label__c, Items_Section_Label__c, Details_Section_Label__c,
                   Show_Header__c, Show_Progress__c, Show_Business_Details__c, Is_Internal__c, Active__c
            FROM Dashboard_Config__c
            WHERE Name = :configName AND Active__c = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (!configs.isEmpty()) {
            Dashboard_Config__c c = configs[0];
            bc.configName = c.Name;
            bc.logoUrl = c.Logo_URL__c;
            bc.dashboardTitle = c.Dashboard_Title__c;
            bc.primaryColor = c.Primary_Color__c;
            bc.secondaryColor = c.Secondary_Color__c;
            bc.accentColor = c.Accent_Color__c;
            bc.headerLabel = c.Header_Section_Label__c;
            bc.progressLabel = c.Progress_Section_Label__c;
            bc.itemsLabel = c.Items_Section_Label__c;
            bc.detailsLabel = c.Details_Section_Label__c;
            bc.showHeader = c.Show_Header__c;
            bc.showProgress = c.Show_Progress__c;
            bc.showBusinessDetails = c.Show_Business_Details__c;
            bc.isInternal = (isInternal != null) ? isInternal : c.Is_Internal__c;
        } else {
            // Sensible defaults if no config record found
            bc.configName = 'Default';
            bc.logoUrl = null;
            bc.dashboardTitle = 'Onboarding Hub';
            bc.primaryColor = '#1B3A5C';
            bc.secondaryColor = '#2E75B6';
            bc.accentColor = '#0D7C8F';
            bc.headerLabel = 'Onboarding';
            bc.progressLabel = 'Your Progress';
            bc.itemsLabel = 'Checklist';
            bc.detailsLabel = 'Business Details';
            bc.showHeader = true;
            bc.showProgress = true;
            bc.showBusinessDetails = true;
            bc.isInternal = (isInternal == true);
        }
        return bc;
    }

    // ──────────────────────────────────────────────
    // MARK A STEP COMPLETE (called from LWC)
    // ──────────────────────────────────────────────
    @AuraEnabled
    public static void completeStep(Id stepId) {
        Checklist_Item_Step__c step = [
            SELECT Id, Status__c, Checklist_Item__c
            FROM Checklist_Item_Step__c
            WHERE Id = :stepId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        step.Status__c = 'Completed';
        step.Completed_Date__c = System.now();
        update step;
        recalcItem(step.Checklist_Item__c);
    }

    // ──────────────────────────────────────────────
    // MARK AN ITEM COMPLETE (called from LWC / Agentforce)
    // ──────────────────────────────────────────────
    @AuraEnabled
    public static void completeItem(Id itemId) {
        Checklist_Item__c item = [
            SELECT Id, Status__c, Checklist__c
            FROM Checklist_Item__c
            WHERE Id = :itemId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        item.Status__c = 'Completed';
        item.Completed_Date__c = System.now();
        update item;
        recalcChecklist(item.Checklist__c);
    }

    // ──────────────────────────────────────────────
    // ROLLUP HELPERS
    // ──────────────────────────────────────────────
    private static void recalcItem(Id itemId) {
        Integer total = 0;
        Integer done = 0;
        for (Checklist_Item_Step__c s : [
            SELECT Status__c FROM Checklist_Item_Step__c WHERE Checklist_Item__c = :itemId
        ]) {
            total++;
            if (s.Status__c == 'Completed') done++;
        }

        Checklist_Item__c item = [SELECT Id, Status__c, Completed_Date__c, Checklist__c FROM Checklist_Item__c WHERE Id = :itemId LIMIT 1];
        item.Steps_Total__c = total;
        item.Steps_Complete__c = done;
        if (total > 0 && done == total) {
            item.Status__c = 'Completed';
            if (item.Completed_Date__c == null) item.Completed_Date__c = System.now();
        } else if (done > 0) {
            item.Status__c = 'In Progress';
        }
        update item;
        recalcChecklist(item.Checklist__c);
    }

    private static void recalcChecklist(Id checklistId) {
        Integer total = 0;
        Integer done = 0;
        for (Checklist_Item__c i : [
            SELECT Status__c FROM Checklist_Item__c WHERE Checklist__c = :checklistId
        ]) {
            total++;
            if (i.Status__c == 'Completed') done++;
        }

        Checklist__c cl = [SELECT Id, Status__c, Progress_Percent__c, Items_Total__c, Items_Complete__c FROM Checklist__c WHERE Id = :checklistId LIMIT 1];
        cl.Items_Total__c = total;
        cl.Items_Complete__c = done;
        cl.Progress_Percent__c = (total > 0) ? (Decimal.valueOf(done) / total * 100).setScale(1) : 0;
        if (total > 0 && done == total) {
            cl.Status__c = 'Completed';
        } else if (done > 0 && cl.Status__c == 'Not Started') {
            cl.Status__c = 'In Progress';
        }
        update cl;
    }
}
