/**
* @description Service class for PAID Product API operations
* Handles complex multi-object data structures including PricebookEntry, BlockPrice, and Cost
* Supports multiple ProductAttributes: base product + Cost records
* Supports multi-currency for both base product and Cost records
* Fully metadata-driven with no hardcoded field names
* Uses existing PAID_API_Configuration__mdt structure
* @author Manusha T
* @date 2025
*/
public class PAIDProductService {
    
    private static final String CREATE_OPERATION = 'Create';
    private static final String UPDATE_OPERATION = 'Update';
    private static final String BLOCK_PRICING_METHOD = 'Block';
    private static final String COST_PRICING_METHOD = 'Cost';
    private static final String PRODUCT_SYNC_INTEGRATION = 'Product_Sync';
    public List<ConsumptionSchedule> consumptionSchedules;
    // >>> USAGE ADDITION (BLOCK 4)
private static final String USAGE_PRICING_METHOD = 'Recurring';

    /**
* @description Performs ONLY the HTTP callout for product creation - NO DML
* Returns result data for later logging
* Used by queueable/batch jobs to separate callouts from DML
*/
    public static CalloutResult createProductCalloutOnly(Id productId) {
        CalloutResult result = new CalloutResult();
        result.productId = productId;
        
        System.debug('=== START CREATE PRODUCT CALLOUT ONLY ===');
        System.debug('Product ID: ' + productId);
        
        try {
            // Get configuration
            PAID_API_Configuration__mdt config = getAPIConfiguration(CREATE_OPERATION);
            if (config == null) {
                throw new PAIDProductException('No active API configuration found for Product Creation');
            }
            
            // Get product data with related records
            ProductData productData = getProductData(productId);
            
            // Validate required fields
            validateRequiredFields(productData.product, CREATE_OPERATION);
            
            // Build request payload
            result.requestBody = buildProductPayload(productData, CREATE_OPERATION, config);
            
            System.debug('=== CREATE PRODUCT PAYLOAD ===');
            System.debug('******'+result.requestBody);
            
            // Make HTTP callout - NO DML AFTER THIS POINT
            HttpResponse response = makeCallout(config, result.requestBody, null);
            
            result.statusCode = response.getStatusCode();
            result.responseBody = response.getBody();
            System.debug('***** result.responseBody : '+ result.responseBody);
            
            result.success = (result.statusCode >= 200 && result.statusCode < 300);
            
            // Extract PAID Product ID from successful response
            if (result.success) {
                try {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(result.responseBody);
                    result.paidExternalId = extractProductId(responseMap);
                } catch (Exception e) {
                    result.success = false;
                    result.errorMessage = 'Failed to extract Product ID from response: ' + e.getMessage();
                }
            } else {
                result.errorMessage = 'HTTP ' + result.statusCode + ': ' + result.responseBody;
            }
            
            System.debug('=== END CREATE PRODUCT CALLOUT - ' + (result.success ? 'SUCCESS' : 'FAILURE') + ' ===');
            
        } catch (PAIDProductException integEx) {
            result.success = false;
            result.errorMessage = 'Integration error: ' + integEx.getMessage();
            result.requestBody = result.requestBody != null ? result.requestBody : 'Payload not generated due to error';
            System.debug('PAIDProductException: ' + result.errorMessage);
            
        } catch (System.SObjectException sObjEx) {
            result.success = false;
            result.errorMessage = 'Missing required field: ' + sObjEx.getMessage();
            result.requestBody = result.requestBody != null ? result.requestBody : 'Payload not generated due to error';
            System.debug('SObjectException: ' + result.errorMessage);
            
        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = 'Unexpected error: ' + ex.getMessage() + ' | Stack Trace: ' + ex.getStackTraceString();
            result.requestBody = result.requestBody != null ? result.requestBody : 'Payload not generated due to error';
            System.debug('Exception: ' + result.errorMessage);
        }
        
        return result;
    }
    
    /**
* @description Performs ONLY the HTTP callout for product update - NO DML
* Returns result data for later logging
* Used by queueable/batch jobs to separate callouts from DML
*/
    public static CalloutResult updateProductCalloutOnly(Id productId) {
        CalloutResult result = new CalloutResult();
        result.productId = productId;
        
        System.debug('=== START UPDATE PRODUCT CALLOUT ONLY ===');
        System.debug('Product ID: ' + productId);
        
        try {
            // Get configuration
            PAID_API_Configuration__mdt config = getAPIConfiguration(UPDATE_OPERATION);
            if (config == null) {
                throw new PAIDProductException('No active API configuration found for Product Update');
            }
            
            // Get product data with related records
            ProductData productData = getProductData(productId);
            
            // Validate PAID External ID exists
            if (String.isBlank(productData.product.PAID_ProductExternalID__c)) {
                throw new PAIDProductException('Cannot update product: PAID_ProductExternalID__c is missing');
            }
            
            result.paidExternalId = productData.product.PAID_ProductExternalID__c;
            
            // Build request payload
            result.requestBody = buildProductPayload(productData, UPDATE_OPERATION, config);
            
            System.debug('=== UPDATE PRODUCT PAYLOAD ===');
            System.debug('Product: ' + productData.product.Name);
            System.debug('Pricing Method: ' + (hasCPQ() ? productData.product.get('SBQQ__PricingMethod__c') : 'N/A'));
            System.debug('Block Prices Count: ' + productData.blockPrices.size());
            System.debug('Cost Records Count: ' + productData.costs.size());
            System.debug('Payload: ' + result.requestBody);
            
            // Make HTTP callout - NO DML AFTER THIS POINT
            HttpResponse response = makeCallout(config, result.requestBody, productData.product.PAID_ProductExternalID__c);
            
            result.statusCode = response.getStatusCode();
            result.responseBody = response.getBody();
            result.success = (result.statusCode >= 200 && result.statusCode < 300);
            
            if (!result.success) {
                result.errorMessage = 'HTTP ' + result.statusCode + ': ' + result.responseBody;
            }
            
            System.debug('=== END UPDATE PRODUCT CALLOUT - ' + (result.success ? 'SUCCESS' : 'FAILURE') + ' ===');
            
        } catch (PAIDProductException integEx) {
            result.success = false;
            result.errorMessage = 'Integration error: ' + integEx.getMessage();
            result.requestBody = result.requestBody != null ? result.requestBody : 'Payload not generated due to error';
            System.debug('PAIDProductException: ' + result.errorMessage);
            
        } catch (System.SObjectException sObjEx) {
            result.success = false;
            result.errorMessage = 'Missing required field: ' + sObjEx.getMessage();
            result.requestBody = result.requestBody != null ? result.requestBody : 'Payload not generated due to error';
            System.debug('SObjectException: ' + result.errorMessage);
            
        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = 'Unexpected error: ' + ex.getMessage() + ' | Stack Trace: ' + ex.getStackTraceString();
            result.requestBody = result.requestBody != null ? result.requestBody : 'Payload not generated due to error';
            System.debug('Exception: ' + result.errorMessage);
        }
        
        return result;
    }
    
