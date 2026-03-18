/**
 * @description Test class for PAIDCustomerCreationQueueable
 * @author Manusha T
 */
@isTest
private class PAIDCustomerCreationQueueableTest {
    
    /**
     * @description Mock HTTP callout for successful PAID API response
     */
    public class MockPAIDSuccessCallout implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success":true,"data":{"id":"CUST-12345","externalId":"CUST-12345","displayId":"CUST-12345"}}');
            res.setStatusCode(200);
            return res;
        }
    }
    
    /**
     * @description Mock HTTP callout for failed PAID API response
     */
    public class MockPAIDFailureCallout implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success":false,"error":"Invalid customer data"}');
            res.setStatusCode(400);
            return res;
        }
    }
    
    /**
     * @description Setup test data
     */
    @TestSetup
    static void setupTestData() {
        // Create Accounts
        List<Account> accounts = new List<Account>();
        accounts.add(new Account(
            Name = 'Test Account 1',
            BillingStreet = '123 Main St',
            BillingCity = 'Test City',
            BillingState = 'CA',
            BillingPostalCode = '12345',
            BillingCountry = 'USA'
        ));
        accounts.add(new Account(
            Name = 'Test Account 2',
            BillingStreet = '456 Oak Ave',
            BillingCity = 'Test City',
            BillingState = 'NY',
            BillingPostalCode = '67890',
            BillingCountry = 'USA'
        ));
        accounts.add(new Account(
            Name = 'Account With Existing PAID ID',
            PAID_CustomerExternalID__c = 'EXISTING-CUST-123',
            BillingStreet = '789 Pine Rd',
            BillingCity = 'Test City',
            BillingState = 'TX',
            BillingPostalCode = '11111',
            BillingCountry = 'USA'
        ));
        insert accounts;
        
        // Create Contacts - with PAID External IDs to prevent contact creation queueable
        List<Contact> contacts = new List<Contact>();
        Integer counter = 1;
        for (Account acc : accounts) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + acc.Name,
                Email = 'test.contact' + counter + '@example.com',
                AccountId = acc.Id,
                PAID_ContactExternalID__c = 'CONTACT-' + counter // Prevent contact creation recursion
            ));
            counter++;
        }
        insert contacts;
        
        // Create Product
        Product2 testProduct = new Product2(
            Name = 'Test Product',
            IsActive = true
        );
        insert testProduct;
        
        // Get Standard Pricebook
        Id pricebookId = Test.getStandardPricebookId();
        
        // Create Pricebook Entry
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 100.00,
            IsActive = true
        );
        insert pbe;
        
        // Create Orders
        List<Order> orders = new List<Order>();
        Map<Id, Contact> contactMap = new Map<Id, Contact>(contacts);
        
        for (Account acc : accounts) {
            Contact relatedContact = null;
            for (Contact con : contacts) {
                if (con.AccountId == acc.Id) {
                    relatedContact = con;
                    break;
                }
            }
            
            orders.add(new Order(
                AccountId = acc.Id,
                BillToContactId = relatedContact?.Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Pricebook2Id = pricebookId
            ));
        }
        insert orders;
        
        // Add OrderItems
        List<OrderItem> orderItems = new List<OrderItem>();
        for (Order ord : orders) {
            orderItems.add(new OrderItem(
                OrderId = ord.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = 100.00
            ));
        }
        insert orderItems;
    }
    
    /**
     * @description Test successful customer creation in PAID
     */
    @isTest
    static void testSuccessfulCustomerCreation() {
        // Set mock callout
        Test.setMock(HttpCalloutMock.class, new MockPAIDSuccessCallout());
        
        // Query test data
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 1' LIMIT 1];
        Order ord = [SELECT Id FROM Order WHERE AccountId = :acc.Id LIMIT 1];
        
        Set<Id> orderIds = new Set<Id>{ord.Id};
        Set<Id> accountIds = new Set<Id>{acc.Id};
        
        Test.startTest();
        
        // Execute queueable
        System.enqueueJob(new PAIDCustomerCreationQueueable(orderIds, accountIds));
        
        Test.stopTest();
        
        // Verify Order was updated
        Order updatedOrder = [SELECT Id, Sent_Customer_to_PAID__c, PAID_Customer_Creation_Status__c, 
                              PAID_CustomerExternalID__c 
                              FROM Order WHERE Id = :ord.Id];
        
        System.assertEquals(true, updatedOrder.Sent_Customer_to_PAID__c, 
                          'Order should be marked as sent to PAID');
        System.assertEquals('Success', updatedOrder.PAID_Customer_Creation_Status__c, 
                          'Order status should be Success');
        System.assertEquals('CUST-12345', updatedOrder.PAID_CustomerExternalID__c, 
                          'Order should have PAID Customer External ID');
        
        // Verify Account was updated
        Account updatedAccount = [SELECT Id, PAID_CustomerExternalID__c 
                                  FROM Account WHERE Id = :acc.Id];
        
        System.assertEquals('CUST-12345', updatedAccount.PAID_CustomerExternalID__c, 
                          'Account should have PAID Customer External ID');
        
        // Verify Event Log was created
        List<Event_Log__c> eventLogs = [SELECT Id, Operations_Key__c, Success_Failure__c, 
                                        Account__c, Order__c
                                        FROM Event_Log__c 
                                        WHERE Order__c = :ord.Id];
        
        System.assertEquals(1, eventLogs.size(), 'One event log should be created');
        System.assertEquals('Create Customer', eventLogs[0].Operations_Key__c, 
                          'Event type should be Create Customer');
        System.assertEquals('Success', eventLogs[0].Success_Failure__c, 
                  'Event log should show success');
    }
    
    /**
     * @description Test customer creation failure from API
     */
   @isTest
    static void testCustomerCreationAPIFailure() {
        // Set mock callout for failure
        Test.setMock(HttpCalloutMock.class, new MockPAIDFailureCallout());
        
        // Query test data
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 1' LIMIT 1];
        Order ord = [SELECT Id FROM Order WHERE AccountId = :acc.Id LIMIT 1];
        
        Set<Id> orderIds = new Set<Id>{ord.Id};
        Set<Id> accountIds = new Set<Id>{acc.Id};
        
        Test.startTest();
        
        // Execute queueable
        System.enqueueJob(new PAIDCustomerCreationQueueable(orderIds, accountIds));
        
        Test.stopTest();
        
        // Verify Order was updated with failure status
        Order updatedOrder = [SELECT Id, Sent_Customer_to_PAID__c, PAID_Customer_Creation_Status__c, 
                              PAID_CustomerExternalID__c 
                              FROM Order WHERE Id = :ord.Id];
        
        System.assertEquals(true, updatedOrder.Sent_Customer_to_PAID__c, 
                          'Order should be marked as sent to PAID');
        System.assertEquals('Failure', updatedOrder.PAID_Customer_Creation_Status__c, 
                          'Order status should be Failure');
        System.assertEquals(null, updatedOrder.PAID_CustomerExternalID__c, 
                          'Order should not have PAID Customer External ID');
        
        // Verify Account was NOT updated
        Account updatedAccount = [SELECT Id, PAID_CustomerExternalID__c 
                                  FROM Account WHERE Id = :acc.Id];
        
        System.assertEquals(null, updatedAccount.PAID_CustomerExternalID__c, 
                          'Account should not have PAID Customer External ID');
        
       // Verify Event Log was created with failure
        List<Event_Log__c> eventLogs = [SELECT Id, Operations_Key__c, Success_Failure__c, 
                                        Error_Message__c
                                        FROM Event_Log__c 
                                        WHERE Order__c = :ord.Id];
        
        System.assertEquals(1, eventLogs.size(), 'One event log should be created');
        System.assertEquals('Failure', eventLogs[0].Success_Failure__c, 
                  'Event log should show failure');
        System.assertNotEquals(null, eventLogs[0].Error_Message__c, 
                             'Event log should have error message');
    
    }
    
    /**
     * @description Test with empty order and account sets
     */
    @isTest
    static void testEmptyOrderAndAccountSets() {
        // Set mock callout
        Test.setMock(HttpCalloutMock.class, new MockPAIDSuccessCallout());
        
        Set<Id> emptyOrderIds = new Set<Id>();
        Set<Id> emptyAccountIds = new Set<Id>();
        
        Test.startTest();
        
        // Execute queueable with empty sets - should not error
        System.enqueueJob(new PAIDCustomerCreationQueueable(emptyOrderIds, emptyAccountIds));
        
        Test.stopTest();
        
        // If we get here without exception, test passes
        System.assert(true, 'Empty sets handled successfully');
    }
}