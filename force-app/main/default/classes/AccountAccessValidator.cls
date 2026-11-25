// Decide quais Accounts o usuário logado pode acessar: primária do Contact + AccountContactRelation ativas.
// Nunca usar um AccountId vindo do frontend sem passar por aqui.
public with sharing class AccountAccessValidator {

    public class AccountAccessException extends Exception {}

    // Mesmo conjunto usado pra listar as contas do seletor e pra validar uma seleção específica.
    public static Set<Id> getAuthorizedAccountIds() {
        Set<Id> accountIds = new Set<Id>();

        Id contactId = getRunningUserContactId();
        if (contactId == null) {
            return accountIds;
        }

        for (Contact c : [
            SELECT AccountId
            FROM Contact
            WHERE Id = :contactId
            WITH USER_MODE
        ]) {
            if (c.AccountId != null) {
                accountIds.add(c.AccountId);
            }
        }

        for (AccountContactRelation acr : [
            SELECT AccountId
            FROM AccountContactRelation
            WHERE ContactId = :contactId
            AND IsActive = true
            WITH USER_MODE
        ]) {
            accountIds.add(acr.AccountId);
        }

        return accountIds;
    }

    public static Boolean hasAccess(Id accountId) {
        if (accountId == null) {
            return false;
        }
        return getAuthorizedAccountIds().contains(accountId);
    }

    // Chamado pelos controllers antes de usar um AccountId recebido do frontend.
    public static void assertHasAccess(Id accountId) {
        if (!hasAccess(accountId)) {
            throw new AccountAccessException('Acesso não autorizado a esta conta.');
        }
    }

    // Sem WITH USER_MODE de propósito: é o próprio User lendo o próprio ContactId,
    // FLS aqui só quebraria o switcher à toa. Público pq outras classes também usam.
    public static Id getRunningUserContactId() {
        List<User> users = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        return users.isEmpty() ? null : users[0].ContactId;
    }
}
