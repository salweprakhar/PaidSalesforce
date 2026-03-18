/**
 * @description Service class for PAID Order Retry Integration
 * Handles customer, contact, and order creation synchronously
 */
public class PAIDOrderRetryIntegrationService {
    
    /**
     * @description Process order integration - creates customer, contact, and/or order based on what's missing
     * @param orderId Salesforce Order ID
     * @return Success message
     */
    public static String processOrderIntegration(String orderId) {
        // Query Order with all external IDs
        List<Order> orders = [
            SELECT Id, OrderNumber, AccountId, BillToContactId,
                   Account.PAID_CustomerExternalID__c,
                   BillToContact.PAID_ContactExternalID__c,
                   PAID_Order_ID__c,PAID_Order_Line_Creation_Status__c, PAID_Order_Activation_Status__c
            FROM Order 
            WHERE Id = :orderId 
            LIMIT 1
        ];
        
        if (orders.isEmpty()) {
            throw new PAIDOrderRetryIntegrationException('Order not found: ' + orderId);
        }
        
        Order ord = orders[0];
        
        // Check what's missing
        Boolean needsCustomer = String.isBlank(ord.Account.PAID_CustomerExternalID__c);
        Boolean needsContact = ord.BillToContactId != null && 
                               String.isBlank(ord.BillToContact.PAID_ContactExternalID__c);
        Boolean needsOrder = String.isBlank(ord.PAID_Order_ID__c);
        Boolean needsOrderItems = !needsOrder && ord.PAID_Order_Line_Creation_Status__c != 'Success';
        Boolean needsActivation = !needsOrder && ord.PAID_Order_Activation_Status__c != 'Success';
        
        System.debug('=== INTEGRATION CHECK ===');
        System.debug('Needs Customer: ' + needsCustomer);
        System.debug('Needs Contact: ' + needsContact);
        System.debug('Needs Order: ' + needsOrder);
        System.debug('Needs Order Items: ' + needsOrderItems);
        System.debug('Needs Activation: ' + needsActivation);
        
        // If nothing is needed, return
        if (!needsCustomer && !needsContact && !needsOrder && !needsOrderItems && !needsActivation) {
            return 'Customer, Contact, Order, Order Items, and Activation already complete in PAID. No action needed.';
        }
        
        // Execute integration
        return executeIntegrationSync(orderId, needsCustomer, needsContact, needsOrder, needsOrderItems, needsActivation);
    }
    
