// Valida dentro de um Flow se o usuário tem acesso a uma conta vinda de uma
// tela/variável do próprio fluxo — nunca confiar nesse valor sem checar aqui.
// Retorna Boolean (não lança exceção) pra usar num Decision comum, sem Fault Path.
public with sharing class AccountSwitcherFlowValidateAccess {

    public class Request {
        @InvocableVariable(label='Id da Conta' required=true)
        public Id accountId;
    }

    public class Result {
        @InvocableVariable(label='Tem Acesso?')
        public Boolean isAuthorized;
    }

    @InvocableMethod(label='Seletor de Contas: Validar Acesso a Conta' category='Seletor de Contas')
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result result = new Result();
            result.isAuthorized = AccountAccessValidator.hasAccess(req.accountId);
            results.add(result);
        }

        return results;
    }
}
