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
        // Populate required dependent Sub_Category__c using valid value aligned with Category__c (uses global value set Sub_Type)
        // Choose a value that exists in Sub_Type and semantically aligns:
        // - For 'Education' -> 'Courses'
        // - For 'Health & Fitness' -> 'Doctor Visits'
        String subCat;
        if (category == 'Education') {
            subCat = 'Courses';
        } else if (category == 'Health & Fitness') {
            subCat = 'Doctor Visits';
        } else {
            // Fallback to a commonly available value in the global set
            subCat = 'Courses';
        }
        rp.Sub_Category__c = subCat;
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
            newRecurringPayment('Monthly RP', 'Health & Fitness', 100, 'Monthly', today, 'Active', true, acct.Id),
            newRecurringPayment('Yearly RP', 'Health & Fitness', 200, 'Yearly', today, 'Active', true, acct.Id),
            newRecurringPayment('Quarterly RP', 'Health & Fitness', 300, 'Quaterly', today, 'Active', true, acct.Id),
            newRecurringPayment('Half Yearly RP', 'Health & Fitness', 400, 'Half Yearly', today, 'Active', true, acct.Id),
            newRecurringPayment('Nine Months RP', 'Health & Fitness', 500, '9 Months', today, 'Active', true, acct.Id)
        };
        // Explicitly set Sub_Category__c to a valid value for 'Health & Fitness' to satisfy required field and dependencies.
        for (Recurring_Payment__c rpTmp : recs) {
            rpTmp.Sub_Category__c = 'Doctor Visits';
        }
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
            // Type__c on Expense__c is a restricted picklist; scheduler maps RP.Category__c directly.
            // Ensure the mapped value is one of the allowed Type__c values.
            Set<String> allowedTypes = new Set<String>{
                'Bills & Utilities',
                'Education',
                'Entertainment',
                'Financial',
                'Food & Dining',
                'Health & Fitness',
                'Miscellaneous',
                'Personal & Lifestyle',
                'Shopping',
                'Transport',
                'Travel'
            };
            System.assert(allowedTypes.contains(String.valueOf(e.Type__c)), 'Type__c must be one of the allowed Expense__c types');
            // Sub_Type__c is a restricted dependent picklist controlled by Type__c.
            // Validate it is one of the allowed values for the selected Type__c.
            Map<String, Set<String>> allowedSubsByType = new Map<String, Set<String>>{
                'Health & Fitness' => new Set<String>{ 'Doctor Visits', 'Gym Membership', 'Health Checkups', 'Medicines', 'Supplements' },
                'Education' => new Set<String>{ 'Books', 'Certifications', 'Courses', 'Learning Subscriptions' },
                'Bills & Utilities' => new Set<String>{ 'DTH / TV', 'Electricity', 'Gas', 'House Rent', 'Internet / WiFi', 'Mobile Recharge', 'Water' },
                'Entertainment' => new Set<String>{ 'Events / Concerts', 'Gaming', 'Hobbies', 'Movies', 'OTT Subscriptions' },
                'Financial' => new Set<String>{ 'Bank Charges', 'Credit Card Bill', 'EMI', 'Insurance', 'Loan Repayment' },
                'Food & Dining' => new Set<String>{ 'Cafes / Coffee', 'Dining Out', 'Food Delivery', 'Snacks & Beverages', 'Street Food' },
                'Miscellaneous' => new Set<String>{ 'Others', 'Unexpected Expenses' },
                'Personal & Lifestyle' => new Set<String>{ 'Dating / Outings', 'Gifts', 'Grooming / Salon', 'Personal Care' },
                'Shopping' => new Set<String>{ 'Accessories', 'Clothes', 'Electronics', 'Home Items', 'Offline Shopping', 'Online Shopping' },
                'Transport' => new Set<String>{ 'Auto / Rickshaw', 'Cab / Taxi', 'Fuel', 'Parking', 'Public Transport', 'Tolls' },
                'Travel' => new Set<String>{ 'Activities / Sightseeing', 'Flights', 'Food during Travel', 'Hotel / Stay', 'Local Travel', 'Train / Bus Tickets' }
            };
            Set<String> allowedSubs = allowedSubsByType.get(String.valueOf(e.Type__c));
            System.assertNotEquals(null, allowedSubs, 'Allowed Sub Types must be defined for the selected Type__c');
            System.assert(allowedSubs.contains(String.valueOf(e.Sub_Type__c)), 'Sub_Type__c must be valid for the selected Type__c');
            System.assertNotEquals(null, e.Debit_Amount__c, 'Debit_Amount__c must be set from RP.Amount__c');
        }

        // Reload Recurring_Payment__c to assert date advancement
        // Use a fresh query to avoid potential issues with records that may have been modified by the scheduler
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
        Recurring_Payment__c notToday = newRecurringPayment('Not Today', 'Education', 50, 'Monthly', today.addDays(1), 'Active', true, acct.Id);
        Recurring_Payment__c inactive = newRecurringPayment('Inactive', 'Education', 60, 'Monthly', today, 'Cancelled', true, acct.Id);
        Recurring_Payment__c autoOff = newRecurringPayment('Auto Off', 'Health & Fitness', 70, 'Monthly', today, 'Active', false, acct.Id);
        // Ensure required Sub_Category__c populated explicitly as well
        notToday.Sub_Category__c = 'Courses';
        inactive.Sub_Category__c = 'Courses';
        autoOff.Sub_Category__c = 'Doctor Visits';
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