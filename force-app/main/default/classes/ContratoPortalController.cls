/**
 * Controller do componente contratoLista (LWC) do portal — lista os
 * Contratos de Locação (Oportunidade_Aprovada__c) da Account atualmente
 * selecionada no Account Switcher, com "Modos de exibição de lista": Todos
 * (padrão), Ativos, Encerrados, Novos — mesmos filtros/colunas das list
 * views nativas equivalentes da produção, conferidas em 06/11/2026.
 *
 * Status__c é uma fórmula (não picklist) com valores possíveis "Ativo",
 * "Novo", "Encerrado", "Cancelado" ou "" (branco) — o rótulo de negócio
 * "Finalizado" (estágio da Oportunidade de origem) vira o valor "Encerrado"
 * aqui. IMPORTANTE: "Ativos" tem que ser Status__c = 'Ativo' exatamente
 * (igual a list view nativa) — usar "NOT IN ('Encerrado','Novo')" é
 * ERRADO, pois deixaria "Cancelado"/branco aparecerem como se fossem
 * ativos (bug corrigido em 06/11/2026).
 *
 * Mesmo princípio de segurança do FaturaPortalController.
 */
public with sharing class ContratoPortalController {

    public class ContratoItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String numero;
        @AuraEnabled public String status;
        @AuraEnabled public Date dataEntrega;
        @AuraEnabled public Date dataInicioContrato;
        @AuraEnabled public Date terminoContrato;
        @AuraEnabled public Id contatoId;
        @AuraEnabled public String contato;
        @AuraEnabled public Id enderecoId;
        @AuraEnabled public String endereco;
        @AuraEnabled public Decimal valor;

        public ContratoItem(Oportunidade_Aprovada__c o) {
            this.id = o.Id;
            this.numero = o.Name;
            this.status = o.Status__c;
            this.dataEntrega = o.data_entrega__c;
            this.dataInicioContrato = o.Data_de_Inicio_do_Contrato__c;
            this.terminoContrato = o.data_retirada__c;
            this.contatoId = o.Contato__c;
            this.contato = o.Contato__c != null ? o.Contato__r.Name : null;
            this.enderecoId = o.Endere_o__c;
            this.endereco = o.Endere_o__c != null ? o.Endere_o__r.Name : null;
            this.valor = o.Valor__c;
        }
    }

    /**
     * viewName: "Todos" (padrão), "Ativos", "Encerrados" ou "Novos".
     */
    @AuraEnabled
    public static List<ContratoItem> getContratos(Id accountId, String viewName) {
        try {
            AccountAccessValidator.assertHasAccess(accountId);
        } catch (AccountAccessValidator.AccountAccessException e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }

        List<ContratoItem> items = new List<ContratoItem>();
        try {
            for (Oportunidade_Aprovada__c o : queryByView(accountId, viewName)) {
                items.add(new ContratoItem(o));
            }
        } catch (QueryException e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
        return items;
    }

    private static List<Oportunidade_Aprovada__c> queryByView(Id accountId, String viewName) {
        String view = String.isBlank(viewName) ? 'Todos' : viewName;

        if (view == 'Ativos') {
            return [
                SELECT Id, Name, Status__c, data_entrega__c, Data_de_Inicio_do_Contrato__c, data_retirada__c,
                       Contato__c, Contato__r.Name, Endere_o__c, Endere_o__r.Name, Valor__c
                FROM Oportunidade_Aprovada__c
                WHERE Conta__c = :accountId
                AND Status__c = 'Ativo'
                ORDER BY data_entrega__c DESC NULLS LAST
                LIMIT 200
            ];
        }
        if (view == 'Encerrados') {
            return [
                SELECT Id, Name, Status__c, data_entrega__c, Data_de_Inicio_do_Contrato__c, data_retirada__c,
                       Contato__c, Contato__r.Name, Endere_o__c, Endere_o__r.Name, Valor__c
                FROM Oportunidade_Aprovada__c
                WHERE Conta__c = :accountId
                AND Status__c = 'Encerrado'
                ORDER BY data_entrega__c DESC NULLS LAST
                LIMIT 200
            ];
        }
        if (view == 'Novos') {
            return [
                SELECT Id, Name, Status__c, data_entrega__c, Data_de_Inicio_do_Contrato__c, data_retirada__c,
                       Contato__c, Contato__r.Name, Endere_o__c, Endere_o__r.Name, Valor__c
                FROM Oportunidade_Aprovada__c
                WHERE Conta__c = :accountId
                AND Status__c = 'Novo'
                ORDER BY data_entrega__c DESC NULLS LAST
                LIMIT 200
            ];
        }

        // "Todos" (padrão) — sem filtro adicional.
        return [
            SELECT Id, Name, Status__c, data_entrega__c, Data_de_Inicio_do_Contrato__c, data_retirada__c,
                   Contato__c, Contato__r.Name, Endere_o__c, Endere_o__r.Name, Valor__c
            FROM Oportunidade_Aprovada__c
            WHERE Conta__c = :accountId
            ORDER BY data_entrega__c DESC NULLS LAST
            LIMIT 200
        ];
    }
}
