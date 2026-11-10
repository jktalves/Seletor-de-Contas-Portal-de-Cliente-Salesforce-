@IsTest
private class LicencaSoftwarePortalControllerTest {

    @TestSetup
    static void setup() {
        Account accA = new Account(Name = 'Empresa A Licenca', CPF_ou_CNPJ__c = '11.111.111/0001-11');
        Account accC = new Account(Name = 'Empresa C Licenca Nao Autorizada', CPF_ou_CNPJ__c = '33.333.333/0001-33');
        insert new List<Account>{ accA, accC };

        insert new List<Licen_a_de_Software__c>{
            new Licen_a_de_Software__c(Conta__c = accA.Id, Status__c = 'Ativo'),
            new Licen_a_de_Software__c(Conta__c = accA.Id, Status__c = 'Inativo'),
            new Licen_a_de_Software__c(Conta__c = accC.Id, Status__c = 'Ativo')
        };

        Contact con = new Contact(
            FirstName = 'Licenca',
            LastName = 'Test',
            AccountId = accA.Id,
            Email = 'portal.test.licenca@example.com'
        );
        insert con;

        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Portal Cliente' LIMIT 1];
        User createdUser = new User(
            FirstName = 'Licenca',
            LastName = 'Portal Test',
            Alias = 'lictest',
            Email = 'portal.test.licenca@example.com',
            Username = 'portal.test.licenca@' + DateTime.now().getTime() + '.example.com',
            CommunityNickname = 'lictest' + DateTime.now().getTime(),
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
    static void testGetLicencasDoesNotThrowForAuthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'lictest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Licenca' LIMIT 1];

        List<LicencaSoftwarePortalController.LicencaItem> result;
        System.runAs(portalUser) {
            Test.startTest();
            result = LicencaSoftwarePortalController.getLicencas(accA.Id, 'Tudo');
            Test.stopTest();
        }

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testGetLicencasThrowsForUnauthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'lictest' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C Licenca Nao Autorizada' LIMIT 1];

        Boolean threw = false;
        System.runAs(portalUser) {
            try {
                LicencaSoftwarePortalController.getLicencas(accC.Id, 'Tudo');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }

        System.assert(threw, 'Deveria bloquear tentativa de ver Licencas de conta nao autorizada (IDOR)');
    }

    @IsTest
    static void testGetLicencasAllViewsRunWithoutError() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'lictest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Licenca' LIMIT 1];
        List<String> views = new List<String>{ 'Tudo', 'Recentes', null };

        System.runAs(portalUser) {
            for (String v : views) {
                List<LicencaSoftwarePortalController.LicencaItem> result = LicencaSoftwarePortalController.getLicencas(accA.Id, v);
                System.assertNotEquals(null, result, 'Modo ' + v + ' nao deveria lancar excecao');
            }
        }
    }

    // Cobre o construtor do wrapper diretamente: o usuário de portal de teste
    // não tem o AccountShare/sharing implícito que existe em produção, então
    // getLicencas() nunca retorna linhas dentro do teste e o construtor de
    // LicencaItem nunca é exercitado pelos outros testes.
    @IsTest
    static void testLicencaItemMapsFields() {
        Licen_a_de_Software__c l = new Licen_a_de_Software__c();

        LicencaSoftwarePortalController.LicencaItem item = new LicencaSoftwarePortalController.LicencaItem(l);

        System.assertEquals(null, item.equipamento);
        System.assertEquals(null, item.contrato);
        System.assertEquals(null, item.equipamentoId);
        System.assertEquals(null, item.contratoId);
    }
}