    /**
     * @description Execute synchronous integration
     */
    private static String executeIntegrationSync(Id orderId, Boolean needsCustomer, Boolean needsContact, Boolean needsOrder, Boolean needsOrderItems, Boolean needsActivation) {
        
        List<Order> ordersToUpdate = new List<Order>();
        List<Contact> contactsToUpdate = new List<Contact>();
        List<Event_Log__c> eventLogs = new List<Event_Log__c>();
        
        String paidCustomerId = null;
        String paidContactId = null;
        String resultMessage = '';
        Boolean customerUpdateSuccess = false; 
        Boolean contactUpdateSuccess = false;
        Boolean orderCreationSuccess = false;
        Boolean orderItemsCreationSuccess = false;
        
        // Query to check if contact exists on order
        List<Order> orderCheck = [SELECT BillToContactId FROM Order WHERE Id = :orderId];
        Boolean hasContact = orderCheck[0].BillToContactId != null;
        
        // STEP 1: CREATE CUSTOMER
        if (needsCustomer) {
            Map<String, Object> customerResult = createCustomer(orderId);
            
            if ((Boolean)customerResult.get('isSuccess')) {
                paidCustomerId = (String)customerResult.get('paidCustomerId');
                resultMessage += 'Customer created successfully. ';
                
                Order orderToUpdate = (Order)customerResult.get('orderToUpdate');
                Account accountToUpdate = (Account)customerResult.get('accountToUpdate');
                Event_Log__c eventLog = (Event_Log__c)customerResult.get('eventLog');
                
                // Update Account and Order immediately
                try {
                    update accountToUpdate;
                    update orderToUpdate;
                    insert eventLog;
                    
                    customerUpdateSuccess = true;
                    System.debug('Account and Order updated successfully with Customer External ID: ' + paidCustomerId);
                    
                } catch (Exception e) {
                    System.debug('Failed to update Account/Order: ' + e.getMessage());
                    resultMessage += 'Failed to update Account/Order in Salesforce. ';
                    throw new PAIDOrderRetryIntegrationException('Failed to update Account/Order: ' + e.getMessage());
                }
                
            } else {
                // Customer creation failed
                ordersToUpdate.add((Order)customerResult.get('orderToUpdate'));
                eventLogs.add((Event_Log__c)customerResult.get('eventLog'));
                
                if (!eventLogs.isEmpty()) insert eventLogs;
                if (!ordersToUpdate.isEmpty()) update ordersToUpdate;
                
                throw new PAIDOrderRetryIntegrationException((String)customerResult.get('errorMessage'));
            }
        } else {
            // Customer already exists - get the ID
            List<Order> orders = [SELECT Account.PAID_CustomerExternalID__c FROM Order WHERE Id = :orderId];
            paidCustomerId = orders[0].Account.PAID_CustomerExternalID__c;
            customerUpdateSuccess = true;
            System.debug('Customer already exists with ID: ' + paidCustomerId);
        }
        
        // STEP 2: CREATE CONTACT (only if customer update was successful)
        if (needsContact && customerUpdateSuccess && paidCustomerId != null) {
            System.debug('Proceeding with Contact creation - Account update was successful');
            
            Map<String, Object> contactResult = createContact(orderId, paidCustomerId);
            
            if ((Boolean)contactResult.get('isSuccess')) {
                paidContactId = (String)contactResult.get('paidContactId');
                resultMessage += 'Contact created successfully. ';
                Contact contactToUpdate = (Contact)contactResult.get('contactToUpdate');
                Event_Log__c eventLog = (Event_Log__c)contactResult.get('eventLog');
                
                // Update Contact immediately
                try {
                    update contactToUpdate;
                    insert eventLog;
                    contactUpdateSuccess = true;
                    System.debug('Contact updated successfully with Contact External ID: ' + paidContactId);
                } catch (Exception e) {
                    System.debug('Failed to update Contact: ' + e.getMessage());
                    resultMessage += 'Failed to update Contact in Salesforce. ';
                    contactUpdateSuccess = false;
                }
                
            } else {
                resultMessage += 'Contact creation failed. ';
                contactUpdateSuccess = false;
                Event_Log__c eventLog = (Event_Log__c)contactResult.get('eventLog');
                if (eventLog != null) {
                    insert eventLog;
                }
            }
        } else if (needsContact && !customerUpdateSuccess) {
            System.debug('Skipping Contact creation - Account update was not successful');
            resultMessage += 'Contact creation skipped (Account update failed). ';
            contactUpdateSuccess = false;
        } else if (!needsContact && hasContact) {
            // Contact already exists - check if it has external ID
            List<Order> orders = [SELECT BillToContact.PAID_ContactExternalID__c FROM Order WHERE Id = :orderId];
            paidContactId = orders[0].BillToContact.PAID_ContactExternalID__c;
            contactUpdateSuccess = String.isNotBlank(paidContactId);
            System.debug('Contact already exists with ID: ' + paidContactId);
        } else if (!hasContact) {
            // No contact on order - proceed without contact requirement
            contactUpdateSuccess = true;
            System.debug('No BillToContact on Order - proceeding without contact requirement');
        }
        
        // STEP 3: CREATE ORDER (only if prerequisites are met)
        if (needsOrder) {
            // Check prerequisites before creating order
            Boolean canCreateOrder = false;
            String skipReason = '';
            
            if (String.isBlank(paidCustomerId)) {
                skipReason = 'Customer External ID is required but not available. ';
            } else if (hasContact && String.isBlank(paidContactId)) {
                skipReason = 'Contact External ID is required but not available. ';
            } else if (hasContact && !contactUpdateSuccess) {
                skipReason = 'Contact creation/update was not successful. ';
            } else {
                canCreateOrder = true;
            }
            
            if (canCreateOrder) {
                System.debug('Prerequisites met - Creating Order'); 
                System.debug('Customer External ID: ' + paidCustomerId);
                System.debug('Contact External ID: ' + paidContactId);
                
                try {
                    //PAIDOrderService.createUpdateOrder(orderId);
                    PAIDOrdService.createUpdateOrder(orderId);
                    resultMessage += 'Order created successfully.';
                    orderCreationSuccess = true;
                } catch (Exception e) {
                    resultMessage += 'Order creation failed: ' + e.getMessage();
                    orderCreationSuccess = false;
                    throw new PAIDOrderRetryIntegrationException(resultMessage);
                }
            } else {
                System.debug('Skipping Order creation - Prerequisites not met: ' + skipReason);
                resultMessage += 'Order creation skipped. ' + skipReason;
                orderCreationSuccess = false;
                throw new PAIDOrderRetryIntegrationException('Cannot create order: ' + skipReason);
            }
        } else {
            resultMessage += 'Order already exists in PAID.';
            orderCreationSuccess = true;
        }
        // STEP 4: CREATE ORDER ITEMS (only if order exists and order items status is not Success)
        if (needsOrderItems && orderCreationSuccess) {
            System.debug('Prerequisites met - Creating Order Items');
            
            try {
                createOrderItems(orderId);
                resultMessage += 'Order Items created successfully. ';
                orderItemsCreationSuccess = true;
            } catch (Exception e) {
                resultMessage += 'Order Items creation failed: ' + e.getMessage() + ' ';
                orderItemsCreationSuccess = false;
                throw new PAIDOrderRetryIntegrationException(resultMessage);
            }
        } else if (needsOrderItems && !orderCreationSuccess) {
            System.debug('Skipping Order Items creation - Order creation was not successful');
            resultMessage += 'Order Items creation skipped (Order creation failed). ';
            orderItemsCreationSuccess = false;
        } else if (!needsOrderItems) {
            // Check status field to provide accurate message
            List<Order> orders = [SELECT PAID_Order_Line_Creation_Status__c FROM Order WHERE Id = :orderId];
            if (orders[0].PAID_Order_Line_Creation_Status__c == 'Success') {
                resultMessage += 'Order Items already exist in PAID. ';
            }
            orderItemsCreationSuccess = true;
        }
        
        // STEP 5: ACTIVATE ORDER (only if order items were created successfully)
        if (needsActivation && orderItemsCreationSuccess) {
            System.debug('Prerequisites met - Activating Order');
            
            try {
                activateOrder(orderId);
                resultMessage += 'Order activated successfully.';
            } catch (Exception e) {
                resultMessage += 'Order activation failed: ' + e.getMessage();
                throw new PAIDOrderRetryIntegrationException(resultMessage);
            }
        } else if (needsActivation && !orderItemsCreationSuccess) {
            System.debug('Skipping Order Activation - Order Items creation was not successful');
            resultMessage += 'Order activation skipped (Order Items creation failed).';
            throw new PAIDOrderRetryIntegrationException(resultMessage);
        } else if (!needsActivation) {
            // Check status field to provide accurate message
            List<Order> orders = [SELECT PAID_Order_Activation_Status__c FROM Order WHERE Id = :orderId];
            if (orders[0].PAID_Order_Activation_Status__c == 'Success') {
                resultMessage += 'Order already activated in PAID.';
            }
        }
        
        return resultMessage;
    }
    
