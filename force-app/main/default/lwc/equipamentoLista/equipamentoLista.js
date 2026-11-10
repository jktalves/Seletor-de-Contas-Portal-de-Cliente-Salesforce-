import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import ACCOUNT_CONTEXT_CHANNEL from '@salesforce/messageChannel/AccountContextChannel__c';
import getEquipamentos from '@salesforce/apex/EquipamentoPortalController.getEquipamentos';

const STORAGE_KEY = 'accountSwitcher.selectedAccountId';
const GENERIC_ERROR = 'Não foi possível carregar os equipamentos.';
const OBJECT_API_NAME = 'Equipamento__c';
const CONTRATO_OBJECT_API_NAME = 'Oportunidade_Aprovada__c';
const CONTACT_OBJECT_API_NAME = 'Contact';
const VIEW_PADRAO = 'Todos';
const MIN_COLUMN_WIDTH = 60;
const ROWNUM_COLUMN_WIDTH = '3.5rem';

// Largura padrão de cada coluna em % (proporcional, se adapta ao tamanho da
// tela — sem barra de rolagem em monitores pequenos). Só vira px fixo quando
// o usuário arrasta a borda da coluna manualmente, igual a list view nativa.
const DEFAULT_COLUMN_WIDTHS_PERCENT = {
    numero: 12,
    descricao: 24,
    contrato: 16,
    dataEntrega: 14,
    usuario: 16,
    valorLocacao: 9,
    valorGarantia: 9
};

// A produção só tem 2 modos nessa aba: "Equipamentos Alugados" (nosso
// "Todos") e "Recente(s)" — conferido com screenshot real em 09/11/2026.
// "Locado"/"Em_Espera" continuam existindo no Apex (categorização acordada
// com o usuário em 17/09/2026) mas não ficam expostos no dropdown.
const VIEWS = [
    { value: 'Todos', label: 'Equipamentos Alugados' },
    { value: 'Recentes', label: 'Recente(s)' }
];

export default class EquipamentoLista extends NavigationMixin(LightningElement) {
    views = VIEWS;
    selectedView = VIEW_PADRAO;
    equipamentos = [];
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
        // ("Equipamentos"). Nosso componente custom não faz isso por padrão,
        // então replicamos aqui para a aba do navegador ficar igual.
        document.title = 'Equipamentos';

        this.subscription = subscribe(this.messageContext, ACCOUNT_CONTEXT_CHANNEL, (message) => {
            this.handleAccountContext(message);
        });

        const cachedAccountId = this.getCachedAccountId();
        if (cachedAccountId) {
            this.accountId = cachedAccountId;
            this.loadEquipamentos();
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
        this.loadEquipamentos();
    }

