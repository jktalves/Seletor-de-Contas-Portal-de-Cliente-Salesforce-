import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import ACCOUNT_CONTEXT_CHANNEL from '@salesforce/messageChannel/AccountContextChannel__c';
import getContratos from '@salesforce/apex/ContratoPortalController.getContratos';

const STORAGE_KEY = 'accountSwitcher.selectedAccountId';
const GENERIC_ERROR = 'Não foi possível carregar os contratos.';
const OBJECT_API_NAME = 'Oportunidade_Aprovada__c';
const CONTACT_OBJECT_API_NAME = 'Contact';
const ENDERECO_OBJECT_API_NAME = 'Endere_o__c';
const VIEW_PADRAO = 'Todos';
const MIN_COLUMN_WIDTH = 60;
const ROWNUM_COLUMN_WIDTH = '3.5rem';

// Peso relativo de cada coluna — a largura % real é recalculada em
// colStyle() dividindo o peso da coluna pela soma dos pesos das colunas
// VISÍVEIS no modo de exibição atual (cada modo mostra um conjunto
// diferente de colunas, replicando as list views nativas da produção), de
// forma que a tabela sempre preenche 100% da largura disponível. Só vira
// px fixo quando o usuário arrasta a borda da coluna manualmente, igual a
// list view nativa.
// "Data de Início do Contrato" não entra: o perfil do portal não tem acesso
// de leitura (FLS) a Data_de_Inicio_do_Contrato__c, então mesmo configurada
// na list view nativa, essa coluna nunca aparece pro cliente de verdade —
// confirmado em 09/11/2026 comparando screenshots reais da produção.
const COLUMN_WEIGHTS = {
    numero: 9,
    dataEntrega: 16,
    terminoContrato: 15,
    contato: 17,
    endereco: 23,
    status: 8,
    valor: 12
};

const VIEWS = [
    { value: 'Todos', label: 'Todos' },
    { value: 'Ativos', label: 'Ativos' },
    { value: 'Encerrados', label: 'Encerrados' },
    { value: 'Novos', label: 'Pedidos novos' }
];

// Rótulo de cada coluna pra linha de metadados ("Classificado por X"),
// igual a list view nativa.
const FIELD_LABELS = {
    numero: 'Número',
    dataEntrega: 'Data Agendada para o Atendimento',
    terminoContrato: 'Término do contrato',
    contato: 'Contato',
    endereco: 'Endereço',
    status: 'Status',
    valor: 'Valor'
};

export default class ContratoLista extends NavigationMixin(LightningElement) {
    views = VIEWS;
    selectedView = VIEW_PADRAO;
    contratos = [];
    isLoading = true;
    errorMessage;
    accountId;
    isPickerOpen = false;
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
        // ("Contratos"). Nosso componente custom não faz isso por padrão,
        // então replicamos aqui para a aba do navegador ficar igual.
        document.title = 'Contratos';

        this.subscription = subscribe(this.messageContext, ACCOUNT_CONTEXT_CHANNEL, (message) => {
            this.handleAccountContext(message);
        });

        const cachedAccountId = this.getCachedAccountId();
        if (cachedAccountId) {
            this.accountId = cachedAccountId;
            this.loadContratos();
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
        this.loadContratos();
    }

