/**
 * @description Queueable class to handle asynchronous customer creation in PAID
 * @author Manusha T
 */
public class PAIDCustomerCreationQueueable implements Queueable, Database.AllowsCallouts {
    
    private Set<Id> orderIds; 
    private Set<Id> accountIds;
    
    /** 
     * @description Constructor
     * @param orderIds Set of order IDs to process
     * @param accountIds Set of related account IDs 
     */
    public PAIDCustomerCreationQueueable(Set<Id> orderIds, Set<Id> accountIds) {
        this.orderIds = orderIds;
        this.accountIds = accountIds;
    }
    
    /**
     * @description Execute method for Queueable
     * @param context QueueableContext
     */
    public void execute(QueueableContext context) {
        
         List<Order> orders = (List<Order>)PAIDHelper.queryRecords(
            'Order',  
            'Customer_Creation', 
            orderIds
        );
        
        List<SObject> accountRecords = PAIDHelper.queryRecordsWithMappings(
            'Account', 
            'Customer_Creation', 
            accountIds,
            'PAID_Customer_Field_Mapping__mdt',
            null,null,null,null
        );
        
        // Convert to Account Map
        Map<Id, Account> accountMap = new Map<Id, Account>();
        for (SObject record : accountRecords) {
            accountMap.put(record.Id, (Account)record);
        }
        
        // Call service method to process customer creation
        PAIDCustomerCreationService.CustomerCreationResult result = 
            PAIDCustomerCreationService.processCustomerCreationBulk(orders, accountMap);
                
        // Perform DML operations
        if (!result.ordersToUpdate.isEmpty()) { 
            update result.ordersToUpdate;
        }
        
        if (!result.accountsToUpdate.isEmpty()) {
            update result.accountsToUpdate;
        }
        
        if (!result.eventLogs.isEmpty()) {
            insert result.eventLogs;
        }
        
        System.debug('orders:::'+orders);
        System.debug('successfullyCreatedAccounts:::'+result.successfullyCreatedAccounts);
        System.debug('accountMap:::'+accountMap);
        // Trigger Contact Creation integration for successful customers
        triggerContactCreation(orders, result.successfullyCreatedAccounts, accountMap);
    }
    
    /**
 * @description Trigger Contact Creation integration for eligible customers
 * Triggers for:
 * 1. Accounts successfully created in this transaction
 * 2. Accounts that already have PAID Customer External ID (created previously)
 * @param orders List of all processed orders
 * @param successfullyCreatedAccounts List of accounts successfully created in this transaction
 * @param allAccountsMap Map of all accounts processed (including those with existing PAID IDs)
 */
private void triggerContactCreation(List<Order> orders, 
                                   List<Account> successfullyCreatedAccounts,
                                   Map<Id, Account> allAccountsMap) {
    System.debug('Entered into contact creation');
    // Build map of AccountId to PAID_CustomerExternalID
    // Include BOTH newly created AND existing accounts with PAID IDs
    Map<Id, String> accountToPaidCustomerId = new Map<Id, String>();
    
    // Add newly created accounts
    for (Account acc : successfullyCreatedAccounts) {
        if (String.isNotBlank(acc.PAID_CustomerExternalID__c)) {
            accountToPaidCustomerId.put(acc.Id, acc.PAID_CustomerExternalID__c);
        }
    }
    
    // Add accounts that already had PAID Customer IDs
    for (Account acc : allAccountsMap.values()) {
        if (String.isNotBlank(acc.PAID_CustomerExternalID__c) && 
            !accountToPaidCustomerId.containsKey(acc.Id)) {
            accountToPaidCustomerId.put(acc.Id, acc.PAID_CustomerExternalID__c);
        }
    }
    
    if (accountToPaidCustomerId.isEmpty()) {
        System.debug('No accounts with PAID Customer IDs found for contact creation');
        return;
    }
    
    System.debug('Accounts eligible for contact creation: ' + accountToPaidCustomerId.keySet());
    
    // Collect BillToContact IDs from Orders for eligible accounts
    Set<Id> contactIds = new Set<Id>();
    Map<Id, Id> contactToOrderMap = new Map<Id, Id>(); // Contact ID -> Order ID
    
    for (Order ord : orders) {
        if (ord.BillToContactId != null && 
            accountToPaidCustomerId.containsKey(ord.AccountId)) {
            contactIds.add(ord.BillToContactId);
            contactToOrderMap.put(ord.BillToContactId, ord.Id);
        }
    }
    
    if (contactIds.isEmpty()) {
        System.debug('No BillToContacts found for contact creation');
        return;
    }
    
    // Query Contacts using helper
    List<SObject> contactRecords = PAIDHelper.queryRecordsWithMappings(
        'Contact', 
        'Contact_Creation', 
        contactIds,
        'PAID_Contact_Field_Mapping__mdt',null,null,null,null
    );
    System.debug('contactRecords::'+contactRecords);
    // Filter contacts that haven't been sent to PAID yet
    List<Contact> eligibleContacts = new List<Contact>();
    for (SObject record : contactRecords) {
        Contact con = (Contact)record;
        
        // Only process if:
        // 1. Contact doesn't have PAID External ID (PAID_ContactExternalID__c is blank)
        // 2. Contact's Account has PAID Customer ID
        if (String.isBlank(con.PAID_ContactExternalID__c) &&
            accountToPaidCustomerId.containsKey(con.AccountId)) {
            eligibleContacts.add(con);
        }
    }
    
    if (!eligibleContacts.isEmpty()) {
        System.debug('Triggering Contact Creation for ' + eligibleContacts.size() + ' contacts');
        
        // Enqueue Contact Creation job
        System.enqueueJob(new PAIDContactCreationQueueable(
            eligibleContacts, 
            accountToPaidCustomerId,
            contactToOrderMap
        ));
    } else {
        System.debug('No eligible contacts found for PAID creation');
    }
}
}