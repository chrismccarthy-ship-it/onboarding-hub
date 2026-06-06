// ============================================================
// Onboarding Hub — Phase 1 Demo Data
// Run in Developer Console → Execute Anonymous AFTER deploying metadata
// Creates: Citi + Citizens branding configs, and a full demo checklist
//          (NACHA integration scenario for a mid-market bank client)
// ============================================================

// ── 1. Branding configs ──
Dashboard_Config__c citi = new Dashboard_Config__c(
    Name = 'Citi',
    Logo_URL__c = '',
    Dashboard_Title__c = 'Citi Treasury Onboarding',
    Primary_Color__c = '#003B70',
    Secondary_Color__c = '#0066B3',
    Accent_Color__c = '#056DAE',
    Header_Section_Label__c = 'Welcome to Citi',
    Progress_Section_Label__c = 'Your Onboarding Progress',
    Items_Section_Label__c = 'Onboarding Tasks',
    Details_Section_Label__c = 'Business Profile',
    Show_Header__c = true, Show_Progress__c = true, Show_Business_Details__c = true,
    Is_Internal__c = false, Active__c = true
);

Dashboard_Config__c citizens = new Dashboard_Config__c(
    Name = 'Citizens',
    Logo_URL__c = '',
    Dashboard_Title__c = 'Citizens Commercial Onboarding',
    Primary_Color__c = '#00857D',
    Secondary_Color__c = '#00A39B',
    Accent_Color__c = '#76BC21',
    Header_Section_Label__c = 'Welcome to Citizens',
    Progress_Section_Label__c = 'Onboarding Status',
    Items_Section_Label__c = 'What We Need From You',
    Details_Section_Label__c = 'Business Information',
    Show_Header__c = true, Show_Progress__c = true, Show_Business_Details__c = true,
    Is_Internal__c = false, Active__c = true
);

insert new List<Dashboard_Config__c>{ citi, citizens };
System.debug('Created branding configs');

// ── 2. Account + checklist (NACHA integration scenario) ──
Account acc = new Account(Name = 'Lakeside Regional Holdings');
insert acc;

Checklist__c cl = new Checklist__c(
    RecordTypeId = Schema.SObjectType.Checklist__c.getRecordTypeInfosByDeveloperName().get('Client').getRecordTypeId(),
    Account__c = acc.Id,
    Checklist_Type__c = 'Onboarding',
    Client_Segment__c = 'B2B',
    Status__c = 'In Progress',
    Start_Date__c = Date.today().addDays(-14),
    Target_Completion_Date__c = Date.today().addDays(30),
    Preferred_Communication__c = 'Email',
    Dashboard_Config_Name__c = 'Citi',
    Legal_Entity_Name__c = 'Lakeside Regional Holdings, Inc.',
    DBA_Name__c = 'Lakeside Bank',
    Business_Address__c = '4400 Lakeshore Dr, Suite 900, Chicago, IL 60611',
    Tax_ID__c = '36-4xxxxxx',
    Date_of_Incorporation__c = Date.newInstance(2009, 3, 17)
);
insert cl;
System.debug('Created checklist: ' + cl.Id);

// ── 3. Checklist items (the NACHA / ERP integration journey) ──
List<Checklist_Item__c> items = new List<Checklist_Item__c>{
    new Checklist_Item__c(Checklist__c = cl.Id, Sequence__c = 1, Title__c = 'Business Verification Documents',
        Description__c = 'Provide articles of incorporation, EIN letter, and proof of business address.',
        Internal_Notes__c = 'Run through KYC/AML screening. Verify against OFAC list. Escalate to compliance if entity flagged.',
        Category__c = 'Identity Verification', Required__c = true, Status__c = 'Completed',
        Due_Date__c = Date.today().addDays(-7), Visible_In_Portal__c = true,
        Requires_Document__c = true, Document_Count__c = 2, AI_Analysis_Enabled__c = true,
        AI_Analysis_Status__c = 'Completed', Completed_Date__c = System.now().addDays(-5)),

    new Checklist_Item__c(Checklist__c = cl.Id, Sequence__c = 2, Title__c = 'NACHA File Specification Review',
        Description__c = 'Review sample NACHA and BAI2 files from the bank and confirm your ERP can consume the format.',
        Internal_Notes__c = 'Send the client our standard NACHA PPD/CCD spec sheet + 2 sample files. Confirm their ERP is NetSuite or SAP before sending format.',
        Category__c = 'Integration', Required__c = true, Status__c = 'In Progress',
        Due_Date__c = Date.today().addDays(-1), Visible_In_Portal__c = true,
        Document_Generation_Enabled__c = true),

    new Checklist_Item__c(Checklist__c = cl.Id, Sequence__c = 3, Title__c = 'SFTP Integration Setup',
        Description__c = 'Establish the secure SFTP connection for automated NACHA file transfer.',
        Internal_Notes__c = 'Provision SFTP credentials via the integrations team. Whitelist client IP. Test connection before UAT.',
        Category__c = 'Integration', Required__c = true, Status__c = 'In Progress',
        Due_Date__c = Date.today().addDays(5), Visible_In_Portal__c = true),

    new Checklist_Item__c(Checklist__c = cl.Id, Sequence__c = 4, Title__c = 'Remittance Rules Configuration',
        Description__c = 'Configure remittance matching rules to reconcile incoming payments.',
        Internal_Notes__c = 'Work with client AR team to map remittance fields. Document edge cases for partial payments.',
        Category__c = 'Integration', Required__c = false, Status__c = 'Not Started',
        Due_Date__c = Date.today().addDays(10), Visible_In_Portal__c = true),

    new Checklist_Item__c(Checklist__c = cl.Id, Sequence__c = 5, Title__c = 'Project Design Sign-Off',
        Description__c = 'Review and approve the integration design document.',
        Category__c = 'Legal', Required__c = true, Status__c = 'Not Started',
        Due_Date__c = Date.today().addDays(12), Visible_In_Portal__c = true,
        Signature_Required__c = true, Document_Generation_Enabled__c = true),

    new Checklist_Item__c(Checklist__c = cl.Id, Sequence__c = 6, Title__c = 'UAT Execution & Sign-Off',
        Description__c = 'Complete user acceptance testing across all transaction scenarios.',
        Internal_Notes__c = 'Run the full UAT script: PPD credit, CCD debit, return handling, NOC processing. Get written sign-off at each stage.',
        Category__c = 'UAT', Required__c = true, Status__c = 'Not Started',
        Due_Date__c = Date.today().addDays(20), Visible_In_Portal__c = true, Signature_Required__c = true),

    new Checklist_Item__c(Checklist__c = cl.Id, Sequence__c = 7, Title__c = 'Internal Risk & Compliance Review',
        Description__c = 'Final internal compliance gate before go-live.',
        Internal_Notes__c = 'INTERNAL ONLY. Compliance officer signs off on transaction monitoring rules. Confirm SAR thresholds configured.',
        Category__c = 'Compliance', Required__c = true, Status__c = 'Not Started',
        Due_Date__c = Date.today().addDays(22), Visible_In_Portal__c = false),

    new Checklist_Item__c(Checklist__c = cl.Id, Sequence__c = 8, Title__c = 'Go-Live & Post-Launch Support',
        Description__c = 'Production cutover and 2-week hypercare support.',
        Category__c = 'Go-Live', Required__c = true, Status__c = 'Not Started',
        Due_Date__c = Date.today().addDays(28), Visible_In_Portal__c = true, Signature_Required__c = true)
};
insert items;
System.debug('Created ' + items.size() + ' items');

