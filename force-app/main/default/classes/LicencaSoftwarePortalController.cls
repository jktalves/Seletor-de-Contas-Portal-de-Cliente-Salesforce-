/**
 * Controller do componente licencaSoftwareLista (LWC) do portal — lista as
 * Licenças de Software da Account atualmente selecionada no Account
 * Switcher, com "Modos de exibição de lista": Tudo (padrão, sem filtro de
 * status) e Recente(s). Mesmo princípio de segurança do
 * FaturaPortalController.
 */
public with sharing class LicencaSoftwarePortalController {

    public class LicencaItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String usuario;
        @AuraEnabled public Id equipamentoId;
        @AuraEnabled public String equipamento;
        @AuraEnabled public String software;
        @AuraEnabled public String status;
        @AuraEnabled public Id contratoId;
        @AuraEnabled public String contrato;

        public LicencaItem(Licen_a_de_Software__c l) {
            this.id = l.Id;
            this.usuario = l.Name;
            this.equipamentoId = l.Equipamento__c;
            this.equipamento = l.Equipamento__r != null ? l.Equipamento__r.Name : null;
            this.software = l.Software__c;
            this.status = l.Status__c;
            this.contratoId = l.Oportunidade_Aprovada__c;
            this.contrato = l.Oportunidade_Aprovada__r != null ? l.Oportunidade_Aprovada__r.Name : null;
        }
    }

    /**
     * viewName: "Tudo" (padrão) ou "Recentes".
     */
    @AuraEnabled
    public static List<LicencaItem> getLicencas(Id accountId, String viewName) {
        try {
            AccountAccessValidator.assertHasAccess(accountId);
        } catch (AccountAccessValidator.AccountAccessException e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }

        List<LicencaItem> items = new List<LicencaItem>();
        try {
            for (Licen_a_de_Software__c l : queryByView(accountId, viewName)) {
                items.add(new LicencaItem(l));
            }
        } catch (QueryException e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
        return items;
    }

    private static List<Licen_a_de_Software__c> queryByView(Id accountId, String viewName) {
        String view = String.isBlank(viewName) ? 'Tudo' : viewName;

        if (view == 'Recentes') {
            return [
                SELECT Id, Name, Equipamento__c, Equipamento__r.Name, Software__c, Status__c,
                       Oportunidade_Aprovada__c, Oportunidade_Aprovada__r.Name
                FROM Licen_a_de_Software__c
                WHERE Conta__c = :accountId
                AND LastViewedDate != null
                ORDER BY LastViewedDate DESC
                LIMIT 200
            ];
        }

        // "Tudo" (padrão) — sem filtro de status.
        return [
            SELECT Id, Name, Equipamento__c, Equipamento__r.Name, Software__c, Status__c,
                   Oportunidade_Aprovada__c, Oportunidade_Aprovada__r.Name
            FROM Licen_a_de_Software__c
            WHERE Conta__c = :accountId
            ORDER BY Name ASC
            LIMIT 200
        ];
    }
}
