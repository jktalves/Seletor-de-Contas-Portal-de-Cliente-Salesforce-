import { createElement } from 'lwc';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import AccountSwitcher from 'c/accountSwitcher';
import getAvailableAccounts from '@salesforce/apex/AccountSwitcherController.getAvailableAccounts';
import selectAccountApex from '@salesforce/apex/AccountSwitcherController.selectAccount';
import { publish } from 'lightning/messageService';

jest.mock(
    '@salesforce/apex/AccountSwitcherController.selectAccount',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const getAvailableAccountsAdapter = registerApexTestWireAdapter(getAvailableAccounts);

const ACCOUNTS_SINGLE = [{ accountId: '001000000000001AAA', name: 'Empresa A', cnpj: '11.111.111/0001-11' }];

const ACCOUNTS_MULTIPLE = [
    { accountId: '001000000000001AAA', name: 'Empresa A', cnpj: '11.111.111/0001-11' },
    { accountId: '001000000000002AAA', name: 'Empresa B', cnpj: '22.222.222/0001-22' }
];

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function emitAccounts(data) {
    getAvailableAccountsAdapter.emit(data);
    await flushPromises();
}

describe('c-account-switcher', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        window.sessionStorage.clear();
    });

    it('mostra estado vazio quando não há contas disponíveis', async () => {
        const element = createElement('c-account-switcher', { is: AccountSwitcher });
        document.body.appendChild(element);

        await emitAccounts([]);

        const emptyState = element.shadowRoot.querySelector('.slds-text-color_weak');
        expect(emptyState.textContent).toContain('Nenhuma conta disponível');
        expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
    });

    it('mostra a conta única sem dropdown quando o usuário tem apenas uma conta', async () => {
        const element = createElement('c-account-switcher', { is: AccountSwitcher });
        document.body.appendChild(element);

        await emitAccounts(ACCOUNTS_SINGLE);

        expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
        const single = element.shadowRoot.querySelector('.account-switcher__single');
        expect(single.textContent).toContain('Empresa A');
        expect(single.textContent).toContain('11.111.111/0001-11');
    });

    it('publica o contexto inicial via LMS ao carregar múltiplas contas', async () => {
        const element = createElement('c-account-switcher', { is: AccountSwitcher });
        document.body.appendChild(element);

        await emitAccounts(ACCOUNTS_MULTIPLE);

        expect(publish).toHaveBeenCalledTimes(1);
        const publishedPayload = publish.mock.calls[0][2];
        expect(publishedPayload.accountId).toBe('001000000000001AAA');
        expect(publishedPayload.accountName).toBe('Empresa A');
    });

    it('mostra o dropdown quando há múltiplas contas e lista as opções corretas', async () => {
        const element = createElement('c-account-switcher', { is: AccountSwitcher });
        document.body.appendChild(element);

        await emitAccounts(ACCOUNTS_MULTIPLE);

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox).not.toBeNull();
        expect(combobox.options).toHaveLength(2);
        expect(combobox.value).toBe('001000000000001AAA');
    });

    it('ao trocar de conta, chama o Apex de validação e publica o novo contexto confirmado pelo servidor', async () => {
        selectAccountApex.mockResolvedValue({
            accountId: '001000000000002AAA',
            name: 'Empresa B',
            cnpj: '22.222.222/0001-22'
        });

        const element = createElement('c-account-switcher', { is: AccountSwitcher });
        document.body.appendChild(element);
        await emitAccounts(ACCOUNTS_MULTIPLE);
        publish.mockClear();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(
            new CustomEvent('change', { detail: { value: '001000000000002AAA' } })
        );
        await flushPromises();

        expect(selectAccountApex).toHaveBeenCalledWith({ accountId: '001000000000002AAA' });
        expect(publish).toHaveBeenCalledTimes(1);
        const publishedPayload = publish.mock.calls[0][2];
        expect(publishedPayload.accountId).toBe('001000000000002AAA');
        expect(publishedPayload.accountName).toBe('Empresa B');
    });

    it('mostra mensagem de erro quando o Apex rejeita a troca de conta (ex.: acesso negado)', async () => {
        selectAccountApex.mockRejectedValue({ body: { message: 'Acesso não autorizado a esta conta.' } });

        const element = createElement('c-account-switcher', { is: AccountSwitcher });
        document.body.appendChild(element);
        await emitAccounts(ACCOUNTS_MULTIPLE);

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(
            new CustomEvent('change', { detail: { value: '001000000000002AAA' } })
        );
        await flushPromises();

        const errorEl = element.shadowRoot.querySelector('[role="alert"]');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('Acesso não autorizado');
    });

    it('mostra mensagem de erro quando o carregamento inicial falha', async () => {
        const element = createElement('c-account-switcher', { is: AccountSwitcher });
        document.body.appendChild(element);

        getAvailableAccountsAdapter.error();
        await flushPromises();

        const errorEl = element.shadowRoot.querySelector('[role="alert"]');
        expect(errorEl).not.toBeNull();
    });
});
