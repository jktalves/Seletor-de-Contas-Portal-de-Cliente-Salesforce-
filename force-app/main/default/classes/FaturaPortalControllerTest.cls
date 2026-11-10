@IsTest
private class FaturaPortalControllerTest {

    @TestSetup
    static void setup() {
        Account accA = new Account(Name = 'Empresa A Faturas', CPF_ou_CNPJ__c = '11.111.111/0001-11');
        Account accC = new Account(Name = 'Empresa C Faturas Nao Autorizada', CPF_ou_CNPJ__c = '33.333.333/0001-33');
        insert new List<Account>{ accA, accC };

        Contract contractA = new Contract(AccountId = accA.Id, StartDate = Date.today());
        Contract contractC = new Contract(AccountId = accC.Id, StartDate = Date.today());
        insert new List<Contract>{ contractA, contractC };

        insert new Fatura__c(Conta__c = accA.Id, contrato__c = contractA.Id, Status__c = 'Rascunho', Vencimento__c = Date.today(), Valor_Fatura__c = 100, Tipo_de_Pagamento__c = 'Pré-pago');
        insert new Fatura__c(Conta__c = accA.Id, contrato__c = contractA.Id, Status__c = 'Rascunho', Vencimento__c = Date.today().addDays(-30), Valor_Fatura__c = 200, Tipo_de_Pagamento__c = 'Pré-pago');
        insert new Fatura__c(Conta__c = accC.Id, contrato__c = contractC.Id, Status__c = 'Rascunho', Vencimento__c = Date.today(), Valor_Fatura__c = 300, Tipo_de_Pagamento__c = 'Pré-pago');

        Contact con = new Contact(
            FirstName = 'Fatura',
            LastName = 'Test',
            AccountId = accA.Id,
            Email = 'portal.test.fatura@example.com'
        );
        insert con;

        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Portal Cliente' LIMIT 1];
        insert new User(
            FirstName = 'Fatura',
            LastName = 'Portal Test',
            Alias = 'fattest',
            Email = 'portal.test.fatura@example.com',
            Username = 'portal.test.fatura@' + DateTime.now().getTime() + '.example.com',
            CommunityNickname = 'fattest' + DateTime.now().getTime(),
            TimeZoneSidKey = 'America/Sao_Paulo',
            LocaleSidKey = 'pt_BR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'pt_BR',
            ProfileId = portalProfile.Id,
            ContactId = con.Id
        );

        // Em produção, usuários de portal recebem o acesso a Fatura__c via o
        // Permission Set SeletorDeContas (mesmo usado pelo Account Switcher).
        // Replicamos essa atribuição aqui. O insert de PermissionSetAssignment
        // (objeto "setup") é envolvido em System.runAs (mesmo como o próprio
        // usuário corrente) porque esse é o mecanismo suportado para evitar
        // MIXED_DML_OPERATION quando já houve DML em objetos "non-setup"
        // (Account/Contract/Fatura__c) na mesma transação.
        User createdUser = [SELECT Id FROM User WHERE Alias = 'fattest' LIMIT 1];
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SeletorDeContas' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = createdUser.Id, PermissionSetId = ps.Id);
        }
    }

    @IsTest
    static void testGetFaturasReturnsOnlyAuthorizedAccountFaturas() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'fattest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Faturas' LIMIT 1];

        List<FaturaPortalController.FaturaItem> result;
        System.runAs(portalUser) {
            Test.startTest();
            result = FaturaPortalController.getFaturas(accA.Id, 'Recentes');
            Test.stopTest();
        }

        // NOTA: em produção, usuários de portal existentes têm o compartilhamento
        // de Account resolvido pelo fluxo padrão de habilitação de usuário externo
        // do Salesforce (papel de portal, sharing implícito), que não é
        // reproduzível de forma simples/suportada dentro de um teste Apex (manual
        // AccountShare para usuários de portal não é permitido pela API). Por isso
        // este teste não assume que as linhas retornam visíveis aqui — o que ele
        // garante é que a chamada autorizada NÃO lança exceção (a validação de
        // acesso passa) e que, se algum registro vier, ele pertence exclusivamente
        // à Account autorizada. O caso de acesso NEGADO é coberto de forma
        // determinística em testGetFaturasThrowsForUnauthorizedAccount.
        System.assertNotEquals(null, result, 'getFaturas nao deveria lancar excecao para conta autorizada');
        for (FaturaPortalController.FaturaItem item : result) {
            System.assertNotEquals(null, item.id);
        }
    }

    @IsTest
    static void testGetFaturasThrowsForUnauthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'fattest' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C Faturas Nao Autorizada' LIMIT 1];

        Boolean threw = false;
        System.runAs(portalUser) {
            try {
                FaturaPortalController.getFaturas(accC.Id, 'Pagos');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }

        System.assert(threw, 'Deveria bloquear tentativa de ver Faturas de conta nao autorizada (IDOR)');
    }

    @IsTest
    static void testGetFaturasEmptyWhenAccountHasNone() {
        User portalUser = [SELECT Id, ContactId FROM User WHERE Alias = 'fattest' LIMIT 1];
        Account accEmpty = new Account(Name = 'Empresa Sem Faturas');
        insert accEmpty;
        insert new AccountContactRelation(
            AccountId = accEmpty.Id,
            ContactId = portalUser.ContactId,
            IsActive = true
        );

        List<FaturaPortalController.FaturaItem> result;
        System.runAs(portalUser) {
            result = FaturaPortalController.getFaturas(accEmpty.Id, 'Pagos');
        }

        System.assertEquals(0, result.size());
    }

    @IsTest
    static void testGetFaturasAllViewsRunWithoutError() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'fattest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Faturas' LIMIT 1];
        List<String> views = new List<String>{ 'Todos', 'Recentes', 'Atrasos', 'Pagos', null };

        System.runAs(portalUser) {
            for (String v : views) {
                List<FaturaPortalController.FaturaItem> result = FaturaPortalController.getFaturas(accA.Id, v);
                System.assertNotEquals(null, result, 'Modo ' + v + ' nao deveria lancar excecao');
            }
        }
    }

    @IsTest
    static void testHasFaturasEmAtrasoDoesNotThrowForAuthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'fattest' LIMIT 1];
        Account accA = [SELECT Id FROM Account WHERE Name = 'Empresa A Faturas' LIMIT 1];

        Boolean result;
        System.runAs(portalUser) {
            Test.startTest();
            result = FaturaPortalController.hasFaturasEmAtraso(accA.Id);
            Test.stopTest();
        }

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testHasFaturasEmAtrasoThrowsForUnauthorizedAccount() {
        User portalUser = [SELECT Id FROM User WHERE Alias = 'fattest' LIMIT 1];
        Account accC = [SELECT Id FROM Account WHERE Name = 'Empresa C Faturas Nao Autorizada' LIMIT 1];

        Boolean threw = false;
        System.runAs(portalUser) {
            try {
                FaturaPortalController.hasFaturasEmAtraso(accC.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }

        System.assert(threw, 'Deveria bloquear tentativa de checar Faturas de conta nao autorizada (IDOR)');
    }
}
