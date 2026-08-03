/**
 * RecurringPaymentSchedulerTest
 * Tests the schedulable class RecurringPaymentScheduler.
 *
 * Verifies:
 * - Scheduler runs via System.schedule within Test.startTest/stopTest
 * - Creates Expense__c for eligible Recurring_Payment__c (Next_Billing_Date__c = today, Active, Auto_Create_Expense__c = true)
 * - Advances Next_Billing_Date__c correctly for each Billing_Cycle__c value
 * - Marks recurring payments Completed when the next billing date goes past the last billing date
 * - Leaves ineligible records unchanged
 */
@IsTest
private class RecurringPaymentSchedulerTest {

    @TestSetup
    static void setupData() {
        Accounts__c accountRecord = new Accounts__c(
            Name = 'Test Debit Account',
            Current_Balance__c = 500000,
            Type__c = 'Bank Account',
            Account_Number__c = '123456'
        );
        insert accountRecord;
    }

    private static Recurring_Payment__c newRecurringPayment(
        String name,
        String category,
        String subCategory,
        Decimal amount,
        String billingCycle,
        Date nextBillingDate,
        String status,
        Boolean autoCreate,
        Id accountId,
        Date lastBillingDate
    ) {
        Recurring_Payment__c rp = new Recurring_Payment__c();
        rp.Name = name;
        rp.Category__c = category;
        rp.Sub_Category__c = subCategory;
        rp.Amount__c = amount;
        rp.Billing_Cycle__c = billingCycle;
        rp.Next_Billing_Date__c = nextBillingDate;
        rp.Status__c = status;
        rp.Auto_Create_Expense__c = autoCreate;
        rp.Accounts__c = accountId;
        rp.Last_Billing_Date__c = lastBillingDate;
        return rp;
    }

    private static void runScheduler() {
        String cron = '0 0 0 15 3 ? 2050';
        System.schedule('RecurringPaymentSchedulerTestJob', cron, new RecurringPaymentScheduler());
    }

    @IsTest
    static void testCreatesExpensesAndAdvancesDates_ForAllBillingCycles() {
        Accounts__c acct = [SELECT Id FROM Accounts__c LIMIT 1];
        Date today = Date.today();

        List<Recurring_Payment__c> recs = new List<Recurring_Payment__c>{
            newRecurringPayment('Monthly RP', 'Bills & Utilities', 'Electricity', 100, 'Monthly', today, 'Active', true, acct.Id, Date.valueOf('2029-01-01')),
            newRecurringPayment('Yearly RP', 'Health & Fitness', 'Gym Membership', 200, 'Yearly', today, 'Active', true, acct.Id, Date.valueOf('2029-01-01')),
            newRecurringPayment('Quarterly RP', 'Education', 'Courses', 300, 'Quaterly', today, 'Active', true, acct.Id, Date.valueOf('2029-01-01')),
            newRecurringPayment('Half Yearly RP', 'Transport', 'Fuel', 400, 'Half Yearly', today, 'Active', true, acct.Id, Date.valueOf('2029-01-01')),
            newRecurringPayment('Nine Months RP', 'Food & Dining', 'Dining Out', 500, '9 Months', today, 'Active', true, acct.Id, Date.valueOf('2029-01-01'))
        };
        insert recs;

        Test.startTest();
        runScheduler();
        Test.stopTest();

        List<Expense__c> expenses = [
            SELECT Id, Name, Debited_On__c, Type__c, Sub_Type__c, Debit_Amount__c, Accounts__c
            FROM Expense__c
        ];
        System.assertEquals(5, expenses.size(), 'Exactly one Expense__c should be created for each eligible RP');

        Map<String, Expense__c> expByName = new Map<String, Expense__c>();
        for (Expense__c e : expenses) {
            expByName.put(e.Name, e);
            System.assertEquals(today, e.Debited_On__c, 'Debited_On__c must be today');
            System.assertNotEquals(null, e.Accounts__c, 'Accounts__c must be set from RP.Accounts__c');
        }

        List<Recurring_Payment__c> updated = [
            SELECT Id, Name, Billing_Cycle__c, Next_Billing_Date__c, Last_Billing_Date__c, Status__c, Auto_Create_Expense__c
            FROM Recurring_Payment__c
            WHERE Id IN :recs
        ];
        Map<String, Recurring_Payment__c> rpByName = new Map<String, Recurring_Payment__c>();
        for (Recurring_Payment__c rp : updated) {
            rpByName.put(rp.Name, rp);
        }

        System.assertEquals(today.addMonths(1), rpByName.get('Monthly RP').Next_Billing_Date__c, 'Monthly should +1 month');
        System.assertEquals(today.addYears(1), rpByName.get('Yearly RP').Next_Billing_Date__c, 'Yearly should +1 year');
        System.assertEquals(today.addMonths(3), rpByName.get('Quarterly RP').Next_Billing_Date__c, 'Quaterly should +3 months');
        System.assertEquals(today.addMonths(6), rpByName.get('Half Yearly RP').Next_Billing_Date__c, 'Half Yearly should +6 months');
        System.assertEquals(today.addMonths(9), rpByName.get('Nine Months RP').Next_Billing_Date__c, '9 Months should +9 months');

        System.assertEquals('Completed', rpByName.get('Monthly RP').Status__c, 'Monthly RP should be Completed once the new next billing date exceeds the last billing date');
        System.assertEquals(false, rpByName.get('Monthly RP').Auto_Create_Expense__c, 'Auto-create should be turned off after deactivation');

        System.assert(expByName.containsKey('Monthly RP'), 'Expense for Monthly RP should exist');
        System.assert(expByName.containsKey('Yearly RP'), 'Expense for Yearly RP should exist');
        System.assert(expByName.containsKey('Quarterly RP'), 'Expense for Quaterly RP should exist');
        System.assert(expByName.containsKey('Half Yearly RP'), 'Expense for Half Yearly RP should exist');
        System.assert(expByName.containsKey('Nine Months RP'), 'Expense for 9 Months RP should exist');
    }

