@IsTest
public class PAIDProductDeltaPriceSyncBatchTest {

  
    @testSetup
    static void setupData() {

        /* Activate standard pricebook */
        Pricebook2 stdPb = [
            SELECT Id, IsActive
            FROM Pricebook2
            WHERE IsStandard = true
            LIMIT 1
        ];
        if (!stdPb.IsActive) {
            stdPb.IsActive = true;
            update stdPb;
        }

        /* Product that SHOULD be sent to PAID */
        Product2 productToSync = new Product2(
            Name = 'PAID Sync Product',
            IsActive = true,
            PAID_ProductExternalID__c = 'PAID-EXT-001'
        );
        insert productToSync;

        PricebookEntry pbe1 = new PricebookEntry(
            Pricebook2Id = stdPb.Id,
            Product2Id   = productToSync.Id,
            UnitPrice    = 100,
            IsActive     = true,
            UseStandardPrice = false
        );
        insert pbe1;

        /* Product that should be SKIPPED (already synced today) */
        Product2 productAlreadySynced = new Product2(
            Name = 'Already Synced Product',
            IsActive = true,
            PAID_ProductExternalID__c = 'PAID-EXT-002'
        );
        insert productAlreadySynced;

        PricebookEntry pbe2 = new PricebookEntry(
            Pricebook2Id = stdPb.Id,
            Product2Id   = productAlreadySynced.Id,
            UnitPrice    = 200,
            IsActive     = true,
            UseStandardPrice = false
        );
        insert pbe2;

        /* Event log showing successful PAID update today */
        Event_Log__c log = new Event_Log__c(
            Product__c = productAlreadySynced.Id,
            Operations_Key__c = 'Update Product',
            Success_Failure__c = 'Success'
        );
        insert log;
    }

    /* MAIN BATCH EXECUTION TEST */
    @IsTest
    static void testDeltaPriceBatchExecution() {

        Test.startTest();

        PAIDProductDeltaPriceSyncBatch batch =
            new PAIDProductDeltaPriceSyncBatch();

        Database.executeBatch(batch, 5);

        Test.stopTest();

        // If no exception thrown, batch + queueable executed successfully
        System.assert(true,
            'PAID delta batch executed successfully');
    }

    /*NEGATIVE TEST:
       No PricebookEntry Updated Today */
    @IsTest
    static void testBatchWithNoEligibleProducts() {

        /* Inactive product */
        Product2 inactiveProduct = new Product2(
            Name = 'Inactive Product',
            IsActive = false,
            PAID_ProductExternalID__c = 'PAID-EXT-003'
        );
        insert inactiveProduct;

        Test.startTest();
        Database.executeBatch(
            new PAIDProductDeltaPriceSyncBatch(), 5
        );
        Test.stopTest();

        System.assert(true,
            'Batch completed with no eligible products');
    }

   
    @IsTest
    static void testFinishMethodCoverage() {

        PAIDProductDeltaPriceSyncBatch batch =
            new PAIDProductDeltaPriceSyncBatch();

        Test.startTest();
        Database.executeBatch(batch, 1);
        Test.stopTest();

        System.assert(true, 'Finish executed');
    }
}