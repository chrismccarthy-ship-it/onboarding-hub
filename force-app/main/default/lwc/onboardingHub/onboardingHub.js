import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getDashboard from '@salesforce/apex/OnboardingDashboardController.getDashboard';
import completeStepApex from '@salesforce/apex/OnboardingDashboardController.completeStep';
import completeItemApex from '@salesforce/apex/OnboardingDashboardController.completeItem';

export default class OnboardingHub extends LightningElement {
    // ── Public config (App Builder / Experience Builder) ──
    @api recordId;                       // when placed on a Checklist record page
    @api checklistId;                    // explicit override
    @api configName;                     // branding profile, e.g. "Citi"
    @api isInternal = false;             // true = internal ops view, false = portal view

    // ── State ──
    @track data;
    @track error;
    @track expandedItems = {};
    detailsExpanded = true;
    activeFilter = 'all';
    wiredResult;

    // ── Wire ──
    @wire(getDashboard, { checklistId: '$resolvedChecklistId', configName: '$configName', isInternal: '$isInternal' })
    wiredDashboard(result) {
        this.wiredResult = result;
        if (result.data) {
            this.data = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.data = undefined;
        }
    }

    get resolvedChecklistId() {
        return this.checklistId || this.recordId;
    }

    // ── Render-state getters ──
    get isLoading() {
        return !this.data && !this.error;
    }
    get isReady() {
        return !!this.data;
    }
    get hasError() {
        return !!this.error;
    }
    get errorMessage() {
        return this.error?.body?.message || 'Unable to load the onboarding dashboard.';
    }

    get checklist() {
        return this.data ? this.data.checklist : {};
    }
    get brand() {
        return this.data ? this.data.brand : {};
    }
    get itemsTotal() {
        return this.data ? this.data.itemsTotal : 0;
    }
    get itemsComplete() {
        return this.data ? this.data.itemsComplete : 0;
    }
    get progressPercent() {
        return this.data ? this.data.progressPercent : 0;
    }
    get progressDisplay() {
        return Math.round(this.progressPercent) + '%';
    }

    get showBusinessDetails() {
        return this.brand && this.brand.showBusinessDetails && this.isInternal;
    }
    get showInternalNotes() {
        return this.isInternal === true;
    }

    get overdueCount() {
        if (!this.data) return 0;
        return this.data.items.filter(i => i.isOverdue).length;
    }
    get noItems() {
        return this.displayItems.length === 0;
    }

    // ── Branding styles (CSS custom properties) ──
    get brandStyle() {
        const b = this.brand || {};
        return [
            `--brand-primary: ${b.primaryColor || '#1B3A5C'}`,
            `--brand-secondary: ${b.secondaryColor || '#2E75B6'}`,
            `--brand-accent: ${b.accentColor || '#0D7C8F'}`
        ].join(';');
    }

    get ringStyle() {
        const circumference = 2 * Math.PI * 52;
        const offset = circumference - (this.progressPercent / 100) * circumference;
        return `stroke-dasharray: ${circumference}; stroke-dashoffset: ${offset};`;
    }
    get barStyle() {
        return `width: ${this.progressPercent}%;`;
    }

    // ── Business detail fields (populated by AI) ──
    get businessFields() {
        const c = this.checklist;
        const fields = [
            { label: 'Legal Entity Name', value: c.Legal_Entity_Name__c },
            { label: 'DBA Name', value: c.DBA_Name__c },
            { label: 'Business Address', value: c.Business_Address__c },
            { label: 'Tax ID / EIN', value: c.Tax_ID__c },
            { label: 'Date of Incorporation', value: c.Date_of_Incorporation__c },
            { label: 'Client Segment', value: c.Client_Segment__c }
        ];
        return fields.map(f => ({ ...f, value: f.value || '—' }));
    }

