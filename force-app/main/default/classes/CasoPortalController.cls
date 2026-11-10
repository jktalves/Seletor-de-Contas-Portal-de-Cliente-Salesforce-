/**
 * Controller do componente casoLista (LWC) do portal — lista os Chamados
 * (Case) da Account atualmente selecionada no Account Switcher, com os
 * "Modos de exibição de lista": Todos (padrão na aba), Em Andamento, Novo,
 * Encerrados, Entregas/Devoluções/Trocas/Outros (por Type).
 *
 * Status_para_o_Cliente__c (fórmula, "Campo criado para o portal de
 * clientes") traduz o Status interno bruto pra um rótulo apresentável ao
 * cliente (ex.: "Escalado"/"Verificar" -> "Em andamento") — replicado da
 * produção em 06/11/2026 (não existia nesta sandbox até então). É sempre
 * esse campo que deve aparecer na coluna "Status", nunca o Status bruto.
 *
 * Em_andamento/Novo usam o campo padrão Status (bruto) só pra FILTRAR —
 * exibição sempre via Status_para_o_Cliente__c. Entregas/Devoluções/
 * Trocas/Outros usam o campo Type pra filtrar.
 *
 * Mesmo princípio do FaturaPortalController: o AccountId recebido do
 * frontend é sempre validado por AccountAccessValidator antes de ser usado
 * em qualquer query. Não usa WITH USER_MODE: o objeto Case já é exibido
 * hoje pelo componente padrão do Experience Builder para este mesmo perfil
 * de portal, então FLS/CRUD/sharing já estão resolvidos pela configuração
 * existente da org — este controller só adiciona o filtro por Account.
 */
