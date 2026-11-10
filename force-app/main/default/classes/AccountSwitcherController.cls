/**
 * Controller do componente accountSwitcher (LWC) do portal Experience Cloud.
 *
 * Regra de ouro: o AccountId recebido do frontend NUNCA é usado diretamente em
 * uma query. Ele é sempre validado primeiro por AccountAccessValidator, que é a
 * única fonte de verdade sobre quais Accounts o usuário corrente pode acessar.
 */
public with sharing class AccountSwitcherController {

    public class AccountOption {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String cnpj;

        public AccountOption(Account acc) {
            this.accountId = acc.Id;
            this.name = acc.Name;
            this.cnpj = acc.CPF_ou_CNPJ__c;
        }
    }

    /**
     * Retorna somente as Accounts que o usuário corrente está autorizado a
     * acessar (Account primária do Contact + relações ativas via
     * AccountContactRelation). Nunca retorna todas as Accounts para depois
     * filtrar no frontend.
     */
    @AuraEnabled(cacheable=true)
    public static List<AccountOption> getAvailableAccounts() {
        Set<Id> authorizedIds = AccountAccessValidator.getAuthorizedAccountIds();
        List<AccountOption> options = new List<AccountOption>();

        if (authorizedIds.isEmpty()) {
            return options;
        }

        for (Account acc : [
            SELECT Id, Name, CPF_ou_CNPJ__c
            FROM Account
            WHERE Id IN :authorizedIds
            WITH USER_MODE
            ORDER BY Name ASC
        ]) {
            options.add(new AccountOption(acc));
        }

        return options;
    }

    /**
     * Confirma a troca de conta ativa. Revalida no servidor se o accountId
     * recebido pertence ao conjunto de contas autorizadas do usuário corrente
     * antes de retornar qualquer dado — o frontend só deve publicar o novo
     * contexto (LMS) depois que este método responder com sucesso.
     */
    @AuraEnabled
    public static AccountOption selectAccount(Id accountId) {
        try {
            AccountAccessValidator.assertHasAccess(accountId);

            List<Account> accounts = [
                SELECT Id, Name, CPF_ou_CNPJ__c
                FROM Account
                WHERE Id = :accountId
                WITH USER_MODE
                LIMIT 1
            ];

            if (accounts.isEmpty()) {
                throw new AccountAccessValidator.AccountAccessException(
                    'Conta não encontrada ou não autorizada.'
                );
            }

            persistActiveAccountOnContact(accountId);

            return new AccountOption(accounts[0]);
        } catch (AccountAccessValidator.AccountAccessException e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * Grava a conta ativa em Contact.Conta_Ativa__c — pedido do Gustavo (CTO)
     * em 30/09/2026 pra Flows que já existem (ex.: formulário de abertura de
     * chamado no portal, exportação via Conga) poderem ler a conta ativa
     * direto do Contato, sem precisar chamar nenhuma Action.
     *
     * Limitação conhecida e aceita: o campo é por Contato, não por
     * aba/sessão — se a mesma pessoa tiver duas abas abertas com contas
     * diferentes, a última troca sobrescreve a outra.
     *
     * Se a gravação falhar por qualquer motivo (sharing, FLS, etc.), não deve
     * quebrar a troca de conta em si — a funcionalidade principal do
     * Account Switcher (LMS/sessionStorage) não depende deste campo.
     */
    private static void persistActiveAccountOnContact(Id accountId) {
        try {
            Id contactId = AccountAccessValidator.getRunningUserContactId();
            if (contactId == null) {
                return;
            }
            update new Contact(Id = contactId, Conta_Ativa__c = accountId);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Não foi possível gravar Conta_Ativa__c no Contato: ' + e.getMessage());
        }
    }
}
