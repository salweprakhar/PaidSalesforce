/**
 * @description Service class for PAID Customer Creation API integration
 * Uses Custom Metadata for configurable field mapping
 * @author Manusha T
 */
public class PAIDCustomerCreationService {
     
    // Cache for field mappings
    public static List<PAID_Customer_Field_Mapping__mdt> fieldMappings;
    // Cache for API Config 
    public static PAID_API_Configuration__mdt apiConfig;
    
    /**
     * @description Wrapper class for validation results
     */
    public class ValidationResult {
        public Boolean isValid;
        public String errorMessage;
        
        public ValidationResult(Boolean isValid, String errorMessage) {
            this.isValid = isValid;
            this.errorMessage = errorMessage;
        }
    }
    
    
    /**
     * @description Wrapper class for callout results
     */
    public class PAIDCalloutResult {
        public Boolean isSuccess;
        public String paidCustomerId;
        public String requestPayload;
        public String responsePayload;
        public Integer statusCode;
        public String errorMessage;
        
        public PAIDCalloutResult() {
            this.isSuccess = false;
        }
    }
    
    /**
     * @description Wrapper class to hold customer creation processing results
     */
    public class CustomerCreationResult {
        public List<Order> ordersToUpdate;
        public List<Account> accountsToUpdate;
        public List<Event_Log__c> eventLogs;
        public List<Account> successfullyCreatedAccounts;
        
        public CustomerCreationResult() {
            this.ordersToUpdate = new List<Order>();
            this.accountsToUpdate = new List<Account>();
            this.eventLogs = new List<Event_Log__c>();
            this.successfullyCreatedAccounts = new List<Account>();
        }
    }
    
    /**
     * @description Process customer creation for multiple orders and accounts
     * @param orders List of Order records to process
     * @param accountMap Map of Account ID to Account record
     * @return CustomerCreationResult with all updates and logs
     */
    public static CustomerCreationResult processCustomerCreationBulk(List<Order> orders, Map<Id, Account> accountMap) {
        CustomerCreationResult result = new CustomerCreationResult();
        
        for (Order ord : orders) {
            Account acc = accountMap.get(ord.AccountId);
            
            if (acc == null) {
                continue; 
            }
            
            // Pre-callout validation
            ValidationResult validationResult = validateCustomerData(acc);
            
            if (!validationResult.isValid) {
                // Validation failed - update Order and log error
                ord.Sent_Customer_to_PAID__c = false;
                ord.PAID_Customer_Creation_Status__c = 'Failure';
                result.ordersToUpdate.add(ord);
                
                // Create event log for validation failure
                result.eventLogs.add(PAIDHelper.createEventLog(
                    'Create Customer',
                    null,
                    null,
                    false,
                    validationResult.errorMessage,
                    acc.Id,
                    null,
                    ord.Id,
                    null,
                    ord.OrderNumber
                ));
                continue;
            }
            
            // Mark as sent before callout
            ord.Sent_Customer_to_PAID__c = true;
            result.ordersToUpdate.add(ord);
            
            // Make callout to PAID
            PAIDCalloutResult calloutResult;
            
            //PAIDCalloutResult calloutResult = createCustomerInPAID(acc);
            // Decide Create vs Update
            if (String.isBlank(acc.PAID_CustomerExternalID__c)) {
                calloutResult = createCustomerInPAID(acc);
            } else {
                calloutResult = updateCustomerInPAID(acc);
            }
            
            String actionName = String.isBlank(acc.PAID_CustomerExternalID__c)
                    ? 'Create Customer'
                    : 'Update Customer';
                
            
            // Handle response
            if (calloutResult.isSuccess) {
                // Success - update Order and Account
                ord.PAID_Customer_Creation_Status__c = 'Success';
                System.debug('calloutResult.paidCustomerId:::'+calloutResult.paidCustomerId);
                if (String.isNotBlank(calloutResult.paidCustomerId)) {
                    ord.PAID_CustomerExternalID__c = calloutResult.paidCustomerId;
                    
                    acc.PAID_CustomerExternalID__c = calloutResult.paidCustomerId;
                }
                result.accountsToUpdate.add(acc);
                
                result.successfullyCreatedAccounts.add(acc);
                
                // Create success event log
                result.eventLogs.add(PAIDHelper.createEventLog(
                    actionName,
                    calloutResult.requestPayload,
                    calloutResult.responsePayload,
                    true,
                    null,
                    acc.Id,
                    null,
                    ord.Id,
                    null,
                    ord.OrderNumber
                ));
                
            } else {
                // Failure - update Order with failure status
                ord.PAID_Customer_Creation_Status__c = 'Failure';
                ord.PAID_CustomerExternalID__c = null;
                
                // Create failure event log
                result.eventLogs.add(PAIDHelper.createEventLog(
                    actionName,
                    calloutResult.requestPayload,
                    calloutResult.responsePayload,
                    false,
                    calloutResult.errorMessage,
                    acc.Id,
                    null,
                    ord.Id,
                    null,
                    ord.OrderNumber
                ));
            }
        }
        
        return result;
    }
    