public with sharing class CasoPortalController {

    public class CasoItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String numero;
        @AuraEnabled public String assunto;
        @AuraEnabled public String nomeConta;
        @AuraEnabled public String tipo;
        @AuraEnabled public Id contatoId;
        @AuraEnabled public String contato;
        @AuraEnabled public Id usuarioId;
        @AuraEnabled public String usuario;
        @AuraEnabled public Id enderecoId;
        @AuraEnabled public String endereco;
        @AuraEnabled public String status;
        @AuraEnabled public String statusCliente;
        @AuraEnabled public Date dataProgramada;
        @AuraEnabled public DateTime dataAbertura;
        @AuraEnabled public DateTime dataFechamento;
        @AuraEnabled public Id contratoId;
        @AuraEnabled public String contrato;
        @AuraEnabled public String ultimoComentario;

        public CasoItem(Case c) {
            this.id = c.Id;
            this.numero = c.CaseNumber;
            this.assunto = c.Subject;
            this.nomeConta = c.Account != null ? c.Account.Name : null;
            this.tipo = c.Type;
            this.contatoId = c.ContactId;
            this.contato = c.Contact != null ? c.Contact.Name : null;
            this.usuarioId = c.Usu_rio__c;
            this.usuario = c.Usu_rio__r != null ? c.Usu_rio__r.Name : null;
            this.enderecoId = c.Endere_o__c;
            this.endereco = c.Endere_o__r != null ? c.Endere_o__r.Name : null;
            this.status = c.Status;
            this.statusCliente = c.Status_para_o_Cliente__c;
            this.dataProgramada = c.Data_Programada__c;
            this.dataAbertura = c.CreatedDate;
            this.dataFechamento = c.ClosedDate;
            this.contratoId = c.Oportunidade_Aprovada__c;
            this.contrato = c.Oportunidade_Aprovada__r != null ? c.Oportunidade_Aprovada__r.Name : null;
            this.ultimoComentario = c.ltimo_coment_rio__c;
        }
    }

    /**
     * viewName: "Todos" (padrão), "Em_andamento", "Novo", "Encerrados",
     * "Entregas", "Devolucoes", "Trocas" ou "Outros".
     */
    @AuraEnabled
    public static List<CasoItem> getCasos(Id accountId, String viewName) {
        try {
            AccountAccessValidator.assertHasAccess(accountId);
        } catch (AccountAccessValidator.AccountAccessException e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }

        List<CasoItem> items = new List<CasoItem>();
        try {
            for (Case c : queryByView(accountId, viewName)) {
                items.add(new CasoItem(c));
            }
        } catch (QueryException e) {
            // Não esconder o erro real como lista vazia — isso já mascarou um
            // problema real de FLS antes. Deixa o erro aparecer pro usuário
            // (e pro log) em vez de simular "nenhum registro".
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
        return items;
    }

    private static List<Case> queryByView(Id accountId, String viewName) {
        String view = String.isBlank(viewName) ? 'Todos' : viewName;

        if (view == 'Em_andamento') {
            // Tudo que não é Novo nem Encerrado.
            return [
                SELECT Id, CaseNumber, Subject, Status, Status_para_o_Cliente__c, Data_Programada__c, Type,
                       AccountId, Account.Name, CreatedDate, ClosedDate, ContactId, Contact.Name, Usu_rio__c, Usu_rio__r.Name,
                       Endere_o__c, Endere_o__r.Name, Oportunidade_Aprovada__c, Oportunidade_Aprovada__r.Name,
                       ltimo_coment_rio__c
                FROM Case
                WHERE AccountId = :accountId
                AND Status NOT IN ('Novo', 'Fechado', 'Cancelado')
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }
        if (view == 'Novo') {
            return [
                SELECT Id, CaseNumber, Subject, Status, Status_para_o_Cliente__c, Data_Programada__c, Type,
                       AccountId, Account.Name, CreatedDate, ClosedDate, ContactId, Contact.Name, Usu_rio__c, Usu_rio__r.Name,
                       Endere_o__c, Endere_o__r.Name, Oportunidade_Aprovada__c, Oportunidade_Aprovada__r.Name,
                       ltimo_coment_rio__c
                FROM Case
                WHERE AccountId = :accountId
                AND Status = 'Novo'
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }
        if (view == 'Encerrados') {
            // Mesmo filtro/colunas da list view nativa "Encerrados" (produção).
            return [
                SELECT Id, CaseNumber, Subject, Status, Status_para_o_Cliente__c, Data_Programada__c, Type,
                       AccountId, Account.Name, CreatedDate, ClosedDate, ContactId, Contact.Name, Usu_rio__c, Usu_rio__r.Name,
                       Endere_o__c, Endere_o__r.Name, Oportunidade_Aprovada__c, Oportunidade_Aprovada__r.Name,
                       ltimo_coment_rio__c
                FROM Case
                WHERE AccountId = :accountId
                AND Status IN ('Fechado', 'Cancelado')
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }
        if (view == 'Entregas') {
            // Mesmo filtro/colunas da list view nativa "Entregas" (produção).
            return [
                SELECT Id, CaseNumber, Subject, Status, Status_para_o_Cliente__c, Data_Programada__c, Type,
                       AccountId, Account.Name, CreatedDate, ClosedDate, ContactId, Contact.Name, Usu_rio__c, Usu_rio__r.Name,
                       Endere_o__c, Endere_o__r.Name, Oportunidade_Aprovada__c, Oportunidade_Aprovada__r.Name,
                       ltimo_coment_rio__c
                FROM Case
                WHERE AccountId = :accountId
                AND Type IN ('Entregas', 'Logística - Entrega')
                AND Status NOT IN ('Fechado', 'Cancelado')
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }
        if (view == 'Devolucoes') {
            // Mesmo filtro/colunas da list view nativa "Devoluções" (produção).
            return [
                SELECT Id, CaseNumber, Subject, Status, Status_para_o_Cliente__c, Data_Programada__c, Type,
                       AccountId, Account.Name, CreatedDate, ClosedDate, ContactId, Contact.Name, Usu_rio__c, Usu_rio__r.Name,
                       Endere_o__c, Endere_o__r.Name, Oportunidade_Aprovada__c, Oportunidade_Aprovada__r.Name,
                       ltimo_coment_rio__c
                FROM Case
                WHERE AccountId = :accountId
                AND Type IN ('Retiradas', 'Logística - Retiradas')
                AND Status NOT IN ('Fechado', 'Cancelado')
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }
        if (view == 'Trocas') {
            // Mesmo filtro/colunas da list view nativa "Trocas" (produção).
            return [
                SELECT Id, CaseNumber, Subject, Status, Status_para_o_Cliente__c, Data_Programada__c, Type,
                       AccountId, Account.Name, CreatedDate, ClosedDate, ContactId, Contact.Name, Usu_rio__c, Usu_rio__r.Name,
                       Endere_o__c, Endere_o__r.Name, Oportunidade_Aprovada__c, Oportunidade_Aprovada__r.Name,
                       ltimo_coment_rio__c
                FROM Case
                WHERE AccountId = :accountId
                AND Type = 'Trocas'
                AND Status NOT IN ('Fechado', 'Cancelado')
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }
        if (view == 'Outros') {
            // Mesmo filtro/colunas da list view nativa "Suporte" (produção):
            // tudo que não é Entregas/Devoluções/Trocas (por Type) e não está
            // fechado/cancelado.
            return [
                SELECT Id, CaseNumber, Subject, Status, Status_para_o_Cliente__c, Data_Programada__c, Type,
                       AccountId, Account.Name, CreatedDate, ClosedDate, ContactId, Contact.Name, Usu_rio__c, Usu_rio__r.Name,
                       Endere_o__c, Endere_o__r.Name, Oportunidade_Aprovada__c, Oportunidade_Aprovada__r.Name,
                       ltimo_coment_rio__c
                FROM Case
                WHERE AccountId = :accountId
                AND Type NOT IN ('Entregas', 'Logística - Entrega', 'Retiradas', 'Logística - Retiradas', 'Trocas')
                AND Status NOT IN ('Fechado', 'Cancelado')
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }
        // "Todos" (padrão) — mesmas colunas da list view nativa "Todos" (produção).
        return [
            SELECT Id, CaseNumber, Subject, Status, Status_para_o_Cliente__c, Data_Programada__c, Type,
                   AccountId, Account.Name, CreatedDate, ClosedDate, ContactId, Contact.Name, Usu_rio__c, Usu_rio__r.Name,
                   Endere_o__c, Endere_o__r.Name, Oportunidade_Aprovada__c, Oportunidade_Aprovada__r.Name,
                   ltimo_coment_rio__c
            FROM Case
            WHERE AccountId = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }
}
