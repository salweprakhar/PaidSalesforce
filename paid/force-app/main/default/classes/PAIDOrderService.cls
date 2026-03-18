// this is combination order and order items logic
public class PAIDOrderService {
    private static final String CREATE_OPERATION = 'Create';
    private static final String UPDATE_OPERATION = 'Update';
    private static final String ORDER_INTEGRATION_TYPE = 'Order_Creation';
    
    /**
* 
* @description trigger PAID Order API using button
*/
    @AuraEnabled
    public static string triggerPAIDOrderAPI(string orderId){
        try {
        
            PAIDOrderRetryIntegrationService.processOrderIntegration(orderId);
            return 'Order created successfully';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    /**
* @description Creates an Order in PAID
* @param orderId Salesforce Order ID
*/
    public static void createUpdateOrder(Id orderId) {
        
        PAID_API_Configuration__mdt config = PAID_API_Configuration__mdt.getInstance('Create_Order');
        if (config == null) {
            throw new PAIDOrderException('No active API configuration found for Order Creation');
        }
        try{
        // Get Order data with related records
        OrderData orderData = getOrderData(orderId);
        
        // Validate required fields
        validateRequiredFields(orderData.order, CREATE_OPERATION);
        
        // Build request payload
        String requestBody = buildOrderPayload(orderData, CREATE_OPERATION);
        
        System.debug('=== CREATE ORDER PAYLOAD ===');
        System.debug(requestBody);
        
        // Make HTTP callout
        HttpResponse response = makeCallout(config, requestBody, null);
        
        
        // IMMEDIATELY mark as sent after callout is made
        Order OrderSentUpdate = new Order(
            Id = orderId,
            Sent_To_Paid__c = true
        );
        // Query OrderItems using PAIDHelper with custom WHERE clause
        List<OrderItem> orderItemsToUpdate = (List<OrderItem>)PAIDHelper.queryRecord(
            'OrderItem',
            ORDER_INTEGRATION_TYPE,
            null,
            'OrderId = :orderId',
            'orderId',
            orderId
        );
        
        for(OrderItem oi : orderItemsToUpdate){
            oi.Sent_To_PAID__c = true;
        }
        
        update OrderSentUpdate;
        update orderItemsToUpdate;
        
        if(response != null){
            Integer statusCode = response.getStatusCode();
            String responseBody = response.getBody();
            System.debug('PAID Order API Response Status Code: ' + statusCode);
            System.debug('PAID Order API Response Body: ' + responseBody);
            processCreateResponse(orderId,orderData.order.OrderNumber, response, requestBody);
            
        }
        }catch(Exception e){
            Event_Log__c log = PAIDHelper.createEventLog(
            ORDER_INTEGRATION_TYPE,
            null,
            null,
            false,
            e.getMessage(),
            null,
            null,
            orderId,
            null,
            null
        );
        insert log;
        }
    }
    /**
* @description Wrapper class to hold order and order Item data
*/
    public class OrderData {
        public Order order;
        public List<OrderItem> orderItems;
        
        public OrderData() {
            this.orderItems = new List<OrderItem>();
        }
    }
    
    private static void processCreateResponse(Id orderId, String orderNumber, HttpResponse response, String requestBody) {
        Integer statusCode = response.getStatusCode();
        String responseBody = response.getBody();
        Boolean isSuccess = statusCode >= 200 && statusCode < 300;
        
        Order orderToUpdate = new Order(Id = orderId);
        
        // Query OrderItems using PAIDHelper with custom WHERE clause
        List<OrderItem> orderItemsToUpdate = (List<OrderItem>)PAIDHelper.queryRecord(
            'OrderItem',
            ORDER_INTEGRATION_TYPE,
            null,
            'OrderId = :orderId',
            'orderId',
            orderId
        );
        
        if (isSuccess) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            String paidOrderId = extractOrderId(responseMap);
            Map<String, String> paidOrderItemIds = extractOrderItemIdsMap(responseMap);
            
            for(OrderItem oi : orderItemsToUpdate){
                if(paidOrderItemIds.containsKey(oi.PAID_ProductExternalID__c)){
                    oi.PAID_Order_Line_ID__c = paidOrderItemIds.get(oi.PAID_ProductExternalID__c);//Order Line Id from PAID
                    oi.PAID_Order_Line_Creation_Status__c = 'Success';
                }else{
                    oi.PAID_Order_Line_Creation_Status__c = 'Failure';
                    oi.PAID_Order_Line_ID__c = null;
                }
            }
            
            orderToUpdate.PAID_Order_ID__c = paidOrderId; //Order Id from PAID
            orderToUpdate.PAID_Order_Creation_Status__c = 'Success';
        } else {
            orderToUpdate.PAID_Order_Creation_Status__c = 'Failure';
            orderToUpdate.PAID_Order_ID__c = null;
            
            for(OrderItem oi : orderItemsToUpdate){
                oi.PAID_Order_Line_Creation_Status__c = 'Failure';
                oi.PAID_Order_Line_ID__c = null;
            }
        }
        
        update orderToUpdate;
        update orderItemsToUpdate;
        
        Event_Log__c log = PAIDHelper.createEventLog(
            'Create Order',
            requestBody,
            responseBody,
            isSuccess,
            isSuccess ? null : 'HTTP ' + statusCode + ': ' + responseBody,
            null,
            null,
            orderId,
 null,
            orderNumber
        );
        
        insert log;

        
    }
    /**
* @description Extracts Product ID from response
*/
    private static String extractOrderId(Map<String, Object> responseMap) {
        if (responseMap.containsKey('id')) {
            return String.valueOf(responseMap.get('id'));
        }
        
        if (responseMap.containsKey('data')) {
            Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
            if (dataMap != null && dataMap.containsKey('id')) {
                return String.valueOf(dataMap.get('id'));
            }
        }
        
        throw new PAIDOrderException('Unable to extract Order ID from response');
    }
    
    /**
* @description Custom exception class
*/
    public class PAIDOrderException extends Exception {}
    
    /**
* @description Extracts Order Item IDs from response
*/
    private static Map<String, String> extractOrderItemIdsMap(Map<String, Object> responseMap) {
        Map<String, String> orderItemIdsMap = new Map<String, String>();
        if (responseMap.containsKey('data')) {
            Map<String, Object> data = (Map<String, Object>) responseMap.get('data');
            
            if (data != null && data.containsKey('OrderLine')) {
                List<Object> orderLines = (List<Object>) data.get('OrderLine');
                if (orderLines != null) {
                    for (Object lineObj : orderLines) {
                        Map<String, Object> lineMap = (Map<String, Object>) lineObj;
                        if (lineMap.containsKey('id') && lineMap.containsKey('productId')) {
                            String paidOrderItemId = String.valueOf(lineMap.get('productId'));
                            String externalId = String.valueOf(lineMap.get('id'));
                            orderItemIdsMap.put(paidOrderItemId, externalId);
                        }
                    }
                }
            }
        }
        
        system.debug('orderItemIdsMap:'+orderItemIdsMap);
        return orderItemIdsMap;
    }
    
    
    /**
* @description Makes HTTP callout to PAID API
* Updated to work with existing PAID_API_Configuration__mdt structure
* @param config API configuration
* @param requestBody JSON request body
* @param orderExternalId PAID Order ID (for updates)
* @return HTTP response
*/
    private static HttpResponse makeCallout(PAID_API_Configuration__mdt config,String requestBody, String orderExternalId) {
        HttpRequest request = new HttpRequest();
        
        // Build endpoint using Named Credential and Endpoint Path
        String endpoint = 'callout:' + config.Named_Credential__c;
        String apiPath = config.Endpoint_Path__c;
        
        // Replace :orderId placeholder for update operations
        if (String.isNotBlank(orderExternalId)) {
            apiPath = apiPath.replace(':orderId', orderExternalId);
            // Also support {orderId} format for backward compatibility
            apiPath = apiPath.replace('{orderId}', orderExternalId);
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
* @description Validates required fields
* @param Order Order record to validate
* @param operationType Create or Update
*/
    private static void validateRequiredFields(Order order, String operationType) {
        List<String> missingFields = new List<String>();
        
        // Get field mappings using helper
        List<SObject> fieldMappings = PAIDHelper.getFieldMappings('PAID_Order_Field_Mapping__mdt','Order');
        
        for (SObject mappingObj : fieldMappings) {
            String sfObject = (String)mappingObj.get('Salesforce_Object__c');
            Boolean isRequired = (Boolean)mappingObj.get('Is_Required__c');
            
            if (isRequired && sfObject == 'Order') {
                String fieldApiName = (String)mappingObj.get('Salesforce_Field_API_Name__c');
                Object fieldValue = order.get(fieldApiName);
                
                if (fieldValue == null || String.valueOf(fieldValue).trim() == '') {
                    missingFields.add(fieldApiName);
                }
            }
        }        
        
        if (!missingFields.isEmpty()) {
            String errorMessage = 'Required fields missing: ' + String.join(missingFields, ', ');
            
            Event_Log__c log = PAIDHelper.createEventLog(
                operationType + ' Order',
                null,
                null,
                false,
                errorMessage,
                null,  // accountId
                null,  // contactId
                order.Id,
                null,
                order.OrderNumber
            );
            
            try {
                insert log;
            } catch (Exception logEx) {
                System.debug('Error creating event log: ' + logEx.getMessage());
            }
            
            throw new PAIDOrderException(errorMessage);
        }
    }
    
    /**
* @description Retrieves order with all related data
* @param orderId Product record Id
* @return ProductData wrapper with all related records
*/
    private static OrderData getOrderData(Id orderId) {
        OrderData data = new OrderData();
        Set<Id> orderIds = new Set<Id>{orderId};
            // Build and execute order query
            List<Order> orders = (List<Order>)PAIDHelper.queryRecords(
                'Order', 
                ORDER_INTEGRATION_TYPE, 
                orderIds
            );
        
        if (orders.isEmpty()) {
            throw new PAIDOrderException('Order not found: ' + orderId);
        }
        
        data.order = orders[0];
        
        //build and execute orderItem query
        data.orderItems = (List<OrderItem>)PAIDHelper.queryRecord(
            'OrderItem',
            ORDER_INTEGRATION_TYPE,
            null,
            'OrderId = :orderId',
            'orderId',
            orderId
        );
        return data;
    }

    /**
* @description Builds JSON payload for PAID API
* @param Order and OrderItem data
* @param operationType Create or Update
* @param config API configuration
* @return JSON string payload
*/
    private static String buildOrderPayload(OrderData orderData, String operationType) {
        Map<String, Object> payload = new Map<String, Object>();
        
        List<SObject> mappingRecords = PAIDHelper.getFieldMappings(
            'PAID_Order_Field_Mapping__mdt',
            'Order'
        );
        // Group mappings by parent object and source
        System.debug('mappingRecords:::'+mappingRecords);
        List<PAID_Order_Field_Mapping__mdt> mappings = new List<PAID_Order_Field_Mapping__mdt>();
        for (SObject record : mappingRecords) {
            PAID_Order_Field_Mapping__mdt mapping = (PAID_Order_Field_Mapping__mdt)record;
            
            // Filter by operation type
            if (mapping.Operation_Type__c == operationType || mapping.Operation_Type__c == 'Both') {
                mappings.add(mapping);
            }
        }
        System.debug('mappings::'+mappings);
        // Process each field mapping
        Order order = orderData.order;
        for (PAID_Order_Field_Mapping__mdt mapping : mappings) {
            System.debug('mapping:'+mapping);
            
            Object fieldValue = order.get(mapping.Salesforce_Field_API_Name__c);
            
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
            
            payload.put('currency', 'USD'); 
            payload.put('creationState','active');
            payload.put(mapping.PAID_Field_Name__c, fieldValue);
            system.debug('payload:'+payload);
            
        }
        
        System.debug('Order payload before order lines: ' + payload);
        
        // Get field mappings for Order Product using PAIDHelper
        List<SObject> mappingOPRecords = PAIDHelper.getFieldMappings(
            'PAID_Order_Field_Mapping__mdt',
            'Order Product'
        );
        // Cast to specific type for easier access
        List<PAID_Order_Field_Mapping__mdt> mappingsOP = new List<PAID_Order_Field_Mapping__mdt>();
        for (SObject record : mappingOPRecords) {
            PAID_Order_Field_Mapping__mdt mapping = (PAID_Order_Field_Mapping__mdt)record;
            
            // Filter by operation type
            if (mapping.Operation_Type__c == operationType || mapping.Operation_Type__c == 'Both') {
                mappingsOP.add(mapping);
            }
        }
        
        List<Map<String, Object>> mappedRecords = new List<Map<String, Object>>();
        
        List<OrderItem> orderItems = OrderData.orderItems;
        system.debug('orderItems: ' + orderItems);
        System.debug('Processing ' + orderItems.size() + ' order items');
        
        for (OrderItem oi : orderItems) {
            Map<String, Object> payloadOrderItem = new Map<String, Object>();
            
            for (PAID_Order_Field_Mapping__mdt mapping : mappingsOP) {
                
                Object value = oi.get(mapping.Salesforce_Field_API_Name__c);
                
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
                
                if (value != null) {
                    payloadOrderItem.put(mapping.PAID_Field_Name__c, value);
                }
            }
            
            mappedRecords.add(payloadOrderItem); 
        }    
        payload.put('lines', mappedRecords);
        system.debug('orderLines:' +mappedRecords);
        System.debug('Final payload: ' + JSON.serializePretty(payload));
        
        return JSON.serialize(payload);
    }  
}