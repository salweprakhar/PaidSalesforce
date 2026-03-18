/**
 * @description Service class for PAID Contact Creation API integration
 * Uses Custom Metadata for configurable field mapping
 * @author Manusha T
 */
public class PAIDContactCreationService {
    
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
        public String paidContactId;
        public String requestPayload;
        public String responsePayload;
        public Integer statusCode;
        public String errorMessage;
        
        public PAIDCalloutResult() {
            this.isSuccess = false;
        }
    }
    
    /**
     * @description Validate contact data before sending to PAID
     * Uses Custom Metadata to determine required fields
     * @param con Contact record
     * @return ValidationResult
     */
    public static ValidationResult validateContactData(Contact con) {
        List<String> missingFields = new List<String>();
        
        // Get field mappings using helper
        List<SObject> fieldMappings = PAIDHelper.getFieldMappings('PAID_Contact_Field_Mapping__mdt','Contact');
        
        // Get required field mappings
        for (SObject mappingObj : fieldMappings) {
            String sfObject = (String)mappingObj.get('Salesforce_Object__c');
            Boolean isRequired = (Boolean)mappingObj.get('Is_Required__c');
            
            if (isRequired && sfObject == 'Contact') {
                String fieldApiName = (String)mappingObj.get('Salesforce_Field_API_Name__c');
                Object fieldValue = con.get(fieldApiName);
                
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
     * @description Create contact in PAID via API
     * @param con Contact record
     * @param paidCustomerId PAID Customer External ID from Account
     * @return PAIDCalloutResult
     */
    public static PAIDCalloutResult createContactInPAID(Contact con, String paidCustomerId) {
        PAIDCalloutResult result = new PAIDCalloutResult();
        
        try {
            // Get API configuration using helper
            PAID_API_Configuration__mdt config = PAIDHelper.getAPIConfiguration('Create Contact');
            
            // Build request payload
            String requestBody = buildRequestPayload(con, paidCustomerId);
            result.requestPayload = requestBody;
            
            System.debug('=== PAID Contact API Request ===');
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
            //req.setTimeout(120000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            result.statusCode = res.getStatusCode();
            result.responsePayload = res.getBody();
            
            System.debug('=== PAID Contact API Response ===');
            System.debug('Response Status Code: ' + result.statusCode);
            System.debug('Response Body: ' + result.responsePayload);
            
            // Check if response is successful (2xx range)
            if (result.statusCode >= 200 && result.statusCode < 300) {
                // Parse response and extract contact ID
                result.paidContactId = parseContactIdFromResponse(res.getBody());
                if (result.paidContactId != null) {
                    result.isSuccess = true;
                } else {
                    result.isSuccess = false;
                    result.errorMessage = 'Failed to extract contact ID from response';
                    System.debug('ERROR: Failed to extract contact ID');
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
            System.debug('EXCEPTION in createContactInPAID: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Build JSON request payload for PAID API using Custom Metadata
     * @param con Contact record
     * @param paidCustomerId PAID Customer External ID
     * @return JSON string
     */
    private static String buildRequestPayload(Contact con, String paidCustomerId) {
        Map<String, Object> payload = new Map<String, Object>();
        Map<String, Map<String, Object>> nestedObjects = new Map<String, Map<String, Object>>();
        
        // Add customer ID to payload
        payload.put('customerId', paidCustomerId);
        
        // Get field mappings using helper
        List<SObject> fieldMappings = PAIDHelper.getFieldMappings('PAID_Contact_Field_Mapping__mdt','Contact');
        
        // Process each field mapping
        for (SObject mappingObj : fieldMappings) {
            String sfObject = (String)mappingObj.get('Salesforce_Object__c');
            
            if (sfObject != 'Contact') {
                continue;
            }
            
            String fieldApiName = (String)mappingObj.get('Salesforce_Field_API_Name__c');
            String paidFieldName = (String)mappingObj.get('PAID_Field_Name__c');
            String dataType = (String)mappingObj.get('Data_Type__c');
            String parentField = (String)mappingObj.get('Parent_Field__c');
            String defaultValue = (String)mappingObj.get('Default_Value__c');
            String transformationRule = (String)mappingObj.get('Transformation_Rule__c');
            
            // Get field value from Contact
            Object fieldValue = con.get(fieldApiName);
            
            // Apply default value if field is null
            if (fieldValue == null && String.isNotBlank(defaultValue)) {
                fieldValue = defaultValue;
            }
            
            // Skip null values (optional fields)
            if (fieldValue == null) {
                continue;
            }
            
            // Apply transformation rules
            fieldValue = PAIDHelper.applyTransformation(fieldValue, transformationRule);
            
            // Convert to appropriate data type
            fieldValue = PAIDHelper.convertDataType(fieldValue, dataType);
            
            // Handle nested objects (like mailingAddress)
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
        
        return JSON.serialize(payload);
    }
    
    /**
     * @description Parse contact ID from PAID API response
     * @param responseBody Response JSON string
     * @return Contact ID or external ID
     */
    private static String parseContactIdFromResponse(String responseBody) {
        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
            System.debug('=== Parsing Contact Response ===');
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
                        String contactId = String.valueOf(dataMap.get('id'));
                        System.debug('Found contact ID in data.id: ' + contactId);
                        return contactId;
                    }
                    
                    // Secondary: Try 'externalId' field
                    if (dataMap.containsKey('externalId')) {
                        String externalId = String.valueOf(dataMap.get('externalId'));
                        System.debug('Found contact ID in data.externalId: ' + externalId);
                        return externalId;
                    }
                    
                    // Tertiary: Try 'displayId' field
                    if (dataMap.containsKey('displayId')) {
                        String displayId = String.valueOf(dataMap.get('displayId'));
                        System.debug('Found contact ID in data.displayId: ' + displayId);
                        return displayId;
                    }
                    
                    System.debug('No recognized ID field found in data object');
                } else {
                    System.debug('Data object is null or not a Map');
                }
            }
            
            // Fallback: Check root level for ID fields
            if (responseMap.containsKey('id')) {
                String contactId = String.valueOf(responseMap.get('id'));
                System.debug('Found contact ID at root level: ' + contactId);
                return contactId;
            }
            
            if (responseMap.containsKey('externalId')) {
                String externalId = String.valueOf(responseMap.get('externalId'));
                System.debug('Found externalId at root level: ' + externalId);
                return externalId;
            }
            
            if (responseMap.containsKey('contactId')) {
                String contactId = String.valueOf(responseMap.get('contactId'));
                System.debug('Found contactId at root level: ' + contactId);
                return contactId;
            }
            
            System.debug('No contact ID found in response at any level');
            return null;
            
        } catch (Exception e) {
            System.debug('EXCEPTION in parseContactIdFromResponse: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return null;
        }
    }
    
    //Sumanpreet
    /**
     * @description Create contact in PAID via API
     * @param con Contact record
     * @param paidCustomerId PAID Customer External ID from Account
     * @return PAIDCalloutResult
     */
    public static PAIDCalloutResult updateContactInPAID(
        Contact con,
        String paidCustomerId,
        String paidContactId
    ) {
        PAIDCalloutResult result = new PAIDCalloutResult();
        
        try {
            PAID_API_Configuration__mdt config =
                PAIDHelper.getAPIConfiguration('Update Contact');
            
            // Build payload (same as create)
            String requestBody = buildRequestPayload(con, paidCustomerId);
            result.requestPayload = requestBody;
            
            // Replace path params
            String endpoint = 'callout:' + config.Named_Credential__c
                + config.Endpoint_Path__c
                .replace('{orgId}', paidCustomerId)
                .replace('{contactId}', paidContactId);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            
            System.debug('Endpoint: ' + endpoint);
            
            req.setMethod(config.HTTP_Method__c);
            req.setHeader('Content-Type', config.Content_Type__c);
            req.setBody(requestBody);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            result.statusCode = res.getStatusCode();
            result.responsePayload = res.getBody();
            
            System.debug('=== PAID Contact API Response ===');
            System.debug('Response Status Code: ' + result.statusCode);
            System.debug('Response Body: ' + result.responsePayload);
            
            if (result.statusCode >= 200 && result.statusCode < 300) {
                result.isSuccess = true;
                result.paidContactId = paidContactId; // remains same
            } else {
                result.isSuccess = false;
                result.errorMessage =
                    'HTTP ' + result.statusCode + ': ' + res.getStatus();
            }
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = e.getMessage();
            result.responsePayload = e.getStackTraceString();
        }
        
        return result;
    }

}