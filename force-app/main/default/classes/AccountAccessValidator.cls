/**
 * Ponto único de autorização de "qual Account o usuário corrente pode acessar".
 *
 * Fonte de verdade: Account primária do Contact (User.ContactId -> Contact.AccountId)
 * combinada com as Accounts relacionadas ativas via AccountContactRelation
 * (Related Accounts). Nunca confia em valores vindos do cliente (LWC/URL/Storage) —
 * o AccountId recebido é sempre validado contra este conjunto antes de qualquer uso.
 */
public with sharing class AccountAccessValidator {

    public class AccountAccessException extends Exception {}

    /**
     * Retorna os Ids de Account que o usuário corrente está autorizado a acessar.
     * Usado tanto para listar as contas do Account Switcher quanto para validar
     * uma seleção específica.
     */
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

    /**
     * Lança AccountAccessException quando o usuário corrente não está autorizado
     * a acessar a Account informada. Deve ser chamado por todo controller que
     * recebe um AccountId do frontend antes de usá-lo em qualquer query.
     */
    public static void assertHasAccess(Id accountId) {
        if (!hasAccess(accountId)) {
            throw new AccountAccessException('Acesso não autorizado a esta conta.');
        }
    }

    /**
     * Consulta o ContactId do próprio usuário autenticado. Não usa WITH USER_MODE
     * aqui de propósito: é uma leitura do próprio registro de User (não expõe dado
     * de terceiros) e depender de FLS neste ponto específico poderia quebrar o
     * Account Switcher para usuários legítimos por uma configuração de campo
     * desalinhada, sem nenhum ganho real de segurança. Público porque outras
     * classes do Seletor de Contas (ex.: AccountSwitcherController) também
     * precisam resolver o Contato do usuário corrente.
     */
    public static Id getRunningUserContactId() {
        List<User> users = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        return users.isEmpty() ? null : users[0].ContactId;
    }
}
