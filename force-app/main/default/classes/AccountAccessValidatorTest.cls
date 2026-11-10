@IsTest
private class AccountAccessValidatorTest {

    @TestSetup
    static void setup() {
        Account accA = new Account(Name = 'Empresa A', CPF_ou_CNPJ__c = '11.111.111/0001-11');
        Account accB = new Account(Name = 'Empresa B', CPF_ou_CNPJ__c = '22.222.222/0001-22');
        Account accC = new Account(Name = 'Empresa C Nao Autorizada', CPF_ou_CNPJ__c = '33.333.333/0001-33');
        Account accD = new Account(Name = 'Empresa D Inativa', CPF_ou_CNPJ__c = '44.444.444/0001-44');
        insert new List<Account>{ accA, accB, accC, accD };

        Contact con = new Contact(
            FirstName = 'Portal',
            LastName = 'Test',
            AccountId = accA.Id,
            Email = 'portal.test.acv@example.com'
        );
        insert con;

        insert new AccountContactRelation(AccountId = accB.Id, ContactId = con.Id, IsActive = true);
        insert new AccountContactRelation(AccountId = accD.Id, ContactId = con.Id, IsActive = false);

        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Portal Cliente' LIMIT 1];
        insert new User(
            FirstName = 'Portal',
            LastName = 'Validator Test',
            Alias = 'pvaltest',
            Email = 'portal.test.acv@example.com',
            Username = 'portal.test.acv@' + DateTime.now().getTime() + '.example.com',
            CommunityNickname = 'pvaltest' + DateTime.now().getTime(),
            TimeZoneSidKey = 'America/Sao_Paulo',
            LocaleSidKey = 'pt_BR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'pt_BR',
            ProfileId = portalProfile.Id,
            ContactId = con.Id
        );
    }

    @IsTest
    static void testAuthorizedAccountsIncludePrimaryAndActiveRelated() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'pvaltest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A' LIMIT 1];
        Account accB = [SELECT Id FROM Account WHERE Name = 'Empresa B' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C Nao Autorizada' LIMIT 1];
        Account accD = [SELECT Id FROM Account WHERE Name = 'Empresa D Inativa' LIMIT 1];

        Set<Id> authorized;
        System.runAs(portalUser) {
            Test.startTest();
            authorized = AccountAccessValidator.getAuthorizedAccountIds();
            Test.stopTest();
        }

        System.assert(authorized.contains(accA.Id), 'Conta primaria do Contact deve estar autorizada');
        System.assert(authorized.contains(accB.Id), 'Conta relacionada ativa (ACR) deve estar autorizada');
        System.assert(!authorized.contains(accC.Id), 'Conta sem nenhuma relacao nao deve estar autorizada');
        System.assert(!authorized.contains(accD.Id), 'Conta com ACR inativo nao deve estar autorizada');
        System.assertEquals(2, authorized.size());
    }

    @IsTest
    static void testHasAccessTrueForRelatedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'pvaltest' LIMIT 1];
        Account accB = [SELECT Id FROM Account WHERE Name = 'Empresa B' LIMIT 1];

        Boolean result;
        System.runAs(portalUser) {
            result = AccountAccessValidator.hasAccess(accB.Id);
        }

        System.assert(result, 'Usuario deveria ter acesso a Empresa B via ACR ativo');
    }

    @IsTest
    static void testHasAccessFalseForUnrelatedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'pvaltest' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C Nao Autorizada' LIMIT 1];

        Boolean result;
        System.runAs(portalUser) {
            result = AccountAccessValidator.hasAccess(accC.Id);
        }

        System.assert(!result, 'Usuario nao deveria ter acesso a conta sem relacao alguma');
    }

    @IsTest
    static void testHasAccessFalseForInactiveRelation() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'pvaltest' LIMIT 1];
        Account accD = [SELECT Id FROM Account WHERE Name = 'Empresa D Inativa' LIMIT 1];

        Boolean result;
        System.runAs(portalUser) {
            result = AccountAccessValidator.hasAccess(accD.Id);
        }

        System.assert(!result, 'ACR inativo nao deve conceder acesso');
    }

    @IsTest
    static void testHasAccessFalseForNullId() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'pvaltest' LIMIT 1];

        Boolean result;
        System.runAs(portalUser) {
            result = AccountAccessValidator.hasAccess(null);
        }

        System.assert(!result, 'Id nulo nunca deve retornar acesso');
    }

    @IsTest
    static void testAssertHasAccessThrowsForUnauthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'pvaltest' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C Nao Autorizada' LIMIT 1];

        Boolean threw = false;
        System.runAs(portalUser) {
            try {
                AccountAccessValidator.assertHasAccess(accC.Id);
            } catch (AccountAccessValidator.AccountAccessException e) {
                threw = true;
            }
        }

        System.assert(threw, 'assertHasAccess deveria lancar excecao para conta nao autorizada');
    }

    @IsTest
    static void testNoAccountsAuthorizedForUserWithoutContact() {
        // Usuario de contexto do teste (admin), sem ContactId -> nenhuma conta autorizada.
        Set<Id> authorized = AccountAccessValidator.getAuthorizedAccountIds();
        System.assertEquals(0, authorized.size(), 'Usuario sem Contact nao deve ter nenhuma conta autorizada');
    }
}