    /**
     * @description Create customer in PAID
     */
    private static Map<String, Object> createCustomer(Id orderId) {
        Map<String, Object> result = new Map<String, Object>();
        
        Set<Id> orderIds = new Set<Id>{orderId};
        List<Order> orders = (List<Order>)PAIDHelper.queryRecords('Order', 'Customer_Creation', orderIds);
        Order ord = orders[0];
        
        Set<Id> accountIds = new Set<Id>{ord.AccountId};
        List<SObject> accountRecords = PAIDHelper.queryRecordsWithMappings(
            'Account', 'Customer_Creation', accountIds, 'PAID_Customer_Field_Mapping__mdt',null,null,null,null
        );
        Account acc = (Account)accountRecords[0];
        
        PAIDCustomerCreationService.ValidationResult validation = 
            PAIDCustomerCreationService.validateCustomerData(acc);
        
        if (!validation.isValid) {
            result.put('isSuccess', false);
            result.put('errorMessage', validation.errorMessage);
            result.put('orderToUpdate', new Order(Id = ord.Id, Sent_Customer_to_PAID__c = false, PAID_Customer_Creation_Status__c = 'Failure'));
            result.put('eventLog', PAIDHelper.createEventLog('Create Customer', null, null, false, validation.errorMessage, acc.Id, null, ord.Id, null,ord.OrderNumber));
            return result;
        }
        
        PAIDCustomerCreationService.PAIDCalloutResult calloutResult = 
            PAIDCustomerCreationService.createCustomerInPAID(acc);
        
        if (!calloutResult.isSuccess) {
            result.put('isSuccess', false);
            result.put('errorMessage', calloutResult.errorMessage);
            result.put('orderToUpdate', new Order(Id = ord.Id, Sent_Customer_to_PAID__c = true, PAID_Customer_Creation_Status__c = 'Failure'));
           result.put('eventLog', PAIDHelper.createEventLog('Create Customer', calloutResult.requestPayload, calloutResult.responsePayload, false, calloutResult.errorMessage, acc.Id, null, ord.Id,null, ord.OrderNumber));
            return result;
        }
        
        result.put('isSuccess', true);
        result.put('paidCustomerId', calloutResult.paidCustomerId);
        
        Order orderToUpdate = new Order(Id = ord.Id, Sent_Customer_to_PAID__c = true, PAID_Customer_Creation_Status__c = 'Success', PAID_CustomerExternalID__c = calloutResult.paidCustomerId);
        result.put('orderToUpdate', orderToUpdate);
        
        acc.PAID_CustomerExternalID__c = calloutResult.paidCustomerId;
        result.put('accountToUpdate', acc);
        
        result.put('eventLog', PAIDHelper.createEventLog('Create Customer', calloutResult.requestPayload, calloutResult.responsePayload, true, null, acc.Id, null, ord.Id,null, ord.OrderNumber));
        
        return result;
    }
    
