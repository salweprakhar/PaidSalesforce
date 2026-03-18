/**
* @description Synchronous service class for PAID Product API operations
* Used for UI buttons, manual retry operations, and REST APIs
* Contains methods that perform callout + DML in same transaction
* 
* DO NOT use from triggers or batch jobs - use PAIDProductService instead
* 
* @author m
* @date 2025
*/
public class PAIDProductSyncService {
    
    private static final String CREATE_OPERATION = 'Create';
    private static final String UPDATE_OPERATION = 'Update';
    
    /**
* @description Synchronously creates a product in PAID with immediate DML
* FOR UI/MANUAL OPERATIONS ONLY
* @param productId Salesforce Product Id
* @return HTTP response from PAID API
*/
    public static HttpResponse createProduct(Id productId) {
        System.debug('=== START SYNC CREATE PRODUCT ===');
        System.debug('Product ID: ' + productId);
        
        String requestBody = null;
        String errorMessage = null;
        HttpResponse response = null;
        
        try {
            // Get configuration
            PAID_API_Configuration__mdt config = PAIDProductService.getAPIConfiguration(CREATE_OPERATION);
            if (config == null) {
                throw new PAIDProductService.PAIDProductException('No active API configuration found for Product Creation');
            }
            
            // Get product data with related records
            PAIDProductService.ProductData productData = PAIDProductService.getProductData(productId);
            
            // Validate required fields
            PAIDProductService.validateRequiredFields(productData.product, CREATE_OPERATION);
            
            // Build request payload
            requestBody = PAIDProductService.buildProductPayload(productData, CREATE_OPERATION, config);
            
            System.debug('=== CREATE PRODUCT PAYLOAD ===');
            System.debug(requestBody);
            
            // Make HTTP callout
            response = PAIDProductService.makeCallout(config, requestBody, null);
            
            // IMMEDIATELY mark as sent after callout is made
            Product2 productSentUpdate = new Product2(
                Id = productId,
                Sent_Product_to_PAID__c = true
            );
            update productSentUpdate;
            
            // Process response
            processCreateResponse(productId, response, requestBody);
            System.debug('=== END SYNC CREATE PRODUCT - SUCCESS ===');
            
            return response;
            
        } catch (System.SObjectException sObjEx) {
            errorMessage = 'Missing required field in Product query: ' + sObjEx.getMessage();
            System.debug('SObjectException: ' + errorMessage);
            
            Event_Log__c log = PAIDHelper.createEventLog(
                CREATE_OPERATION + ' Product',                                         // operationKey
                requestBody != null ? requestBody : 'Payload not generated due to error', // request
                null,                                                                  // response
                false,                                                                 // success (false for Failure)
                errorMessage,                                                          // errorMessage
                null,                                                                  // accountId
                null,                                                                  // contactId
                null,                                                                  // orderId
                productId,                                                             // productId
                null                                                                   // orderNumber
            );
            insert log;
            
            updateProductWithError(productId, CREATE_OPERATION);
            
            System.debug('=== END SYNC CREATE PRODUCT - SOBJECT EXCEPTION ===');
            throw sObjEx;
            
        } catch (PAIDProductService.PAIDProductException integEx) {
            errorMessage = 'Integration error: ' + integEx.getMessage();
            System.debug('PAIDProductException: ' + errorMessage);
            
            Event_Log__c log = PAIDHelper.createEventLog(
                CREATE_OPERATION + ' Product',
                requestBody != null ? requestBody : 'Payload not generated due to error',
                null,
                false,
                errorMessage,
                null, null, null, productId, null
            );
            insert log;
            
            updateProductWithError(productId, CREATE_OPERATION);
            
            System.debug('=== END SYNC CREATE PRODUCT - INTEGRATION EXCEPTION ===');
            throw integEx;
            
        } catch (Exception ex) {
            errorMessage = 'Unexpected error: ' + ex.getMessage() + ' | Stack Trace: ' + ex.getStackTraceString();
            System.debug('Exception: ' + errorMessage);
            
            Event_Log__c log = PAIDHelper.createEventLog(
                CREATE_OPERATION + ' Product',
                requestBody != null ? requestBody : 'Payload not generated due to error',
                null,
                false,
                errorMessage,
                null, null, null, productId, null
            );
            insert log;
            
            updateProductWithError(productId, CREATE_OPERATION);
            
            System.debug('=== END SYNC CREATE PRODUCT - GENERAL EXCEPTION ===');
            throw ex;
        }
    }
    
