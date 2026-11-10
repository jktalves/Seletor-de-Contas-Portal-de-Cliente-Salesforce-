import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import ACCOUNT_CONTEXT_CHANNEL from '@salesforce/messageChannel/AccountContextChannel__c';
import getFaturas from '@salesforce/apex/FaturaPortalController.getFaturas';

// Mesma chave usada pelo accountSwitcher para cache de UI em sessionStorage.
// Necessário porque esta lista pode montar DEPOIS do accountSwitcher já ter
// publicado o contexto inicial. A segurança não depende disso: o AccountId
// lido daqui é sempre revalidado no Apex antes de qualquer dado ser retornado.
const STORAGE_KEY = 'accountSwitcher.selectedAccountId';
const GENERIC_ERROR = 'Não foi possível carregar as faturas.';
const OBJECT_API_NAME = 'Fatura__c';
const VIEW_PADRAO = 'Todos';
const MIN_COLUMN_WIDTH = 60;
const ROWNUM_COLUMN_WIDTH = '3.5rem';

// Peso relativo de cada coluna — a largura % real é recalculada em
// colStyle() dividindo o peso da coluna pela soma dos pesos das colunas
// VISÍVEIS no modo de exibição atual (Contrato só aparece em "Recentes"),
// pra tabela sempre preencher 100% mesmo com menos colunas. Data de
// Aprovação/Link do Boleto/Forma de Pagamento foram removidos: o perfil do
// portal não tem FLS de leitura nesses campos (conferido em 09/11/2026).
const COLUMN_WEIGHTS = {
    numero: 16,
    status: 18,
    valor: 20,
    vencimento: 20,
    contrato: 26
};

// 5 modos reais da produção (conferidos com screenshots em 09/11/2026):
// Todos→"Todas", Em_Aberto→"Em Aberto/Recentes", Atrasos→"Em Atraso",
// Pagos→"Pagas", Recentes→"Recente(s)". Todos sempre aparecem no dropdown —
// produção não esconde "Em Atraso" mesmo com 0 itens.
const VIEWS = [
    { value: VIEW_PADRAO, label: 'Todas' },
    { value: 'Em_Aberto', label: 'Em Aberto/Recentes' },
    { value: 'Atrasos', label: 'Em Atraso' },
    { value: 'Pagos', label: 'Pagas' },
    { value: 'Recentes', label: 'Recente(s)' }
];

export default class FaturaLista extends NavigationMixin(LightningElement) {
    views = VIEWS;
    selectedView = VIEW_PADRAO;
    faturas = [];
    isLoading = true;
    errorMessage;
    accountId;
    isPickerOpen = false;
    searchTerm = '';
    sortField;
    sortDirection = 'asc';
    subscription;

    // Menu "Quebrar texto / Cortar texto" por coluna (igual list view nativa).
    openColumnMenuField;
    wrapFields = new Set();

    // Redimensionamento de coluna (arrastar a borda), igual a list view
    // nativa. Vazio = usa a largura % padrão (flexível); ganha uma entrada em
    // px só depois que o usuário arrasta aquela coluna manualmente.
    columnWidths = {};
    resizingField;
    resizeStartX = 0;
    resizeStartWidth = 0;

    @wire(MessageContext)
    messageContext;

    // Fecha os dropdowns via overlay transparente (em vez de listener no
    // document): assim não depende de nenhum outro componente da página
    // (ex.: o lightning-combobox do Seletor de Contas) deixar o clique
    // borbulhar até lá — o clique é capturado localmente, pelo nosso próprio
    // overlay, antes de chegar em qualquer outra coisa.
    handleOverlayClick(event) {
        event.stopPropagation();
        this.isPickerOpen = false;
    }

    // Arrastar a borda da coluna pra redimensionar. mousemove/mouseup
    // precisam ficar no window (não dá pra prever até onde o mouse vai
    // durante o arraste), mas só ficam ativos durante o próprio arraste —
    // diferente do listener permanente que causava conflito com outros
    // componentes da página.
    handleResizeStart(event) {
        event.preventDefault();
        event.stopPropagation();
        const field = event.currentTarget.dataset.field;
        const th = event.currentTarget.closest('th');
        this.resizingField = field;
        this.resizeStartX = event.clientX;
        this.resizeStartWidth = th ? th.getBoundingClientRect().width : MIN_COLUMN_WIDTH;
        window.addEventListener('mousemove', this.handleResizeMove);
        window.addEventListener('mouseup', this.handleResizeEnd);
        document.body.style.cursor = 'col-resize';
        document.body.style.userSelect = 'none';
    }

    handleResizeMove = (event) => {
        if (!this.resizingField) {
            return;
        }
        const delta = event.clientX - this.resizeStartX;
        const newWidth = Math.max(MIN_COLUMN_WIDTH, this.resizeStartWidth + delta);
        this.columnWidths = { ...this.columnWidths, [this.resizingField]: newWidth };
    };

    handleResizeEnd = () => {
        this.resizingField = undefined;
        window.removeEventListener('mousemove', this.handleResizeMove);
        window.removeEventListener('mouseup', this.handleResizeEnd);
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
    };