    async loadContratos() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const data = await getContratos({ accountId: this.accountId, viewName: this.selectedView });
            this.contratos = await this.attachRecordUrls(data);
        } catch (error) {
            this.contratos = [];
            this.errorMessage = this.extractErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    attachRecordUrls(records) {
        return Promise.all(
            records.map(async (record) => {
                const [recordUrl, contatoUrl, enderecoUrl] = await Promise.all([
                    this[NavigationMixin.GenerateUrl]({
                        type: 'standard__recordPage',
                        attributes: { recordId: record.id, objectApiName: OBJECT_API_NAME, actionName: 'view' }
                    }),
                    record.contatoId
                        ? this[NavigationMixin.GenerateUrl]({
                              type: 'standard__recordPage',
                              attributes: { recordId: record.contatoId, objectApiName: CONTACT_OBJECT_API_NAME, actionName: 'view' }
                          })
                        : Promise.resolve(null),
                    record.enderecoId
                        ? this[NavigationMixin.GenerateUrl]({
                              type: 'standard__recordPage',
                              attributes: { recordId: record.enderecoId, objectApiName: ENDERECO_OBJECT_API_NAME, actionName: 'view' }
                          })
                        : Promise.resolve(null)
                ]);
                return {
                    ...record,
                    recordUrl,
                    contatoUrl,
                    enderecoUrl,
                    dataEntregaFormatada: this.formatDate(record.dataEntrega),
                    terminoContratoFormatado: this.formatDate(record.terminoContrato),
                    valorFormatado: this.formatCurrency(record.valor)
                };
            })
        );
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        // Date puro (sem hora) do Apex vem como "yyyy-mm-dd" — monta local
        // pra não sofrer deslocamento de fuso na conversão.
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

    get totalCount() {
        return this.contratos.length;
    }

    // Linha de metadados abaixo do dropdown de exibição, igual a list view
    // nativa: "X itens • Classificado por Y • Filtrado por Z - Status".
    get sortFieldLabel() {
        return FIELD_LABELS[this.sortField || 'numero'];
    }

    get listMetaText() {
        return `${this.totalCount} itens • Classificado por ${this.sortFieldLabel} • Filtrado por ${this.selectedViewLabel} - Status`;
    }

    get showListMeta() {
        return !this.isLoading && !this.errorMessage && !!this.accountId;
    }

    get sortedContratos() {
        const list = [...this.contratos];
        if (!this.sortField) {
            return list;
        }
        const field = this.sortField;
        const dir = this.sortDirection === 'desc' ? -1 : 1;
        const isDateField = field === 'dataEntrega' || field === 'terminoContrato';
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

    get isSortedByDataEntrega() {
        return this.sortField === 'dataEntrega';
    }

    get isSortedByStatus() {
        return this.sortField === 'status';
    }

    get isSortedByTerminoContrato() {
        return this.sortField === 'terminoContrato';
    }

    get isSortedByContato() {
        return this.sortField === 'contato';
    }

    get isSortedByEndereco() {
        return this.sortField === 'endereco';
    }

    get isSortedByValor() {
        return this.sortField === 'valor';
    }

    // Classe do <th>: coluna ativa na ordenação ganha a borda laranja, igual
    // a list view nativa do Salesforce.
    get numeroThClass() {
        return this.thClass(this.isSortedByNumero);
    }

    get dataEntregaThClass() {
        return this.thClass(this.isSortedByDataEntrega);
    }

    get statusThClass() {
        return this.thClass(this.isSortedByStatus);
    }

    get terminoContratoThClass() {
        return this.thClass(this.isSortedByTerminoContrato);
    }

    get contatoThClass() {
        return this.thClass(this.isSortedByContato);
    }

    get enderecoThClass() {
        return this.thClass(this.isSortedByEndereco);
    }

    get valorThClass() {
        return this.thClass(this.isSortedByValor);
    }

    thClass(isActive) {
        return isActive ? 'list-card__sortable-th list-card__sortable-th--active' : 'list-card__sortable-th';
    }

    // Quais colunas o modo de exibição atual mostra — replica exatamente o
    // conjunto de colunas da list view nativa equivalente na produção
    // (conferido em 06/11/2026). "Status" só aparece em "Todos", já que os
    // outros modos já estão filtrados por um status específico.
    get showDataEntrega() {
        return this.selectedView !== 'Encerrados';
    }

    get showTerminoContrato() {
        return this.selectedView !== 'Novos';
    }

    get showStatus() {
        return this.selectedView === 'Todos';
    }

    get showValor() {
        return this.selectedView !== 'Todos';
    }

    get visibleColumnFields() {
        const fields = ['numero', 'contato', 'endereco'];
        if (this.showDataEntrega) {
            fields.push('dataEntrega');
        }
        if (this.showTerminoContrato) {
            fields.push('terminoContrato');
        }
        if (this.showStatus) {
            fields.push('status');
        }
        if (this.showValor) {
            fields.push('valor');
        }
        return fields;
    }

    // Largura de cada coluna, aplicada via <colgroup> — assim todas as
    // células da coluna (th e td) acompanham o mesmo valor. Usa % (flexível,
    // recalculada a partir do peso da coluna sobre a soma dos pesos das
    // colunas visíveis) até o usuário arrastar a borda da coluna; a partir
    // daí vira px fixo.
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

    get dataEntregaColStyle() {
        return this.colStyle('dataEntrega');
    }

    get terminoContratoColStyle() {
        return this.colStyle('terminoContrato');
    }

    get contatoColStyle() {
        return this.colStyle('contato');
    }

    get enderecoColStyle() {
        return this.colStyle('endereco');
    }

    get statusColStyle() {
        return this.colStyle('status');
    }

    get valorColStyle() {
        return this.colStyle('valor');
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

    get isColumnMenuOpenDataEntrega() {
        return this.openColumnMenuField === 'dataEntrega';
    }

    get isColumnMenuOpenStatus() {
        return this.openColumnMenuField === 'status';
    }

    get isColumnMenuOpenTerminoContrato() {
        return this.openColumnMenuField === 'terminoContrato';
    }

    get isColumnMenuOpenContato() {
        return this.openColumnMenuField === 'contato';
    }

    get isColumnMenuOpenEndereco() {
        return this.openColumnMenuField === 'endereco';
    }

    get isColumnMenuOpenValor() {
        return this.openColumnMenuField === 'valor';
    }

    get numeroCellClass() {
        return this.wrapFields.has('numero') ? 'list-card__cell--wrap' : '';
    }

    get dataEntregaCellClass() {
        return this.wrapFields.has('dataEntrega') ? 'list-card__cell--wrap' : '';
    }

    get statusCellClass() {
        return this.wrapFields.has('status') ? 'list-card__cell--wrap' : '';
    }

    get terminoContratoCellClass() {
        return this.wrapFields.has('terminoContrato') ? 'list-card__cell--wrap' : '';
    }

    get contatoCellClass() {
        return this.wrapFields.has('contato') ? 'list-card__cell--wrap' : '';
    }

    get enderecoCellClass() {
        return this.wrapFields.has('endereco') ? 'list-card__cell--wrap' : '';
    }

    get valorCellClass() {
        return this.wrapFields.has('valor') ? 'list-card__cell--wrap' : '';
    }

    get displayedContratos() {
        return this.sortedContratos.map((c, idx) => ({ ...c, rowNumber: idx + 1 }));
    }

    get hasContratos() {
        return this.displayedContratos.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && !this.hasContratos && this.accountId;
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
            this.loadContratos();
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

    // Navegação pros registros relacionados (Contato/Endereço) exibidos
    // como link nas respectivas colunas.
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
