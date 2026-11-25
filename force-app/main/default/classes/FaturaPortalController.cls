// Controller do componente faturaLista (LWC) — lista as Faturas da conta
// ativa, modos: Todos, Em_Aberto, Atrasos, Pagos e Recentes.
//
// Data_Aprova_o__c, Link_Boleto__c e Forma_de_Pagamento__c não aparecem: o
// perfil do portal não tem FLS de leitura nesses campos.
//
// hasFaturasEmAtraso() existe só pro LWC decidir se mostra "Atrasos" no dropdown.
public with sharing class FaturaPortalController {

    public class FaturaItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String numero;
        @AuraEnabled public String status;
        @AuraEnabled public Date vencimento;
        @AuraEnabled public Decimal valor;
        @AuraEnabled public String contrato;

        public FaturaItem(Fatura__c f) {
            this.id = f.Id;
            this.numero = f.Name;
            this.status = f.Status__c;
            this.vencimento = f.Vencimento__c;
            this.valor = f.Valor_Fatura__c;
            this.contrato = f.contrato__r != null ? f.contrato__r.ContractNumber : null;
        }
    }

    // viewName: Todos (padrão), Em_Aberto, Atrasos, Pagos ou Recentes.
    @AuraEnabled
    public static List<FaturaItem> getFaturas(Id accountId, String viewName) {
        try {
            AccountAccessValidator.assertHasAccess(accountId);
        } catch (AccountAccessValidator.AccountAccessException e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }

        List<FaturaItem> items = new List<FaturaItem>();
        try {
            for (Fatura__c f : queryByView(accountId, viewName)) {
                items.add(new FaturaItem(f));
            }
        } catch (QueryException e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
        return items;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean hasFaturasEmAtraso(Id accountId) {
        try {
            AccountAccessValidator.assertHasAccess(accountId);
        } catch (AccountAccessValidator.AccountAccessException e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }

        List<Fatura__c> overdue = [
            SELECT Id
            FROM Fatura__c
            WHERE Conta__c = :accountId
            AND Status__c IN :ATRASADO_STATUSES
            WITH USER_MODE
            LIMIT 1
        ];
        return !overdue.isEmpty();
    }

    private static final List<String> ATRASADO_STATUSES = new List<String>{
        'Atrasado', 'Protestado l Atrasado', 'Protestado e Parcelado (Atrasado)'
    };
    private static final List<String> PAGO_STATUSES = new List<String>{
        'Recebido', 'Protestado | Recebido', 'Protestado e Parcelado (Quitado)'
    };

    private static List<Fatura__c> queryByView(Id accountId, String viewName) {
        String view = String.isBlank(viewName) ? 'Todos' : viewName;

        if (view == 'Recentes') {
            return [
                SELECT Id, Name, Status__c, Vencimento__c, Valor_Fatura__c, contrato__r.ContractNumber
                FROM Fatura__c
                WHERE Conta__c = :accountId
                AND LastViewedDate != null
                WITH USER_MODE
                ORDER BY LastViewedDate DESC
            ];
        }
        if (view == 'Em_Aberto') {
            return [
                SELECT Id, Name, Status__c, Vencimento__c, Valor_Fatura__c, contrato__r.ContractNumber
                FROM Fatura__c
                WHERE Conta__c = :accountId
                AND (Status__c NOT IN ('Rascunho', 'Cancelado', 'Recebido') OR CreatedDate >= LAST_N_MONTHS:3)
                WITH USER_MODE
                ORDER BY Vencimento__c DESC
            ];
        }
        if (view == 'Atrasos') {
            return [
                SELECT Id, Name, Status__c, Vencimento__c, Valor_Fatura__c, contrato__r.ContractNumber
                FROM Fatura__c
                WHERE Conta__c = :accountId
                AND Status__c IN :ATRASADO_STATUSES
                WITH USER_MODE
                ORDER BY Vencimento__c ASC
            ];
        }
        if (view == 'Pagos') {
            return [
                SELECT Id, Name, Status__c, Vencimento__c, Valor_Fatura__c, contrato__r.ContractNumber
                FROM Fatura__c
                WHERE Conta__c = :accountId
                AND Status__c IN :PAGO_STATUSES
                WITH USER_MODE
                ORDER BY Vencimento__c DESC
            ];
        }

        return [
            SELECT Id, Name, Status__c, Vencimento__c, Valor_Fatura__c, contrato__r.ContractNumber
            FROM Fatura__c
            WHERE Conta__c = :accountId
            WITH USER_MODE
            ORDER BY Vencimento__c DESC
        ];
    }
}