public with sharing class RecurringPaymentScheduler Implements Schedulable {
    public void execute(SchedulableContext sc){
        try {
            Date TodaysDate = System.today();
            List<Recurring_Payment__c> recurringPayments = [SELECT Id, Name, Category__c, Sub_Category__c, Amount__c, Billing_Cycle__c, Next_Billing_Date__c, Accounts__c, Last_Billing_Date__c, Status__c, Auto_Create_Expense__c
                                                            FROM Recurring_Payment__c
                                                            WHERE Status__c = 'Active'
                                                            AND Auto_Create_Expense__c = TRUE
                                                            AND Next_Billing_Date__c = :TodaysDate
                                                           ];
            List<Expense__c> expenseToCreate = new List<Expense__c>();
            List<Recurring_Payment__c> PaymentToUpdate = new List<Recurring_Payment__c>();
            for(Recurring_Payment__c recurringPayment : recurringPayments){
                if(recurringPayment.Next_Billing_Date__c == TodaysDate && recurringPayment.Last_Billing_Date__c >= TodaysDate){
                    Boolean dateAdvanced = true;
                    switch on recurringPayment.Billing_Cycle__c{
                        when 'Monthly' {
                            recurringPayment.Next_Billing_Date__c = recurringPayment.Next_Billing_Date__c.addMonths(1);
                        }
                        when 'Yearly' {
                            recurringPayment.Next_Billing_Date__c = recurringPayment.Next_Billing_Date__c.addYears(1);
                        }
                        when 'Quaterly' {
                            recurringPayment.Next_Billing_Date__c = recurringPayment.Next_Billing_Date__c.addMonths(3);
                        }
                        when 'Half Yearly' {
                            recurringPayment.Next_Billing_Date__c = recurringPayment.Next_Billing_Date__c.addMonths(6);
                        }
                        when '9 Months' {
                            recurringPayment.Next_Billing_Date__c = recurringPayment.Next_Billing_Date__c.addMonths(9);
                        }
                        when else {
                            dateAdvanced = false;
                        }
                    }
                    if(dateAdvanced) {
                        expenseToCreate.add(new Expense__c(
                            Name = recurringPayment.Name,
                            Debited_On__c = TodaysDate,
                            Type__c = recurringPayment.Category__c,
                            Sub_Type__c = recurringPayment.Sub_Category__c,
                            Debit_Amount__c = recurringPayment.Amount__c,
                            Accounts__c = recurringPayment.Accounts__c,
                            Recurring_Payment__c = recurringPayment.Id
                        ));
                        if(recurringPayment.Next_Billing_Date__c >= recurringPayment.Last_Billing_Date__c) {
                            recurringPayment.Status__c = 'Completed';
                            recurringPayment.Auto_Create_Expense__c = false;
                        }
                        PaymentToUpdate.add(recurringPayment);
                    }
                }
            }
            if(!expenseToCreate.isEmpty()) {
                insert expenseToCreate;
            }
            if(!PaymentToUpdate.isEmpty()) {
                update PaymentToUpdate;
            }
        } catch(Exception e) {
            System.debug(LoggingLevel.ERROR, 'RecurringPaymentScheduler failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

}
