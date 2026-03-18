/**
 * @description Enhanced test class for PAIDCustomerCreationService
 * Targets 90%+ coverage with comprehensive scenario testing
 * @author Manusha T
 */
@isTest
private class PAIDCustomerCreationServiceTest {
    
    /**
     * @description Mock HTTP response - success
     */
    private class MockHttpResponseSuccess implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;
        
        public MockHttpResponseSuccess(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * @description Mock HTTP response - failure
     */
    private class MockHttpResponseFailure implements HttpCalloutMock {
        private Integer statusCode;
        private String errorMessage;
        
        public MockHttpResponseFailure(Integer statusCode, String errorMessage) {
            this.statusCode = statusCode;
            this.errorMessage = errorMessage;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody('{"error": "' + errorMessage + '"}');
            res.setStatus(errorMessage);
            return res;
        }
    }
    
    /**
     * @description Setup test data
     */
    @TestSetup
    static void setupTestData() {
        Id pricebookId = Test.getStandardPricebookId();
        
        List<Account> accounts = new List<Account>();
        
        // Account 1: Complete data
        accounts.add(new Account(
            Name = 'Complete Customer',
            BillingStreet = '123 Main St',
            BillingCity = 'San Francisco',
            BillingState = 'CA',
            BillingPostalCode = '94105',
            BillingCountry = 'USA',
            Phone = '415-555-1234'
        ));
        
        // Account 2: Minimal data (for validation failure)
        accounts.add(new Account(
            Name = 'Incomplete Customer',
            BillingCity = 'New York'
        ));
        
        // Account 3: Another complete account for bulk testing
        accounts.add(new Account(
            Name = 'Second Customer',
            BillingStreet = '456 Oak Ave',
            BillingCity = 'Boston',
            BillingState = 'MA',
            BillingPostalCode = '02101',
            BillingCountry = 'USA',
            Phone = '617-555-5678'
        ));
        
        insert accounts;
        
        List<Order> orders = new List<Order>();
        for (Account acc : accounts) {
            orders.add(new Order(
                AccountId = acc.Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Pricebook2Id = pricebookId
            ));
        }
        insert orders;
    }
    
    /**
     * @description Helper to get test data
     */
    private static Map<String, Object> getTestData(String accountName) {
        // Include all fields that might be in metadata mappings
        Account acc = [SELECT Id, Name, BillingStreet, BillingCity, BillingState, 
                       BillingPostalCode, BillingCountry, Phone, NumberOfEmployees,
                       AnnualRevenue, Website, SBQQ__TaxExempt__c, AccountSource, PAID_CustomerExternalID__c
                       FROM Account WHERE Name = :accountName LIMIT 1];
        
        List<Order> orders = [SELECT Id, AccountId, OrderNumber 
                              FROM Order WHERE AccountId = :acc.Id LIMIT 1];
        
        return new Map<String, Object>{
            'account' => acc,
            'orders' => orders,
            'accountMap' => new Map<Id, Account>{acc.Id => acc}
        };
    }
    
    @isTest
    static void testFailure_401Unauthorized() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseFailure(401, 'Unauthorized'));
        
        Map<String, Object> testData = getTestData('Complete Customer');
        
        Test.startTest();
        PAIDCustomerCreationService.CustomerCreationResult result = 
            PAIDCustomerCreationService.processCustomerCreationBulk(
                (List<Order>)testData.get('orders'), 
                (Map<Id, Account>)testData.get('accountMap')
            );
        Test.stopTest();
        
