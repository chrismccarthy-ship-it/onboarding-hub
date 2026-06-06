@isTest
private class OnboardingDashboardControllerTest {

    @testSetup
    static void setup() {
        // Branding config
        Dashboard_Config__c cfg = new Dashboard_Config__c(
            Name = 'Citi',
            Logo_URL__c = 'https://example.com/citi.png',
            Dashboard_Title__c = 'Citi Onboarding',
            Primary_Color__c = '#003B70',
            Secondary_Color__c = '#0066B3',
            Accent_Color__c = '#D9261C',
            Header_Section_Label__c = 'Welcome',
            Progress_Section_Label__c = 'Your Progress',
            Items_Section_Label__c = 'Your Tasks',
            Details_Section_Label__c = 'Business Details',
            Show_Header__c = true,
            Show_Progress__c = true,
            Show_Business_Details__c = true,
            Is_Internal__c = false,
            Active__c = true
        );
        insert cfg;

        // Account + checklist
        Account acc = new Account(Name = 'Test Bank Client');
        insert acc;

        Checklist__c cl = new Checklist__c(
            Account__c = acc.Id,
            Checklist_Type__c = 'Onboarding',
            Client_Segment__c = 'B2B',
            Status__c = 'In Progress',
            Start_Date__c = Date.today().addDays(-10),
            Target_Completion_Date__c = Date.today().addDays(20),
            Preferred_Communication__c = 'Email',
            Dashboard_Config_Name__c = 'Citi'
        );
        insert cl;

        // Items
        Checklist_Item__c item1 = new Checklist_Item__c(
            Checklist__c = cl.Id, Title__c = 'Provide business documents', Sequence__c = 1,
            Required__c = true, Status__c = 'Completed', Due_Date__c = Date.today().addDays(-2),
            Visible_In_Portal__c = true, Completed_Date__c = System.now()
        );
        Checklist_Item__c item2 = new Checklist_Item__c(
            Checklist__c = cl.Id, Title__c = 'SFTP integration setup', Sequence__c = 2,
            Required__c = true, Status__c = 'In Progress', Due_Date__c = Date.today().addDays(-1),
            Visible_In_Portal__c = true
        );
        Checklist_Item__c item3 = new Checklist_Item__c(
            Checklist__c = cl.Id, Title__c = 'Internal compliance review', Sequence__c = 3,
            Required__c = true, Status__c = 'Not Started', Visible_In_Portal__c = false
        );
        insert new List<Checklist_Item__c>{ item1, item2, item3 };

        // Steps on item2
        insert new List<Checklist_Item_Step__c>{
            new Checklist_Item_Step__c(Checklist_Item__c = item2.Id, Title__c = 'Exchange SFTP keys', Sequence__c = 1, Status__c = 'Completed', Completed_Date__c = System.now()),
            new Checklist_Item_Step__c(Checklist_Item__c = item2.Id, Title__c = 'Test file transfer', Sequence__c = 2, Status__c = 'Not Started'),
            new Checklist_Item_Step__c(Checklist_Item__c = item2.Id, Title__c = 'UAT sign-off', Sequence__c = 3, Status__c = 'Not Started')
        };
    }

    @isTest
    static void testGetDashboardInternal() {
        Checklist__c cl = [SELECT Id FROM Checklist__c LIMIT 1];
        Test.startTest();
        OnboardingDashboardController.DashboardData data =
            OnboardingDashboardController.getDashboard(cl.Id, 'Citi', true);
        Test.stopTest();

        System.assertNotEquals(null, data, 'Dashboard data should return');
        System.assertEquals('Citi', data.brand.configName, 'Brand should be Citi');
        System.assertEquals(3, data.items.size(), 'Internal view should see all 3 items');
        System.assertEquals(true, data.brand.isInternal, 'Internal flag should be true');
    }

    @isTest
    static void testGetDashboardExternal() {
        Checklist__c cl = [SELECT Id FROM Checklist__c LIMIT 1];
        Test.startTest();
        OnboardingDashboardController.DashboardData data =
            OnboardingDashboardController.getDashboard(cl.Id, 'Citi', false);
        Test.stopTest();

        // item3 is not portal-visible, so external view should see only 2
        System.assertEquals(2, data.items.size(), 'External view should hide non-portal items');
    }

    @isTest
    static void testCompleteStepAndItem() {
        Checklist_Item_Step__c step = [SELECT Id FROM Checklist_Item_Step__c WHERE Status__c = 'Not Started' LIMIT 1];
        Test.startTest();
        OnboardingDashboardController.completeStep(step.Id);
        Test.stopTest();

        Checklist_Item_Step__c updated = [SELECT Status__c FROM Checklist_Item_Step__c WHERE Id = :step.Id];
        System.assertEquals('Completed', updated.Status__c, 'Step should be completed');
    }

    @isTest
    static void testDefaultBrandConfig() {
        Test.startTest();
        OnboardingDashboardController.BrandConfig bc =
            OnboardingDashboardController.getBrandConfig('NonExistent', true);
        Test.stopTest();
        System.assertEquals('Default', bc.configName, 'Should fall back to Default');
    }

    @isTest
    static void testAgentActions() {
        Checklist__c cl = [SELECT Id FROM Checklist__c LIMIT 1];
        OnboardingAgentActions.StatusRequest req = new OnboardingAgentActions.StatusRequest();
        req.checklistId = cl.Id;

        Test.startTest();
        List<OnboardingAgentActions.StatusResponse> resp =
            OnboardingAgentActions.getChecklistStatus(new List<OnboardingAgentActions.StatusRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, resp.size(), 'Should return one response');
        System.assertNotEquals(null, resp[0].summary, 'Summary should be populated');
    }

    @isTest
    static void testAgentCompleteItem() {
        Checklist_Item__c item = [SELECT Id FROM Checklist_Item__c WHERE Status__c = 'Not Started' LIMIT 1];
        OnboardingAgentActions.CompleteRequest req = new OnboardingAgentActions.CompleteRequest();
        req.itemId = item.Id;

        Test.startTest();
        List<OnboardingAgentActions.CompleteResponse> resp =
            OnboardingAgentActions.completeItem(new List<OnboardingAgentActions.CompleteRequest>{ req });
        Test.stopTest();

        System.assertEquals('Item marked complete.', resp[0].result, 'Item should complete');
    }
}