    /**
* @description Wrapper class to hold product and related data
*/
    public class ProductData {
        public Product2 product;
        public List<PricebookEntry> pricebookEntries;
        public List<SBQQ__BlockPrice__c> blockPrices;
        public List<SBQQ__Cost__c> costs;
         public List<ConsumptionSchedule> consumptionSchedules;
        
        public ProductData() {
            this.pricebookEntries = new List<PricebookEntry>();
            this.blockPrices  = new List<SBQQ__BlockPrice__c>();
            this.costs = new List<SBQQ__Cost__c>();
			this.consumptionSchedules = new List<ConsumptionSchedule>();        
        }
    }
    
    //Usage
    // >>> USAGE ADDITION 
    private static List<ConsumptionSchedule> getConsumptionSchedules(Id productId) {
        return [SELECT Id, UnitOfMeasure, RatingMethod, Type, BillingTerm, BillingTermUnit,
               (SELECT Id, LowerBound, UpperBound, Price 
                FROM ConsumptionRates 
                ORDER BY LowerBound ASC) 
                FROM ConsumptionSchedule
                WHERE Id IN (SELECT ConsumptionScheduleId 
                             FROM ProductConsumptionSchedule 
                             WHERE ProductId = :productId) ];
    }



    /**
    * @description Wrapper class to hold callout results
    * Used to separate HTTP callouts from DML operations
    */
    public class CalloutResult {
        public Id productId;
        public Boolean success;
        public String requestBody;
        public String responseBody;
        public Integer statusCode;
        public String errorMessage;
        public String paidExternalId;
        
        public CalloutResult() {
            this.success = false;
        }
    }
    
    /**
    * @description Retrieves product with all related data
    * @param productId Product record Id
    * @return ProductData wrapper with all related records
    */
    public static ProductData getProductData(Id productId) {
        ProductData data = new ProductData();
        
        // Get Product2 using PAIDHelper with base fields and mapped fields
        Set<Id> productIds = new Set<Id>{productId};
            
            List<Product2> products = (List<Product2>)PAIDHelper.queryRecordsWithMappings(
                'Product2',                          // objectName
                PRODUCT_SYNC_INTEGRATION,                      // integrationType
                productIds,                          // recordIds
                'PAID_Product_Field_Mapping__mdt',  // fieldMappingType
                null,                                // whereClause
                null,                                // bindVarName
                null,                                 // bindVarValue
                null
            );
        
        if (products.isEmpty()) {
            throw new PAIDProductException('Product not found: ' + productId);
        }
        
        data.product = products[0];
        
        // Get PricebookEntry records for this product
        data.pricebookEntries = getPricebookEntries(productId);
        
        // Get BlockPrice records if CPQ is installed and pricing method is Block
        if (hasCPQ() && isBlockPricing(data.product)) {
            data.blockPrices  = getBlockPrices(productId);
            System.debug('Block Pricing detected - BlockPrices found: ' + data.blockPrices.size());
        } else {
            System.debug('Standard Pricing - No BlockPrices needed');
        }
        
        // Get Cost records if CPQ is installed and pricing method is Cost
        if (hasCPQ() && isCostPricing(data.product)) {
            data.costs = getCostRecords(productId);
            System.debug('Cost Pricing detected - Cost records found: ' + data.costs.size());
        }
        // >>> USAGE ADDITION (BLOCK 3)
        data.consumptionSchedules = getConsumptionSchedules(productId);
        System.debug('Usage schedules found: ' + data.consumptionSchedules.size());

        return data;
    }
    
    /**
    * @description Retrieves PricebookEntry records for the product
    * @param productId Product Id
    * @return List of PricebookEntry records
    */
    private static List<PricebookEntry> getPricebookEntries(Id productId) {
        List<SObject> entries = PAIDHelper.queryRecordsWithMappings(
            'PricebookEntry',                    // objectName
            PRODUCT_SYNC_INTEGRATION,            // integrationType (Product_Sync)
            null,                                // recordIds (not used)
            null,                                // fieldMappingType (no mappings needed for this query)
            null,                                // whereClause (handled by bindVar)
            'productId',                         // bindVarName
            productId,                           // bindVarValue
            null                                 // orderByClause
        );
        
        List<PricebookEntry> pricebookEntries = new List<PricebookEntry>();
        for (SObject entry : entries) {
            pricebookEntries.add((PricebookEntry)entry);
        }
        
        return pricebookEntries;
    }
    /* >>> USAGE ADDITION (BLOCK 5)
    private static List<Map<String, Object>> buildUsageProductAttributes(
        ProductData productData,
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent
    ) {
        List<Map<String, Object>> attributes = new List<Map<String, Object>>();
    
        if (productData.consumptionSchedules == null || productData.consumptionSchedules.isEmpty()) {
            System.debug('Usage pricing selected but no Consumption Schedules found');
            return attributes;
        }

    for (ConsumptionSchedule cs : productData.consumptionSchedules) {
        Map<String, Object> attribute = new Map<String, Object>();

        // Keep existing ProductAttribute mappings
        if (mappingsByParent.containsKey('ProductAttribute')) {
            for (PAID_Product_Field_Mapping__mdt mapping : mappingsByParent.get('ProductAttribute')) {
                Object value = getFieldValue(productData.product, mapping);
                if (value != null) {
                    attribute.put(mapping.PAID_Field_Name__c, value);
                }
            }
        }

        Map<String, Object> pricing = new Map<String, Object>();
        pricing.put('pricingMethod', 'Usage');
        pricing.put('uom', cs.UnitOfMeasure);
        pricing.put('ratingMethod', cs.RatingMethod);
        pricing.put('billingTerm', cs.BillingTerm);
        pricing.put('billingTermUnit', cs.BillingTermUnit);

        Map<String, Object> pricePoints = new Map<String, Object>();
        Map<String, Object> defaultPoint = new Map<String, Object>();
        defaultPoint.put('unitPrice', 0);
        defaultPoint.put('minQuantity', null);
        defaultPoint.put('includedQuantity', null);

        List<Map<String, Object>> tiers = new List<Map<String, Object>>();
        for (ConsumptionRate cr : cs.ConsumptionRates) {
            Map<String, Object> tier = new Map<String, Object>();
            tier.put('from', cr.LowerBound);
            tier.put('to', cr.UpperBound);
            tier.put('price', cr.Price * 100); // PAID expects cents
            tiers.add(tier);
        }

        defaultPoint.put('tiers', tiers);
        pricePoints.put('USD', defaultPoint); // currency logic same as your base pricing

        pricing.put('PricePoints', pricePoints);
        attribute.put('pricing', pricing);

        attributes.add(attribute);
    }

    return attributes;
}
*/
   // >>> USAGE ADDITION - detect usage product based on Recurring charge type + Consumption Schedule
    private static Boolean isUsageProduct(PAIDProductService.ProductData productData) {
        try {
            String chargeType = (String) productData.product.get('SBQQ__ChargeType__c');
            
            Boolean hasConsumptionSchedule =
                productData.consumptionSchedules != null &&
                !productData.consumptionSchedules.isEmpty();
            
            System.debug('Usage detection -> ChargeType: ' + chargeType +
                         ', Has ConsumptionSchedule: ' + hasConsumptionSchedule);
            
            return chargeType == 'Recurring' && hasConsumptionSchedule;  //Usage adding to cons
        } catch (Exception e) {
            System.debug('Usage detection failed: ' + e.getMessage());
            return false;
        }
    }

