/**
 * RecurringPaymentSchedulerTest
 * Tests the schedulable class RecurringPaymentScheduler.
 *
 * Verifies:
 * - Scheduler runs via System.schedule within Test.startTest/stopTest
 * - Creates Expense__c for eligible Recurring_Payment__c (Next_Billing_Date__c = today, Active, Auto_Create_Expense__c = true)
 * - Advances Next_Billing_Date__c correctly for each Billing_Cycle__c value
 * - Ineligible records do not create expenses and are not updated
 *
 * Note:
 * The production class performs DML inside the loop. These tests account for current behavior
 * while asserting correct outcomes.
 */
@IsTest
private class RecurringPaymentSchedulerTest {

    /**
     * Common test data creation.
     * Creates an Account used for Debit_Account__c lookup on Expense__c.
     */
    @TestSetup
    static void setupData() {
        Account a = new Account(Name = 'Test Debit Account', Current_Balance__c = 50000);
        insert a;
    }

    /**
     * Helper to create Recurring_Payment__c records with flexible attributes.
     */
    private static Recurring_Payment__c newRecurringPayment(
        String name,
        String category,
        String subCategory,
        Decimal amount,
        String billingCycle,
        Date nextBillingDate,
        String status,
        Boolean autoCreate,
        Id accountId
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
        rp.Account__c = accountId;
        return rp;
    }

    /**
     * Schedules the RecurringPaymentScheduler and ensures it executes within the test context.
     */
    private static void runScheduler() {
        // Any valid CRON in the future; actual time is irrelevant in tests since stopTest runs queued jobs.
        String cron = '0 0 0 15 3 ? 2050';
        System.schedule('RecurringPaymentSchedulerTestJob', cron, new RecurringPaymentScheduler());
    }

    /**
     * Validates that expenses are created and next billing dates are advanced for each billing cycle option.
     */
    @IsTest
    static void testCreatesExpensesAndAdvancesDates_ForAllBillingCycles() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Date today = Date.today();

        // Choose Category__c values that are ALSO valid for Expense__c.Type__c to avoid restricted picklist conflicts.
        // Using only values common to both sets: Education, Health & Fitness, Travel (and other valid Expense types where needed).
        // Ensure Sub_Category__c has a valid value by explicitly overriding when needed (helper sets a default too).
        // To align with scheduler hardcoded Sub_Type__c = 'Doctor Visits', make all eligible records Type/Category = 'Health & Fitness'
        // so that dependent Sub_Type__c is valid.
        List<Recurring_Payment__c> recs = new List<Recurring_Payment__c>{
            newRecurringPayment('Monthly RP', 'Bills & Utilities','Electricity', 100, 'Monthly', today, 'Active', true, acct.Id),
            newRecurringPayment('Yearly RP', 'Health & Fitness','Gym Membership', 200, 'Yearly', today, 'Active', true, acct.Id),
            newRecurringPayment('Quarterly RP', 'Education','Courses', 300, 'Quaterly', today, 'Active', true, acct.Id),
            newRecurringPayment('Half Yearly RP', 'Transport','Fuel', 400, 'Half Yearly', today, 'Active', true, acct.Id),
            newRecurringPayment('Nine Months RP', 'Food & Dining','Dining Out', 500, '9 Months', today, 'Active', true, acct.Id)
        };
        insert recs;

        Test.startTest();
        runScheduler();
        Test.stopTest();

        // Assert 5 expenses created
        List<Expense__c> expenses = [
            SELECT Id, Name, Debited_On__c, Type__c, Sub_Type__c, Debit_Amount__c, Debit_Account__c
            FROM Expense__c
        ];
        System.assertEquals(5, expenses.size(), 'Exactly one Expense__c should be created for each eligible RP');

        // Validate field mappings for each created expense
        Map<String, Expense__c> expByName = new Map<String, Expense__c>();
        for (Expense__c e : expenses) {
            expByName.put(e.Name, e);
            System.assertEquals(today, e.Debited_On__c, 'Debited_On__c must be today');
            System.assertNotEquals(null, e.Debit_Account__c, 'Debit_Account__c must be set from RP.Account__c');
        }

        // Reload Recurring_Payment__c to assert date advancement
        List<Recurring_Payment__c> updated = [
            SELECT Id, Name, Billing_Cycle__c, Next_Billing_Date__c
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

        // Ensure there is an expense with each expected name
        System.assert(expByName.containsKey('Monthly RP'), 'Expense for Monthly RP should exist');
        System.assert(expByName.containsKey('Yearly RP'), 'Expense for Yearly RP should exist');
        System.assert(expByName.containsKey('Quarterly RP'), 'Expense for Quaterly RP should exist');
        System.assert(expByName.containsKey('Half Yearly RP'), 'Expense for Half Yearly RP should exist');
        System.assert(expByName.containsKey('Nine Months RP'), 'Expense for 9 Months RP should exist');
    }

    /**
     * Validates no expenses are created for ineligible records and dates are not changed.
     * Ineligible scenarios:
     * - Next_Billing_Date__c not today
     * - Status__c not Active
     * - Auto_Create_Expense__c = false
     */
    @IsTest
    static void testNoCreation_ForIneligibleRecords() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Date today = Date.today();

        // Ineligible records also use values valid for Expense__c.Type__c to avoid Type__c DML failures.
        Recurring_Payment__c notToday = newRecurringPayment('Not Today', 'Education','Courses', 50, 'Monthly', today.addDays(1), 'Active', true, acct.Id);
        Recurring_Payment__c inactive = newRecurringPayment('Inactive', 'Education','Courses', 60, 'Monthly', today, 'Cancelled', true, acct.Id);
        Recurring_Payment__c autoOff = newRecurringPayment('Auto Off', 'Health & Fitness','Doctor Visits', 70, 'Monthly', today, 'Active', false, acct.Id);
        insert new List<Recurring_Payment__c>{ notToday, inactive, autoOff };

        Test.startTest();
        runScheduler();
        Test.stopTest();

        // No expenses expected
        Integer expCount = [SELECT COUNT() FROM Expense__c];
        System.assertEquals(0, expCount, 'No expenses should be created for ineligible records');

        // Dates should be unchanged for all ineligible records
        Map<Id, Recurring_Payment__c> afterMap = new Map<Id, Recurring_Payment__c>([
            SELECT Id, Next_Billing_Date__c FROM Recurring_Payment__c WHERE Id IN :new List<Id>{ notToday.Id, inactive.Id, autoOff.Id }
        ]);
        System.assertEquals(today.addDays(1), afterMap.get(notToday.Id).Next_Billing_Date__c, 'Date should remain unchanged for not-today');
        System.assertEquals(today, afterMap.get(inactive.Id).Next_Billing_Date__c, 'Date should remain unchanged for non-active (Cancelled)');
        System.assertEquals(today, afterMap.get(autoOff.Id).Next_Billing_Date__c, 'Date should remain unchanged when auto-create is off');
    }
}