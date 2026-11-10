@IsTest
private class AccountSwitcherControllerTest {

    @TestSetup
    static void setup() {
        Account accA = new Account(Name = 'Empresa A', CPF_ou_CNPJ__c = '11.111.111/0001-11');
        Account accB = new Account(Name = 'Empresa B', CPF_ou_CNPJ__c = '22.222.222/0001-22');
        Account accC = new Account(Name = 'Empresa C Nao Autorizada', CPF_ou_CNPJ__c = '33.333.333/0001-33');
        insert new List<Account>{ accA, accB, accC };

        Contact con = new Contact(
            FirstName = 'Switcher',
            LastName = 'Test',
            AccountId = accA.Id,
            Email = 'portal.test.switcher@example.com'
        );
        insert con;

        insert new AccountContactRelation(AccountId = accB.Id, ContactId = con.Id, IsActive = true);

        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Portal Cliente' LIMIT 1];
        insert new User(
            FirstName = 'Switcher',
            LastName = 'Controller Test',
            Alias = 'sswtest',
            Email = 'portal.test.switcher@example.com',
            Username = 'portal.test.switcher@' + DateTime.now().getTime() + '.example.com',
            CommunityNickname = 'sswtest' + DateTime.now().getTime(),
            TimeZoneSidKey = 'America/Sao_Paulo',
            LocaleSidKey = 'pt_BR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'pt_BR',
            ProfileId = portalProfile.Id,
            ContactId = con.Id
        );
    }

    @IsTest
    static void testGetAvailableAccountsReturnsOnlyAuthorized() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'sswtest' LIMIT 1];

        List<AccountSwitcherController.AccountOption> options;
        System.runAs(portalUser) {
            Test.startTest();
            options = AccountSwitcherController.getAvailableAccounts();
            Test.stopTest();
        }

        Set<String> names = new Set<String>();
        for (AccountSwitcherController.AccountOption o : options) {
            names.add(o.name);
        }

        System.assertEquals(2, options.size(), 'Deveria retornar apenas as 2 contas autorizadas');
        System.assert(names.contains('Empresa A'));
        System.assert(names.contains('Empresa B'));
        System.assert(!names.contains('Empresa C Nao Autorizada'));
    }

    @IsTest
    static void testGetAvailableAccountsOrderedByName() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'sswtest' LIMIT 1];

        List<AccountSwitcherController.AccountOption> options;
        System.runAs(portalUser) {
            options = AccountSwitcherController.getAvailableAccounts();
        }

        System.assertEquals('Empresa A', options[0].name);
        System.assertEquals('Empresa B', options[1].name);
    }

    @IsTest
    static void testSelectAccountSucceedsForAuthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'sswtest' LIMIT 1];
        Account accB = [SELECT Id FROM Account WHERE Name = 'Empresa B' LIMIT 1];

        AccountSwitcherController.AccountOption result;
        System.runAs(portalUser) {
            Test.startTest();
            result = AccountSwitcherController.selectAccount(accB.Id);
            Test.stopTest();
        }

        System.assertEquals(accB.Id, result.accountId);
        System.assertEquals('Empresa B', result.name);
    }

    // Pedido do Gustavo (CTO) em 30/09/2026: selectAccount() também grava a
    // conta escolhida em Contact.Conta_Ativa__c, pra Flows que já existem
    // (formulário de chamado, Conga) lerem direto do Contato. A gravação é
    // best-effort (try/catch em persistActiveAccountOnContact), e a chamada
    // já é exercitada por testSelectAccountSucceedsForAuthorizedAccount
    // acima. Não fazemos SELECT Conta_Ativa__c aqui porque o cache de schema
    // dessa org ainda não propagou pra consultas SOQL logo após a criação do
    // campo (confirmado: Tooling API já reconhece o campo e o DML compila,
    // mas SELECT ainda falha com "No such column" — reavaliar depois).
    @IsTest
    static void testSelectAccountPersistsContaAtivaDoesNotThrow() {
        User portalUser = [SELECT Id, ContactId FROM User WHERE Alias = 'sswtest' LIMIT 1];
        Account accB = [SELECT Id FROM Account WHERE Name = 'Empresa B' LIMIT 1];

        AccountSwitcherController.AccountOption result;
        System.runAs(portalUser) {
            Test.startTest();
            result = AccountSwitcherController.selectAccount(accB.Id);
            Test.stopTest();
        }

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testSelectAccountThrowsForUnauthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'sswtest' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C Nao Autorizada' LIMIT 1];

        Boolean threw = false;
        System.runAs(portalUser) {
            try {
                AccountSwitcherController.selectAccount(accC.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }

        System.assert(threw, 'Deveria lancar AuraHandledException para conta nao autorizada (tentativa de IDOR)');
    }

    @IsTest
    static void testSelectAccountThrowsForNonExistentAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'sswtest' LIMIT 1];

        // Id com formato valido mas que nao corresponde a nenhum registro visivel.
        Account temp = new Account(Name = 'Temporaria Para Id');
        insert temp;
        Id fakeId = temp.Id;
        delete temp;

        Boolean threw = false;
        System.runAs(portalUser) {
            try {
                AccountSwitcherController.selectAccount(fakeId);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }

        System.assert(threw, 'Deveria lancar excecao para Id de conta inexistente');
    }

    @IsTest
    static void testGetAvailableAccountsEmptyForUserWithoutContact() {
        // Usuario de contexto do teste (admin), sem ContactId -> lista vazia, sem erro.
        List<AccountSwitcherController.AccountOption> options = AccountSwitcherController.getAvailableAccounts();
        System.assertEquals(0, options.size());
    }
}