    /**
     * @description Create contact in PAID
     */
    private static Map<String, Object> createContact(Id orderId, String paidCustomerId) {
        Map<String, Object> result = new Map<String, Object>();
        
        List<Order> orders = [SELECT Id, OrderNumber, AccountId, BillToContactId FROM Order WHERE Id = :orderId];
        Order ord = orders[0];
        
        Set<Id> contactIds = new Set<Id>{ord.BillToContactId};
        List<SObject> contactRecords = PAIDHelper.queryRecordsWithMappings(
            'Contact', 'Contact_Creation', contactIds, 'PAID_Contact_Field_Mapping__mdt',null,null,null,null
        );
        Contact con = (Contact)contactRecords[0];
        
        PAIDContactCreationService.ValidationResult validation = 
            PAIDContactCreationService.validateContactData(con);
        
        if (!validation.isValid) {
            result.put('isSuccess', false);
            result.put('eventLog', PAIDHelper.createEventLog('Create Contact', null, null, false, validation.errorMessage, ord.AccountId, con.Id, ord.Id,null, ord.OrderNumber));
            return result;
        }
        
        PAIDContactCreationService.PAIDCalloutResult calloutResult = 
            PAIDContactCreationService.createContactInPAID(con, paidCustomerId);
        
        if (calloutResult.isSuccess) {
            result.put('isSuccess', true);
            result.put('paidContactId', calloutResult.paidContactId);
            con.PAID_ContactExternalID__c = calloutResult.paidContactId;
            result.put('contactToUpdate', con);
           result.put('eventLog', PAIDHelper.createEventLog('Create Contact', calloutResult.requestPayload, calloutResult.responsePayload, true, null, ord.AccountId, con.Id, ord.Id,null, ord.OrderNumber));
        } else {
            result.put('isSuccess', false);
            result.put('eventLog', PAIDHelper.createEventLog('Create Contact', calloutResult.requestPayload, calloutResult.responsePayload, false, calloutResult.errorMessage, ord.AccountId, con.Id, ord.Id,null, ord.OrderNumber));
        }
        
        return result;
    }
    
    /**
     * @description Create order items in PAID
     */
    private static void createOrderItems(Id orderId) {
        System.debug('=== Creating Order Items ===');
        
        // Query order items that need to be created
        List<OrderItem> orderItems = [
            SELECT Id, PAID_Order_Line_ID__c 
            FROM OrderItem 
            WHERE OrderId = :orderId 
            AND PAID_Order_Line_ID__c = null
        ];
        
        if (orderItems.isEmpty()) {
            System.debug('No order items need to be created');
            return;
        }
        
        System.debug('Found ' + orderItems.size() + ' order items to create');
        
        // Process each order item
        for (OrderItem oi : orderItems) {
            try {
                PAIDOrderLineService.createUpdateOrder(oi.Id);
                System.debug('Order Item created successfully: ' + oi.Id);
            } catch (Exception e) {
                System.debug('Failed to create Order Item ' + oi.Id + ': ' + e.getMessage());
                throw new PAIDOrderRetryIntegrationException('Order Item creation failed for ' + oi.Id + ': ' + e.getMessage());
            }
        }
    }
    
   /**
 * @description Activate order in PAID
 */
private static void activateOrder(Id orderId) {
    System.debug('=== Activating Order ===');
    
    // Query to get PAID Order ID
    List<Order> orders = [
        SELECT Id, PAID_Order_ID__c 
        FROM Order 
        WHERE Id = :orderId 
        LIMIT 1
    ];
    
    if (orders.isEmpty()) {
        throw new PAIDOrderRetryIntegrationException('Order not found: ' + orderId);
    }
    
    String paidOrderId = orders[0].PAID_Order_ID__c;
    
    if (String.isBlank(paidOrderId)) {
        throw new PAIDOrderRetryIntegrationException('PAID Order ID is missing on Order: ' + orderId);
    }
    
    System.debug('PAID Order ID: ' + paidOrderId);
    
    try {
        PAIDOrderItemService.activateOrderInPAID(paidOrderId, orderId);
        System.debug('Order activated successfully: ' + orderId);
    } catch (Exception e) {
        System.debug('Failed to activate order ' + orderId + ': ' + e.getMessage());
        throw new PAIDOrderRetryIntegrationException('Order activation failed: ' + e.getMessage());
    }
}
    
    /**
     * @description Custom exception class
     */
    public class PAIDOrderRetryIntegrationException extends Exception {}
}