    get detailsChevron() {
        return this.detailsExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    // ── Filters ──
    get filterOptions() {
        const opts = [
            { value: 'all', label: 'All' },
            { value: 'open', label: 'Open' },
            { value: 'overdue', label: 'Overdue' },
            { value: 'complete', label: 'Complete' }
        ];
        return opts.map(o => ({
            ...o,
            cssClass: this.activeFilter === o.value ? 'filter-pill filter-pill-active' : 'filter-pill'
        }));
    }

    // ── The rendered item rows ──
    get displayItems() {
        if (!this.data) return [];
        return this.data.items
            .filter(row => {
                if (this.activeFilter === 'all') return true;
                if (this.activeFilter === 'complete') return row.item.Status__c === 'Completed';
                if (this.activeFilter === 'overdue') return row.isOverdue;
                if (this.activeFilter === 'open') return row.item.Status__c !== 'Completed';
                return true;
            })
            .map(row => {
                const isComplete = row.item.Status__c === 'Completed';
                const expanded = !!this.expandedItems[row.item.Id];
                const hasSteps = row.steps && row.steps.length > 0;

                return {
                    ...row,
                    isComplete,
                    expanded,
                    hasSteps,
                    cardClass: expanded ? 'item-card item-card-open' : 'item-card',
                    chevronIcon: expanded ? 'utility:chevronup' : 'utility:chevrondown',
                    statusDotClass: this.dotClassFor(row.item.Status__c, row.isOverdue),
                    statusBadgeClass: this.badgeClassFor(row.item.Status__c, row.isOverdue),
                    dueDateDisplay: this.formatDate(row.item.Due_Date__c),
                    stepsCompleteDisplay: hasSteps
                        ? `${row.item.Steps_Complete__c || 0}/${row.item.Steps_Total__c || row.steps.length} steps`
                        : '',
                    steps: (row.steps || []).map(s => ({
                        ...s,
                        isComplete: s.Status__c === 'Completed',
                        canComplete: s.Status__c !== 'Completed' && this.isInternal,
                        dotClass: s.Status__c === 'Completed' ? 'step-dot step-dot-done' : 'step-dot'
                    }))
                };
            });
    }

    dotClassFor(status, overdue) {
        if (status === 'Completed') return 'status-dot status-dot-complete';
        if (overdue) return 'status-dot status-dot-overdue';
        if (status === 'In Progress') return 'status-dot status-dot-progress';
        return 'status-dot';
    }
    badgeClassFor(status, overdue) {
        if (status === 'Completed') return 'status-badge badge-complete';
        if (overdue) return 'status-badge badge-overdue';
        if (status === 'In Progress') return 'status-badge badge-progress';
        if (status === 'Under Review') return 'status-badge badge-review';
        return 'status-badge badge-default';
    }
    formatDate(dateStr) {
        if (!dateStr) return '';
        const d = new Date(dateStr + 'T00:00:00');
        return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    }

    // ── Handlers ──
    toggleDetails() {
        this.detailsExpanded = !this.detailsExpanded;
    }
    toggleItem(event) {
        const id = event.currentTarget.dataset.id;
        this.expandedItems = { ...this.expandedItems, [id]: !this.expandedItems[id] };
    }
    handleFilter(event) {
        this.activeFilter = event.currentTarget.dataset.filter;
    }

    handleCompleteStep(event) {
        event.stopPropagation();
        const stepId = event.currentTarget.dataset.id;
        completeStepApex({ stepId })
            .then(() => {
                this.toast('Step completed', 'Progress updated.', 'success');
                return refreshApex(this.wiredResult);
            })
            .catch(e => this.toast('Error', this.msg(e), 'error'));
    }

    handleCompleteItem(event) {
        event.stopPropagation();
        const itemId = event.currentTarget.dataset.id;
        completeItemApex({ itemId })
            .then(() => {
                this.toast('Item completed', 'The checklist item is marked complete.', 'success');
                return refreshApex(this.wiredResult);
            })
            .catch(e => this.toast('Error', this.msg(e), 'error'));
    }

    handleAnalyze(event) {
        event.stopPropagation();
        // Phase 2 wires this to real Agentforce Prompt Builder document analysis.
        this.toast('AI Analysis', 'Document analysis runs in Phase 2 (Agentforce Prompt Builder).', 'info');
    }
    handleGenerateDoc(event) {
        event.stopPropagation();
        this.toast('Generate & Send', 'Document generation + email is built in Phase 3.', 'info');
    }
    handleRemind(event) {
        event.stopPropagation();
        this.toast('Reminder', 'Reminder engine with escalation is built in Phase 3.', 'info');
    }

    // ── Utils ──
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    msg(e) {
        return e?.body?.message || 'Something went wrong.';
    }
}
