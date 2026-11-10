/**
 * Invocable Apex Action pra validar, dentro de um Flow, se o usuário
 * corrente tem acesso à conta informada — usar antes de qualquer
 * exportação/consulta que dependa de um Id de conta escolhido numa tela do
 * Flow. Nunca confiar no valor só porque veio de uma tela do próprio
 * fluxo, mesmo princípio de segurança usado no restante do projeto
 * (AccountAccessValidator).
 *
 * Retorna Boolean (não lança exceção) pra dar pra usar num Decision comum
 * no Flow Builder, sem precisar montar Fault Path.
 */
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