    // Absorve o "click" que segue o mousedown+mouseup do arraste, pra não
    // disparar a ordenação da coluna (handleSort) sem querer.
    handleResizeHandleClick(event) {
        event.stopPropagation();
    }

    handleColumnOverlayClick(event) {
        event.stopPropagation();
        this.openColumnMenuField = undefined;
    }

    connectedCallback() {
        // Produção usa a list view nativa (forceCommunity:objectHome), que
        // define o título da aba do navegador como o rótulo do objeto
        // ("Faturas"). Nosso componente custom não faz isso por padrão,
        // então replicamos aqui para a aba do navegador ficar igual.
        document.title = 'Faturas';

        this.subscription = subscribe(this.messageContext, ACCOUNT_CONTEXT_CHANNEL, (message) => {
            this.handleAccountContext(message);
        });

        const cachedAccountId = this.getCachedAccountId();
        if (cachedAccountId) {
            this.accountId = cachedAccountId;
            this.loadFaturas();
        } else {
            this.isLoading = false;
        }
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = undefined;
        // Segurança: se o componente desmontar no meio de um arraste.
        window.removeEventListener('mousemove', this.handleResizeMove);
        window.removeEventListener('mouseup', this.handleResizeEnd);
    }

    handleAccountContext(message) {
        if (!message || !message.accountId || message.accountId === this.accountId) {
            return;
        }
        this.accountId = message.accountId;
        this.loadFaturas();
    }

