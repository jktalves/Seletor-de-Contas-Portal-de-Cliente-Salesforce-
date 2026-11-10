/**
 * Invocable Apex Action pra expor a lista de contas autorizadas do Seletor
 * de Contas dentro de um Flow — pedido do CTO pra reaproveitar a MESMA
 * lógica (AccountSwitcherController) em vez de duplicar um segundo seletor
 * de contas dentro de um fluxo (ex.: exportação de Equipamentos via Conga
 * precisa saber quais contas o usuário pode escolher).
 *
 * Não duplica query nem regra de negócio: só delega pro método já usado
 * pelo accountSwitcher (LWC).
 */
public with sharing class AccountSwitcherFlowGetAccounts {

    public class Request {
        // Sem uso — existe só porque um Invocable Method exige que o tipo
        // de entrada tenha pelo menos uma @InvocableVariable. A lista de
        // contas autorizadas depende exclusivamente do usuário corrente do
        // Flow, não de nenhuma entrada.
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

    /**
     * Retorna as contas que o usuário corrente do Flow tem acesso — a
     * mesma lista que aparece no seletor de contas do portal.
     */
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
