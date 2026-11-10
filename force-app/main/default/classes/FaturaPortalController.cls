/**
 * Controller do componente faturaLista (LWC) do portal — lista as Faturas da
 * Account atualmente selecionada no Account Switcher, com "Modos de
 * exibição de lista": Todos/Todas (padrão), Em_Aberto ("Em Aberto/Recentes"),
 * Atrasos ("Em Atraso"), Pagos ("Pagas") e Recentes ("Recente(s)") —
 * conferidos com screenshots reais da produção em 09/11/2026.
 *
 * Data_Aprova_o__c, Link_Boleto__c e Forma_de_Pagamento__c foram REMOVIDOS
 * da exibição: o perfil do portal não tem FLS de leitura nesses campos (nem
 * a list view nativa "Em_Aberto" os mostra de verdade pro cliente, mesmo
 * configurados nela) — confirmado consultando FieldPermissions na produção.
 *
 * contrato__c é Master-Detail pro objeto padrão Contract — esse tipo de
 * relacionamento não exige FieldPermissions pra aparecer (diferente de
 * Lookup/fórmula), por isso aparece normalmente na view "Recentes".
 *
 * "Atrasos" só deve aparecer no dropdown do LWC se a conta tiver alguma
 * fatura atrasada — hasFaturasEmAtraso() existe pra alimentar essa decisão.
 *
 * Segue o mesmo princípio do AccountSwitcherController: o AccountId recebido
 * do frontend é sempre validado por AccountAccessValidator antes de ser
 * usado em qualquer query.
 */
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

    /**
     * Retorna as Faturas da Account informada, no modo de exibição pedido,
     * somente se o usuário corrente estiver autorizado a acessar a Account
     * (AccountAccessValidator). Nunca retorna Faturas de outra Account.
     *
     * viewName: "Todos" (padrão), "Em_Aberto", "Atrasos", "Pagos" ou "Recentes".
     */
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

    /**
     * Indica se a Account tem alguma Fatura em atraso — usado pelo LWC pra
     * decidir se mostra a opção "Atrasos" no dropdown de modos de exibição.
     */
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

    // Status__c que representam fatura em atraso (inclui as variantes de
    // protesto). "Pago" inclui as variantes correspondentes de recebido/quitado.
    private static final List<String> ATRASADO_STATUSES = new List<String>{
        'Atrasado', 'Protestado l Atrasado', 'Protestado e Parcelado (Atrasado)'
    };
    private static final List<String> PAGO_STATUSES = new List<String>{
        'Recebido', 'Protestado | Recebido', 'Protestado e Parcelado (Quitado)'
    };

    private static List<Fatura__c> queryByView(Id accountId, String viewName) {
        String view = String.isBlank(viewName) ? 'Todos' : viewName;

        if (view == 'Recentes') {
            // Mesmo princípio das views "Recente(s)" de Equipamentos/Licenças.
            return [
                SELECT Id, Name, Status__c, Vencimento__c, Valor_Fatura__c, contrato__r.ContractNumber
                FROM Fatura__c
                WHERE Conta__c = :accountId
                AND LastViewedDate != null
                WITH USER_MODE
                ORDER BY LastViewedDate DESC
                LIMIT 200
            ];
        }
        if (view == 'Em_Aberto') {
            // Mesmo filtro da list view nativa "Em Aberto/Recentes" (produção).
            return [
                SELECT Id, Name, Status__c, Vencimento__c, Valor_Fatura__c, contrato__r.ContractNumber
                FROM Fatura__c
                WHERE Conta__c = :accountId
                AND (Status__c NOT IN ('Rascunho', 'Cancelado', 'Recebido') OR CreatedDate >= LAST_N_MONTHS:3)
                WITH USER_MODE
                ORDER BY Vencimento__c DESC
                LIMIT 200
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
                LIMIT 200
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
                LIMIT 200
            ];
        }

        // "Todos" ("Todas") (padrão) — sem filtro adicional.
        return [
            SELECT Id, Name, Status__c, Vencimento__c, Valor_Fatura__c, contrato__r.ContractNumber
            FROM Fatura__c
            WHERE Conta__c = :accountId
            WITH USER_MODE
            ORDER BY Vencimento__c DESC
            LIMIT 200
        ];
    }
}
