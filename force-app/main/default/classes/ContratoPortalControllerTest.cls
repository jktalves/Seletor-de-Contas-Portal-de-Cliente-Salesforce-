@IsTest
private class ContratoPortalControllerTest {

    @TestSetup
    static void setup() {
        Account accA = new Account(Name = 'Empresa A Contrato', CPF_ou_CNPJ__c = '11.111.111/0001-11');
        Account accC = new Account(Name = 'Empresa C Contrato Nao Autorizada', CPF_ou_CNPJ__c = '33.333.333/0001-33');
        insert new List<Account>{ accA, accC };

        insert new List<Oportunidade_Aprovada__c>{
            new Oportunidade_Aprovada__c(Conta__c = accA.Id),
            new Oportunidade_Aprovada__c(Conta__c = accA.Id),
            new Oportunidade_Aprovada__c(Conta__c = accC.Id)
        };

        Contact con = new Contact(
            FirstName = 'Contrato',
            LastName = 'Test',
            AccountId = accA.Id,
            Email = 'portal.test.contrato@example.com'
        );
        insert con;

        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Portal Cliente' LIMIT 1];
        User createdUser = new User(
            FirstName = 'Contrato',
            LastName = 'Portal Test',
            Alias = 'contest',
            Email = 'portal.test.contrato@example.com',
            Username = 'portal.test.contrato@' + DateTime.now().getTime() + '.example.com',
            CommunityNickname = 'contest' + DateTime.now().getTime(),
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
    static void testGetContratosDoesNotThrowForAuthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'contest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Contrato' LIMIT 1];

        List<ContratoPortalController.ContratoItem> result;
        System.runAs(portalUser) {
            Test.startTest();
            result = ContratoPortalController.getContratos(accA.Id, 'Ativos');
            Test.stopTest();
        }

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testGetContratosThrowsForUnauthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'contest' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C Contrato Nao Autorizada' LIMIT 1];

        Boolean threw = false;
        System.runAs(portalUser) {
            try {
                ContratoPortalController.getContratos(accC.Id, 'Todos');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }

        System.assert(threw, 'Deveria bloquear tentativa de ver Contratos de conta nao autorizada (IDOR)');
    }

    @IsTest
    static void testGetContratosAllViewsRunWithoutError() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'contest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Contrato' LIMIT 1];
        List<String> views = new List<String>{ 'Todos', 'Ativos', 'Encerrados', 'Novos', null };

        System.runAs(portalUser) {
            for (String v : views) {
                List<ContratoPortalController.ContratoItem> result = ContratoPortalController.getContratos(accA.Id, v);
                System.assertNotEquals(null, result, 'Modo ' + v + ' nao deveria lancar excecao');
            }
        }
    }

    // Cobre o construtor do wrapper diretamente: o usuário de portal de teste
    // não tem o AccountShare/sharing implícito que existe em produção (não é
    // simulável via API, ver comentário no FaturaPortalControllerTest), então
    // getContratos() nunca retorna linhas dentro do teste e o construtor de
    // ContratoItem nunca é exercitado pelos outros testes. Status__c e
    // Valor__c são fórmulas (não dá pra atribuir num sObject em memória) —
    // ficam nulas aqui, o que não afeta a cobertura das linhas de atribuição.
    @IsTest
    static void testContratoItemMapsFields() {
        Oportunidade_Aprovada__c o = new Oportunidade_Aprovada__c(data_entrega__c = Date.today());

        ContratoPortalController.ContratoItem item = new ContratoPortalController.ContratoItem(o);

        System.assertEquals(Date.today(), item.dataEntrega);
    }
}