    @IsTest
    static void testMarksRecurringPaymentsCompleted_WhenNextDateExceedsLastBillingDate() {
        Accounts__c acct = [SELECT Id FROM Accounts__c LIMIT 1];
        Date today = Date.today();

        Recurring_Payment__c rp = newRecurringPayment(
            'Monthly RP',
            'Bills & Utilities',
            'Electricity',
            100,
            'Monthly',
            today,
            'Active',
            true,
            acct.Id,
            Date.valueOf('2023-01-01')
        );
        insert rp;

        Test.startTest();
        runScheduler();
        Test.stopTest();

        List<Expense__c> expenses = [SELECT Id FROM Expense__c WHERE Recurring_Payment__c = :rp.Id];
        System.assertEquals(1, expenses.size(), 'An expense should be created for the eligible recurring payment');

        Recurring_Payment__c updated = [
            SELECT Status__c, Auto_Create_Expense__c, Next_Billing_Date__c, Last_Billing_Date__c
            FROM Recurring_Payment__c
            WHERE Id = :rp.Id
        ];
        System.assertEquals('Completed', updated.Status__c, 'The recurring payment should be marked Completed when the next billing date exceeds the last billing date');
        System.assertEquals(false, updated.Auto_Create_Expense__c, 'Auto-create should be disabled when the recurring payment is deactivated');
        System.assertEquals(today.addMonths(1), updated.Next_Billing_Date__c, 'Next billing date should be advanced by one month');
        System.assertEquals(today, updated.Last_Billing_Date__c, 'Last billing date should be updated to today');
    }

    @IsTest
    static void testNoCreation_ForIneligibleRecords() {
        Accounts__c acct = [SELECT Id FROM Accounts__c LIMIT 1];
        Date today = Date.today();

        Recurring_Payment__c notToday = newRecurringPayment('Not Today', 'Education', 'Courses', 50, 'Monthly', today.addDays(1), 'Active', true, acct.Id, Date.valueOf('2029-01-01'));
        Recurring_Payment__c Completed = newRecurringPayment('Completed', 'Education', 'Courses', 60, 'Monthly', today, 'Cancelled', true, acct.Id, Date.valueOf('2029-01-01'));
        Recurring_Payment__c autoOff = newRecurringPayment('Auto Off', 'Health & Fitness', 'Doctor Visits', 70, 'Monthly', today, 'Active', false, acct.Id, Date.valueOf('2029-01-01'));
        Recurring_Payment__c pastLastBilling = newRecurringPayment('Past Last Billing Date', 'Health & Fitness', 'Doctor Visits', 70, 'Monthly', today, 'Active', true, acct.Id, Date.valueOf('2026-07-27'));
        Recurring_Payment__c todayLastBilling = newRecurringPayment('Today Last Billing Date', 'Health & Fitness', 'Doctor Visits', 70, 'Monthly', today, 'Active', true, acct.Id, Date.valueOf('2026-07-31'));
        insert new List<Recurring_Payment__c>{ notToday, Completed, autoOff, pastLastBilling, todayLastBilling };

        Test.startTest();
        runScheduler();
        Test.stopTest();

        Integer expCount = [SELECT COUNT() FROM Expense__c];
        System.assertEquals(0, expCount, 'No expenses should be created for ineligible records');

        Map<Id, Recurring_Payment__c> afterMap = new Map<Id, Recurring_Payment__c>([
            SELECT Id, Next_Billing_Date__c, Last_Billing_Date__c FROM Recurring_Payment__c WHERE Id IN :new List<Id>{ notToday.Id, Completed.Id, autoOff.Id, pastLastBilling.Id, todayLastBilling.Id }
        ]);
        System.assertEquals(today.addDays(1), afterMap.get(notToday.Id).Next_Billing_Date__c, 'Date should remain unchanged for not-today');
        System.assertEquals(today, afterMap.get(Completed.Id).Next_Billing_Date__c, 'Date should remain unchanged for non-active (Cancelled)');
        System.assertEquals(today, afterMap.get(autoOff.Id).Next_Billing_Date__c, 'Date should remain unchanged when auto-create is off');
        System.assertEquals(today, afterMap.get(pastLastBilling.Id).Next_Billing_Date__c, 'Date should remain unchanged when last billing date is past today');
        System.assertEquals(today, afterMap.get(todayLastBilling.Id).Next_Billing_Date__c, 'Date should remain unchanged when last billing date is today');
    }
}