    /**
     * @description Validate customer data before sending to PAID
     * Uses Custom Metadata to determine required fields
     * @param acc Account record
     * @return ValidationResult
     */
    public static ValidationResult validateCustomerData(Account acc) {
        List<String> missingFields = new List<String>();
        
        // Get field mappings using helper
        List<SObject> fieldMappings = PAIDHelper.getFieldMappings('PAID_Customer_Field_Mapping__mdt','Account');
        
        for (SObject mappingObj : fieldMappings) {
            String sfObject = (String)mappingObj.get('Salesforce_Object__c');
            Boolean isRequired = (Boolean)mappingObj.get('Is_Required__c');
            
            if (isRequired && sfObject == 'Account') {
                String fieldApiName = (String)mappingObj.get('Salesforce_Field_API_Name__c');
                Object fieldValue = acc.get(fieldApiName);
                
                if (fieldValue == null || String.valueOf(fieldValue).trim() == '') {
                    missingFields.add(fieldApiName);
                }
            }
        }
        
        if (!missingFields.isEmpty()) {
            String errorMsg = 'Missing required fields: ' + String.join(missingFields, ', ');
            return new ValidationResult(false, errorMsg);
        }
        
        return new ValidationResult(true, null);
    }
    
    /**
     * @description Create customer in PAID via API
     * @param acc Account record
     * @return PAIDCalloutResult
     */
    public static PAIDCalloutResult createCustomerInPAID(Account acc) {
        PAIDCalloutResult result = new PAIDCalloutResult();
        
        try {
            
            // Get API configuration using helper
            PAID_API_Configuration__mdt config = PAIDHelper.getAPIConfiguration('Create Customer');
            
            // Build request payload
            String requestBody = buildRequestPayload(acc);
            result.requestPayload = requestBody;
            
            System.debug('=== PAID API Request ===');
            System.debug('Request Body: ' + requestBody);
            
            // Build endpoint URL
            String endpoint = 'callout:' + config.Named_Credential__c + config.Endpoint_Path__c;
            System.debug('Endpoint: ' + endpoint);
            
            // Make HTTP callout
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod(config.HTTP_Method__c);
            req.setHeader('Content-Type', config.Content_Type__c);
            req.setBody(requestBody);
            req.setTimeout(120000); 
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            result.statusCode = res.getStatusCode();
            result.responsePayload = res.getBody();
            
            System.debug('=== PAID API Response ===');
            System.debug('Response Status Code: ' + result.statusCode);
            System.debug('Response Body: ' + result.responsePayload);
            
            // Check if response is successful (2xx range)
            if (result.statusCode >= 200 && result.statusCode < 300) {
                
                // Parse response and extract customer ID
                result.paidCustomerId = parseCustomerIdFromResponse(res.getBody());
                if(result.paidCustomerId != null) {
                    result.isSuccess = true;
                }else{
                    result.isSuccess = false;
                    result.errorMessage = 'Failed to extract customer ID from response';
                    System.debug('ERROR: Failed to extract customer ID');
                } 
            } else {
                // Handle failure (4xx or 5xx)
                result.isSuccess = false;
                result.errorMessage = 'HTTP ' + result.statusCode + ': ' + res.getStatus();
                System.debug('ERROR: HTTP failure - ' + result.errorMessage);
            }
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'Exception: ' + e.getMessage();
            result.responsePayload = e.getStackTraceString();
            System.debug('EXCEPTION in createCustomerInPAID: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Build JSON request payload for PAID API using Custom Metadata
     * @param acc Account record
     * @return JSON string
     */
    public static String buildRequestPayload(Account acc) {
        Map<String, Object> payload = new Map<String, Object>();
        Map<String, Map<String, Object>> nestedObjects = new Map<String, Map<String, Object>>();
        
        // Get field mappings using helper
        List<SObject> fieldMappings = PAIDHelper.getFieldMappings('PAID_Customer_Field_Mapping__mdt','Account');
        
        // Process each field mapping
        for (SObject mappingObj : fieldMappings) {
            String sfObject = (String)mappingObj.get('Salesforce_Object__c');
            
            if (sfObject != 'Account') {
                continue;
            }
            
            String fieldApiName = (String)mappingObj.get('Salesforce_Field_API_Name__c');
            String paidFieldName = (String)mappingObj.get('PAID_Field_Name__c');
            String dataType = (String)mappingObj.get('Data_Type__c');
            String parentField = (String)mappingObj.get('Parent_Field__c');
            String defaultValue = (String)mappingObj.get('Default_Value__c');
            String transformationRule = (String)mappingObj.get('Transformation_Rule__c');
            
             // Get field value from Account
            Object fieldValue = acc.get(fieldApiName);
            
             // Apply default value if field is null
            if (fieldValue == null && String.isNotBlank(defaultValue)) {
                fieldValue = defaultValue;
            }
            
            // Skip null values (optional fields)
            if (fieldValue == null) {
                continue;
            }
            
            // Apply transformation rules using PAIDHelper
        	fieldValue = PAIDHelper.applyTransformation(fieldValue, transformationRule);
            
            // Convert to appropriate data type
            fieldValue = PAIDHelper.convertDataType(fieldValue, dataType);
            
            // Handle nested objects (like billingAddress)
            if (String.isNotBlank(parentField)) { 
                // Nested field
                if (!nestedObjects.containsKey(parentField)) {
                    nestedObjects.put(parentField, new Map<String, Object>());
                }
                nestedObjects.get(parentField).put(paidFieldName, fieldValue);
            } else {
                // Top-level field
                payload.put(paidFieldName, fieldValue);
            }
        }
        
        // Add nested objects to payload
        if (!nestedObjects.isEmpty()) {
        for (String parentField : nestedObjects.keySet()) {
            Map<String, Object> nestedObj = nestedObjects.get(parentField);
            if (!nestedObj.isEmpty()) {
                payload.put(parentField, nestedObj);
            }
        }
        }
        
        // Add metadata for tracking
        /*Map<String, Object> metadata = new Map<String, Object>();
        metadata.put('salesforceAccountId', acc.Id);
        metadata.put('source', 'Salesforce');
        metadata.put('syncDate', System.now().format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
        payload.put('metadata', metadata);*/
        System.debug('payload:::'+payload);
        return JSON.serialize(payload);
    }
 
    /**
     * @description Parse customer ID from PAID API response
     * @param responseBody Response JSON string
     * @return Customer ID or external ID
     */
    public static String parseCustomerIdFromResponse(String responseBody) {
        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
             System.debug('=== Parsing Response ===');
            System.debug('Response Map Keys: ' + responseMap.keySet());
            
           // Check for 'data' object (common API wrapper pattern)
            if (responseMap.containsKey('data')) {
                Object dataObj = responseMap.get('data');
                
                // Validate data object exists and is a Map
                if (dataObj != null && dataObj instanceof Map<String, Object>) {
                    Map<String, Object> dataMap = (Map<String, Object>) dataObj;
                    
                    System.debug('Data Map Keys: ' + dataMap.keySet());
                    
                    // Primary: Try to get 'id' field from data object
                    if (dataMap.containsKey('id')) {
                        String customerId = String.valueOf(dataMap.get('id'));
                        System.debug('Found customer ID in data.id: ' + customerId);
                        return customerId;
                    }
                    
                    // Secondary: Try 'externalId' field
                    if (dataMap.containsKey('externalId')) {
                        String externalId = String.valueOf(dataMap.get('externalId'));
                        System.debug('Found customer ID in data.externalId: ' + externalId);
                        return externalId;
                    }
                    
                    // Tertiary: Try 'displayId' field
                    if (dataMap.containsKey('displayId')) {
                        String displayId = String.valueOf(dataMap.get('displayId'));
                        System.debug('Found customer ID in data.displayId: ' + displayId);
                        return displayId;
                    }
                    
                    System.debug('No recognized ID field found in data object');
                } else {
                    System.debug( 'Data object is null or not a Map');
                }
            }
            
            // Fallback: Check root level for ID fields (for different API response structures)
            if (responseMap.containsKey('id')) {
                String customerId = String.valueOf(responseMap.get('id'));
                System.debug('Found customer ID at root level: ' + customerId);
                return customerId;
            }
            
            if (responseMap.containsKey('externalId')) {
                String externalId = String.valueOf(responseMap.get('externalId'));
                System.debug('Found externalId at root level: ' + externalId);
                return externalId;
            }
            
            if (responseMap.containsKey('customerId')) {
                String customerId = String.valueOf(responseMap.get('customerId'));
                System.debug('Found customerId at root level: ' + customerId);
                return customerId;
            }
            
            System.debug('No customer ID found in response at any level');
            return null; 
            
        } catch (Exception e) {
            System.debug('EXCEPTION in parseCustomerIdFromResponse: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return null;
        }
    }
    
    /**
    * @description Update existing customer in PAID via API
    * Uses Custom Metadata for endpoint and field mapping
    * @param acc Account record
    * @return PAIDCalloutResult
    */
    public static PAIDCalloutResult updateCustomerInPAID(Account acc) {
        PAIDCalloutResult result = new PAIDCalloutResult();
        
        try {
            // Validate PAID Customer ID exists
            if (String.isBlank(acc.PAID_CustomerExternalID__c)) {
                result.isSuccess = false;
                result.errorMessage = 'PAID Customer ID not found on Account';
                return result;
            }
            
            // Get API configuration for Update Customer
            PAID_API_Configuration__mdt config =
                PAIDHelper.getAPIConfiguration('Update Customer');
            
            // Build request payload using same metadata mapping
            String requestBody = buildRequestPayload(acc);
            result.requestPayload = requestBody;
            
            System.debug('=== PAID Update Customer API Request ===');
            System.debug('Request Body: ' + requestBody);
            
            // Build endpoint (append PAID Customer ID)
            String endpoint = 'callout:' + config.Named_Credential__c
                + config.Endpoint_Path__c
                + '/' + acc.PAID_CustomerExternalID__c;
            
            System.debug('Endpoint: ' + endpoint);
            
            // Prepare HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod(config.HTTP_Method__c); // PUT / PATCH
            req.setHeader('Content-Type', config.Content_Type__c);
            req.setBody(requestBody);
            req.setTimeout(120000);
            
            // Send request
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            result.statusCode = res.getStatusCode();
            result.responsePayload = res.getBody();
            
            System.debug('=== PAID Update Customer API Response ===');
            System.debug('Status Code: ' + result.statusCode);
            System.debug('Response Body: ' + result.responsePayload);
            
            // Success check
            if (result.statusCode >= 200 && result.statusCode < 300) {
                result.isSuccess = true;
            } else {
                result.isSuccess = false;
                result.errorMessage = 'HTTP ' + result.statusCode + ': ' + res.getStatus();
            }
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'Exception: ' + e.getMessage();
            result.responsePayload = e.getStackTraceString();
            
            System.debug('EXCEPTION in updateCustomerInPAID: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
        
        return result;
    }
}