    // >>> USAGE ADDITION - build ProductAttributes for usage-based products (Consumption Schedules)
    private static List<Map<String, Object>> buildUsageProductAttributes(
        PAIDProductService.ProductData productData,
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent
    ) {
        List<Map<String, Object>> attributes = new List<Map<String, Object>>();
        
        if (productData.consumptionSchedules == null || productData.consumptionSchedules.isEmpty()) {
            System.debug('Usage pricing selected but no Consumption Schedules found');
            return attributes;
        }
        
        for (ConsumptionSchedule cs : productData.consumptionSchedules) {
            Map<String, Object> attribute = new Map<String, Object>();
            
            // Keep existing ProductAttribute mappings
            if (mappingsByParent.containsKey('ProductAttribute')) {
                for (PAID_Product_Field_Mapping__mdt mapping : mappingsByParent.get('ProductAttribute')) {
                    Object value = getFieldValue(productData.product, mapping);
                    System.debug('**** mapping.PAID_Field_Name__c: '+mapping.PAID_Field_Name__c);
                    System.debug('**** value: '+value);
                    if (value != null) {
                        attribute.put(mapping.PAID_Field_Name__c, value);
                    }
                    
                }
            }
            
            Map<String, Object> pricing = new Map<String, Object>();
            pricing.put('chargeType', 'Usage');		//Sumanpreet
            pricing.put('uom', cs.UnitOfMeasure);
            pricing.put('ratingMethod', cs.RatingMethod);
            pricing.put('billingTerm', cs.BillingTerm);
            pricing.put('billingFrequency', cs.BillingTermUnit == 'Month' ? 'monthly' : cs.BillingTermUnit); // Sumanpreet
            pricing.put('pricingModel', 'VolumePricing');
            
            Map<String, Object> pricePoints = new Map<String, Object>();
            Map<String, Object> defaultPoint = new Map<String, Object>();
            defaultPoint.put('unitPrice', 0);
            defaultPoint.put('minQuantity', null);
            defaultPoint.put('includedQuantity', null);
            
            List<Map<String, Object>> tiers = new List<Map<String, Object>>();
            for (ConsumptionRate cr : cs.ConsumptionRates) {
                Map<String, Object> tier = new Map<String, Object>();
                tier.put('lowerBound', cr.LowerBound);					//Sumanpreet
                tier.put('upperBound', cr.UpperBound);					//Sumanpreet
                tier.put('unitAmount', cr.Price * 100); // PAID expects cents			//Sumanpreet
                tiers.add(tier);
            }
            
            defaultPoint.put('tiers', tiers);
            pricePoints.put('USD', defaultPoint); // keep same currency logic
            
            pricing.put('PricePoints', pricePoints);
            attribute.put('pricing', pricing);
            
            attributes.add(attribute);
        }
        
        return attributes;
    }



    /**
    * @description Retrieves BlockPrice records grouped by PricebookEntry
    * @param productId Product Id
    * @return List of BlockPrice records
    */
    private static List<SBQQ__BlockPrice__c> getBlockPrices(Id productId) {
    // Use PAIDHelper with existing PAID_Product_Field_Mapping__mdt
    // The Salesforce_Object__c = 'BlockPrice' will filter the correct fields    
        List<SObject> results = PAIDHelper.queryRecordsWithMappings(
            'SBQQ__BlockPrice__c',           
            'Product_Sync',                   
            null,                             
            'PAID_Product_Field_Mapping__mdt', 
            null,                             
            'productId',                      
            productId,                       
            'SBQQ__LowerBound__c ASC'        
        );
        
        // Cast to specific type
        List<SBQQ__BlockPrice__c> blockPrices = new List<SBQQ__BlockPrice__c>();
        for (SObject record : results) {
            blockPrices.add((SBQQ__BlockPrice__c)record);
        }
       
        return blockPrices;
    }
    
   
    private static List<SBQQ__Cost__c> getCostRecords(Id productId) {
        // Use PAIDHelper with metadata-driven query
        List<SObject> results = PAIDHelper.queryRecordsWithMappings(
            'SBQQ__Cost__c',                  
            'Product_Sync',                    
            null,                             
            'PAID_Product_Field_Mapping__mdt', 
            null,                              
            'productId',                       
            productId,                         
            null                               
        );
        
        // Cast to specific type
        List<SBQQ__Cost__c> costs = new List<SBQQ__Cost__c>();
        for (SObject record : results) {
            costs.add((SBQQ__Cost__c)record);
        }
        
        return costs;
    }
    
    /**
    * @description Checks if Salesforce CPQ is installed
    * @return true if CPQ is available
    */
    public static Boolean hasCPQ() {
        return Schema.getGlobalDescribe().containsKey('SBQQ__Quote__c');
    }
    
