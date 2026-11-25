// Expõe as contas autorizadas do seletor dentro de um Flow, delegando pro
// AccountSwitcherController (sem duplicar query/regra de negócio).
public with sharing class AccountSwitcherFlowGetAccounts {

    public class Request {
        // Sem uso real — só existe pq Invocable Method exige pelo menos uma @InvocableVariable de entrada.
        @InvocableVariable(label='(sem uso)')
        public String naoUsado;
    }

    public class AccountOption {
        @InvocableVariable(label='Id da Conta')
        public Id accountId;

        @InvocableVariable(label='Nome da Conta')
        public String name;

        @InvocableVariable(label='CNPJ')
        public String cnpj;
    }

    public class Result {
        @InvocableVariable(label='Contas Autorizadas')
        public List<AccountOption> accounts;
    }

    // Mesma lista que aparece no seletor de contas do portal.
    @InvocableMethod(label='Seletor de Contas: Obter Contas Autorizadas' category='Seletor de Contas')
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Integer i = 0; i < requests.size(); i++) {
            Result result = new Result();
            result.accounts = new List<AccountOption>();

            for (AccountSwitcherController.AccountOption opt : AccountSwitcherController.getAvailableAccounts()) {
                AccountOption item = new AccountOption();
                item.accountId = opt.accountId;
                item.name = opt.name;
                item.cnpj = opt.cnpj;
                result.accounts.add(item);
            }

            results.add(result);
        }

        return results;
    }
}
