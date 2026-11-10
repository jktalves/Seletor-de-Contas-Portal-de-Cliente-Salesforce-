/**
 * Controller do componente equipamentoLista (LWC) do portal — lista os
 * Equipamentos da Account atualmente selecionada no Account Switcher, com
 * "Modos de exibição de lista": Todos (padrão), Locado e Em Espera — os
 * últimos dois baseados em Status__c (valueSet global
 * Status_do_Equipamento, que não tem valores literais "Locado"/"Em Espera"
 * — mapeamento definido com o usuário em 17/09/2026). Mesmo princípio de
 * segurança do FaturaPortalController.
 */
public with sharing class EquipamentoPortalController {

    public class EquipamentoItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String numero;
        @AuraEnabled public String descricao;
        @AuraEnabled public Id contratoId;
        @AuraEnabled public String contrato;
        @AuraEnabled public Date dataEntrega;
        @AuraEnabled public Id usuarioId;
        @AuraEnabled public String usuario;
        @AuraEnabled public Decimal valorLocacao;
        @AuraEnabled public Decimal valorGarantia;

        public EquipamentoItem(Equipamento__c e) {
            this.id = e.Id;
            this.numero = e.Name;
            this.descricao = e.Descri_o_modelo_e_processador__c;
            this.contratoId = e.Contrato_Portal__c;
            this.contrato = e.Contrato_Portal__r != null ? e.Contrato_Portal__r.Name : null;
            this.dataEntrega = e.DataEntrega__c;
            this.usuarioId = e.Contato_Usu_rio__c;
            this.usuario = e.Contato_Usu_rio__r != null ? e.Contato_Usu_rio__r.Name : null;
            this.valorLocacao = e.Valor_de_loca_o_f_rmula__c;
            this.valorGarantia = e.Valor_do_Seguro__c;
        }
    }

    /**
     * viewName: "Todos" (padrão), "Locado" ou "Em_Espera".
     */
    @AuraEnabled
    public static List<EquipamentoItem> getEquipamentos(Id accountId, String viewName) {
        try {
            AccountAccessValidator.assertHasAccess(accountId);
        } catch (AccountAccessValidator.AccountAccessException e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }

        List<EquipamentoItem> items = new List<EquipamentoItem>();
        try {
            for (Equipamento__c e : queryByView(accountId, viewName)) {
                items.add(new EquipamentoItem(e));
            }
        } catch (QueryException ex) {
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());
            ahe.setMessage(ex.getMessage());
            throw ahe;
        }
        return items;
    }

    private static List<Equipamento__c> queryByView(Id accountId, String viewName) {
        String view = String.isBlank(viewName) ? 'Todos' : viewName;

        if (view == 'Recentes') {
            // Mesmo princípio das views "Recente(s)" de Faturas/Licenças.
            return [
                SELECT Id, Name, Descri_o_modelo_e_processador__c, Contrato_Portal__c, Contrato_Portal__r.Name,
                       DataEntrega__c, Contato_Usu_rio__c, Contato_Usu_rio__r.Name,
                       Valor_de_loca_o_f_rmula__c, Valor_do_Seguro__c
                FROM Equipamento__c
                WHERE Conta_Registro__c = :accountId
                AND LastViewedDate != null
                ORDER BY LastViewedDate DESC
                LIMIT 200
            ];
        }
        if (view == 'Locado') {
            return [
                SELECT Id, Name, Descri_o_modelo_e_processador__c, Contrato_Portal__c, Contrato_Portal__r.Name,
                       DataEntrega__c, Contato_Usu_rio__c, Contato_Usu_rio__r.Name,
                       Valor_de_loca_o_f_rmula__c, Valor_do_Seguro__c
                FROM Equipamento__c
                WHERE Conta_Registro__c = :accountId
                AND Status__c IN ('OK', 'Funcional', 'Estoque RJ / Em Locação', 'Estoque SP / Em Locação')
                ORDER BY Name ASC
                LIMIT 200
            ];
        }
        if (view == 'Em_Espera') {
            return [
                SELECT Id, Name, Descri_o_modelo_e_processador__c, Contrato_Portal__c, Contrato_Portal__r.Name,
                       DataEntrega__c, Contato_Usu_rio__c, Contato_Usu_rio__r.Name,
                       Valor_de_loca_o_f_rmula__c, Valor_do_Seguro__c
                FROM Equipamento__c
                WHERE Conta_Registro__c = :accountId
                AND Status__c IN ('A Preparar', 'Reservado', 'Pre-cadastro', 'Revisão', 'Manutenção', 'Manutenção - Aguardando peças')
                ORDER BY Name ASC
                LIMIT 200
            ];
        }

        // "Todos" — mesmo princípio da list view nativa "Equipamentos_Alugados"
        // (ligada a esta mesma aba em produção): não mostra equipamento
        // Vendido/Extraviado/etc. União dos status de "Locado" + "Em_Espera"
        // pra nunca ficar menor que a soma dos outros dois modos (bug
        // corrigido em 06/11/2026 — antes não tinha filtro nenhum).
        return [
            SELECT Id, Name, Descri_o_modelo_e_processador__c, Contrato_Portal__c, Contrato_Portal__r.Name,
                   DataEntrega__c, Contato_Usu_rio__c, Contato_Usu_rio__r.Name,
                   Valor_de_loca_o_f_rmula__c, Valor_do_Seguro__c
            FROM Equipamento__c
            WHERE Conta_Registro__c = :accountId
            AND Status__c IN ('OK', 'Funcional', 'Estoque RJ / Em Locação', 'Estoque SP / Em Locação',
                               'A Preparar', 'Reservado', 'Pre-cadastro', 'Revisão', 'Manutenção',
                               'Manutenção - Aguardando peças')
            ORDER BY Name ASC
            LIMIT 200
        ];
    }
}
