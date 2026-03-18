public with sharing class PaidAiIntegrationService {
public static void syncProduct(Id productId) {
        Product2 p = [
            SELECT Id, Name, Description, ProductCode, IsActive
            FROM Product2
            WHERE Id = :productId
        ];

        Map<String, Object> payload = new Map<String, Object>{
            'name' => p.Name,
            'description' => p.Description,
            'externalId' => p.Id,
            'type' => 'product',
            'active' => p.IsActive,
            'productCode' => p.ProductCode
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.agentpaid.io');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 300) {
            throw new CalloutException(res.getBody());
        }
    }
}