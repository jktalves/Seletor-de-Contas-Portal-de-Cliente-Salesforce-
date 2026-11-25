// Controller do componente accountSwitcher (LWC). AccountId do frontend nunca
// é usado direto numa query — sempre valida primeiro com AccountAccessValidator.
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

    // Retorna só as contas autorizadas — nunca todas as Accounts pra filtrar no frontend.
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

    // Revalida no servidor antes de confirmar a troca — frontend só publica o
    // novo contexto (LMS) depois que este método responder com sucesso.
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

    // Grava a conta ativa em Contact.Conta_Ativa__c pra flows (Conga, abertura de
    // chamado) lerem sem precisar chamar uma Action. É por Contato, não por aba —
    // duas abas abertas com contas diferentes, a última troca vence a outra.
    // Falha aqui não pode quebrar a troca de conta em si (LMS não depende disso).
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