// ── 4. Steps on the multi-stage items ──
List<Checklist_Item_Step__c> steps = new List<Checklist_Item_Step__c>{
    // SFTP Integration Setup steps
    new Checklist_Item_Step__c(Checklist_Item__c = items[2].Id, Sequence__c = 1, Title__c = 'Exchange SFTP credentials', Status__c = 'Completed', Completed_Date__c = System.now().addDays(-2)),
    new Checklist_Item_Step__c(Checklist_Item__c = items[2].Id, Sequence__c = 2, Title__c = 'Whitelist client IP addresses', Status__c = 'In Progress'),
    new Checklist_Item_Step__c(Checklist_Item__c = items[2].Id, Sequence__c = 3, Title__c = 'Test file transfer end-to-end', Status__c = 'Not Started'),

    // UAT steps
    new Checklist_Item_Step__c(Checklist_Item__c = items[5].Id, Sequence__c = 1, Title__c = 'PPD credit transaction test', Status__c = 'Not Started'),
    new Checklist_Item_Step__c(Checklist_Item__c = items[5].Id, Sequence__c = 2, Title__c = 'CCD debit transaction test', Status__c = 'Not Started'),
    new Checklist_Item_Step__c(Checklist_Item__c = items[5].Id, Sequence__c = 3, Title__c = 'Return & NOC handling test', Status__c = 'Not Started'),

    // Go-Live steps
    new Checklist_Item_Step__c(Checklist_Item__c = items[7].Id, Sequence__c = 1, Title__c = 'Production cutover', Status__c = 'Not Started'),
    new Checklist_Item_Step__c(Checklist_Item__c = items[7].Id, Sequence__c = 2, Title__c = 'First live file validation', Status__c = 'Not Started'),
    new Checklist_Item_Step__c(Checklist_Item__c = items[7].Id, Sequence__c = 3, Title__c = 'Hypercare sign-off', Status__c = 'Not Started')
};
insert steps;
System.debug('Created ' + steps.size() + ' steps');

// ── 5. Roll up counts so progress shows immediately ──
for (Checklist_Item__c it : items) {
    Integer st = 0, sc = 0;
    for (Checklist_Item_Step__c s : steps) {
        if (s.Checklist_Item__c == it.Id) {
            st++;
            if (s.Status__c == 'Completed') sc++;
        }
    }
    it.Steps_Total__c = st;
    it.Steps_Complete__c = sc;
}
update items;

Integer total = items.size();
Integer done = 0;
for (Checklist_Item__c it : items) if (it.Status__c == 'Completed') done++;
cl.Items_Total__c = total;
cl.Items_Complete__c = done;
cl.Progress_Percent__c = (Decimal.valueOf(done) / total * 100).setScale(1);
update cl;

System.debug('========================================');
System.debug('DEMO DATA READY');
System.debug('Checklist Id: ' + cl.Id);
System.debug('Progress: ' + cl.Progress_Percent__c + '%');
System.debug('Open the Checklist record or set this Id on the Onboarding Hub component.');
System.debug('Switch Dashboard_Config_Name__c between "Citi" and "Citizens" to rebrand.');
System.debug('========================================');
