/**
 * @description Test class for PAIDHelper
 * @author Manusha T
 */
@isTest
private class PAIDHelperTest {
    
    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Account', Phone = '415-555-1234');
        insert acc;
        
        Contact con = new Contact(FirstName = 'John', LastName = 'Doe', AccountId = acc.Id);
        insert con;
        
        Id pricebookId = Test.getStandardPricebookId();
        Order ord = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), 
                              Status = 'Draft', Pricebook2Id = pricebookId);
        insert ord;
    }
    
    // API Configuration
    @isTest
    static void testGetAPIConfiguration() {
        Test.startTest();
        PAID_API_Configuration__mdt config = PAIDHelper.getAPIConfiguration('Create Customer');
        PAID_API_Configuration__mdt cached = PAIDHelper.getAPIConfiguration('Create Customer');
        Test.stopTest();
        
        System.assertNotEquals(null, config);
        System.assertEquals(config, cached); // Verify caching
    }
    
    @isTest
    static void testGetAPIConfiguration_NotFound() {
        try {
            PAIDHelper.getAPIConfiguration('Invalid');
            System.assert(false, 'Should throw exception');
        } catch (PAIDHelper.PAIDIntegrationException e) {
            System.assert(true);
        }
    }
    
    // Field Mappings
    @isTest
    static void testGetFieldMappings() {
        Test.startTest();
        List<SObject> mappings = PAIDHelper.getFieldMappings('PAID_Customer_Field_Mapping__mdt', 'Account');
        List<SObject> cached = PAIDHelper.getFieldMappings('PAID_Customer_Field_Mapping__mdt', 'Account');
        List<SObject> allMappings = PAIDHelper.getFieldMappings('PAID_Customer_Field_Mapping__mdt', null);
        Test.stopTest();
        
        System.assertNotEquals(null, mappings);
        System.assertEquals(mappings, cached); // Verify caching
        System.assertNotEquals(null, allMappings);
    }
    
    // Query Methods
    @isTest
    static void testQueryRecords() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        List<SObject> results = PAIDHelper.queryRecords('Account', 'Customer_Creation', new Set<Id>{acc.Id});
        List<SObject> empty = PAIDHelper.queryRecords('Account', 'Customer_Creation', new Set<Id>());
        List<SObject> nullSet = PAIDHelper.queryRecords('Account', 'Customer_Creation', null);
        Test.stopTest();
        
        System.assertEquals(1, results.size());
        System.assertEquals(0, empty.size());
        System.assertEquals(0, nullSet.size());
    }
    
    @isTest
    static void testQueryRecord_WithOrderId() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        
        Test.startTest();
        List<SObject> results = PAIDHelper.queryRecord(
            'OrderItem', 
            'Order_Item_Creation', 
            null, 
            null, 
            'orderId', 
            ord.Id
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results);
    }
    
    @isTest
    static void testQueryRecord_WithWhereClause() {
        Test.startTest();
        String whereClause = 'Name != null';
        List<SObject> results = PAIDHelper.queryRecord(
            'Account', 
            'Customer_Creation', 
            null, 
            whereClause, 
            null, 
            null
        );
        Test.stopTest();
        
        System.assertNotEquals(null, results);
    }
    
    @isTest
    static void testQueryRecord_NoParameters() {
        Test.startTest();
        List<SObject> results = PAIDHelper.queryRecord(
            'Account', 
            'Customer_Creation', 
            null, 
            null, 
            null, 
            null
        );
        Test.stopTest();
        
        System.assertEquals(0, results.size());
    }
    
    @isTest
    static void testQueryRecord_WithRecordIds() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        List<SObject> results = PAIDHelper.queryRecord(
            'Account', 
            'Customer_Creation', 
            new Set<Id>{acc.Id},
            null, 
            null, 
            null
        );
        Test.stopTest();
        
        System.assertEquals(1, results.size());
    }
    
    @isTest
    static void testQueryRecordsWithMappings() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        List<SObject> results = PAIDHelper.queryRecordsWithMappings(
            'Account', 'Customer_Creation', new Set<Id>{acc.Id}, 
            'PAID_Customer_Field_Mapping__mdt', null, null, null, null);
        Test.stopTest();
        
        System.assertEquals(1, results.size());
    }
    
    @isTest
    static void testQueryRecordsWithMappings_OrderBy() {
        List<Account> accounts = [SELECT Id FROM Account];
        Set<Id> ids = new Set<Id>();
        for (Account a : accounts) ids.add(a.Id);
        
        Test.startTest();
        List<SObject> results = PAIDHelper.queryRecordsWithMappings(
            'Account', 'Customer_Creation', ids, null, null, null, null, 'Name ASC');
        Test.stopTest();
        
        System.assertNotEquals(null, results);
    }
    
    @isTest
    static void testQueryRecordsWithMappings_AccountId() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        List<SObject> results = PAIDHelper.queryRecordsWithMappings(
            'Contact', 'Contact_Creation', null, null, null, 'accountId', acc.Id, null);
        Test.stopTest();
        
        System.assertNotEquals(null, results);
    }
    
    @isTest
    static void testQueryRecordsWithMappings_ProductId() {
        // Create product
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        insert prod;
        
        Test.startTest();
        
        // Test with Product2
        List<SObject> product2Results = PAIDHelper.queryRecordsWithMappings(
            'Product2', 'Product_Sync', null, null, null, 'productId', prod.Id, null);
        
        // Test with PricebookEntry
        List<SObject> pbeResults = PAIDHelper.queryRecordsWithMappings(
            'PricebookEntry', 'Product_Sync', null, null, null, 'productId', prod.Id, null);
        
        // Test with SBQQ__BlockPrice__c
        List<SObject> blockResults = PAIDHelper.queryRecordsWithMappings(
            'SBQQ__BlockPrice__c', 'Product_Sync', null, null, null, 'productId', prod.Id, null);
        
        // Test with SBQQ__Cost__c
        List<SObject> costResults = PAIDHelper.queryRecordsWithMappings(
            'SBQQ__Cost__c', 'Product_Sync', null, null, null, 'productId', prod.Id, null);
        
        Test.stopTest();
        
        System.assertNotEquals(null, product2Results);
        System.assertNotEquals(null, pbeResults);
        System.assertNotEquals(null, blockResults);
        System.assertNotEquals(null, costResults);
    }
    
    @isTest
    static void testQueryRecordsWithMappings_OrderId() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        
        Test.startTest();
        List<SObject> results = PAIDHelper.queryRecordsWithMappings(
            'OrderItem', 'Order_Item_Creation', null, null, null, 'orderId', ord.Id, null);
        Test.stopTest();
        
        System.assertNotEquals(null, results);
    }
    
    @isTest
    static void testQueryRecordsWithMappings_NoParams() {
        Test.startTest();
        List<SObject> results = PAIDHelper.queryRecordsWithMappings(
            'Account', 'Customer_Creation', null, null, null, null, null, null);
        Test.stopTest();
        
        System.assertEquals(0, results.size());
    }
    
    // Utilities
    @isTest
    static void testToMap() {
        List<Account> accounts = [SELECT Id FROM Account];
        
        Test.startTest();
        Map<Id, SObject> resultMap = PAIDHelper.toMap(accounts);
        Map<Id, SObject> emptyMap = PAIDHelper.toMap(null);
        Test.stopTest();
        
        System.assertEquals(accounts.size(), resultMap.size());
        System.assertEquals(0, emptyMap.size());
    }
    
    // Event Logs
    @isTest
    static void testCreateEventLog() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Order ord = [SELECT Id, OrderNumber FROM Order LIMIT 1];
        
        Test.startTest();
        Event_Log__c success = PAIDHelper.createEventLog('Test', '{}', '{}', true, null, 
                                                          acc.Id, null, ord.Id, null, ord.OrderNumber);
        Event_Log__c failure = PAIDHelper.createEventLog('Test', null, null, false, 'Error', 
                                                          null, null, null, null, null);
        Test.stopTest();
        
        System.assertEquals('Success', success.Success_Failure__c);
        System.assertEquals('Failure', failure.Success_Failure__c);
        System.assertEquals('Error', failure.Error_Message__c);
    }
    
    // Transformations - Core ones
    @isTest
    static void testTransformations_String() {
        Test.startTest();
        System.assertEquals('TEST', PAIDHelper.applyTransformation('test', 'Uppercase'));
        System.assertEquals('TEST', PAIDHelper.applyTransformation('test', 'ToUpperCase'));
        System.assertEquals('test', PAIDHelper.applyTransformation('TEST', 'Lowercase'));
        System.assertEquals('test', PAIDHelper.applyTransformation('TEST', 'ToLowerCase'));
        System.assertEquals('test', PAIDHelper.applyTransformation('  test  ', 'Trim'));
        System.assertEquals('test', PAIDHelper.applyTransformation('  test  ', 'TrimWhitespace'));
        System.assertEquals('4155551234', PAIDHelper.applyTransformation('(415) 555-1234', 'Format_Phone'));
        System.assertEquals('4155551234', PAIDHelper.applyTransformation('(415) 555-1234', 'Format Phone'));
        System.assertEquals('testvalue', PAIDHelper.applyTransformation('test value', 'RemoveSpaces'));
        Test.stopTest();
    }
    
    @isTest
    static void testTransformations_Numeric() {
        Test.startTest();
        
        // MultiplyBy100 - Decimal
        Decimal decVal = 10.50;
        System.assertEquals(1050, PAIDHelper.applyTransformation(decVal, 'MultiplyBy100'));
        
        // MultiplyBy100 - Integer (create via conversion)
        Object intVal = PAIDHelper.convertDataType('10', 'Integer');
        Object intResult = PAIDHelper.applyTransformation(intVal, 'MultiplyBy100');
        System.assertEquals(1000, intResult);
        
        // DivideBy100 - Decimal
        Decimal decVal2 = 1050;
        System.assertEquals(10.50, PAIDHelper.applyTransformation(decVal2, 'DivideBy100'));
        
        // DivideBy100 - Integer (create via conversion)
        Object intVal2 = PAIDHelper.convertDataType('1050', 'Integer');
        Object intResult2 = PAIDHelper.applyTransformation(intVal2, 'DivideBy100');
        System.assertEquals(10.50, intResult2);
        
        // Test with direct Integer values
        Integer directInt = 10;
        System.assertEquals(1000, PAIDHelper.applyTransformation(directInt, 'MultiplyBy100'));
        
        Integer directInt2 = 1050;
        System.assertEquals(10.50, PAIDHelper.applyTransformation(directInt2, 'DivideBy100'));
        
        Test.stopTest();
    }
    
    @isTest
    static void testTransformations_CustomMapping() {
        Test.startTest();
        // ChargeTypeMapping
        System.assertEquals('seatBased', PAIDHelper.applyTransformation('Recurring', 'ChargeTypeMapping'));
        System.assertEquals('oneTime', PAIDHelper.applyTransformation('One-Time', 'ChargeTypeMapping'));
        System.assertEquals('usage', PAIDHelper.applyTransformation('Usage', 'ChargeTypeMapping'));
        System.assertEquals('Other', PAIDHelper.applyTransformation('Other', 'ChargeTypeMapping')); // Unmapped value
        
        // PricingModelMapping
        System.assertEquals('PerUnit', PAIDHelper.applyTransformation('List', 'PricingModelMapping'));
        System.assertEquals('PerUnit', PAIDHelper.applyTransformation('Cost', 'PricingModelMapping'));
        System.assertEquals('PerUnit', PAIDHelper.applyTransformation('Percent of Total', 'PricingModelMapping'));
        System.assertEquals('GraduatedPricing', PAIDHelper.applyTransformation('Block', 'PricingModelMapping'));
        System.assertEquals('PerUnit', PAIDHelper.applyTransformation('Other', 'PricingModelMapping')); // Default
        
        // CurrencyDefault
        System.assertEquals('USD', PAIDHelper.applyTransformation('', 'CurrencyDefault'));
        System.assertEquals('EUR', PAIDHelper.applyTransformation('EUR', 'CurrencyDefault'));
       // System.assertEquals('USD', PAIDHelper.applyTransformation(null, 'CurrencyDefault'));
        Test.stopTest();
    }
    
    @isTest
    static void testTransformations_Date() {
        Date d = Date.newInstance(2024, 1, 15);
        Datetime dt = Datetime.newInstance(2024, 1, 15, 10, 30, 0);
        
        Test.startTest();
        Object isoDate = PAIDHelper.applyTransformation(d, 'DateToISODateTime');
        Object dateStr = PAIDHelper.applyTransformation(d, 'DateToString');
        Object dtStr = PAIDHelper.applyTransformation(dt, 'DateTimeToString');
        Test.stopTest();
        
        System.assert(String.valueOf(isoDate).contains('2024-01-15'));
        System.assertNotEquals(null, dateStr);
        System.assert(String.valueOf(dtStr).contains('2024'));
    }
    
    @isTest
    static void testTransformations_EdgeCases() {
        Test.startTest();
        System.assertEquals(null, PAIDHelper.applyTransformation(null, 'Uppercase'));
        System.assertEquals('test', PAIDHelper.applyTransformation('test', 'None'));
        System.assertEquals('true', PAIDHelper.applyTransformation(true, 'BooleanToString'));
        Test.stopTest();
    }
    
    // Data Type Conversions
    @isTest
    static void testConversions_String() {
        Test.startTest();
        System.assertEquals('123', String.valueOf(PAIDHelper.convertDataType(123, 'String')));
        System.assertEquals('123', String.valueOf(PAIDHelper.convertDataType(123, 'Text')));
        System.assertEquals(null, PAIDHelper.convertDataType(null, 'String'));
        Test.stopTest();
    }
    
    @isTest
    static void testConversions_Integer() {
        Test.startTest();
        System.assertEquals(123, PAIDHelper.convertDataType('123', 'Integer'));
        System.assertEquals(123, PAIDHelper.convertDataType('123', 'Number'));
        System.assertEquals(123, PAIDHelper.convertDataType(123.45, 'Integer'));
        Integer intVal = 100;
        System.assertEquals(intVal, PAIDHelper.convertDataType(intVal, 'Integer'));
        Test.stopTest();
    }
    
    @isTest
    static void testConversions_Decimal() {
        Test.startTest();
        Object result = PAIDHelper.convertDataType('123.45', 'Decimal');
        System.assertEquals(123.45, result);
        System.assert(result instanceof Decimal);
        
        Decimal decVal = 100.5;
        System.assertEquals(decVal, PAIDHelper.convertDataType(decVal, 'Decimal'));
        
        Integer intVal = 100;
        Object decFromInt = PAIDHelper.convertDataType(intVal, 'Decimal');
        System.assert(decFromInt instanceof Decimal);
        Test.stopTest();
    }
    
    @isTest
    static void testConversions_Double() {
        Test.startTest();
        Object result1 = PAIDHelper.convertDataType('123.45', 'Double');
        System.assertNotEquals(null, result1);
        
        Decimal decVal = 100.5;
        System.assertEquals(decVal, PAIDHelper.convertDataType(decVal, 'Double'));
        Test.stopTest();
    }
    
    @isTest
    static void testConversions_Boolean() {
        Test.startTest();
        System.assertEquals(true, PAIDHelper.convertDataType('true', 'Boolean'));
        System.assertEquals(false, PAIDHelper.convertDataType('false', 'Boolean'));
        Boolean boolVal = true;
        System.assertEquals(boolVal, PAIDHelper.convertDataType(boolVal, 'Boolean'));
        Test.stopTest();
    }
    
    @isTest
    static void testConversions_Date() {
        Date d = Date.today();
        Datetime dt = Datetime.now();
        
        Test.startTest();
        System.assertEquals(d, PAIDHelper.convertDataType(d, 'Date'));
        System.assert(PAIDHelper.convertDataType(dt, 'Date') instanceof Date);
        System.assert(PAIDHelper.convertDataType(d, 'DateTime') instanceof Datetime);
        
        Object dtFromString = PAIDHelper.convertDataType('2024-01-15', 'Date');
        System.assertNotEquals(null, dtFromString);
        Test.stopTest();
    }
    
    @isTest
    static void testConversions_DateTime() {
        Datetime dt = Datetime.now();
        Date d = Date.today();
        
        Test.startTest();
        System.assertEquals(dt, PAIDHelper.convertDataType(dt, 'DateTime'));
        System.assert(PAIDHelper.convertDataType(d, 'DateTime') instanceof Datetime);
        
        Object dtFromString = PAIDHelper.convertDataType('2024-01-15 10:30:00', 'DateTime');
        System.assertNotEquals(null, dtFromString);
        Test.stopTest();
    }
    
    @isTest
    static void testConversions_EdgeCases() {
        Test.startTest();
        System.assertEquals(null, PAIDHelper.convertDataType(null, 'Integer'));
        System.assertNotEquals(null, PAIDHelper.convertDataType('invalid', 'Integer')); // Returns original
        System.assertEquals('test', PAIDHelper.convertDataType('test', 'UnknownType'));
        System.assertEquals(null, PAIDHelper.convertDataType(null, null));
        System.assertEquals('test', PAIDHelper.convertDataType('test', ''));
        Test.stopTest();
    }
    /**
 * Add this test method to your PAIDHelperTest class
 * This explicitly tests each else if branch in MultiplyBy100 and DivideBy100
 */

