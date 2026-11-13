/**
 * OnboardingReminderScheduler — schedules the reminder/escalation batch.
 * Run once from Execute Anonymous:  OnboardingReminderScheduler.scheduleDaily();
 */
public with sharing class OnboardingReminderScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new OnboardingReminderBatch(), 50);
    }

    /** Schedules a daily 7:00 run and returns the job Id. */
    public static String scheduleDaily() {
        return System.schedule('Onboarding Reminders Daily', '0 0 7 * * ?', new OnboardingReminderScheduler());
    }
}
