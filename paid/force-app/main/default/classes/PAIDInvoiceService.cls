/**
 public class PAIDInvoiceService {
    /**
    * @description Service class for PAID Invoice API operations
    * Handles complex multi-object data structures including PricebookEntry, BlockPrice, and Cost
    * Supports multiple InvoiceAttributes: base Invoice + Cost records
    * Supports multi-currency for both base Invoice and Cost records
    * Fully metadata-driven with no hardcoded field names
    * Uses existing PAID_API_Configuration__mdt structure
    * @author Sumanpreet
    * @date 2026
    
    private static final String CREATE_OPERATION = 'Create';
    private static final String UPDATE_OPERATION = 'Update';
    private static final String Invoice_SYNC_INTEGRATION = 'Invoice_Sync';
    
  
    public static CalloutResult createInvoiceCalloutOnly(Id invoiceId) {
        CalloutResult result = new CalloutResult();
        result.invoiceId = invoiceId;
        
        System.debug('=== START CREATE Invoice CALLOUT ONLY ===');
        System.debug('Invoice ID: ' + invoiceId);
    
        try {
            // Get configuration
            PAID_API_Configuration__mdt config = getAPIConfiguration(CREATE_OPERATION);
            System.debug('config :'+config);
            if (config == null) {
                throw new PAIDInvoiceException('No active API configuration found for Invoice Creation');
            }
    
     		// Get invoice data with related records
            InvoiceData invoiceData = getInvoiceData(invoiceId);
            
            // Validate required fields
            validateRequiredFields(invoiceData.invoice, CREATE_OPERATION);
            
            // Build request payload
            result.requestBody = buildInvoicePayload(invoiceData, CREATE_OPERATION, config);
            
            System.debug('=== CREATE INVOICE PAYLOAD ===');
            System.debug('****** Request Body : '+result.requestBody);
            
            // Make HTTP callout - NO DML AFTER THIS POINT
            HttpResponse response = makeCallout(config, result.requestBody, invoiceId);
            
            result.statusCode = response.getStatusCode();
            result.responseBody = response.getBody();
            
            System.debug('****** result Status : '+result.statusCode);
                         
            result.success = (result.statusCode >= 200 && result.statusCode < 300);
            
            // Extract PAID Product ID from successful response
            if (result.success) {
                try {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(result.responseBody);
                    result.paidExternalId = extractInvoiceId(responseMap);
                } catch (Exception e) {
                    result.success = false;
                    result.errorMessage = 'Failed to extract Invoice ID from response: ' + e.getMessage();
                }
            } else {
                result.errorMessage = 'HTTP ' + result.statusCode + ': ' + result.responseBody;
            }
            
            System.debug('=== END CREATE INVOICE CALLOUT - ' + (result.success ? 'SUCCESS' : 'FAILURE') + ' ===');
            
        }
        catch (PAIDInvoiceException integEx) {
            result.success = false;
            result.errorMessage = 'Integration error: ' + integEx.getMessage();
            result.requestBody = result.requestBody != null ? result.requestBody : 'Payload not generated due to error';
            System.debug('PAIDInvoiceException: ' + result.errorMessage);
            
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
    * @description Retrieves API configuration from metadata
    * Updated to work with existing PAID_API_Configuration__mdt structure
    * @param operationType Create or Update
    * @return API configuration metadata record
   
    public static PAID_API_Configuration__mdt getAPIConfiguration(String operationType) {
        // Search for "Create Invoice" or "Update Invoice" in Operation_Type__c
        String searchOperation = operationType + ' Invoice';
        
        List<PAID_API_Configuration__mdt> configs = [
            SELECT Endpoint_Path__c, HTTP_Method__c, Named_Credential__c, 
            Content_Type__c
            FROM PAID_API_Configuration__mdt
            WHERE Operation_Type__c =: searchOperation
            AND Active__c = true
            LIMIT 1
        ];
        
        return configs.isEmpty() ? null : configs[0];
    }
    
    
    public static InvoiceData getInvoiceData(Id invoiceId) {
        InvoiceData data = new InvoiceData();
        
        // Get Invoice using PAIDHelper with base fields and mapped fields
        Set<Id> invoiceIds = new Set<Id>{invoiceId};
            
            List<blng__Invoice__c> invoices = (List<blng__Invoice__c>)PAIDHelper.queryRecordsWithMappings(
                'blng__Invoice__c',                          // objectName
                Invoice_SYNC_INTEGRATION,           // integrationType
                invoiceIds,                         // recordIds
                'PAID_Invoice_Field_Mapping__mdt',  // fieldMappingType
                null,                               // whereClause
                null,                               // bindVarName
                null,                               // bindVarValue
                null
            );
        
        if (invoices.isEmpty()) {
            throw new PAIDInvoiceException('Invoice not found: ' + invoiceId);
        }
        
        data.invoice = invoices[0];
        
        //build and execute invoiceItem query
        data.invoiceLines = [
            SELECT Id, blng__TaxAmount__c,
            blng__Quantity__c,
            blng__TotalAmount__c,
            blng__StartDate__c,
            blng__EndDate__c,
            blng__Notes__c
            FROM blng__InvoiceLine__c
            WHERE blng__Invoice__c = :invoiceId
        ];
        return data;
    }
    
   
    public static void validateRequiredFields(blng__Invoice__c invoice, String operationType) {
        List<PAID_Invoice_Field_Mapping__mdt> requiredMappings = [
            SELECT Salesforce_Field_API_Name__c, PAID_Field_Name__c, MasterLabel
            FROM PAID_Invoice_Field_Mapping__mdt
            WHERE Active__c = true
            AND Is_Required__c = true
            AND Salesforce_Object__c = 'blng__Invoice__c'
        ];
        
        List<String> missingFields = new List<String>();
        
        for (PAID_Invoice_Field_Mapping__mdt mapping : requiredMappings) {
            
            if (String.isNotBlank(mapping.Salesforce_Field_API_Name__c)) {
                try {
                    Object fieldValue = invoice.get(mapping.Salesforce_Field_API_Name__c);
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
                operationType + ' Invoice',               // operationKey
                'Invoice Id: ' + invoice.Id,              // request
                null,                                     // response
                false,                                    // success
                errorMessage,                             // errorMessage
                null,                                     // accountId
                null,                                     // contactId
                null,                                     // orderId
                invoice.Id,                               // invoiceId
                null                                      // orderNumber
            );
            insert log;
            throw new PAIDInvoiceException(errorMessage);
        }
    }
    
    
    /**
    * @description Builds JSON payload for PAID API
    * @param invoiceData Invoice and related data
    * @param operationType Create or Update
    * @param config API configuration
    * @return JSON string payload
   
    public static String buildInvoicePayload(InvoiceData invoiceData, String operationType,PAID_API_Configuration__mdt config) {
        Map<String, Object> payload = new Map<String, Object>();
        
        List<SObject> mappingRecords = PAIDHelper.getFieldMappings(
            'PAID_Invoice_Field_Mapping__mdt',
            'blng__Invoice__c'  
        );

        List<PAID_Invoice_Field_Mapping__mdt> mappings = new List<PAID_Invoice_Field_Mapping__mdt>();
        for (SObject record : mappingRecords) {
            PAID_Invoice_Field_Mapping__mdt mapping = (PAID_Invoice_Field_Mapping__mdt)record;
            
            // Filter by operation type
            //if (mapping.Operation_Type__c == operationType || mapping.Operation_Type__c == 'Both') {
                mappings.add(mapping);
            //}
        }
        // Process each field mapping
        blng__Invoice__c invoice = invoiceData.invoice;
        for (PAID_Invoice_Field_Mapping__mdt mapping : mappings) {
            Object fieldValue = invoice.get(mapping.Salesforce_Field_API_Name__c);
            
            // Apply default value if field is null
            if (fieldValue == null && String.isNotBlank(mapping.Default_Value__c)) {
                fieldValue = mapping.Default_Value__c;
            }
            
            // Skip null values (optional fields)
            if (fieldValue == null) {
                continue;
            }
            
            // Apply any transformations if needed
            if (String.isNotBlank(mapping.Transformation_Rule__c)) {
                fieldValue = PAIDHelper.applyTransformation(fieldValue, mapping.Transformation_Rule__c);
            }
        
            // Apply data type conversions if needed
            if (String.isNotBlank(mapping.Data_Type__c)) {
                fieldValue = PAIDHelper.convertDataType(fieldValue, mapping.Data_Type__c);
            }
            
            if (fieldValue instanceof Date) {
                Date d = (Date)fieldValue;
                Datetime dt = Datetime.newInstance(d.year(), d.month(), d.day(), 0, 0, 0);
                fieldValue = dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
            } else if (fieldValue instanceof Datetime) {
                fieldValue = ((Datetime)fieldValue).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
            }
            
            
            
            //payload.put('currency', 'USD'); 
            //payload.put('creationState','active');
            payload.put(mapping.PAID_Field_Name__c, fieldValue);
        }
        
        System.debug('Invoice payload before order lines: ' + payload);
        
        // Get field mappings for Order Product using PAIDHelper
        List<SObject> mappingILRecords = PAIDHelper.getFieldMappings(
            'PAID_Invoice_Field_Mapping__mdt',
            'blng__InvoiceLine__c'
        );
        
        // Cast to specific type for easier access
        List<PAID_Invoice_Field_Mapping__mdt> mappingsIL = new List<PAID_Invoice_Field_Mapping__mdt>();
        for (SObject record : mappingILRecords) {
            PAID_Invoice_Field_Mapping__mdt mapping = (PAID_Invoice_Field_Mapping__mdt)record;
            
            // Filter by operation type
            //if (mapping.Operation_Type__c == operationType || mapping.Operation_Type__c == 'Both') {
                mappingsIL.add(mapping);
            //}
        }
        
        List<Map<String, Object>> mappedRecords = new List<Map<String, Object>>();
        
        List<blng__InvoiceLine__c> invoiceLines = invoiceData.invoiceLines;
        system.debug('invoiceLines: ' + invoiceLines);
        System.debug('Processing ' + invoiceLines.size() + ' invoice Lines');
        
        for (blng__InvoiceLine__c il : invoiceLines) {
            Map<String, Object> payloadinvoiceLine = new Map<String, Object>();
            
            for (PAID_Invoice_Field_Mapping__mdt mapping : mappingsIL) {
                
                Object value = il.get(mapping.Salesforce_Field_API_Name__c);
                
                // Apply default value if field is null
                if (value == null && String.isNotBlank(mapping.Default_Value__c)) {
                    value = mapping.Default_Value__c;
                }
                
                // Skip null values (optional fields)
                if (value == null) {
                    continue;
                }
                
                // Apply any transformations if needed
                if (String.isNotBlank(mapping.Transformation_Rule__c)) {
                    value = PAIDHelper.applyTransformation(value, mapping.Transformation_Rule__c);
                }
				
                // Apply data type conversions if needed
                if (String.isNotBlank(mapping.Data_Type__c)) {
                    value = PAIDHelper.convertDataType(value, mapping.Data_Type__c);
                }
                
                if (value instanceof Date) {
                    Date d = (Date)value;
                    Datetime dt = Datetime.newInstance(d.year(), d.month(), d.day(), 0, 0, 0);
                    value = dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
                    
                    
                } else if (value instanceof Datetime) {
                    value = ((Datetime)value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
                }
                
                if (value != null) {
                    payloadinvoiceLine.put(mapping.PAID_Field_Name__c, value);
                }
            }
            mappedRecords.add(payloadinvoiceLine); 
        }    
        payload.put('lines', mappedRecords);
        
        return JSON.serialize(payload);
    }
    
    /**
    * @description Extracts and transforms field value
    * @param record Source record (Invoice)
    * @param mapping Field mapping configuration
    * @return Transformed field value
    
    public static Object getFieldValue(SObject record, PAID_Invoice_Field_Mapping__mdt mapping) {
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
    * @description Makes HTTP callout to PAID API
    * Updated to work with existing PAID_API_Configuration__mdt structure
    * @param config API configuration
    * @param requestBody JSON request body
    * @param invoiceExternalId PAID Invoice ID (for updates)
    * @return HTTP response
    
    public static HttpResponse makeCallout(PAID_API_Configuration__mdt config, String requestBody, String invoiceExternalId) {
        HttpRequest request = new HttpRequest();
        
        // Build endpoint using Named Credential and Endpoint Path
        String endpoint = 'callout:' + config.Named_Credential__c;
        String apiPath = config.Endpoint_Path__c;
        
        // Replace :invoiceId placeholder for update operations
        if (String.isNotBlank(invoiceExternalId)) {
            apiPath = apiPath.replace(':invoiceId', invoiceExternalId);
            // Also support {productId} format for backward compatibility
            apiPath = apiPath.replace('{invoiceId}', '');//invoiceExternalId);
            apiPath = apiPath.replace('{orgId}', '2d9e9a8d-81dc-4171-b469-c30bb620881c');
        }
        
        endpoint += apiPath;
        System.debug('endpoint TEST::'+endpoint);
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
    * @description Extracts Product ID from response
    
    public static String extractInvoiceId(Map<String, Object> responseMap) {
        if (responseMap.containsKey('id')) {
            return String.valueOf(responseMap.get('id'));
        }
        
        if (responseMap.containsKey('invoiceId')) {
            return String.valueOf(responseMap.get('invoiceId'));
        }
        
        if (responseMap.containsKey('data')) {
            Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
            if (dataMap != null && dataMap.containsKey('id')) {
                return String.valueOf(dataMap.get('id'));
            }
        }
        
        throw new PAIDInvoiceException('Unable to extract Invoice ID from response');
    }
    
    /**
    * @description Wrapper class to hold invoice and related data
    
    public class InvoiceData {
        public blng__Invoice__c invoice;
        public List<blng__InvoiceLine__c > invoiceLines;
        
        public InvoiceData() {
            this.invoiceLines = new List<blng__InvoiceLine__c >();
        }
        
    }

	/**
    * @description Wrapper class to hold callout results
    * Used to separate HTTP callouts from DML operations
   
    public class CalloutResult {
        public Id invoiceId;
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

    public class PAIDInvoiceException extends Exception {}
}
*/
public class PAIDInvoiceService{
    
}