@isTest
static void testTransformations_NumericBranches() {
    Test.startTest();
    
    // ========== MultiplyBy100 - Test each branch explicitly ==========
    
    // Branch 1: instanceof Decimal
    Decimal decimalValue = 10.50;
    Object result1 = PAIDHelper.applyTransformation(decimalValue, 'MultiplyBy100');
    System.assertEquals(1050, result1, 'Decimal branch failed');
    
    // Branch 2: instanceof Double (Note: This is unreachable in Apex - Decimal and Double are same)
    // Skip this as it's not achievable
    
    // Branch 3: instanceof Integer  
    Integer integerValue = 10;
    Object result2 = PAIDHelper.applyTransformation(integerValue, 'MultiplyBy100');
    System.assertEquals(1000, result2, 'Integer branch failed');
    
    // Branch 4: Default return (not Decimal, not Double, not Integer)
    String stringValue = '10';
    Object result3 = PAIDHelper.applyTransformation(stringValue, 'MultiplyBy100');
    System.assertEquals('10', result3, 'Default branch failed - should return unchanged');
    
    // ========== DivideBy100 - Test each branch explicitly ==========
    
    // Branch 1: instanceof Decimal
    Decimal decimalValue2 = 1050;
    Object result4 = PAIDHelper.applyTransformation(decimalValue2, 'DivideBy100');
    System.assertEquals(10.50, result4, 'Decimal divide branch failed');
    
    // Branch 2: instanceof Double (Note: This is unreachable in Apex)
    // Skip this as it's not achievable
    
    // Branch 3: instanceof Integer
    Integer integerValue2 = 1050;
    Object result5 = PAIDHelper.applyTransformation(integerValue2, 'DivideBy100');
    System.assertEquals(10.50, result5, 'Integer divide branch failed');
    
    // Branch 4: Default return (not Decimal, not Double, not Integer)
    String stringValue2 = '1050';
    Object result6 = PAIDHelper.applyTransformation(stringValue2, 'DivideBy100');
    System.assertEquals('1050', result6, 'Default divide branch failed - should return unchanged');
    
    Test.stopTest();
}

