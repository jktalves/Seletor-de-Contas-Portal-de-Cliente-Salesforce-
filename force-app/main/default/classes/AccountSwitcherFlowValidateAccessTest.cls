@IsTest
private class AccountSwitcherFlowValidateAccessTest {

    @TestSetup
    static void setup() {
        Account accA = new Account(Name = 'Empresa A FlowValidate', CPF_ou_CNPJ__c = '11.111.111/0001-11');
        Account accC = new Account(Name = 'Empresa C FlowValidate Nao Autorizada', CPF_ou_CNPJ__c = '33.333.333/0001-33');
        insert new List<Account>{ accA, accC };

        Contact con = new Contact(
            FirstName = 'FlowValidate',
            LastName = 'Test',
            AccountId = accA.Id,
            Email = 'portal.test.flowvalidate@example.com'
        );
        insert con;

        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Portal Cliente' LIMIT 1];
        insert new User(
            FirstName = 'FlowValidate',
            LastName = 'Portal Test',
            Alias = 'fvatest',
            Email = 'portal.test.flowvalidate@example.com',
            Username = 'portal.test.flowvalidate@' + DateTime.now().getTime() + '.example.com',
            CommunityNickname = 'fvatest' + DateTime.now().getTime(),
            TimeZoneSidKey = 'America/Sao_Paulo',
            LocaleSidKey = 'pt_BR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'pt_BR',
            ProfileId = portalProfile.Id,
            ContactId = con.Id
        );
    }

    @IsTest
    static void testExecuteTrueForAuthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'fvatest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A FlowValidate' LIMIT 1];

        AccountSwitcherFlowValidateAccess.Request req = new AccountSwitcherFlowValidateAccess.Request();
        req.accountId = accA.Id;

        List<AccountSwitcherFlowValidateAccess.Result> results;
        System.runAs(portalUser) {
            Test.startTest();
            results = AccountSwitcherFlowValidateAccess.execute(
                new List<AccountSwitcherFlowValidateAccess.Request>{ req }
            );
            Test.stopTest();
        }

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isAuthorized);
    }

    @IsTest
    static void testExecuteFalseForUnauthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'fvatest' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C FlowValidate Nao Autorizada' LIMIT 1];

        AccountSwitcherFlowValidateAccess.Request req = new AccountSwitcherFlowValidateAccess.Request();
        req.accountId = accC.Id;

        List<AccountSwitcherFlowValidateAccess.Result> results;
        System.runAs(portalUser) {
            results = AccountSwitcherFlowValidateAccess.execute(
                new List<AccountSwitcherFlowValidateAccess.Request>{ req }
            );
        }

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isAuthorized, 'Nao deveria autorizar conta de outra empresa (IDOR)');
    }

    @IsTest
    static void testExecuteBulkification() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'fvatest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A FlowValidate' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C FlowValidate Nao Autorizada' LIMIT 1];

        AccountSwitcherFlowValidateAccess.Request reqA = new AccountSwitcherFlowValidateAccess.Request();
        reqA.accountId = accA.Id;
        AccountSwitcherFlowValidateAccess.Request reqC = new AccountSwitcherFlowValidateAccess.Request();
        reqC.accountId = accC.Id;

        List<AccountSwitcherFlowValidateAccess.Result> results;
        System.runAs(portalUser) {
            results = AccountSwitcherFlowValidateAccess.execute(
                new List<AccountSwitcherFlowValidateAccess.Request>{ reqA, reqC }
            );
        }

        System.assertEquals(2, results.size(), 'Deveria retornar um resultado por request, na mesma ordem');
        System.assertEquals(true, results[0].isAuthorized);
        System.assertEquals(false, results[1].isAuthorized);
    }
}