    async loadFaturas() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const data = await getFaturas({ accountId: this.accountId, viewName: this.selectedView });
            this.faturas = await this.attachRecordUrls(data);
        } catch (error) {
            this.faturas = [];
            this.errorMessage = this.extractErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    attachRecordUrls(records) {
        return Promise.all(
            records.map(async (record) => {
                const url = await this[NavigationMixin.GenerateUrl]({
                    type: 'standard__recordPage',
                    attributes: { recordId: record.id, objectApiName: OBJECT_API_NAME, actionName: 'view' }
                });
                return {
                    ...record,
                    recordUrl: url,
                    vencimentoFormatado: this.formatDate(record.vencimento),
                    valorFormatado: this.formatCurrency(record.valor)
                };
            })
        );
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        const [year, month, day] = value.split('-');
        return `${day}/${month}/${year}`;
    }

    formatCurrency(value) {
        if (value == null) {
            return '';
        }
        return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(value);
    }

    get selectedViewLabel() {
        const found = this.views.find((v) => v.value === this.selectedView);
        return found ? found.label : '';
    }

    get filteredFaturas() {
        if (!this.searchTerm) {
            return this.faturas;
        }
        const term = this.searchTerm.toLowerCase();
        return this.faturas.filter((f) => {
            return (
                (f.numero && f.numero.toLowerCase().includes(term)) ||
                (f.status && f.status.toLowerCase().includes(term)) ||
                (f.contrato && f.contrato.toLowerCase().includes(term))
            );
        });
    }

    get totalCount() {
        return this.filteredFaturas.length;
    }

    get sortedFaturas() {
        const list = [...this.filteredFaturas];
        if (!this.sortField) {
            return list;
        }
        const field = this.sortField;
        const dir = this.sortDirection === 'desc' ? -1 : 1;
        const isDateField = field === 'vencimento';
        const isNumberField = field === 'valor';

        return list.sort((a, b) => {
            const valA = a[field];
            const valB = b[field];
            if (valA == null && valB == null) {
                return 0;
            }
            if (valA == null) {
                return -1 * dir;
            }
            if (valB == null) {
                return 1 * dir;
            }
            if (isDateField) {
                return (new Date(valA) - new Date(valB)) * dir;
            }
            if (isNumberField) {
                return (valA - valB) * dir;
            }
            return String(valA).localeCompare(String(valB), 'pt-BR', { numeric: true, sensitivity: 'base' }) * dir;
        });
    }

    get sortIconName() {
        return this.sortDirection === 'desc' ? 'utility:arrowdown' : 'utility:arrowup';
    }

    get isSortedByNumero() {
        return this.sortField === 'numero';
    }

    get isSortedByStatus() {
        return this.sortField === 'status';
    }

    get isSortedByVencimento() {
        return this.sortField === 'vencimento';
    }

    get isSortedByValor() {
        return this.sortField === 'valor';
    }

    get isSortedByContrato() {
        return this.sortField === 'contrato';
    }

    // Classe do <th>: coluna ativa na ordenação ganha a borda laranja, igual
    // a list view nativa do Salesforce.
    get numeroThClass() {
        return this.thClass(this.isSortedByNumero);
    }

    get statusThClass() {
        return this.thClass(this.isSortedByStatus);
    }

    get vencimentoThClass() {
        return this.thClass(this.isSortedByVencimento);
    }

    get valorThClass() {
        return this.thClass(this.isSortedByValor);
    }

    get contratoThClass() {
        return this.thClass(this.isSortedByContrato);
    }

    thClass(isActive) {
        return isActive ? 'list-card__sortable-th list-card__sortable-th--active' : 'list-card__sortable-th';
    }

    // Largura de cada coluna, aplicada via <colgroup> — assim todas as
    // células da coluna (th e td) acompanham o mesmo valor. Usa % (flexível)
    // até o usuário arrastar a borda da coluna; a partir daí vira px fixo.
    colStyle(field) {
        const px = this.columnWidths[field];
        if (px) {
            return `width: ${px}px`;
        }
        const visibleFields = this.visibleColumnFields;
        const totalWeight = visibleFields.reduce((sum, f) => sum + (COLUMN_WEIGHTS[f] || 0), 0);
        const fraction = totalWeight > 0 ? COLUMN_WEIGHTS[field] / totalWeight : 0;
        return `width: calc((100% - ${ROWNUM_COLUMN_WIDTH}) * ${fraction})`;
    }

    get numeroColStyle() {
        return this.colStyle('numero');
    }

    get statusColStyle() {
        return this.colStyle('status');
    }

    get valorColStyle() {
        return this.colStyle('valor');
    }

    get vencimentoColStyle() {
        return this.colStyle('vencimento');
    }

    get contratoColStyle() {
        return this.colStyle('contrato');
    }

    // Colunas conferidas com screenshots reais da produção em 09/11/2026.
    // "Recente(s)" é a única view com ordem diferente (Vencimento antes de
    // Valor, Status depois dos dois, Contrato no final) — mesma coluna,
    // duas posições possíveis, mutuamente exclusivas (igual padrão usado em
    // Chamados pro Usuário em "Trocas").
    get showStatusEarly() {
        return ['Todos', 'Em_Aberto'].includes(this.selectedView);
    }

    get showStatusLate() {
        return this.selectedView === 'Recentes';
    }

    get showContrato() {
        return this.selectedView === 'Recentes';
    }

    get showValorVencimentoNormal() {
        return this.selectedView !== 'Recentes';
    }

    get showVencimentoValorInvertido() {
        return this.selectedView === 'Recentes';
    }

    get visibleColumnFields() {
        const fields = ['numero', 'valor', 'vencimento'];
        if (this.showStatusEarly || this.showStatusLate) {
            fields.push('status');
        }
        if (this.showContrato) {
            fields.push('contrato');
        }
        return fields;
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (this.sortField === field) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortField = field;
            this.sortDirection = 'asc';
        }
    }

    handleColumnMenuToggle(event) {
        event.stopPropagation();
        const field = event.currentTarget.dataset.field;
        this.openColumnMenuField = this.openColumnMenuField === field ? undefined : field;
    }

    handleColumnModeSelect(event) {
        event.stopPropagation();
        const field = event.currentTarget.dataset.field;
        const mode = event.currentTarget.dataset.mode;
        const wrapFields = new Set(this.wrapFields);
        if (mode === 'wrap') {
            wrapFields.add(field);
        } else {
            wrapFields.delete(field);
        }
        this.wrapFields = wrapFields;
        this.openColumnMenuField = undefined;
    }

    get isColumnMenuOpenNumero() {
        return this.openColumnMenuField === 'numero';
    }

    get isColumnMenuOpenStatus() {
        return this.openColumnMenuField === 'status';
    }

    get isColumnMenuOpenValor() {
        return this.openColumnMenuField === 'valor';
    }

    get isColumnMenuOpenVencimento() {
        return this.openColumnMenuField === 'vencimento';
    }

    get isColumnMenuOpenContrato() {
        return this.openColumnMenuField === 'contrato';
    }

    get numeroCellClass() {
        return this.wrapFields.has('numero') ? 'list-card__cell--wrap' : '';
    }

    get statusCellClass() {
        return this.wrapFields.has('status') ? 'list-card__cell--wrap' : '';
    }

    get valorCellClass() {
        return this.wrapFields.has('valor') ? 'list-card__cell--wrap' : '';
    }

    get vencimentoCellClass() {
        return this.wrapFields.has('vencimento') ? 'list-card__cell--wrap' : '';
    }

    get contratoCellClass() {
        return this.wrapFields.has('contrato') ? 'list-card__cell--wrap' : '';
    }

    get displayedFaturas() {
        return this.sortedFaturas.map((f, idx) => ({ ...f, rowNumber: idx + 1 }));
    }

    get hasFaturas() {
        return this.displayedFaturas.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && !this.hasFaturas && this.accountId;
    }

    get showWaitingForAccount() {
        return !this.isLoading && !this.errorMessage && !this.accountId;
    }

    togglePicker() {
        this.isPickerOpen = !this.isPickerOpen;
    }

    handleViewSelect(event) {
        const newView = event.currentTarget.dataset.value;
        this.isPickerOpen = false;
        if (newView === this.selectedView) {
            return;
        }
        this.selectedView = newView;
        if (this.accountId) {
            this.loadFaturas();
        }
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
    }

    handleRefresh() {
        if (this.accountId) {
            this.loadFaturas();
        }
    }

    handleRecordClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.recordId;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: OBJECT_API_NAME, actionName: 'view' }
        });
    }

    getCachedAccountId() {
        try {
            return window.sessionStorage.getItem(STORAGE_KEY);
        } catch (e) {
            return null;
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