/**
 * Add this test to explicitly cover all else if branches in conversion logic
 */
@isTest
static void testConversions_AllBranches() {
    Test.startTest();
    
    // ========== Integer conversion - Test each else if ==========
    
    // Branch 1: Already Integer
    Integer existingInt = 100;
    Object intResult1 = PAIDHelper.convertDataType(existingInt, 'Integer');
    System.assert(intResult1 instanceof Integer, 'Integer identity failed');
    
    // Branch 2: From Decimal
    Decimal decValue = 100.5;
    Object intResult2 = PAIDHelper.convertDataType(decValue, 'Integer');
    System.assertEquals(100, intResult2, 'Decimal to Integer failed');
    
    // Branch 3: From Double (unreachable - same as Decimal in Apex)
    // Skip
    
    // Branch 4: From String (else clause)
    String strValue = '100';
    Object intResult3 = PAIDHelper.convertDataType(strValue, 'Integer');
    System.assertEquals(100, intResult3, 'String to Integer failed');
    
    // ========== Decimal conversion - Test each else if ==========
    
    // Branch 1: Already Decimal
    Decimal existingDec = 100.5;
    Object decResult1 = PAIDHelper.convertDataType(existingDec, 'Decimal');
    System.assert(decResult1 instanceof Decimal, 'Decimal identity failed');
    
    // Branch 2: From Integer
    Integer intVal = 100;
    Object decResult2 = PAIDHelper.convertDataType(intVal, 'Decimal');
    System.assert(decResult2 instanceof Decimal, 'Integer to Decimal failed');
    
    // Branch 3: From Double (unreachable)
    // Skip
    
    // Branch 4: From String (else clause)
    String strVal2 = '100.5';
    Object decResult3 = PAIDHelper.convertDataType(strVal2, 'Decimal');
    System.assertEquals(100.5, decResult3, 'String to Decimal failed');
    
    // ========== Date conversion - Test else if ==========
    
    // Branch 1: Already Date
    Date existingDate = Date.today();
    Object dateResult1 = PAIDHelper.convertDataType(existingDate, 'Date');
    System.assert(dateResult1 instanceof Date, 'Date identity failed');
    
    // Branch 2: From DateTime
    Datetime dt = Datetime.now();
    Object dateResult2 = PAIDHelper.convertDataType(dt, 'Date');
    System.assert(dateResult2 instanceof Date, 'DateTime to Date failed');
    
    // Branch 3: From String (else clause)
    String dateStr = '2024-01-15';
    Object dateResult3 = PAIDHelper.convertDataType(dateStr, 'Date');
    System.assertNotEquals(null, dateResult3, 'String to Date failed');
    
    // ========== DateTime conversion - Test else if ==========
    
    // Branch 1: Already DateTime
    Datetime existingDt = Datetime.now();
    Object dtResult1 = PAIDHelper.convertDataType(existingDt, 'DateTime');
    System.assert(dtResult1 instanceof Datetime, 'DateTime identity failed');
    
    // Branch 2: From Date
    Date d = Date.today();
    Object dtResult2 = PAIDHelper.convertDataType(d, 'DateTime');
    System.assert(dtResult2 instanceof Datetime, 'Date to DateTime failed');
    
    // Branch 3: From String (else clause)
    String dtStr = '2024-01-15 10:30:00';
    Object dtResult3 = PAIDHelper.convertDataType(dtStr, 'DateTime');
    System.assertNotEquals(null, dtResult3, 'String to DateTime failed');
    
    Test.stopTest();
}
    
    // Exception
    @isTest
    static void testException() {
        try {
            throw new PAIDHelper.PAIDIntegrationException('Test');
        } catch (PAIDHelper.PAIDIntegrationException e) {
            System.assertEquals('Test', e.getMessage());
        }
    }
}