        System.assertNotEquals(null, result);
    }
    
    @isTest
    static void testResponseParsing_DataAsArray() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess(200, 
            '{"data": [1, 2, 3]}'));
        
        Map<String, Object> testData = getTestData('Complete Customer');
        
        Test.startTest();
        PAIDCustomerCreationService.CustomerCreationResult result = 
            PAIDCustomerCreationService.processCustomerCreationBulk(
                (List<Order>)testData.get('orders'), 
                (Map<Id, Account>)testData.get('accountMap')
            );
        Test.stopTest();
        
        System.assertNotEquals(null, result);
    }

    @isTest
    static void testValidation_MissingRequiredFields() {
        Map<String, Object> testData = getTestData('Incomplete Customer');
        
        Test.startTest();
        PAIDCustomerCreationService.CustomerCreationResult result = 
            PAIDCustomerCreationService.processCustomerCreationBulk(
                (List<Order>)testData.get('orders'), 
                (Map<Id, Account>)testData.get('accountMap')
            );
        Test.stopTest();
        
        System.assertEquals(1, result.ordersToUpdate.size());
        System.assertEquals(1, result.eventLogs.size());
    }
    
    @isTest
    static void testMixedSuccessAndFailure() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess(200, 
            '{"data": {"id": "MIXED-TEST"}}'));
        
        List<Account> accounts = [SELECT Id, Name, BillingStreet, BillingCity, BillingState, 
                                   BillingPostalCode, BillingCountry, Phone, NumberOfEmployees,
                                   AnnualRevenue, Website, SBQQ__TaxExempt__c, AccountSource, PAID_CustomerExternalID__c
                                   FROM Account];
        Map<Id, Account> accountMap = new Map<Id, Account>(accounts);
        List<Order> orders = [SELECT Id, AccountId, OrderNumber 
                              FROM Order WHERE AccountId IN :accountMap.keySet()];
        
        Test.startTest();
        PAIDCustomerCreationService.CustomerCreationResult result = 
            PAIDCustomerCreationService.processCustomerCreationBulk(orders, accountMap);
        Test.stopTest();
        
        System.assertEquals(3, result.ordersToUpdate.size());
    }
    
   @isTest
    static void testParseCustomerIdFromResponse_AllFormats() {
        Test.startTest();
        
        // Test data.id
        String id1 = PAIDCustomerCreationService.parseCustomerIdFromResponse(
            '{"data": {"id": "ID-1"}}');
        System.assertEquals('ID-1', id1);
        
        // Test data.externalId
        String id2 = PAIDCustomerCreationService.parseCustomerIdFromResponse(
            '{"data": {"externalId": "EXT-2"}}');
        System.assertEquals('EXT-2', id2);
        
        // Test data.displayId
        String id3 = PAIDCustomerCreationService.parseCustomerIdFromResponse(
            '{"data": {"displayId": "DISP-3"}}');
        System.assertEquals('DISP-3', id3);
        
        // Test root id
        String id4 = PAIDCustomerCreationService.parseCustomerIdFromResponse(
            '{"id": "ROOT-4"}');
        System.assertEquals('ROOT-4', id4);
        
        // Test root externalId
        String id5 = PAIDCustomerCreationService.parseCustomerIdFromResponse(
            '{"externalId": "ROOT-EXT-5"}');
        System.assertEquals('ROOT-EXT-5', id5);
        
        // Test root customerId
        String id6 = PAIDCustomerCreationService.parseCustomerIdFromResponse(
            '{"customerId": "ROOT-CUST-6"}');
        System.assertEquals('ROOT-CUST-6', id6);
        
        // Test no ID found
        String id7 = PAIDCustomerCreationService.parseCustomerIdFromResponse(
            '{"data": {"status": "ok"}}');
        System.assertEquals(null, id7);
        
        // Test invalid JSON
        String id8 = PAIDCustomerCreationService.parseCustomerIdFromResponse(
            'Invalid JSON {{{');
        System.assertEquals(null, id8);
        
        Test.stopTest();
    }
    
    @isTest
    static void testUpdateCustomer_Success() {
        // Mock successful update response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess(200, 
            '{"data": {"id": "PAID-EXISTING-123"}}'));
    
        // Fetch an existing account
        Account acc = [ SELECT Id, Name, BillingStreet, BillingCity, BillingState, 
                        BillingPostalCode, BillingCountry, Phone, NumberOfEmployees,
                        AnnualRevenue, Website, SBQQ__TaxExempt__c, AccountSource, PAID_CustomerExternalID__c
                        FROM Account
                        WHERE Name = 'Complete Customer'
                        LIMIT 1 ];
    
        // IMPORTANT: Set PAID Customer ID so UPDATE path is used
        acc.PAID_CustomerExternalID__c = 'PAID-EXISTING-123';
        update acc;
    
        Order ord = [
            SELECT Id, AccountId, OrderNumber
            FROM Order
            WHERE AccountId = :acc.Id
            LIMIT 1
        ];
    
        Test.startTest();
        PAIDCustomerCreationService.CustomerCreationResult result =
            PAIDCustomerCreationService.processCustomerCreationBulk(
                new List<Order>{ ord },
                new Map<Id, Account>{ acc.Id => acc }
            );
        Test.stopTest();
    
        // Assertions
        System.assertEquals(1, result.ordersToUpdate.size());
        System.assertEquals('Success', result.ordersToUpdate[0].PAID_Customer_Creation_Status__c);
        System.assertEquals(1, result.accountsToUpdate.size());
        System.assertEquals(1, result.eventLogs.size());
    }

}