import { LightningElement, track, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import ACCOUNT_CONTEXT_CHANNEL from '@salesforce/messageChannel/AccountContextChannel__c';
import getAvailableAccounts from '@salesforce/apex/AccountSwitcherController.getAvailableAccounts';
import selectAccountApex from '@salesforce/apex/AccountSwitcherController.selectAccount';

const STORAGE_KEY = 'accountSwitcher.selectedAccountId';
const GENERIC_ERROR = 'Não foi possível carregar as contas disponíveis.';

export default class AccountSwitcher extends LightningElement {
    @track accounts = [];
    @track selectedAccountId;
    isLoading = true;
    errorMessage;

    @wire(MessageContext)
    messageContext;

    @wire(getAvailableAccounts)
    wiredAccounts({ data, error }) {
        this.isLoading = false;

        if (data) {
            this.errorMessage = undefined;
            this.accounts = data;
            this.initializeSelection();
        } else if (error) {
            this.accounts = [];
            this.errorMessage = this.extractErrorMessage(error);
        }
    }

    get hasAccounts() {
        return this.accounts.length > 0;
    }

    get hasSingleAccount() {
        return this.accounts.length === 1;
    }

    get showDropdown() {
        return this.accounts.length > 1;
    }

    get selectedAccount() {
        return this.accounts.find((acc) => acc.accountId === this.selectedAccountId);
    }

    get selectOptions() {
        return this.accounts.map((acc) => ({
            label: acc.cnpj ? `${acc.name} — ${acc.cnpj}` : acc.name,
            value: acc.accountId
        }));
    }

    initializeSelection() {
        if (!this.hasAccounts) {
            this.selectedAccountId = undefined;
            return;
        }

        const storedId = this.getStoredAccountId();
        const storedIsValid = storedId && this.accounts.some((acc) => acc.accountId === storedId);
        const initialId = storedIsValid ? storedId : this.accounts[0].accountId;

        this.applySelection(initialId);
    }

    async handleChange(event) {
        const newAccountId = event.detail.value;
        if (!newAccountId || newAccountId === this.selectedAccountId) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const confirmed = await selectAccountApex({ accountId: newAccountId });
            this.applySelection(confirmed.accountId, confirmed);
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    applySelection(accountId, accountData) {
        this.selectedAccountId = accountId;
        this.setStoredAccountId(accountId);
        this.publishAccountContext(accountData || this.selectedAccount);
    }

    publishAccountContext(account) {
        if (!account) {
            return;
        }
        publish(this.messageContext, ACCOUNT_CONTEXT_CHANNEL, {
            accountId: account.accountId,
            accountName: account.name,
            accountCnpj: account.cnpj
        });
    }

    getStoredAccountId() {
        try {
            return window.sessionStorage.getItem(STORAGE_KEY);
        } catch (e) {
            return null;
        }
    }

    setStoredAccountId(accountId) {
        try {
            // Somente cache de UI (sobrevive à navegação entre páginas na mesma aba).
            // Não é usado para nenhuma decisão de segurança — a Account é revalidada
            // no Apex a cada seleção.
            window.sessionStorage.setItem(STORAGE_KEY, accountId);
        } catch (e) {
            // sessionStorage indisponível (ex.: navegação privada) — sem impacto de segurança.
        }
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return GENERIC_ERROR;
    }
}