    /**
* @description Synchronously updates a product in PAID with immediate DML
* FOR UI/MANUAL OPERATIONS ONLY
* @param productId Salesforce Product Id
* @return HTTP response from PAID API
*/
    public static HttpResponse updateProduct(Id productId) {
        System.debug('=== START SYNC UPDATE PRODUCT ===');
        System.debug('Product ID: ' + productId);
        
        String requestBody = null;
        String errorMessage = null;
        HttpResponse response = null;
        
        try {
            // Get configuration
            PAID_API_Configuration__mdt config = PAIDProductService.getAPIConfiguration(UPDATE_OPERATION);
            if (config == null) {
                throw new PAIDProductService.PAIDProductException('No active API configuration found for Product Update');
            }
            
            // Get product data with related records
            PAIDProductService.ProductData productData = PAIDProductService.getProductData(productId);
            
            // Validate PAID External ID exists
            if (String.isBlank(productData.product.PAID_ProductExternalID__c)) {
                throw new PAIDProductService.PAIDProductException('Cannot update product: PAID_ProductExternalID__c is missing');
            }
            
            // Build request payload
            requestBody = PAIDProductService.buildProductPayload(productData, UPDATE_OPERATION, config);
            
            System.debug('=== UPDATE PRODUCT PAYLOAD ===');
            System.debug('Product: ' + productData.product.Name);
            System.debug('Pricing Method: ' + (PAIDProductService.hasCPQ() ? productData.product.get('SBQQ__PricingMethod__c') : 'N/A'));
            System.debug('Block Prices Count: ' + productData.blockPrices.size());
            System.debug('Cost Records Count: ' + productData.costs.size());
            System.debug('Payload: ' + requestBody);
            
            // Make HTTP callout
            response = PAIDProductService.makeCallout(config, requestBody, productData.product.PAID_ProductExternalID__c);
            
            Product2 productSentUpdate = new Product2(
                Id = productId,
                Sent_UpdateProduct_to_PAID__c = true
            );
            update productSentUpdate;
            
            // Process response
            processUpdateResponse(productId, response, requestBody);
            
            System.debug('=== END SYNC UPDATE PRODUCT - SUCCESS ===');
            return response;
            
        } catch (System.SObjectException sObjEx) {
            errorMessage = 'Missing required field in Product query: ' + sObjEx.getMessage();
            System.debug('SObjectException: ' + errorMessage);
            
            Event_Log__c log = PAIDHelper.createEventLog(
                UPDATE_OPERATION + ' Product',
                requestBody != null ? requestBody : 'Payload not generated due to error',
                null,
                false,
                errorMessage,
                null, null, null, productId, null
            );
            insert log;
            
            updateProductWithError(productId, UPDATE_OPERATION);
            
            System.debug('=== END SYNC UPDATE PRODUCT - SOBJECT EXCEPTION ===');
            throw sObjEx;
            
        } catch (PAIDProductService.PAIDProductException integEx) {
            errorMessage = 'Integration error: ' + integEx.getMessage();
            System.debug('PAIDProductException: ' + errorMessage);
            
            Event_Log__c log = PAIDHelper.createEventLog(
                UPDATE_OPERATION + ' Product',
                requestBody != null ? requestBody : 'Payload not generated due to error',
                null,
                false,
                errorMessage,
                null, null, null, productId, null
            );
            insert log;
            
            updateProductWithError(productId, UPDATE_OPERATION);
            
            System.debug('=== END SYNC UPDATE PRODUCT - INTEGRATION EXCEPTION ===');
            throw integEx;
            
        } catch (Exception ex) {
            errorMessage = 'Unexpected error: ' + ex.getMessage() + ' | Stack Trace: ' + ex.getStackTraceString();
            System.debug('Exception: ' + errorMessage);
            
            Event_Log__c log = PAIDHelper.createEventLog(
                UPDATE_OPERATION + ' Product',
                requestBody != null ? requestBody : 'Payload not generated due to error',
                null,
                false,
                errorMessage,
                null, null, null, productId, null
            );
            insert log;
            
            updateProductWithError(productId, UPDATE_OPERATION);
            
            System.debug('=== END SYNC UPDATE PRODUCT - GENERAL EXCEPTION ===');
            throw ex;
        }
    }
    
    // ========== PRIVATE HELPER METHODS ==========
    
    /**
* @description Processes CREATE response from PAID
*/
    private static void processCreateResponse(Id productId, HttpResponse response, String requestBody) {
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
            'Create Product',
            requestBody,
            responseBody,
            isSuccess,
            isSuccess ? null : 'HTTP ' + statusCode + ': ' + responseBody,
            null, null, null, productId, null
        );
        insert log;
    }
    
    /**
* @description Processes UPDATE response from PAID
*/
    private static void processUpdateResponse(Id productId, HttpResponse response, String requestBody) {
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
            'Update Product',
            requestBody,
            responseBody,
            isSuccess,
            isSuccess ? null : 'HTTP ' + statusCode + ': ' + responseBody,
            null, null, null, productId, null
        );
        insert log;
    }
    
    /**
* @description Extracts Product ID from response
*/
    private static String extractProductId(Map<String, Object> responseMap) {
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
        
        throw new PAIDProductService.PAIDProductException('Unable to extract Product ID from response');
    }
    
    /**
* @description Update Product2 record with failed status
*/
    private static void updateProductWithError(Id productId, String operationType) {
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
            System.debug('Error updating product with error status: ' + updateEx.getMessage());
        }
    }
    
    
}