    async loadEquipamentos() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const data = await getEquipamentos({ accountId: this.accountId, viewName: this.selectedView });
            this.equipamentos = await this.attachRecordUrls(data);
        } catch (error) {
            this.equipamentos = [];
            this.errorMessage = this.extractErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    attachRecordUrls(records) {
        return Promise.all(
            records.map(async (record) => {
                const [recordUrl, contratoUrl, usuarioUrl] = await Promise.all([
                    this[NavigationMixin.GenerateUrl]({
                        type: 'standard__recordPage',
                        attributes: { recordId: record.id, objectApiName: OBJECT_API_NAME, actionName: 'view' }
                    }),
                    record.contratoId
                        ? this[NavigationMixin.GenerateUrl]({
                              type: 'standard__recordPage',
                              attributes: { recordId: record.contratoId, objectApiName: CONTRATO_OBJECT_API_NAME, actionName: 'view' }
                          })
                        : Promise.resolve(null),
                    record.usuarioId
                        ? this[NavigationMixin.GenerateUrl]({
                              type: 'standard__recordPage',
                              attributes: { recordId: record.usuarioId, objectApiName: CONTACT_OBJECT_API_NAME, actionName: 'view' }
                          })
                        : Promise.resolve(null)
                ]);
                return {
                    ...record,
                    recordUrl,
                    contratoUrl,
                    usuarioUrl,
                    dataEntregaFormatada: this.formatDate(record.dataEntrega),
                    valorLocacaoFormatado: this.formatCurrency(record.valorLocacao),
                    valorGarantiaFormatado: this.formatCurrency(record.valorGarantia)
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

    get filteredEquipamentos() {
        if (!this.searchTerm) {
            return this.equipamentos;
        }
        const term = this.searchTerm.toLowerCase();
        return this.equipamentos.filter((e) => {
            return (
                (e.numero && e.numero.toLowerCase().includes(term)) ||
                (e.descricao && e.descricao.toLowerCase().includes(term)) ||
                (e.contrato && e.contrato.toLowerCase().includes(term)) ||
                (e.usuario && e.usuario.toLowerCase().includes(term))
            );
        });
    }

    get totalCount() {
        return this.filteredEquipamentos.length;
    }

    get sortedEquipamentos() {
        const list = [...this.filteredEquipamentos];
        if (!this.sortField) {
            return list;
        }
        const field = this.sortField;
        const dir = this.sortDirection === 'desc' ? -1 : 1;
        const isDateField = field === 'dataEntrega';
        const isNumberField = field === 'valorLocacao' || field === 'valorGarantia';

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

    get isSortedByDescricao() {
        return this.sortField === 'descricao';
    }

    get isSortedByContrato() {
        return this.sortField === 'contrato';
    }

    get isSortedByDataEntrega() {
        return this.sortField === 'dataEntrega';
    }

    get isSortedByUsuario() {
        return this.sortField === 'usuario';
    }

    get isSortedByValorLocacao() {
        return this.sortField === 'valorLocacao';
    }

    get isSortedByValorGarantia() {
        return this.sortField === 'valorGarantia';
    }

    // Classe do <th>: coluna ativa na ordenação ganha a borda laranja, igual
    // a list view nativa do Salesforce.
    get numeroThClass() {
        return this.thClass(this.isSortedByNumero);
    }

    get descricaoThClass() {
        return this.thClass(this.isSortedByDescricao);
    }

    get contratoThClass() {
        return this.thClass(this.isSortedByContrato);
    }

    get dataEntregaThClass() {
        return this.thClass(this.isSortedByDataEntrega);
    }

    get usuarioThClass() {
        return this.thClass(this.isSortedByUsuario);
    }

    get valorLocacaoThClass() {
        return this.thClass(this.isSortedByValorLocacao);
    }

    get valorGarantiaThClass() {
        return this.thClass(this.isSortedByValorGarantia);
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
        const fraction = DEFAULT_COLUMN_WIDTHS_PERCENT[field] / 100;
        return `width: calc((100% - ${ROWNUM_COLUMN_WIDTH}) * ${fraction})`;
    }

    get numeroColStyle() {
        return this.colStyle('numero');
    }

    get descricaoColStyle() {
        return this.colStyle('descricao');
    }

    get contratoColStyle() {
        return this.colStyle('contrato');
    }

    get dataEntregaColStyle() {
        return this.colStyle('dataEntrega');
    }

    get usuarioColStyle() {
        return this.colStyle('usuario');
    }

    get valorLocacaoColStyle() {
        return this.colStyle('valorLocacao');
    }

    get valorGarantiaColStyle() {
        return this.colStyle('valorGarantia');
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

    get isColumnMenuOpenDescricao() {
        return this.openColumnMenuField === 'descricao';
    }

    get isColumnMenuOpenContrato() {
        return this.openColumnMenuField === 'contrato';
    }

    get isColumnMenuOpenDataEntrega() {
        return this.openColumnMenuField === 'dataEntrega';
    }

    get isColumnMenuOpenUsuario() {
        return this.openColumnMenuField === 'usuario';
    }

    get isColumnMenuOpenValorLocacao() {
        return this.openColumnMenuField === 'valorLocacao';
    }

    get isColumnMenuOpenValorGarantia() {
        return this.openColumnMenuField === 'valorGarantia';
    }

    get numeroCellClass() {
        return this.wrapFields.has('numero') ? 'list-card__cell--wrap' : '';
    }

    get descricaoCellClass() {
        return this.wrapFields.has('descricao') ? 'list-card__cell--wrap' : '';
    }

    get contratoCellClass() {
        return this.wrapFields.has('contrato') ? 'list-card__cell--wrap' : '';
    }

    get dataEntregaCellClass() {
        return this.wrapFields.has('dataEntrega') ? 'list-card__cell--wrap' : '';
    }

    get usuarioCellClass() {
        return this.wrapFields.has('usuario') ? 'list-card__cell--wrap' : '';
    }

    get valorLocacaoCellClass() {
        return this.wrapFields.has('valorLocacao') ? 'list-card__cell--wrap' : '';
    }

    get valorGarantiaCellClass() {
        return this.wrapFields.has('valorGarantia') ? 'list-card__cell--wrap' : '';
    }

    get displayedEquipamentos() {
        return this.sortedEquipamentos.map((e, idx) => ({ ...e, rowNumber: idx + 1 }));
    }

    get hasEquipamentos() {
        return this.displayedEquipamentos.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && !this.hasEquipamentos && this.accountId;
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
            this.loadEquipamentos();
        }
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
    }

    handleRefresh() {
        if (this.accountId) {
            this.loadEquipamentos();
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

    // Navegação pros registros relacionados (Contrato/Usuário) exibidos como
    // link nas respectivas colunas.
    handleRelatedRecordClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.recordId;
        const objectApiName = event.currentTarget.dataset.object;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
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
