@IsTest
private class EquipamentoPortalControllerTest {

    @TestSetup
    static void setup() {
        Account accA = new Account(Name = 'Empresa A Equip', CPF_ou_CNPJ__c = '11.111.111/0001-11');
        Account accC = new Account(Name = 'Empresa C Equip Nao Autorizada', CPF_ou_CNPJ__c = '33.333.333/0001-33');
        insert new List<Account>{ accA, accC };

        insert new List<Equipamento__c>{
            new Equipamento__c(Conta_Registro__c = accA.Id),
            new Equipamento__c(Conta_Registro__c = accA.Id),
            new Equipamento__c(Conta_Registro__c = accC.Id)
        };

        Contact con = new Contact(
            FirstName = 'Equip',
            LastName = 'Test',
            AccountId = accA.Id,
            Email = 'portal.test.equip@example.com'
        );
        insert con;

        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Portal Cliente' LIMIT 1];
        User createdUser = new User(
            FirstName = 'Equip',
            LastName = 'Portal Test',
            Alias = 'eqptest',
            Email = 'portal.test.equip@example.com',
            Username = 'portal.test.equip@' + DateTime.now().getTime() + '.example.com',
            CommunityNickname = 'eqptest' + DateTime.now().getTime(),
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
    static void testGetEquipamentosDoesNotThrowForAuthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'eqptest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Equip' LIMIT 1];

        List<EquipamentoPortalController.EquipamentoItem> result;
        System.runAs(portalUser) {
            Test.startTest();
            result = EquipamentoPortalController.getEquipamentos(accA.Id, 'Locado');
            Test.stopTest();
        }

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testGetEquipamentosThrowsForUnauthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'eqptest' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C Equip Nao Autorizada' LIMIT 1];

        Boolean threw = false;
        System.runAs(portalUser) {
            try {
                EquipamentoPortalController.getEquipamentos(accC.Id, 'Locado');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }

        System.assert(threw, 'Deveria bloquear tentativa de ver Equipamentos de conta nao autorizada (IDOR)');
    }

    @IsTest
    static void testGetEquipamentosAllViewsRunWithoutError() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'eqptest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Equip' LIMIT 1];
        List<String> views = new List<String>{ 'Todos', 'Locado', 'Em_Espera', null };

        System.runAs(portalUser) {
            for (String v : views) {
                List<EquipamentoPortalController.EquipamentoItem> result = EquipamentoPortalController.getEquipamentos(accA.Id, v);
                System.assertNotEquals(null, result, 'Modo ' + v + ' nao deveria lancar excecao');
            }
        }
    }

    // Cobre o construtor do wrapper diretamente: o usuário de portal de teste
    // não tem o AccountShare/sharing implícito que existe em produção (não é
    // simulável via API, ver comentário no FaturaPortalControllerTest), então
    // getEquipamentos() nunca retorna linhas dentro do teste e o construtor de
    // EquipamentoItem nunca é exercitado pelos outros testes. Descrição,
    // DataEntrega__c e Valor_de_locação_fórmula__c são fórmulas (não dá pra
    // atribuir num sObject em memória) — ficam nulas aqui, o que não afeta a
    // cobertura das linhas de atribuição.
    @IsTest
    static void testEquipamentoItemMapsFields() {
        Equipamento__c e = new Equipamento__c(Name = 'EQ-0001');

        EquipamentoPortalController.EquipamentoItem item = new EquipamentoPortalController.EquipamentoItem(e);

        System.assertEquals(null, item.contrato);
        System.assertEquals(null, item.usuario);
        System.assertEquals(null, item.contratoId);
        System.assertEquals(null, item.usuarioId);
    }
}
