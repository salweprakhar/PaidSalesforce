/**
 * @description Handler class for Product trigger - manages PAID integration logic
 * Uses metadata-driven field monitoring for update triggers
 * @author Manusha T
 * @date 2025
 */
public class PAIDProductTriggerHandler {
    
    // Cache for monitored fields from metadata
    private static Set<String> monitoredFields;
    
    /**
     * @description Handles after insert events for Product creation in PAID
     * @param newProducts List of newly inserted products
     */
    public void handleAfterInsert(List<Product2> newProducts) {
        List<Id> productIdsToCreate = new List<Id>();
        
        for (Product2 product : newProducts) {
            
            if (product.IsActive && 
                String.isBlank(product.PAID_ProductExternalID__c) && 
                !product.Sent_Product_to_PAID__c) {
                
                productIdsToCreate.add(product.Id);
            }
        }
        
        if (!productIdsToCreate.isEmpty()) {
            System.enqueueJob(new PAIDProductCreateQueueable(productIdsToCreate));
        }
    }
    
    /**
     * @description Handles after update events for Product updates in PAID
     * @param newProducts List of updated products
     * @param oldProductMap Map of old product versions
     */
    public void handleAfterUpdate(List<Product2> newProducts, Map<Id, Product2> oldProductMap) {
        List<Id> productIdsToCreate = new List<Id>();
        List<Id> productIdsToUpdate = new List<Id>();
        
        for (Product2 newProduct : newProducts) {
            Product2 oldProduct = oldProductMap.get(newProduct.Id);
            
            // Check if product just became active and needs creation
            if (newProduct.IsActive && 
                !oldProduct.IsActive && 
                String.isBlank(newProduct.PAID_ProductExternalID__c) && 
                !newProduct.Sent_Product_to_PAID__c) {
                
                productIdsToCreate.add(newProduct.Id);
                continue;
            }
            
            // Check if product needs update in PAID
            if (shouldUpdateProduct(newProduct, oldProduct)) {
                productIdsToUpdate.add(newProduct.Id);
            }
        }
        
        // Enqueue creation jobs
        if (!productIdsToCreate.isEmpty()) {
            System.enqueueJob(new PAIDProductCreateQueueable(productIdsToCreate));
        }
        
        // Enqueue update jobs
        if (!productIdsToUpdate.isEmpty()) {
            System.enqueueJob(new PAIDProductUpdateQueueable(productIdsToUpdate));
        }
    }
    
    /**
     * @description Determines if a product update should be sent to PAID
     * Dynamically checks fields from metadata configuration
     * @param newProduct Updated product record
     * @param oldProduct Previous version of product
     * @return true if update should be sent to PAID
     */
    private Boolean shouldUpdateProduct(Product2 newProduct, Product2 oldProduct) {
        // Must be active and have PAID External ID
        if (!newProduct.IsActive || String.isBlank(newProduct.PAID_ProductExternalID__c)) {
            return false;
        }
        
        // Must not be already processing
        if (newProduct.Sent_UpdateProduct_to_PAID__c) {
            return false;
        }
        
        // Get monitored fields from metadata (cached)
        Set<String> fieldsToMonitor = getMonitoredFields();
        
        // Check if any monitored fields changed
        for (String fieldName : fieldsToMonitor) {
            try {
                Object newValue = newProduct.get(fieldName);
                Object oldValue = oldProduct.get(fieldName);
                
                if (newValue != oldValue) {
                    return true;
                }
            } catch (Exception e) {
                // Field doesn't exist or not accessible, skip it
                System.debug('Unable to compare field: ' + fieldName + ' - ' + e.getMessage());
                continue;
            }
        }
        
        return false;
    }
    
    /**
     * @description Retrieves monitored fields from metadata configuration
     * Fields are cached to avoid repeated SOQL queries
     * @return Set of field API names that should trigger updates
     */
    private static Set<String> getMonitoredFields() {  
        // Return cached value if available
        if (monitoredFields != null) {
            return monitoredFields;
        }
        
        monitoredFields = new Set<String>();
        
        // Query metadata for all active Product2 fields that support Update operation
        List<PAID_Product_Field_Mapping__mdt> mappings = [
            SELECT Salesforce_Field_API_Name__c
            FROM PAID_Product_Field_Mapping__mdt
            WHERE Active__c = true
            AND Salesforce_Object__c = 'Product2'
            AND (Operation_Type__c = 'Update' OR Operation_Type__c = 'Both')
            AND Salesforce_Field_API_Name__c != null
        ];
        
        // Build set of field names
        for (PAID_Product_Field_Mapping__mdt mapping : mappings) {
            if (String.isNotBlank(mapping.Salesforce_Field_API_Name__c)) {
                monitoredFields.add(mapping.Salesforce_Field_API_Name__c);
            }
        }
        
        // Always monitor these critical fields regardless of metadata
        monitoredFields.add('IsActive');
        
        return monitoredFields;
    }
}