    /**
    * @description Checks if product uses block pricing
    * @param product Product2 record
    * @return true if pricing method is Block
    */
    private static Boolean isBlockPricing(Product2 product) {
        if (!hasCPQ()) return false;
        
        try {
            String pricingMethod = (String)product.get('SBQQ__PricingMethod__c');
            return pricingMethod == BLOCK_PRICING_METHOD;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
    * @description Checks if product uses cost pricing
    * @param product Product2 record
    * @return true if pricing method is Cost
    */
    private static Boolean isCostPricing(Product2 product) {
        if (!hasCPQ()) return false;
        
        try {
            String pricingMethod = (String)product.get('SBQQ__PricingMethod__c');
            return pricingMethod == COST_PRICING_METHOD;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
    * @description Builds JSON payload for PAID API
    * @param productData Product and related data
    * @param operationType Create or Update
    * @param config API configuration
    * @return JSON string payload
    */
    public static String buildProductPayload(ProductData productData, String operationType,PAID_API_Configuration__mdt config) {
        Map<String, Object> payload = new Map<String, Object>();
        
        List<SObject> mappingRecords = PAIDHelper.getFieldMappings(
            'PAID_Product_Field_Mapping__mdt',
            null  
        );
        
        List<PAID_Product_Field_Mapping__mdt> mappings = new List<PAID_Product_Field_Mapping__mdt>();
        for (SObject record : mappingRecords) {
            PAID_Product_Field_Mapping__mdt mapping = (PAID_Product_Field_Mapping__mdt)record;
            
            if (mapping.Operation_Type__c == operationType || mapping.Operation_Type__c == 'Both') {
                mappings.add(mapping);
            }
        }
        
        // Group mappings by parent object and source
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent = 
            new Map<String, List<PAID_Product_Field_Mapping__mdt>>();
        
        for (PAID_Product_Field_Mapping__mdt mapping : mappings) {
            String key = String.isBlank(mapping.Parent_Field__c) ? 'root' : mapping.Parent_Field__c;
            if (!mappingsByParent.containsKey(key)) {
                mappingsByParent.put(key, new List<PAID_Product_Field_Mapping__mdt>());
            }
            mappingsByParent.get(key).add(mapping);
        }
        
        // Build root level fields
        if (mappingsByParent.containsKey('root')) {
            for (PAID_Product_Field_Mapping__mdt mapping : mappingsByParent.get('root')) {
                if (String.isNotBlank(mapping.Salesforce_Field_API_Name__c) &&
                    String.isNotBlank(mapping.PAID_Field_Name__c)) {
                        Object value = getFieldValue(productData.product, mapping);
                        if (value != null && mapping.PAID_Field_Name__c != null) {
                            payload.put(mapping.PAID_Field_Name__c, value);
                        }
                    }
            }
        }
        
        // Build ProductAttribute array
        List<Map<String, Object>> productAttributes = buildProductAttributes(
            productData, 
            mappingsByParent
        );
        
        if (!productAttributes.isEmpty()) {
            payload.put('ProductAttribute', productAttributes);
        }
        
        return JSON.serialize(payload);
    }
    
    /**
    * @description Builds ProductAttribute array structure
    * Conditionally builds attributes based on pricing method:
    * List or Percent of Total: Base product with PricebookEntry pricing only
    * Block: Base product with block pricing tiers only
    * Cost: Cost-based ProductAttributes only (no base product)
    * @param productData Product and related data
    * @param mappingsByParent Field mappings grouped by parent
    * @return List of ProductAttribute maps
    */
    public static List<Map<String, Object>> buildProductAttributes(
        ProductData productData,
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent
    ) {
        List<Map<String, Object>> attributes = new List<Map<String, Object>>();
        
        // Determine pricing method
        String pricingMethod = 'List'; // Default to List
        if (hasCPQ()) {
            try {
                pricingMethod = (String)productData.product.get('SBQQ__PricingMethod__c');
            } catch (Exception e) {
                System.debug('Could not get pricing method, defaulting to List');
            }
        }
        
        System.debug('Pricing Method: ' + pricingMethod);
        
        // Build attributes based on pricing method
        if (pricingMethod == COST_PRICING_METHOD) {
            // Cost pricing: Send only Cost-based ProductAttributes
            if (!productData.costs.isEmpty()) {
                List<Map<String, Object>> costAttributes = buildCostProductAttributes(
                    productData,
                    mappingsByParent
                );
                attributes.addAll(costAttributes);
                System.debug('Cost Pricing: Added ' + costAttributes.size() + ' Cost ProductAttributes');
            } else {
                System.debug('Cost Pricing selected but no Cost records found');
            }
        } else if (pricingMethod == BLOCK_PRICING_METHOD) {
            // Block pricing: Send base ProductAttribute with tiers only
            List<Map<String, Object>> blockAttributes  = buildBlockPricingProductAttributes(
                productData, 
                mappingsByParent
            );
            attributes.addAll(blockAttributes);
        } else if (isUsageProduct(productData)) {

            System.debug('Usage product detected via Recurring + Consumption Schedule');
            attributes.addAll(buildUsageProductAttributes(productData, mappingsByParent));
            
        }

        else {
            // List or Percent of Total pricing (default): Send base ProductAttribute with standard pricing only
            Map<String, Object> baseAttribute = buildBaseProductAttribute(
                productData, 
                mappingsByParent
            );
            attributes.add(baseAttribute);
        }
        
        return attributes;
    }
    
    /**
    * @description Builds the base/main ProductAttribute (for the product itself)
    * @param productData Product and related data
    * @param mappingsByParent Field mappings grouped by parent
    * @return Base ProductAttribute map
    */
    private static Map<String, Object> buildBaseProductAttribute(
        ProductData productData,
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent
    ) {
        Map<String, Object> attribute = new Map<String, Object>();
        
        // Add ProductAttribute level fields from Product2
        if (mappingsByParent.containsKey('ProductAttribute')) {
            for (PAID_Product_Field_Mapping__mdt mapping : mappingsByParent.get('ProductAttribute')) {
                Object value = getFieldValue(productData.product, mapping);
                if (value != null) {
                    attribute.put(mapping.PAID_Field_Name__c, value);
                }
            }
        }
        
        // Build pricing object for base product
        Map<String, Object> pricing = buildBasePricing(productData, mappingsByParent);
        if (!pricing.isEmpty()) {
            attribute.put('pricing', pricing);
        }
        
        return attribute;
    }
    
    /**
    * @description Builds ProductAttribute for Block pricing
    * Includes tiers but NO unitPrice from PricebookEntry
    * @param productData Product and related data
    * @param mappingsByParent Field mappings grouped by parent
    * @return List containing Block pricing ProductAttribute
    */
    private static List<Map<String, Object>> buildBlockPricingProductAttributes(
        ProductData productData,
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent
    ) {
        List<Map<String, Object>> attributes = new List<Map<String, Object>>();
        
        // Build base attribute structure (name, active, etc.)
        Map<String, Object> attribute = new Map<String, Object>();
        
        // Add ProductAttribute level fields from Product2
        if (mappingsByParent.containsKey('ProductAttribute')) {
            for (PAID_Product_Field_Mapping__mdt mapping : mappingsByParent.get('ProductAttribute')) {
                Object value = getFieldValue(productData.product, mapping);
                if (value != null && mapping.PAID_Field_Name__c != null) {
                    attribute.put(mapping.PAID_Field_Name__c, value);
                }
            }
        }
        
        // Build pricing with block price tiers (no unitPrice)
        Map<String, Object> pricing = buildBasePricing(productData, mappingsByParent);
        
        //Replace PricePoints with block-specific version (tiers only, no unitPrice)
        Map<String, Object> pricePoints = buildBlockPricePoints(productData, mappingsByParent);
        pricing.put('PricePoints', pricePoints);
        
        attribute.put('pricing', pricing);
        attributes.add(attribute);
        return attributes;
    }
    
    /**
    * @description Builds PricePoints for Block pricing (tiers only, no unitPrice)
    * @param productData Product and related data
    * @param mappingsByParent Field mappings grouped by parent
    * @return PricePoints map with tiers only
    */
    private static Map<String, Object> buildBlockPricePoints(
        ProductData productData,
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent
    ) {
        Map<String, Object> pricePoints = new Map<String, Object>();
       
        // Get tier field mappings
        List<PAID_Product_Field_Mapping__mdt> tierMappings = 
            mappingsByParent.get('ProductAttribute.pricing.PricePoints.tiers') != null ? 
            mappingsByParent.get('ProductAttribute.pricing.PricePoints.tiers') : 
        new List<PAID_Product_Field_Mapping__mdt>();
        
        // Group block prices by currency (if multi-currency is enabled)
        Map<String, List<SBQQ__BlockPrice__c>> blockPricesByCurrency = new Map<String, List<SBQQ__BlockPrice__c>>();
        
        for (SBQQ__BlockPrice__c blockPrice : productData.blockPrices) {
            String currencyCode = 'USD'; // Default currency
            
            // Get currency from block price if multi-currency is enabled
            if (UserInfo.isMultiCurrencyOrganization()) {
                try {
                    Object currencyValue = blockPrice.get('CurrencyIsoCode');
                    if (currencyValue != null) {
                        currencyCode = String.valueOf(currencyValue);
                    }
                } catch (Exception e) {
                    System.debug('CurrencyIsoCode not available on BlockPrice');
                }
            }
            
            // Group by currency
            if (!blockPricesByCurrency.containsKey(currencyCode)) {
                blockPricesByCurrency.put(currencyCode, new List<SBQQ__BlockPrice__c>());
            }
            blockPricesByCurrency.get(currencyCode).add(blockPrice);
        }
        
        // If no block prices, use default currency from PricebookEntry or system
        if (blockPricesByCurrency.isEmpty()) {
            String defaultCurrency = 'USD';
            if (!productData.pricebookEntries.isEmpty() && UserInfo.isMultiCurrencyOrganization()) {
                try {
                    defaultCurrency = (String)productData.pricebookEntries[0].get('CurrencyIsoCode');
                } catch (Exception e) {
                    System.debug('Could not get currency from PricebookEntry');
                }
            } else if (UserInfo.isMultiCurrencyOrganization()) {
                defaultCurrency = UserInfo.getDefaultCurrency();
            }
            blockPricesByCurrency.put(defaultCurrency, new List<SBQQ__BlockPrice__c>());
        }
        
        // Build PricePoints for each currency
        for (String currencyCode : blockPricesByCurrency.keySet()) {
            Map<String, Object> pricePoint = new Map<String, Object>();
            
            //NO unitPrice for Block pricing - only tiers
            
            // Set null values for quantity fields
            pricePoint.put('includedQuantity', null);
            pricePoint.put('minQuantity', null);
            pricePoint.put('unitPrice', 0); //added by him
            
            // Build tiers array
            List<SBQQ__BlockPrice__c> currencyBlockPrices = blockPricesByCurrency.get(currencyCode);
            List<Map<String, Object>> tiers = buildTiers(
                currencyBlockPrices,
                mappingsByParent
            );
            
            pricePoint.put('tiers', tiers);
            pricePoints.put(currencyCode, pricePoint);
        }

        return pricePoints;
    }
    
    /**
    * @description Builds tiers array from BlockPrice records
    * @param blockPrices List of BlockPrice records
    * @param mappingsByParent Field mappings grouped by parent
    * @return List of tier maps
    */
    private static List<Map<String, Object>> buildTiers(
        List<SBQQ__BlockPrice__c> blockPrices,
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent
    ) {
        List<Map<String, Object>> tiers = new List<Map<String, Object>>();
        
        // Get tier field mappings from metadata
        List<PAID_Product_Field_Mapping__mdt> tierMappings = new List<PAID_Product_Field_Mapping__mdt>();
        if (mappingsByParent.containsKey('ProductAttribute.pricing.PricePoints.tiers')) {
            tierMappings = mappingsByParent.get('ProductAttribute.pricing.PricePoints.tiers');
        }
        
        // If no tier mappings found, return empty list
        if (tierMappings.isEmpty()) {
            return tiers;
        }
        
        // Build tier objects from BlockPrice records using metadata
        for (SBQQ__BlockPrice__c blockPrice : blockPrices) {
            
            Map<String, Object> tier = new Map<String, Object>();
            
            // Apply each tier field mapping
            for (PAID_Product_Field_Mapping__mdt mapping : tierMappings) {
                if (String.isNotBlank(mapping.Salesforce_Field_API_Name__c)) {
                    try {
                        Object value = blockPrice.get(mapping.Salesforce_Field_API_Name__c);
                        
                        // Apply data type conversion
                        if (value != null) {
                            value = PAIDHelper.convertDataType(value, mapping.Data_Type__c);
                            
                            // Multiply price fields by 100
                            if (mapping.Salesforce_Field_API_Name__c == 'SBQQ__Price__c' && value != null) {
                                value = (Decimal)value * 100;
                            }
                        }
                        
                        tier.put(mapping.PAID_Field_Name__c, value);
                        System.debug('  Set tier.' + mapping.PAID_Field_Name__c + ' = ' + value);
                    } catch (Exception e) {
                        System.debug('Error getting tier field ' + mapping.Salesforce_Field_API_Name__c + ': ' + e.getMessage());
                    }
                }
            }
            System.debug('Tier object built: ' + tier);
            tiers.add(tier);
        }
        System.debug('=== BUILD TIERS DEBUG END ===');
    System.debug('Total tiers built: ' + tiers.size());
        return tiers;
    }
    
    /**
    * @description Builds ProductAttribute entries for each Cost record
    * Always sets feeType as "custom" for cost-based ProductAttributes
    * Creates PricePoints for all currencies found in PricebookEntry records
    * @param productData Product and related data
    * @param mappingsByParent Field mappings grouped by parent
    * @return List of Cost ProductAttribute maps
    */
    public static List<Map<String, Object>> buildCostProductAttributes(
        ProductData productData,
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent
    ) {
        List<Map<String, Object>> costAttributes = new List<Map<String, Object>>();
        
        // Get cost field mappings from metadata
        List<PAID_Product_Field_Mapping__mdt> costMappings = new List<PAID_Product_Field_Mapping__mdt>();
        if (mappingsByParent.containsKey('ProductAttribute.Cost')) {
            costMappings = mappingsByParent.get('ProductAttribute.Cost');
        }
        
        // Get pricing level mappings for cost (if any)
        List<PAID_Product_Field_Mapping__mdt> costPricingMappings = new List<PAID_Product_Field_Mapping__mdt>();
        if (mappingsByParent.containsKey('ProductAttribute.Cost.pricing')) {
            costPricingMappings = mappingsByParent.get('ProductAttribute.Cost.pricing');
        }
        
        // Get Product2-level pricing fields (chargeType, taxable, etc.)
        List<PAID_Product_Field_Mapping__mdt> productPricingMappings = new List<PAID_Product_Field_Mapping__mdt>();
        if (mappingsByParent.containsKey('ProductAttribute.pricing')) {
            productPricingMappings = mappingsByParent.get('ProductAttribute.pricing');
        }
        
        // Extract all currencies from PricebookEntry records
        Set<String> currencies = extractCurrenciesFromPricebookEntries(productData.pricebookEntries);
        
        // Build a ProductAttribute for each Cost record
        for (SBQQ__Cost__c cost : productData.costs) {
            Map<String, Object> costAttribute = new Map<String, Object>();
            
            // Set name from Cost.Name
            String costName = (String)cost.get('Name');
            costAttribute.put('name', String.isNotBlank(costName) ? costName : '');
            
            // Set active from SBQQ__Active__c (default to true if field doesn't exist)
            Boolean isActive = false ;
            // try {
            Object activeValue = cost.get('SBQQ__Active__c');
            System.debug('Cost Name: ' + costName);
            System.debug('Cost Active Value (raw): ' + activeValue);
            
            if (activeValue != null) {
                isActive = (Boolean)activeValue;
            }
            // } catch (Exception e) {
            System.debug('SBQQ__Active__c not found on Cost, defaulting to true');
            // }
            System.debug('Final isActive value: ' + isActive);
            costAttribute.put('active', isActive);
            
            // Apply ProductAttribute level fields from Cost record
            for (PAID_Product_Field_Mapping__mdt mapping : costMappings) {
                if (mapping.PAID_Field_Name__c == 'active' || mapping.PAID_Field_Name__c == 'name') {
                    continue;
                }
                
                if (String.isNotBlank(mapping.Salesforce_Field_API_Name__c) && String.isNotBlank(mapping.PAID_Field_Name__c)) {
                    try {
                        Object value = cost.get(mapping.Salesforce_Field_API_Name__c);
                        
                        if (value != null) {
                            value = PAIDHelper.convertDataType(value, mapping.Data_Type__c);
                        }
                        
                        costAttribute.put(mapping.PAID_Field_Name__c, value);
                    } catch (Exception e) {
                        System.debug('Error getting cost field ' + mapping.Salesforce_Field_API_Name__c + ': ' + e.getMessage());
                    }
                }
            }
            
            // Build pricing object for this cost
            Map<String, Object> costPricing = new Map<String, Object>();
            
            // ALWAYS set feeType as "custom" for cost-based ProductAttributes
            costPricing.put('feeType', 'custom');
            
            //Apply Product2-level pricing fields (chargeType, taxable, billingType, billingFrequency)
            // These come from the Product2 record, not the Cost record
            for (PAID_Product_Field_Mapping__mdt mapping : productPricingMappings) {
                // Skip feeType as it's already set to "custom"
                if (mapping.PAID_Field_Name__c == 'feeType') {
                    continue;
                }
                
                if (String.isNotBlank(mapping.Salesforce_Field_API_Name__c) && 
                    String.isNotBlank(mapping.PAID_Field_Name__c)) {
                        try {
                            // Get value from Product2 record, not Cost record
                            Object value = getFieldValue(productData.product, mapping);
                            
                            if (value != null) {
                                costPricing.put(mapping.PAID_Field_Name__c, value);
                            }
                        } catch (Exception e) {
                            System.debug('Error getting product pricing field ' + mapping.Salesforce_Field_API_Name__c + ': ' + e.getMessage());
                        }
                    }
            }
            
            // Apply other pricing level fields from metadata
            for (PAID_Product_Field_Mapping__mdt mapping : costPricingMappings) {
                if (String.isNotBlank(mapping.Salesforce_Field_API_Name__c) && String.isNotBlank(mapping.PAID_Field_Name__c)) {
                    try {
                        Object value = cost.get(mapping.Salesforce_Field_API_Name__c);
                        
                        if (value != null) {
                            value = PAIDHelper.convertDataType(value, mapping.Data_Type__c);
                        }
                        
                        costPricing.put(mapping.PAID_Field_Name__c, value);
                    } catch (Exception e) {
                        System.debug('Error getting cost pricing field ' + mapping.Salesforce_Field_API_Name__c + ': ' + e.getMessage());
                    }
                }
            }
            
            // Build PricePoints for ALL currencies found in PricebookEntry
            Map<String, Object> pricePoints = new Map<String, Object>();
            
            for (String currencyCode : currencies) {
                Map<String, Object> pricePoint = new Map<String, Object>();
                pricePoint.put('unitPrice', cost.SBQQ__UnitCost__c != null ? cost.SBQQ__UnitCost__c*100 : 0);
                pricePoint.put('minQuantity', null);
                pricePoint.put('includedQuantity', null);
                pricePoint.put('tiers', new List<Map<String, Object>>());
                
                pricePoints.put(currencyCode, pricePoint);
            }
            
            costPricing.put('PricePoints', pricePoints);
            
            costAttribute.put('pricing', costPricing);
            
            costAttributes.add(costAttribute);
            System.debug('costAttributes:::'+costAttributes);
        }
        
        return costAttributes;
    }
    
    /**
    * @description Extracts all unique currencies from PricebookEntry records
    * @param pricebookEntries List of PricebookEntry records
    * @return Set of currency codes
    */
    public static Set<String> extractCurrenciesFromPricebookEntries(List<PricebookEntry> pricebookEntries) {
        Set<String> currencies = new Set<String>();
        
        if (pricebookEntries.isEmpty()) {
            // Default to USD if no PricebookEntry exists
            String defaultCurrency = 'USD';
            if (UserInfo.isMultiCurrencyOrganization()) {
                defaultCurrency = UserInfo.getDefaultCurrency();
            }
            currencies.add(defaultCurrency);
        } else {
            for (PricebookEntry entry : pricebookEntries) {
                String currencyCode = 'USD';
                if (UserInfo.isMultiCurrencyOrganization()) {
                    currencyCode = (String)entry.get('CurrencyIsoCode');
                }
                currencies.add(currencyCode);
            }
        }
        
        return currencies;
    }
    
    /**
    * @description Builds pricing object for base product (with PricePoints)
    * @param productData Product and related data
    * @param mappingsByParent Field mappings grouped by parent
    * @return Pricing map
    */
    public static Map<String, Object> buildBasePricing(
        ProductData productData,
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent
    ) {
        Map<String, Object> pricing = new Map<String, Object>();
        
        // Add pricing level fields from Product2
        if (mappingsByParent.containsKey('ProductAttribute.pricing')) {
            for (PAID_Product_Field_Mapping__mdt mapping : mappingsByParent.get('ProductAttribute.pricing')) {
                Object value = getFieldValue(productData.product, mapping);
                if (value != null) {
                    pricing.put(mapping.PAID_Field_Name__c, value);
                }
            }
        }
        
        // Build PricePoints object (currency-specific pricing)
        Map<String, Object> pricePoints = buildBasePricePoints(productData, mappingsByParent);
        if (!pricePoints.isEmpty()) {
            pricing.put('PricePoints', pricePoints);
        }
        
        return pricing;
    }
    
    /**
    * @description Builds PricePoints object for base product from PricebookEntry
    * Includes tiers for Block pricing
    * @param productData Product and related data
    * @param mappingsByParent Field mappings grouped by parent
    * @return PricePoints map
    */
        
    public static Map<String, Object> buildBasePricePoints(
        ProductData productData,
        Map<String, List<PAID_Product_Field_Mapping__mdt>> mappingsByParent
    ) {
        Map<String, Object> pricePoints = new Map<String, Object>();
        
        if (!productData.pricebookEntries.isEmpty()) {
            // Query price book information to create meaningful keys
            Set<Id> priceBookIds = new Set<Id>();
            for (PricebookEntry entry : productData.pricebookEntries) {
                priceBookIds.add(entry.Pricebook2Id);
            }
            
            Map<Id, Pricebook2> priceBookMap = new Map<Id, Pricebook2>([
                SELECT Id, Name, IsStandard 
                FROM Pricebook2 
                WHERE Id IN :priceBookIds
            ]);
            
            // Build PricePoints from ALL PricebookEntry records
            for (PricebookEntry entry : productData.pricebookEntries) {
                // Get currency (USD default if not multi-currency)
                String currencyCode = 'USD';
                if (UserInfo.isMultiCurrencyOrganization()) {
                    currencyCode = (String)entry.get('CurrencyIsoCode');
                }
                
                // Get price book information
                Pricebook2 priceBook = priceBookMap.get(entry.Pricebook2Id);
                String priceBookName = priceBook.IsStandard ? 'Standard' : priceBook.Name;
                
                // Create composite key: USD_Standard, USD_EnterprisePriceBook, EUR_Standard, etc.
                // Remove spaces from price book name for cleaner key
               // String sanitizedPriceBookName = priceBookName.replaceAll('\\s+', '');
                String pricePointKey = currencyCode;
                
                // Build the price point object - CLEAN structure only
                Map<String, Object> pricePoint = new Map<String, Object>();
                pricePoint.put('unitPrice', entry.UnitPrice * 100);
                pricePoint.put('minQuantity', null);
                pricePoint.put('includedQuantity', null);
                pricePoint.put('tiers', new List<Map<String, Object>>());
                
                // NOTE: Metadata removed - PAID API doesn't accept these extra fields
                // We only use them for logging below
                
                pricePoints.put(pricePointKey, pricePoint);
                
                System.debug('Added PricePoint [' + pricePointKey + ']: ' + 
                             entry.UnitPrice + ' ' + currencyCode + 
                             ' from ' + priceBookName + ' Price Book (ID: ' + entry.Pricebook2Id + ')');
            }
            
            System.debug('Total PricePoints created: ' + pricePoints.size());
        } else {
            // No PricebookEntry: Create default PricePoint
            System.debug('No PricebookEntry found, creating default PricePoint');
            
            String defaultCurrency = 'USD';
            if (UserInfo.isMultiCurrencyOrganization()) {
                defaultCurrency = UserInfo.getDefaultCurrency();
            }
            
            Map<String, Object> pricePoint = new Map<String, Object>();
            pricePoint.put('unitPrice', 0);
            pricePoint.put('minQuantity', null);
            pricePoint.put('includedQuantity', null);
            pricePoint.put('tiers', new List<Map<String, Object>>());
            
            pricePoints.put(defaultCurrency, pricePoint);
        }
        
        return pricePoints;
    }
    /**
    * @description Extracts and transforms field value
    * @param record Source record (Product2)
    * @param mapping Field mapping configuration
    * @return Transformed field value
    */
    public static Object getFieldValue(SObject record, PAID_Product_Field_Mapping__mdt mapping) {
        Object rawValue = null;
        
        if (String.isNotBlank(mapping.Salesforce_Field_API_Name__c)) {
            try {
                rawValue = record.get(mapping.Salesforce_Field_API_Name__c);
            }catch (System.SObjectException sObjEx) {
                // Re-throw SObjectException - this means a required field is missing from the query
                throw sObjEx;
            } catch (Exception e) {
                // Other exceptions - field might not exist on this object type
                System.debug('Field access warning for ' + mapping.Salesforce_Field_API_Name__c + ': ' + e.getMessage());
                rawValue = null;
            }
        }
        
        // Use default if value is null
        if (rawValue == null && !String.isBlank(mapping.Default_Value__c)) {
            rawValue = mapping.Default_Value__c;
        }
        
        if (rawValue == null) {
            return null;
        }
        
        // Apply transformation logic
        if (String.isNotBlank(mapping.Transformation_Rule__c) && mapping.Transformation_Rule__c != 'None') {
            rawValue = PAIDHelper.applyTransformation(rawValue, mapping.Transformation_Rule__c);
        }
        
        // Apply data type conversion
        return PAIDHelper.convertDataType(rawValue, mapping.Data_Type__c);
    }
    
    /**
    * @description Retrieves API configuration from metadata
    * Updated to work with existing PAID_API_Configuration__mdt structure
    * @param operationType Create or Update
    * @return API configuration metadata record
    */
    public static PAID_API_Configuration__mdt getAPIConfiguration(String operationType) {
        // Search for "Create Product" or "Update Product" in Operation_Type__c
        String searchOperation = operationType + ' Product';
        
        List<PAID_API_Configuration__mdt> configs = [
            SELECT Endpoint_Path__c, HTTP_Method__c, Named_Credential__c, 
            Content_Type__c
            FROM PAID_API_Configuration__mdt
            WHERE Operation_Type__c = :searchOperation
            AND Active__c = true
            LIMIT 1
        ];
        
        return configs.isEmpty() ? null : configs[0];
    }
    
    /**
    * @description Validates required fields
    * @param product Product record to validate
    * @param operationType Create or Update
    */
    public static void validateRequiredFields(Product2 product, String operationType) {
        List<PAID_Product_Field_Mapping__mdt> requiredMappings = [
            SELECT Salesforce_Field_API_Name__c, PAID_Field_Name__c, MasterLabel
            FROM PAID_Product_Field_Mapping__mdt
            WHERE Active__c = true
            AND Is_Required__c = true
            AND Salesforce_Object__c = 'Product2'
            AND (Operation_Type__c = :operationType OR Operation_Type__c = 'Both')
        ];
        
        List<String> missingFields = new List<String>();
        
        for (PAID_Product_Field_Mapping__mdt mapping : requiredMappings) {
            if (String.isNotBlank(mapping.Salesforce_Field_API_Name__c)) {
                try {
                    Object fieldValue = product.get(mapping.Salesforce_Field_API_Name__c);
                    if (fieldValue == null || String.valueOf(fieldValue).trim() == '') {
                        missingFields.add(mapping.MasterLabel);
                    }
                } catch (Exception e) {
                    missingFields.add(mapping.MasterLabel + ' (field not accessible)');
                }
            }
        }
        
        if (!missingFields.isEmpty()) {
            String errorMessage = 'Required fields missing: ' + String.join(missingFields, ', ');
            
            Event_Log__c log = PAIDHelper.createEventLog(
                operationType + ' Product',              // operationKey
                'Product2 Id: ' + product.Id,            // request
                null,                                     // response
                false,                                    // success
                errorMessage,                             // errorMessage
                null,                                     // accountId
                null,                                     // contactId
                null,                                     // orderId
                product.Id,                               // productId
                null                                      // orderNumber
            );
            insert log;
            
            throw new PAIDProductException(errorMessage);
        }
    }
    
    /**
    * @description Makes HTTP callout to PAID API
    * Updated to work with existing PAID_API_Configuration__mdt structure
    * @param config API configuration
    * @param requestBody JSON request body
    * @param productExternalId PAID Product ID (for updates)
    * @return HTTP response
    */
    public static HttpResponse makeCallout(PAID_API_Configuration__mdt config, String requestBody, String productExternalId) {
        HttpRequest request = new HttpRequest();
        
        // Build endpoint using Named Credential and Endpoint Path
        String endpoint = 'callout:' + config.Named_Credential__c;
        String apiPath = config.Endpoint_Path__c;
        
        // Replace :productId placeholder for update operations
        if (String.isNotBlank(productExternalId)) {
            apiPath = apiPath.replace(':productId', productExternalId);
            // Also support {productId} format for backward compatibility
            apiPath = apiPath.replace('{productId}', productExternalId);
        }
        
        endpoint += apiPath;
        
        request.setEndpoint(endpoint);
        request.setMethod(config.HTTP_Method__c);
        
        // Use Content_Type__c from metadata if available, otherwise default
        String contentType = String.isNotBlank(config.Content_Type__c) ? 
            config.Content_Type__c : 'application/json';
        request.setHeader('Content-Type', contentType);
        
        request.setBody(requestBody);
        
        Http http = new Http();
        return http.send(request);
    }
    
    /**
    * @description Processes CREATE response from PAID
    */
    public static void processCreateResponse(Id productId, HttpResponse response, String requestBody) {
        Integer statusCode = response.getStatusCode();
        String responseBody = response.getBody();
        Boolean isSuccess = statusCode >= 200 && statusCode < 300;
        
        Product2 productToUpdate = new Product2(Id = productId);
        
        if (isSuccess) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            String paidProductId = extractProductId(responseMap);
            
            productToUpdate.PAID_ProductExternalID__c = paidProductId;
            productToUpdate.PAID_Product_Creation_Status__c = 'Success';
        } else {
            productToUpdate.PAID_Product_Creation_Status__c = 'Failure';
            productToUpdate.PAID_ProductExternalID__c = null;
        }
        
        update productToUpdate;
        Event_Log__c log = PAIDHelper.createEventLog(
            'Create Product',                                              // operationKey
            requestBody,                                                   // request
            responseBody,                                                  // response
            isSuccess,                                                     // success (Boolean)
            isSuccess ? null : 'HTTP ' + statusCode + ': ' + responseBody, // errorMessage
            null,                                                          // accountId
            null,                                                          // contactId
            null,                                                          // orderId
            productId,                                                     // productId
            null                                                           // orderNumber
        );
        insert log;
    }
    
    /**
    * @description Processes UPDATE response from PAID
    */
    public static void processUpdateResponse(Id productId, HttpResponse response, String requestBody) {
        Integer statusCode = response.getStatusCode();
        String responseBody = response.getBody();
        Boolean isSuccess = statusCode >= 200 && statusCode < 300;
        
        Product2 productToUpdate = new Product2(Id = productId);
        
        if (isSuccess) {
            productToUpdate.PAID_Product_Update_Status__c = 'Success';
            productToUpdate.Sent_UpdateProduct_to_PAID__c = false;
        } else {
            productToUpdate.PAID_Product_Update_Status__c = 'Failure';
            productToUpdate.Sent_UpdateProduct_to_PAID__c = false;
        }
        
        update productToUpdate;
        
        Event_Log__c log = PAIDHelper.createEventLog(
            'Update Product',                                              // operationKey
            requestBody,                                                   // request
            responseBody,                                                  // response
            isSuccess,                                                     // success (Boolean)
            isSuccess ? null : 'HTTP ' + statusCode + ': ' + responseBody, // errorMessage
            null,                                                          // accountId
            null,                                                          // contactId
            null,                                                          // orderId
            productId,                                                     // productId
            null                                                           // orderNumber
        );
        insert log;
    }
    
    /**
    * @description Extracts Product ID from response
    */
    public static String extractProductId(Map<String, Object> responseMap) {
        if (responseMap.containsKey('id')) {
            return String.valueOf(responseMap.get('id'));
        }
        
        if (responseMap.containsKey('productId')) {
            return String.valueOf(responseMap.get('productId'));
        }
        
        if (responseMap.containsKey('data')) {
            Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
            if (dataMap != null && dataMap.containsKey('id')) {
                return String.valueOf(dataMap.get('id'));
            }
        }
        
        throw new PAIDProductException('Unable to extract Product ID from response');
    }
    
    /**
    * @description Handles exceptions
    */
    public static void handleException(Id productId, String operation, Exception e, String requestBody) {
        Product2 productToUpdate = new Product2(Id = productId);
        
        if (operation == CREATE_OPERATION) {
            productToUpdate.PAID_Product_Creation_Status__c = 'Failure';
            productToUpdate.Sent_Product_to_PAID__c = false;
        } else {
            productToUpdate.PAID_Product_Update_Status__c = 'Failure';
            productToUpdate.Sent_UpdateProduct_to_PAID__c = false;
        }
        
        update productToUpdate;
        
        Event_Log__c log = PAIDHelper.createEventLog(
            operation + ' Product',                                                      // operationKey
            requestBody,                                                                 // request
            null,                                                                        // response
            false,                                                                       // success (always false for exceptions)
            e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString(),  // errorMessage
            null,                                                                        // accountId
            null,                                                                        // contactId
            null,                                                                        // orderId
            productId,                                                                   // productId
            null                                                                         // orderNumber
        );
        insert log;
    }
    /**
    * @description Update Product2 record with failed status
    * @param productId Product ID
    * @param operationType CREATE_OPERATION or UPDATE_OPERATION
    */
    public static void updateProductWithError(Id productId, String operationType) {
        try {
            Product2 productUpdate = new Product2(Id = productId);
            
            if (operationType == CREATE_OPERATION) {
                productUpdate.PAID_Product_Creation_Status__c = 'Failed';
                productUpdate.Sent_Product_to_PAID__c = false;
            } else if (operationType == UPDATE_OPERATION) {
                productUpdate.PAID_Product_Update_Status__c = 'Failed';
                productUpdate.Sent_UpdateProduct_to_PAID__c = false;
            }
            
            update productUpdate;
            
        } catch (Exception updateEx) {
            // Log but don't throw - we've already captured the main error
            System.debug('Error updating product with error status: ' + updateEx.getMessage());
        }
    }
    

    
    public class PAIDProductException extends Exception {}
}