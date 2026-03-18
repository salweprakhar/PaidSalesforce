public class PAIDOrderItemService {
    private static final String CREATE_OPERATION = 'Create';
    private static final String UPDATE_OPERATION = 'Update';
    private static final String ORDER_ITEM_INTEGRATION_TYPE = 'Order_Item_Creation';
    
    /**
* @description Creates Order Items in PAID
* @param orderId Salesforce Order ID
* @param paidOrderId PAID Order ID
*/
    public static void createOrderItems(Id orderId, String paidOrderId, String contextType) {
        
        
        
        Order order = null;
        List<OrderItem> orderItems = new List<OrderItem>();
        
        try {
            // Get Order and OrderItems data
            order = getOrderData(orderId);
            orderItems = getOrderItemsData(orderId);
            
            if (orderItems.isEmpty()) {
                System.debug('No order items found for Order: ' + orderId);
                return;
            }

           /* PAID_API_Configuration__mdt config;
            String operationType;
            if(contextType == 'Update'){
                config = PAID_API_Configuration__mdt.getInstance('Update_OrderLine');
                if (config == null) {
                    throw new PAIDOrderItemException('No active API configuration found for Order Item Creation');
                }
                operationType = UPDATE_OPERATION;
            }else{
                config = PAID_API_Configuration__mdt.getInstance('Create_OrderLine');
                if (config == null) {
                    throw new PAIDOrderItemException('No active API configuration found for Order Item Creation');
                }
                operationType = CREATE_OPERATION;
            }*/
            PAID_API_Configuration__mdt config;
           String operationType;

           // Always use Update OrderLine configuration
        config = PAID_API_Configuration__mdt.getInstance('Update_OrderLine');

if (config == null) {
    throw new PAIDOrderItemException('No active API configuration found for Order Item Creation');
}

operationType = UPDATE_OPERATION;
            
            // Build request payload
            String requestBody = buildOrderItemsPayload(orderItems, operationType);
            
            System.debug('=== CREATE ORDER ITEMS PAYLOAD ===');
            System.debug(requestBody);
            
            // Make HTTP callout
            HttpResponse response = makeCallout(config, requestBody, paidOrderId);
            
            // IMMEDIATELY mark OrderItems as sent after callout is made
            List<OrderItem> orderItemsToUpdate = new List<OrderItem>();
            for (OrderItem oi : orderItems) {
                orderItemsToUpdate.add(new OrderItem(
                    Id = oi.Id,
                    Sent_To_PAID__c = true
                ));
            }
            update orderItemsToUpdate;
            
            if (response != null) {
                Integer statusCode = response.getStatusCode();
                String responseBody = response.getBody();
                System.debug('PAID Order Item API Response Status Code: ' + statusCode);
                System.debug('PAID Order Item API Response Body: ' + responseBody);
                processCreateResponse(orderId, order.OrderNumber, orderItems, response, requestBody);
            }
            
        } catch (Exception e) {
            Event_Log__c log = PAIDHelper.createEventLog(
                ORDER_ITEM_INTEGRATION_TYPE,
                null,
                null,
                false,
                e.getMessage() + '\n' + e.getStackTraceString(),
                null,
                null,
                orderId,
                null,
                order != null ? order.OrderNumber : null
            );
            insert log;
        }
    }
    
    /**
* @description Processes the API response for order item creation
*/
    private static void processCreateResponse(Id orderId, String orderNumber, List<OrderItem> orderItems, HttpResponse response, String requestBody) {
        Integer statusCode = response.getStatusCode();
        String responseBody = response.getBody();
        Boolean isSuccess = statusCode >= 200 && statusCode < 300;
        
        List<OrderItem> orderItemsToUpdate = new List<OrderItem>();
        Integer successCount = 0;
        Integer failureCount = 0;
        
        if (isSuccess) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Map<String, String> paidOrderItemIds = extractOrderItemIdsMap(responseMap);
            
            for (OrderItem oi : orderItems) {
                OrderItem itemToUpdate = new OrderItem(Id = oi.Id);
                
                String productKey = String.valueOf(oi.Product2Id);
                
                if (paidOrderItemIds.containsKey(productKey)) {
                    itemToUpdate.PAID_Order_Line_ID__c = paidOrderItemIds.get(productKey);
                    itemToUpdate.PAID_Order_Line_Creation_Status__c = 'Success';
                    successCount++;
                } else {
                    itemToUpdate.PAID_Order_Line_Creation_Status__c = 'Failure';
                    itemToUpdate.PAID_Order_Line_ID__c = null;
                    failureCount++;
                }
                
                orderItemsToUpdate.add(itemToUpdate);
            }
        } else {
            for (OrderItem oi : orderItems) {
                orderItemsToUpdate.add(new OrderItem(
                    Id = oi.Id,
                    PAID_Order_Line_Creation_Status__c = 'Failure',
                    PAID_Order_Line_ID__c = null
                ));
                failureCount++;
            }
        }
        OrderTriggerHandler.isOrderPAIDTriggered = true;
        update orderItemsToUpdate;
        
        // Update Order with overall status - Success only if ALL succeeded
        String overallStatus = (failureCount == 0) ? 'Success' : 'Failure';
        
        Order orderToUpdate = new Order(
            Id = orderId,
            PAID_Order_Line_Creation_Status__c = overallStatus
        );
        OrderTriggerHandler.isOrderPAIDTriggered = true;
        update orderToUpdate;                                          
        
        Event_Log__c log = PAIDHelper.createEventLog(
            'Create Order Items',
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
        
        //Activate order in PAID if all order lines were created successfully
        if (failureCount == 0) {
            System.debug('All order lines created successfully. Activating order in PAID...');
            
            // Get PAID Order ID from Order record
            List<Order> orders = [SELECT PAID_Order_ID__c FROM Order WHERE Id = :orderId LIMIT 1];
            if (!orders.isEmpty() && String.isNotBlank(orders[0].PAID_Order_ID__c)) {
                String paidOrderId = orders[0].PAID_Order_ID__c;
                // Enqueue activation in a separate queueable to avoid DML before callout error
                System.enqueueJob(new PAIDOrderActivationQueueable(orderId, paidOrderId));           
            }
        }
    }
    /**
* @description Extracts Order Item IDs from response
*/
    private static Map<String, String> extractOrderItemIdsMap(Map<String, Object> responseMap) {
        Map<String, String> orderItemIdsMap = new Map<String, String>();
        
        // Check for data.OrderLine structure (this is the actual response format)
        if (responseMap.containsKey('data')) {
            Map<String, Object> data = (Map<String, Object>) responseMap.get('data');
            
            if (data != null && data.containsKey('OrderLine')) {
                List<Object> orderLines = (List<Object>) data.get('OrderLine');
                if (orderLines != null) {
                    for (Object lineObj : orderLines) {
                        Map<String, Object> lineMap = (Map<String, Object>) lineObj;
                        
                        // Get the order line ID
                        String paidOrderLineId = lineMap.containsKey('id') ? 
                            String.valueOf(lineMap.get('id')) : null;
                        
                        if (String.isNotBlank(paidOrderLineId)) {
                            // Check for product.externalId (this is our Salesforce Product2Id)
                            if (lineMap.containsKey('product')) {
                                Map<String, Object> product = (Map<String, Object>) lineMap.get('product');
                                if (product != null && product.containsKey('externalId')) {
                                    String productExternalId = String.valueOf(product.get('externalId'));
                                    orderItemIdsMap.put(productExternalId, paidOrderLineId);
                                    System.debug('Mapped Product External ID: ' + productExternalId + ' to Order Line ID: ' + paidOrderLineId);
                                }
                            }
                            
                            // Also check for productId at line level as fallback
                            if (lineMap.containsKey('productId')) {
                                String productId = String.valueOf(lineMap.get('productId'));
                                orderItemIdsMap.put(productId, paidOrderLineId);
                                System.debug('Mapped Product ID: ' + productId + ' to Order Line ID: ' + paidOrderLineId);
                            }
                        }
                    }
                }
            }
        }
        
        System.debug('Final orderItemIdsMap: ' + orderItemIdsMap);
        return orderItemIdsMap;
    }
    
    /**
* @description Custom exception class
*/
    public class PAIDOrderItemException extends Exception {}
    
    /**
* @description Makes HTTP callout to PAID API
*/
    private static HttpResponse makeCallout(PAID_API_Configuration__mdt config, String requestBody, String paidOrderId) {
        HttpRequest request = new HttpRequest();
        
        // Build endpoint using Named Credential and Endpoint Path
        String endpoint = 'callout:' + config.Named_Credential__c;
        String apiPath = config.Endpoint_Path__c;
        
        // Replace :orderId placeholder with PAID Order ID
        if (String.isNotBlank(paidOrderId)) {
            apiPath = apiPath.replace(':orderId', paidOrderId);
            apiPath = apiPath.replace('{orderId}', paidOrderId);
        }
        
        endpoint += apiPath;
        
        request.setEndpoint(endpoint);
        request.setMethod(config.HTTP_Method__c);
        
        String contentType = String.isNotBlank(config.Content_Type__c) ? 
            config.Content_Type__c : 'application/json';
        request.setHeader('Content-Type', contentType);
        
        request.setBody(requestBody);
        
        Http http = new Http();
        return http.send(request);
    }
    
    /**
* @description Retrieves order with order number
*/
    private static Order getOrderData(Id orderId) {
        //List<Order> orders = [SELECT Id, OrderNumber FROM Order WHERE Id = :orderId LIMIT 1];
        Set<Id> orderIds = new Set<Id>{orderId};
            
            List<Order> orders = (List<Order>)PAIDHelper.queryRecords(
                'Order',
                ORDER_ITEM_INTEGRATION_TYPE,
                orderIds
            );
        
        if (orders.isEmpty()) {
            throw new PAIDOrderItemException('Order not found: ' + orderId);
        }
        
        return orders[0];
    }
    
    /**
* @description Retrieves order items with all mapped fields
*/
    private static List<OrderItem> getOrderItemsData(Id orderId) {
        return (List<OrderItem>)PAIDHelper.queryRecordsWithMappings(
            'OrderItem',                              // objectName
            ORDER_ITEM_INTEGRATION_TYPE,              // integrationType
            null,                                     // recordIds (not querying by Id)
            'PAID_Order_Item_Field_Mapping__mdt',    // fieldMappingType
            null,                                     // whereClause (using bind variable)
            'orderId',                                // bindVarName
            orderId,                                   // bindVarValue
            null
        );
    }
    
    /**
* @description Builds JSON payload for PAID API
*/
    private static String buildOrderItemsPayload(List<OrderItem> orderItems, String operationType) {
        List<Map<String, Object>> linesPayload = new List<Map<String, Object>>();
        
        List<SObject> mappingRecords = PAIDHelper.getFieldMappings(
            'PAID_Order_Item_Field_Mapping__mdt',
            'OrderItem'
        );
        
        // Cast to specific type
        List<PAID_Order_Item_Field_Mapping__mdt> mappings = new List<PAID_Order_Item_Field_Mapping__mdt>();
        for (SObject record : mappingRecords) {
            PAID_Order_Item_Field_Mapping__mdt mapping = (PAID_Order_Item_Field_Mapping__mdt)record;
            
            // Filter by operation type and active status
            if ((mapping.Operation_Type__c == operationType || mapping.Operation_Type__c == 'Both') 
                && mapping.Active__c) {
                    mappings.add(mapping);
                }
        }
        
        System.debug('OrderItem mappings: ' + mappings);
        Set<Id> orderIds = new Set<Id>();
        Map<Id, List<sObject>> listOfRecordsOfChild = new Map<Id, List<sObject>>();
        for(OrderItem oi : orderItems) {
            orderIds.add(oi.Id);
            orderIds.add(oi.Product2Id);
        }
        if(orderIds.size() > 0){
            for(SBQQ__OrderItemConsumptionSchedule__c consumptionSch : [SELECT Id, SBQQ__OrderItem__c, (SELECT Id,SBQQ__LowerBound__c, SBQQ__UpperBound__c, SBQQ__ProcessingOrder__c, SBQQ__PricingMethod__c, SBQQ__Price__c from SBQQ__OrderItemConsumptionRates__r) from SBQQ__OrderItemConsumptionSchedule__c WHERE SBQQ__OrderItem__c IN :orderIds]){
                if(!listOfRecordsOfChild.containsKey(consumptionSch.SBQQ__OrderItem__c)){
                    listOfRecordsOfChild.put(consumptionSch.SBQQ__OrderItem__c, new List<sObject>());
                }
                listOfRecordsOfChild.get(consumptionSch.SBQQ__OrderItem__c).add(consumptionSch);
            }

            for(SBQQ__BlockPrice__c blockPrice : [SELECT Id, SBQQ__OrderProduct__c, SBQQ__Product__c, SBQQ__LowerBound__c, SBQQ__UpperBound__c, SBQQ__Price__c, CurrencyIsoCode from SBQQ__BlockPrice__c WHERE SBQQ__OrderProduct__c IN :orderIds OR SBQQ__Product__c IN :orderIds]){
                Id priceVal = blockPrice.SBQQ__OrderProduct__c == null ? blockPrice.SBQQ__Product__c : blockPrice.SBQQ__OrderProduct__c;
                if(!listOfRecordsOfChild.containsKey(priceVal)){
                    listOfRecordsOfChild.put(priceVal, new List<sObject>());
                }
                listOfRecordsOfChild.get(priceVal).add(blockPrice);

            }
        }
        
        // Process each OrderItem
        OrderRequestWrapper wrapper = new OrderRequestWrapper();
        List<OrderRequestWrapper.OrderLine> newOrderline = new  List<OrderRequestWrapper.OrderLine>();
        for (OrderItem oi : orderItems) {
            Map<String, Object> linePayload = new Map<String, Object>();
            /*if(listOfRecordsOfChild.containsKey(oi.Id) && listOfRecordsOfChild.get(oi.Id).size() > 0){
            

        Map<String, Object> order = new Map<String, Object>{
            'orderId' => oi.PAID_Order_Id__c,
            'productId' => oi.PAID_ProductExternalID__c,
            'planProductId' => null,
            'description' => '',
            'endDate' => null,
            'name' => oi.Product2.Name,
            'startDate' => String.valueOf(oi.ServiceDate),
            'totalAmount' => 0,
            'billedAmountWithoutTax' => 0,
            'billedTax' => 0,
            'totalBilledAmount' => 0,
            'creationState' => 'active',
            'lineType' => 'STANDARD',
            'relatedToLineId' => null,
            'effectiveUntil' => null,
            'endedByAmendmentId' => null,
            'planProduct' => null
        };

        List<Object> orderLineAttributes = new List<Object>();
        

        // Loop schedules
        for (SBQQ__OrderItemConsumptionSchedule__c conssch : (List<SBQQ__OrderItemConsumptionSchedule__c>)listOfRecordsOfChild.get(oi.Id)) {

            List<Object> tiers = new List<Object>();
            Integer tierIndex = 0;

            // Loop rates
            for (SBQQ__OrderItemConsumptionRate__c consRate :
                 conssch.SBQQ__OrderItemConsumptionRates__r) {

                tiers.add(new Map<String, Object>{
                    'index' => tierIndex,
                    'number' => tierIndex,
                    'flatAmount' => null,
                    'lowerBound' => consRate.SBQQ__LowerBound__c,
                    'unitAmount' => consRate.SBQQ__Price__c,
                    'upperBound' => consRate.SBQQ__UpperBound__c
                });

                tierIndex++;
            }

            Map<String, Object> pricePoint = new Map<String, Object>{
                'tiers' => tiers,
                'currency' => 'USD',
                'unitPrice' => oi.UnitPrice,
                'minQuantity' => 0,
                'includedQuantity' => 0
            };

            Map<String, Object> pricing = new Map<String, Object>{
                'eventName' => 'unit_1',
                'chargeType' => 'usage',
                'pricePoint' => pricePoint,
                'signalType' => 'activity',
                'billingType' => 'Arrears',
                'pricingModel' => 'VolumePricing',
                'creditBenefits' => new List<Object>(),
                'isInfiniteTotal' => false,
                'billingFrequency' => 'Monthly',
                'overageUnitPrice' => null,
                'creditsCurrencyId' => null,
                'billingFrequencyCustomMonths' => 1
            };

            orderLineAttributes.add(new Map<String, Object>{
                'pricing' => pricing,
                'currency' => 'USD',
                'quantity' => 1,
                'status' => '',
                'billRunProcessingStatus' => 'pending_billing',
                'totalAmount' => 0,
                'creationState' => 'active'
            });
        }

        order.put('OrderLineAttribute', orderLineAttributes);
        //newOrderline.add(order);
        }*///else{
                OrderRequestWrapper.OrderLine line = new OrderRequestWrapper.OrderLine();
                line.orderId = oi.PAID_Order_Id__c;
                line.productId = oi.PAID_ProductExternalID__c;
                line.name = oi.Product2.Name;
                line.startDate = String.valueOf(oi.ServiceDate);
                line.creationState = 'active';
                line.lineType = 'STANDARD';

    // Product
                line.product = new OrderRequestWrapper.Product();
                line.product.id = oi.PAID_ProductExternalID__c;
                line.product.name = oi.Product2.Name;
                line.product.type = 'product';
                line.product.active = true;

    // Attribute
                line.OrderLineAttribute = new List<OrderRequestWrapper.OrderLineAttribute>();

                OrderRequestWrapper.OrderLineAttribute attr = new OrderRequestWrapper.OrderLineAttribute();
                if(oi.PAID_Order_Line_ID__c != null){
                    attr.orderLineId = oi.PAID_Order_Line_ID__c;
                }
                attr.currencyType = oi.CurrencyIsoCode;
                attr.quantity = oi.Quantity;
                attr.creationState = 'active';
                attr.unitPrice = 0;
                attr.discountType = 'percentage';
                attr.discountPercent = 1;
                attr.billingPeriods= 0;
                attr.discountedUnitPrice= 0;
                attr.periodAmountExclTax= 0;
                attr.contractAmountExclTax= 0;
                attr.contractEstimatedTax= 0;
                attr.contractAmountInclTax= 0;
                attr.billedAmountExclTax= 0;
                attr.billedTax = 0;
                attr.totalBilling = 0;

                attr.pricing = new OrderRequestWrapper.Pricing();
                if(oi.SBQQ__PricingMethod__c == 'List' && oi.SBQQ__SubscriptionPricing__c == 'Fixed Price'){
                    attr.pricing.chargeType = 'usage';
                    attr.pricing.taxable = false;
                    attr.pricing.pricingModel= 'VolumePricing';
                    attr.pricing.eventName = 'Unit';
                    attr.pricing.billingFrequency= oi.SBQQ__BillingFrequency__c;
                    attr.pricing.billingFrequencyCustomMonths =1;
                }else if(oi.SBQQ__SubscriptionPricing__c == 'Fixed Price'){
                    attr.pricing.chargeType = 'seatBased';
                    attr.pricing.taxable = false;
                    attr.pricing.pricingModel= 'PerUnit';
                    attr.pricing.billingType= oi.SBQQ__BillingType__c;
                    attr.pricing.billingFrequency= oi.SBQQ__BillingFrequency__c;
                }else if(oi.SBQQ__PricingMethod__c == 'Block'){
                    attr.pricing.chargeType = 'oneTime';
                    attr.pricing.taxable = false;
                    attr.pricing.pricingModel= 'GraduatedPricing';
                }else if(oi.SBQQ__PricingMethod__c == 'Cost'){
                    attr.pricing.chargeType = 'oneTime';
                    attr.pricing.taxable = false;
                    attr.pricing.pricingModel= 'GraduatedPricing';
                } 

                attr.pricing.pricePoint = new OrderRequestWrapper.PricePoint();
                attr.pricing.pricePoint.currencyType = oi.CurrencyIsoCode;
                attr.pricing.pricePoint.unitPrice = oi.UnitPrice == null ? 0 : (oi.UnitPrice * 100);
                attr.pricing.pricePoint.minQuantity = 1;
                attr.pricing.pricePoint.includedQuantity = 0;
                if(oi.SBQQ__PricingMethod__c == 'Block'){
                    List<OrderRequestWrapper.Tier> orderTierForBlock = new List<OrderRequestWrapper.Tier>();
                    Id priceVal = oi.Product2Id;
                    for(SBQQ__BlockPrice__c blockCheck : (List<SBQQ__BlockPrice__c>)listOfRecordsOfChild.get(priceVal)){
                        OrderRequestWrapper.Tier tier = new OrderRequestWrapper.Tier();
                        tier.lowerBound = blockCheck.SBQQ__LowerBound__c;
                        tier.upperBound = blockCheck.SBQQ__UpperBound__c;
                        tier.unitAmount = blockCheck.SBQQ__Price__c * 100;
                        orderTierForBlock.add(tier);
                        attr.pricing.pricePoint.tiers=orderTierForBlock;
                    }
                }else if(oi.SBQQ__PricingMethod__c == 'List'){
                    List<OrderRequestWrapper.Tier> orderTierForBlock = new List<OrderRequestWrapper.Tier>();
                    for (SBQQ__OrderItemConsumptionSchedule__c conssch : (List<SBQQ__OrderItemConsumptionSchedule__c>)listOfRecordsOfChild.get(oi.Id)) {
                        List<Object> tiers = new List<Object>();
                        Integer tierIndex = 0;
                        for (SBQQ__OrderItemConsumptionRate__c consRate :
                                conssch.SBQQ__OrderItemConsumptionRates__r) {

                            OrderRequestWrapper.Tier tier = new OrderRequestWrapper.Tier();
                            tier.lowerBound = consRate.SBQQ__LowerBound__c;
                            tier.upperBound = consRate.SBQQ__UpperBound__c;
                            tier.unitAmount = consRate.SBQQ__Price__c * 100;
                            orderTierForBlock.add(tier);
                    }
                    attr.pricing.pricePoint.tiers=orderTierForBlock;
                }
                }else{
                   attr.pricing.pricePoint.tiers= new List<OrderRequestWrapper.Tier>(); 
                }

                line.OrderLineAttribute.add(attr);
                newOrderline.add(line);
                System.debug('wrapper here '+ newOrderline);

                //linesPayload.add(linePayload);
            //}
            
            
        }
        
        System.debug('Final OrderItem payload: ' + JSON.serialize(newOrderline, true));
        String jsonOutput = JSON.serialize(newOrderline);
        jsonOutput = jsonOutput.replace('"currencyType"', '"currency"');
        jsonOutput = jsonOutput.replace('"discountAmount":null,', '');
        jsonOutput = jsonOutput.replace('"billingType":null,', '');
        jsonOutput = jsonOutput.replace('"eventName":null,', '');
        return jsonOutput;
    }
    
    /**
* @description Activates order in PAID after successful order line creation
* @param paidOrderId PAID Order ID
* @param orderId Salesforce Order ID
*/
    public static void activateOrderInPAID(String paidOrderId, Id orderId) {
        PAID_API_Configuration__mdt config = PAID_API_Configuration__mdt.getInstance('Activate_Order');
        if (config == null) {
            System.debug('No API configuration found for Order Activation');
            return;
        }
        
        try {
            // Build endpoint
            String endpoint = 'callout:' + config.Named_Credential__c;
            String apiPath = config.Endpoint_Path__c.replace('{orderId}', paidOrderId);
            endpoint += apiPath;
            
            // Make HTTP request
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod(config.HTTP_Method__c);
            request.setHeader('Content-Type', 'application/json');
            request.setTimeout(120000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            Integer statusCode = response.getStatusCode();
            String responseBody = response.getBody();
            
            System.debug('PAID Order Activation Response Status Code: ' + statusCode);
            System.debug('PAID Order Activation Response Body: ' + responseBody);
            
            // Update Order activation status only on success
            if (statusCode >= 200 && statusCode < 300) {
                Order orderToUpdate = new Order(
                    Id = orderId,
                    PAID_Order_Activation_Status__c = 'Active'
                );
                //fetchAndCreateInvoice(orderId, paidOrderId);
                update orderToUpdate;
                 // Fetch invoice after activation
    //System.enqueueJob(new FetchInvoiceQueueable(orderId, paidOrderId));
                
                // Log success
                Event_Log__c log = PAIDHelper.createEventLog(
                    'Activate Order',
                    'Order ID: ' + paidOrderId,
                    responseBody,
                    true,
                    null,
                    null,
                    null,
                    orderId,
                    null,
                    null
                );
                insert log;
                
                System.debug('Order activated successfully in PAID: ' + paidOrderId);
            } else {
                // Log failure but don't update status (remains Draft)
                Event_Log__c log = PAIDHelper.createEventLog(
                    'Activate Order',
                    'Order ID: ' + paidOrderId,
                    responseBody,
                    false,
                    'HTTP ' + statusCode + ': Failed to activate order',
                    null,
                    null,
                    orderId,
                    null,
                    null
                );
                insert log;
                
                System.debug('Failed to activate order in PAID: ' + statusCode);
            }
            
        } catch (Exception e) {
            System.debug('Error activating order in PAID: ' + e.getMessage());
            
            // Log exception but don't update status (remains Draft)
            Event_Log__c log = PAIDHelper.createEventLog(
                'Activate Order',
                'Order ID: ' + paidOrderId,
                null,
                false,
                e.getMessage() + '\n' + e.getStackTraceString(),
                null,
                null,
                orderId,
                null,
                null
            );
            insert log;
        }
        
    }
 /** FOR Invoice store in Order
// Fetch invoice using CustomerId 
public static void fetchInvoiceByCustomer(Id orderId) {

    Order ord = [
        SELECT Id, PAID_Order_Id__c, PAID_CustomerExternalID__c, PAID_Invoice_Id__c
        FROM Order
        WHERE Id = :orderId
        LIMIT 1
    ];

    String paidOrderId = ord.PAID_Order_Id__c;
    String customerId = ord.PAID_CustomerExternalID__c;

    if(String.isBlank(customerId)){
        System.debug('CustomerId missing on Order');
        return;
    }

    PAID_API_Configuration__mdt config =
        PAID_API_Configuration__mdt.getInstance('Get_Invoices');

    if(config == null){
        System.debug('Invoice API config missing');
        return;
    }

    try {

        String endpoint =
            'callout:' + config.Named_Credential__c +
            config.Endpoint_Path__c +
            '?customerId=' + customerId;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(config.HTTP_Method__c);
        req.setHeader('Content-Type','application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('Customer Invoice API Response: ' + res.getBody());

        if(res.getStatusCode() == 200){

            Map<String,Object> response =
                (Map<String,Object>)JSON.deserializeUntyped(res.getBody());

            List<Object> invoices =
                (List<Object>)response.get('data');

            String invoiceId;

            if(invoices != null){

                for(Object obj : invoices){

                    Map<String,Object> inv =
                        (Map<String,Object>)obj;

                    String orderIdFromInvoice =
                        (String)inv.get('orderId');

                    if(orderIdFromInvoice != null &&
                       orderIdFromInvoice.equalsIgnoreCase(paidOrderId)){

                        invoiceId = (String)inv.get('id');
                        break;
                    }
                }
            }

            if(invoiceId != null){

                ord.PAID_Invoice_Id__c = invoiceId;
                update ord;

                System.debug('Invoice stored: ' + invoiceId);

            } else {

                System.debug('No invoice found for this order');

            }

        }

    } catch(Exception e){

        System.debug('Invoice fetch error: ' + e.getMessage());

    }

}**/
    


    public static void deactivateOrderInPAID(String paidOrderId, Id orderId) {
        PAID_API_Configuration__mdt config = PAID_API_Configuration__mdt.getInstance('De_Activate_Order');
        if (config == null) {
            System.debug('No API configuration found for Order Activation');
            return;
        }
        
        try {
            // Build endpoint
            String endpoint = 'callout:' + config.Named_Credential__c;
            String apiPath = config.Endpoint_Path__c.replace('{orderId}', paidOrderId);
            endpoint += apiPath;
            
            // Make HTTP request
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod(config.HTTP_Method__c);
            request.setHeader('Content-Type', 'application/json');
            request.setTimeout(120000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            Integer statusCode = response.getStatusCode();
            String responseBody = response.getBody();
            
            System.debug('PAID Order Activation Response Status Code: ' + statusCode);
            System.debug('PAID Order Activation Response Body: ' + responseBody);
            
            // Update Order activation status only on success
            if (statusCode >= 200 && statusCode < 300) {
                Order orderToUpdate = new Order(
                    Id = orderId,
                    PAID_Order_Activation_Status__c = 'Draft'
                );
                //fetchAndCreateInvoice(orderId, paidOrderId);
                update orderToUpdate;
                
                // Log success
                Event_Log__c log = PAIDHelper.createEventLog(
                    'De-Activate Order',
                    'Order ID: ' + paidOrderId,
                    responseBody,
                    true,
                    null,
                    null,
                    null,
                    orderId,
                    null,
                    null
                );
                insert log;
                
                System.debug('Order De-activated successfully in PAID: ' + paidOrderId);
            } else {
                // Log failure but don't update status (remains Draft)
                Event_Log__c log = PAIDHelper.createEventLog(
                    'De-Activate Order',
                    'Order ID: ' + paidOrderId,
                    responseBody,
                    false,
                    'HTTP ' + statusCode + ': Failed to activate order',
                    null,
                    null,
                    orderId,
                    null,
                    null
                );
                insert log;
                
                System.debug('Failed to activate order in PAID: ' + statusCode);
            }
            
        } catch (Exception e) {
            System.debug('Error activating order in PAID: ' + e.getMessage());
            
            // Log exception but don't update status (remains Draft)
            Event_Log__c log = PAIDHelper.createEventLog(
                'Activate Order',
                'Order ID: ' + paidOrderId,
                null,
                false,
                e.getMessage() + '\n' + e.getStackTraceString(),
                null,
                null,
                orderId,
                null,
                null
            );
            insert log;
        }
    }
    
  /*  private static void fetchAndCreateInvoice(Id sfOrderId, String paidOrderId) {
        PAID_API_Configuration__mdt invConfig = PAID_API_Configuration__mdt.getInstance('Get_Invoices');
        Order sfOrder = [SELECT AccountId, BillToContactId, OrderNumber FROM Order WHERE Id = :sfOrderId LIMIT 1];
        
        // Callout to get Invoices
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + invConfig.Named_Credential__c + invConfig.Endpoint_Path__c);
        req.setMethod('GET');
        HttpResponse res = new Http().send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> invoiceList = (List<Object>) root.get('data');
            
            if (invoiceList != null && !invoiceList.isEmpty()) {
                Map<String, Object> invData = (Map<String, Object>) invoiceList[0];
                String externalInvoiceId = (String) invData.get('id');
                
                // IMPORTANT: Get lines BEFORE inserting the Invoice to avoid "Uncommitted Work"
                List<blng__InvoiceLine__c> linesToInsert = fetchInvoiceLinesCallout(externalInvoiceId);
                
                // NOW START DML
                blng__Invoice__c stdInv = new blng__Invoice__c(
                    blng__Account__c = sfOrder.AccountId,
                    blng__Order__c = sfOrderId,
                    blng__Notes__c = 'PAID Invoice ID: ' + externalInvoiceId,
                    blng__InvoiceStatus__c = 'Draft' // Keep Draft until lines are added
                );
                insert stdInv;
                
                for(blng__InvoiceLine__c line : linesToInsert) {
                    line.blng__Invoice__c = stdInv.Id;
                }
                insert linesToInsert;
                
                // Final Update to Post
                stdInv.blng__InvoiceStatus__c = 'Posted';
                update stdInv;
            }
        }
    }
    
    private static List<blng__InvoiceLine__c> fetchInvoiceLinesCallout(String paidInvoiceId) {
        List<blng__InvoiceLine__c> lines = new List<blng__InvoiceLine__c>();
        PAID_API_Configuration__mdt invConfig = PAID_API_Configuration__mdt.getInstance('Get_Invoices');
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + invConfig.Named_Credential__c + '/api/v2/invoices/' + paidInvoiceId + '/lines');
        req.setMethod('GET');
        HttpResponse res = new Http().send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> lineDataList = (List<Object>) root.get('data');
            for (Object obj : lineDataList) {
                Map<String, Object> lineMap = (Map<String, Object>) obj;
                lines.add(new blng__InvoiceLine__c(
                    blng__Quantity__c = (Decimal) lineMap.get('quantity'),
                    blng__UnitPrice__c = (Decimal) lineMap.get('totalPriceBeforeTax') / 100,
                    blng__TotalAmount__c = (Decimal) lineMap.get('totalPriceAfterTax') / 100,
                    blng__TaxAmount__c = (Decimal) lineMap.get('tax') / 100
                ));
            }
        }
        return lines;
    }
*/
}