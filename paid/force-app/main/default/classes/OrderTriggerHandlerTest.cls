/**
 * @description Test class for OrderTriggerHandler
 * @author Manusha T
 */
@isTest
private class OrderTriggerHandlerTest {
    
    /**
     * @description Setup test data including Accounts, Contacts, Products, Pricebooks, and Orders
     */
    @TestSetup
    static void setupTestData() {
        // Create test Accounts
        Account accWithoutExternalId = new Account(
            Name = 'Test Account Without External ID'
        );
        insert accWithoutExternalId;
        
        Account accWithExternalId = new Account(
            Name = 'Test Account With External ID',
            PAID_CustomerExternalID__c = 'CUST-12345'
        );
        insert accWithExternalId;
        
        // Create test Contacts
        Contact conWithoutExternalId = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john.doe@test.com',
            AccountId = accWithExternalId.Id
        );
        insert conWithoutExternalId;
        
        Contact conWithExternalId = new Contact(
            FirstName = 'Jane',
            LastName = 'Smith',
            Email = 'jane.smith@test.com',
            AccountId = accWithExternalId.Id,
            PAID_ContactExternalID__c = 'CONTACT-67890'
        );
        insert conWithExternalId;
        
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
    }
    
    /**
     * @description Test Order activation when Account has Customer ID but Contact doesn't
     * Should trigger contact creation only
     */
    @isTest
    static void testOrderActivationWithCustomerWithoutContact() {
        // Query Account with External ID
        Account acc = [SELECT Id, PAID_CustomerExternalID__c 
                       FROM Account 
                       WHERE PAID_CustomerExternalID__c = 'CUST-12345' 
                       LIMIT 1];
        
        // Query Contact without External ID
        Contact con = [SELECT Id, PAID_ContactExternalID__c 
                       FROM Contact 
                       WHERE AccountId = :acc.Id 
                       AND PAID_ContactExternalID__c = null 
                       LIMIT 1];
        
        // Query PricebookEntry
        PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice 
                              FROM PricebookEntry 
                              WHERE Pricebook2Id = :Test.getStandardPricebookId() 
                              LIMIT 1];
        
        // Create Draft Order
        Order testOrder = new Order(
            AccountId = acc.Id,
            BillToContactId = con.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOrder;
        
        // Add OrderItem (required for Order activation)
        OrderItem oi = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = pbe.UnitPrice
        );
        insert oi;
        
        Test.startTest();
        
        // Activate the Order
        testOrder.Status = 'Activated';
        update testOrder;
        
        Test.stopTest();
        
        // Verify Order was activated
        System.assertEquals('Activated', [SELECT Status FROM Order WHERE Id = :testOrder.Id].Status, 
                          'Order should be activated');
    }
    
    /**
     * @description Test Order activation when both Account and Contact have External IDs
     * Should not trigger any PAID creation
     */
    @isTest
    static void testOrderActivationWithBothExternalIds() {
        // Query Account with External ID
        Account acc = [SELECT Id, PAID_CustomerExternalID__c 
                       FROM Account 
                       WHERE PAID_CustomerExternalID__c = 'CUST-12345' 
                       LIMIT 1];
        
        // Query Contact with External ID
        Contact con = [SELECT Id, PAID_ContactExternalID__c 
                       FROM Contact 
                       WHERE AccountId = :acc.Id 
                       AND PAID_ContactExternalID__c = 'CONTACT-67890' 
                       LIMIT 1];
        
        // Query PricebookEntry
        PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice 
                              FROM PricebookEntry 
                              WHERE Pricebook2Id = :Test.getStandardPricebookId() 
                              LIMIT 1];
        
        // Create Draft Order with External IDs already set
        Order testOrder = new Order(
            AccountId = acc.Id,
            BillToContactId = con.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId(),
            PAID_CustomerExternalID__c = 'CUST-12345',
            PAID_ContactExternalID__c = 'CONTACT-67890'
        );
        insert testOrder;
        
        // Add OrderItem (required for Order activation)
        OrderItem oi = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = pbe.UnitPrice
        );
        insert oi;
        
        Test.startTest();
        
        // Activate the Order - should not trigger any PAID creation
        testOrder.Status = 'Activated';
        update testOrder;
        
        Test.stopTest();
        
        // Verify Order was activated
        System.assertEquals('Activated', [SELECT Status FROM Order WHERE Id = :testOrder.Id].Status, 
                          'Order should be activated');
    }
    
    
    
    /**
     * @description Test Order activation without BillToContact
     * Should still process for customer creation but not contact creation
     */
    @isTest
    static void testOrderActivationWithoutContact() {
        // Query Account without External ID
        Account acc = [SELECT Id FROM Account 
                       WHERE PAID_CustomerExternalID__c = null 
                       LIMIT 1];
        
        // Query PricebookEntry
        PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice 
                              FROM PricebookEntry 
                              WHERE Pricebook2Id = :Test.getStandardPricebookId() 
                              LIMIT 1];
        
        // Create Draft Order without BillToContact
        Order testOrder = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOrder;
        
        // Add OrderItem (required for Order activation)
        OrderItem oi = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = pbe.UnitPrice
        );
        insert oi;
        
        Test.startTest();
        
        // Activate the Order
        testOrder.Status = 'Activated';
        update testOrder;
        
        Test.stopTest();
        
        // Verify Order was activated
        System.assertEquals('Activated', [SELECT Status FROM Order WHERE Id = :testOrder.Id].Status, 
                          'Order should be activated');
    }

    /**
     * @description Test multiple orders activation in bulk
     * Should handle bulk processing correctly
     */
    @isTest
    static void testBulkOrderActivation() {
        // Query Accounts
        List<Account> accounts = [SELECT Id FROM Account WHERE PAID_CustomerExternalID__c = null];
        
        // Query PricebookEntry
        PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice 
                              FROM PricebookEntry 
                              WHERE Pricebook2Id = :Test.getStandardPricebookId() 
                              LIMIT 1];
        
        List<Order> ordersToInsert = new List<Order>();
        
        // Create multiple Draft Orders
        for (Account acc : accounts) {
            ordersToInsert.add(new Order(
                AccountId = acc.Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Pricebook2Id = Test.getStandardPricebookId()
            ));
        }
        
        insert ordersToInsert;
        
        // Add OrderItems to each Order (required for activation)
        List<OrderItem> orderItems = new List<OrderItem>();
        for (Order ord : ordersToInsert) {
            orderItems.add(new OrderItem(
                OrderId = ord.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = pbe.UnitPrice
            ));
        }
        insert orderItems;
        
        Test.startTest();
        
        // Activate all Orders
        for (Order ord : ordersToInsert) {
            ord.Status = 'Activated';
        }
        update ordersToInsert;
        
        Test.stopTest();
        
        // Verify all Orders were activated
        List<Order> activatedOrders = [SELECT Status FROM Order WHERE Id IN :ordersToInsert];
        for (Order ord : activatedOrders) {
            System.assertEquals('Activated', ord.Status, 'Order should be activated');
        }
    }
}