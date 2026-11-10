@IsTest
private class CasoPortalControllerTest {

    @TestSetup
    static void setup() {
        Account accA = new Account(Name = 'Empresa A Casos', CPF_ou_CNPJ__c = '11.111.111/0001-11');
        Account accC = new Account(Name = 'Empresa C Casos Nao Autorizada', CPF_ou_CNPJ__c = '33.333.333/0001-33');
        insert new List<Account>{ accA, accC };

        insert new List<Case>{
            new Case(AccountId = accA.Id, Subject = 'Caso 1 Empresa A'),
            new Case(AccountId = accA.Id, Subject = 'Caso 2 Empresa A'),
            new Case(AccountId = accC.Id, Subject = 'Caso Empresa C')
        };

        Contact con = new Contact(
            FirstName = 'Caso',
            LastName = 'Test',
            AccountId = accA.Id,
            Email = 'portal.test.caso@example.com'
        );
        insert con;

        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Portal Cliente' LIMIT 1];
        User createdUser = new User(
            FirstName = 'Caso',
            LastName = 'Portal Test',
            Alias = 'castest',
            Email = 'portal.test.caso@example.com',
            Username = 'portal.test.caso@' + DateTime.now().getTime() + '.example.com',
            CommunityNickname = 'castest' + DateTime.now().getTime(),
            TimeZoneSidKey = 'America/Sao_Paulo',
            LocaleSidKey = 'pt_BR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'pt_BR',
            ProfileId = portalProfile.Id,
            ContactId = con.Id
        );
        insert createdUser;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SeletorDeContas' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = createdUser.Id, PermissionSetId = ps.Id);
        }
    }

    @IsTest
    static void testGetCasosDoesNotThrowForAuthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'castest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Casos' LIMIT 1];

        List<CasoPortalController.CasoItem> result;
        System.runAs(portalUser) {
            Test.startTest();
            result = CasoPortalController.getCasos(accA.Id, 'Em_andamento');
            Test.stopTest();
        }

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testGetCasosThrowsForUnauthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'castest' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C Casos Nao Autorizada' LIMIT 1];

        Boolean threw = false;
        System.runAs(portalUser) {
            try {
                CasoPortalController.getCasos(accC.Id, 'Todos');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }

        System.assert(threw, 'Deveria bloquear tentativa de ver Casos de conta nao autorizada (IDOR)');
    }

    @IsTest
    static void testGetCasosAllViewsRunWithoutError() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'castest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Casos' LIMIT 1];
        List<String> views = new List<String>{ 'Em_andamento', 'Novo', 'Encerrados', 'Entregas', 'Devolucoes', 'Trocas', 'Outros', 'Todos', null };

        System.runAs(portalUser) {
            for (String v : views) {
                List<CasoPortalController.CasoItem> result = CasoPortalController.getCasos(accA.Id, v);
                System.assertNotEquals(null, result, 'Modo ' + v + ' nao deveria lancar excecao');
            }
        }
    }
}
