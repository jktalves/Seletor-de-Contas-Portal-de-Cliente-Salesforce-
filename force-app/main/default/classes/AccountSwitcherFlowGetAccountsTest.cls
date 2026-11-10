@IsTest
private class AccountSwitcherFlowGetAccountsTest {

    @TestSetup
    static void setup() {
        Account accA = new Account(Name = 'Empresa A Flow', CPF_ou_CNPJ__c = '11.111.111/0001-11');
        Account accC = new Account(Name = 'Empresa C Flow Nao Autorizada', CPF_ou_CNPJ__c = '33.333.333/0001-33');
        insert new List<Account>{ accA, accC };

        Contact con = new Contact(
            FirstName = 'FlowGetAccounts',
            LastName = 'Test',
            AccountId = accA.Id,
            Email = 'portal.test.flowgetaccounts@example.com'
        );
        insert con;

        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Portal Cliente' LIMIT 1];
        insert new User(
            FirstName = 'FlowGetAccounts',
            LastName = 'Portal Test',
            Alias = 'fgatest',
            Email = 'portal.test.flowgetaccounts@example.com',
            Username = 'portal.test.flowgetaccounts@' + DateTime.now().getTime() + '.example.com',
            CommunityNickname = 'fgatest' + DateTime.now().getTime(),
            TimeZoneSidKey = 'America/Sao_Paulo',
            LocaleSidKey = 'pt_BR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'pt_BR',
            ProfileId = portalProfile.Id,
            ContactId = con.Id
        );
    }

    @IsTest
    static void testExecuteReturnsOnlyAuthorizedAccounts() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'fgatest' LIMIT 1];

        List<AccountSwitcherFlowGetAccounts.Result> results;
        System.runAs(portalUser) {
            Test.startTest();
            results = AccountSwitcherFlowGetAccounts.execute(
                new List<AccountSwitcherFlowGetAccounts.Request>{ new AccountSwitcherFlowGetAccounts.Request() }
            );
            Test.stopTest();
        }

        System.assertEquals(1, results.size(), 'Deveria retornar um resultado por request (bulkificacao)');
        List<AccountSwitcherFlowGetAccounts.AccountOption> accounts = results[0].accounts;

        Set<String> names = new Set<String>();
        for (AccountSwitcherFlowGetAccounts.AccountOption a : accounts) {
            names.add(a.name);
        }

        System.assertEquals(1, accounts.size(), 'Deveria retornar apenas a conta autorizada');
        System.assert(names.contains('Empresa A Flow'));
        System.assert(!names.contains('Empresa C Flow Nao Autorizada'));
    }

    @IsTest
    static void testExecuteBulkification() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'fgatest' LIMIT 1];

        List<AccountSwitcherFlowGetAccounts.Result> results;
        System.runAs(portalUser) {
            results = AccountSwitcherFlowGetAccounts.execute(
                new List<AccountSwitcherFlowGetAccounts.Request>{
                    new AccountSwitcherFlowGetAccounts.Request(),
                    new AccountSwitcherFlowGetAccounts.Request()
                }
            );
        }

        System.assertEquals(2, results.size(), 'Deveria retornar um resultado por request, na mesma ordem');
    }
}
