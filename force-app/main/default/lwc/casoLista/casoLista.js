import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import ACCOUNT_CONTEXT_CHANNEL from '@salesforce/messageChannel/AccountContextChannel__c';
import getCasos from '@salesforce/apex/CasoPortalController.getCasos';

const STORAGE_KEY = 'accountSwitcher.selectedAccountId';
const GENERIC_ERROR = 'Não foi possível carregar os chamados.';
const OBJECT_API_NAME = 'Case';
const CONTACT_OBJECT_API_NAME = 'Contact';
const ENDERECO_OBJECT_API_NAME = 'Endere_o__c';
const CONTRATO_OBJECT_API_NAME = 'Oportunidade_Aprovada__c';
const MIN_COLUMN_WIDTH = 60;
const ROWNUM_COLUMN_WIDTH = '3.5rem';

// Peso relativo de cada coluna — a largura % real é recalculada em
// colStyle() dividindo o peso da coluna pela soma dos pesos das colunas
// VISÍVEIS no modo de exibição atual (cada modo mostra um conjunto
// diferente de colunas, replicando as list views nativas da produção), de
// forma que a tabela sempre preenche 100% da largura disponível. Só vira
// px fixo quando o usuário arrasta a borda da coluna manualmente, igual a
// list view nativa.
// Peso relativo de cada coluna — a largura % real é recalculada em
// colStyle() dividindo o peso da coluna pela soma dos pesos das colunas
// VISÍVEIS no modo de exibição atual (cada modo mostra um conjunto
// diferente de colunas, replicando as list views nativas da produção), de
// forma que a tabela sempre preenche 100% da largura disponível. Só vira
// px fixo quando o usuário arrasta a borda da coluna manualmente, igual a
// list view nativa.
// Contrato e Último Comentário foram removidos: o perfil do portal não tem
// acesso de leitura (FLS) a Oportunidade_Aprovada__c nem ltimo_coment_rio__c
// em Case, então a list view nativa configura essas colunas mas elas nunca
// aparecem pro cliente de verdade — confirmado em 09/11/2026 comparando
// screenshots reais da produção com a definição das list views.
const COLUMN_WEIGHTS = {
    numero: 10,
    assunto: 18,
    contato: 15,
    usuario: 14,
    endereco: 14,
    status: 10,
    dataProgramada: 11,
    dataFechamento: 14
};

// Padrão da aba (tab): "Todos" — o widget compacto da Início continua com o
// padrão antigo ("Em_andamento") porque passa initialView explícito.
const VIEW_PADRAO = 'Todos';

const VIEWS = [
    { value: 'Devolucoes', label: 'Devoluções' },
    { value: 'Encerrados', label: 'Encerrados' },
    { value: 'Entregas', label: 'Entregas' },
    { value: 'Outros', label: 'Suporte' },
    { value: 'Todos', label: 'Todos' },
    { value: 'Trocas', label: 'Trocas' }
];

// Modo compacto (widget da página Início): mantém o conjunto de colunas
// enxuto que já existia, via lightning-datatable — sem mexer no que o
// usuário já validou lá.
const COLUMNS_COMPACT = [
    { label: 'Número', fieldName: 'recordUrl', type: 'url', typeAttributes: { label: { fieldName: 'numero' }, target: '_self' } },
    { label: 'Assunto', fieldName: 'assunto', type: 'text' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Data Programada', fieldName: 'dataProgramada', type: 'date-local' }
];

export default class CasoLista extends NavigationMixin(LightningElement) {
    // Modo compacto: usado no widget da página Início (sem ícone, sem
    // dropdown de modos, título em caixa alta, lista limitada + "Exibir tudo").
    @api compact = false;
    @api maxRows;
    @api initialView;

    views = VIEWS;
    columns = COLUMNS_COMPACT;
    selectedView = VIEW_PADRAO;
    casos = [];
    isLoading = true;
    errorMessage;
    accountId;
    isPickerOpen = false;
    isFilterPanelOpen = false;
    searchTerm = '';
    sortField;
    sortDirection = 'asc';
    subscription;

    // Menu "Quebrar texto / Cortar texto" por coluna (igual list view nativa).
    // openColumnMenuField guarda qual coluna tem o menu aberto agora (só uma
    // por vez); wrapFields guarda o conjunto de colunas em modo "Quebrar texto".
    openColumnMenuField;
    wrapFields = new Set();

    // Redimensionamento de coluna (arrastar a borda), igual a list view nativa.
    // Vazio = usa a largura % padrão (flexível); ganha uma entrada em px só
    // depois que o usuário arrasta aquela coluna manualmente.
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

    toggleFilterPanel() {
        this.isFilterPanelOpen = !this.isFilterPanelOpen;
    }

    handleFilterOverlayClick(event) {
        event.stopPropagation();
        this.isFilterPanelOpen = false;
    }

    handleFilterPanelClose(event) {
        event.stopPropagation();
        this.isFilterPanelOpen = false;
    }

    get filterButtonClass() {
        return this.isFilterPanelOpen ? 'list-card__filter list-card__filter--active' : 'list-card__filter';
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
        // Mede a largura realmente renderizada (seja ela % ou já um px
        // de um arraste anterior) pra começar o arraste sem salto.
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
        // ("Chamados"). Nosso componente custom não faz isso por padrão,
        // então replicamos aqui para a aba do navegador ficar igual.
        document.title = 'Chamados';

        if (this.initialView) {
            this.selectedView = this.initialView;
        }

        this.subscription = subscribe(this.messageContext, ACCOUNT_CONTEXT_CHANNEL, (message) => {
            this.handleAccountContext(message);
        });

        const cachedAccountId = this.getCachedAccountId();
        if (cachedAccountId) {
            this.accountId = cachedAccountId;
            this.loadCasos();
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
        this.loadCasos();
    }

    async loadCasos() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const data = await getCasos({ accountId: this.accountId, viewName: this.selectedView });
            this.casos = await this.attachRecordUrls(data);
        } catch (error) {
            this.casos = [];
            this.errorMessage = this.extractErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    attachRecordUrls(records) {
        return Promise.all(
            records.map(async (record) => {
                const [recordUrl, contatoUrl, usuarioUrl, enderecoUrl, contratoUrl] = await Promise.all([
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
                    record.usuarioId
                        ? this[NavigationMixin.GenerateUrl]({
                              type: 'standard__recordPage',
                              attributes: { recordId: record.usuarioId, objectApiName: CONTACT_OBJECT_API_NAME, actionName: 'view' }
                          })
                        : Promise.resolve(null),
                    record.enderecoId
                        ? this[NavigationMixin.GenerateUrl]({
                              type: 'standard__recordPage',
                              attributes: { recordId: record.enderecoId, objectApiName: ENDERECO_OBJECT_API_NAME, actionName: 'view' }
                          })
                        : Promise.resolve(null),
                    record.contratoId
                        ? this[NavigationMixin.GenerateUrl]({
                              type: 'standard__recordPage',
                              attributes: { recordId: record.contratoId, objectApiName: CONTRATO_OBJECT_API_NAME, actionName: 'view' }
                          })
                        : Promise.resolve(null)
                ]);
                return {
                    ...record,
                    recordUrl,
                    contatoUrl,
                    usuarioUrl,
                    enderecoUrl,
                    contratoUrl,
                    dataProgramadaFormatada: this.formatDate(record.dataProgramada),
                    dataAberturaFormatada: this.formatDateTime(record.dataAbertura),
                    dataFechamentoFormatada: this.formatDateTime(record.dataFechamento)
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

    formatDateTime(value) {
        if (!value) {
            return '';
        }
        return new Date(value).toLocaleString('pt-BR', {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    get selectedViewLabel() {
        const found = this.views.find((v) => v.value === this.selectedView);
        return found ? found.label : '';
    }

    // Busca client-side (quick-find) sobre o que já foi carregado da conta
    // ativa/modo de exibição atual — não dispara nova chamada ao Apex.
    get filteredCasos() {
        if (!this.searchTerm) {
            return this.casos;
        }
        const term = this.searchTerm.toLowerCase();
        return this.casos.filter((c) => {
            return (
                (c.numero && c.numero.toLowerCase().includes(term)) ||
                (c.assunto && c.assunto.toLowerCase().includes(term)) ||
                (c.contato && c.contato.toLowerCase().includes(term)) ||
                (c.usuario && c.usuario.toLowerCase().includes(term)) ||
                (c.endereco && c.endereco.toLowerCase().includes(term)) ||
                (c.statusCliente && c.statusCliente.toLowerCase().includes(term))
            );
        });
    }

    get totalCount() {
        return this.filteredCasos.length;
    }

    // Ordenação client-side (clicar no cabeçalho da coluna) — modo tab
    // (não compacto) apenas, sobre o que já foi carregado/filtrado.
    get sortedCasos() {
        const list = [...this.filteredCasos];
        if (!this.sortField) {
            return list;
        }
        const field = this.sortField;
        const dir = this.sortDirection === 'desc' ? -1 : 1;
        const isDateField = field === 'dataProgramada' || field === 'dataFechamento';

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
            return String(valA).localeCompare(String(valB), 'pt-BR', { numeric: true, sensitivity: 'base' }) * dir;
        });
    }

    get sortIconName() {
        return this.sortDirection === 'desc' ? 'utility:arrowdown' : 'utility:arrowup';
    }

    get isSortedByNumero() {
        return this.sortField === 'numero';
    }

    get isSortedByAssunto() {
        return this.sortField === 'assunto';
    }

    get isSortedByContato() {
        return this.sortField === 'contato';
    }

    get isSortedByUsuario() {
        return this.sortField === 'usuario';
    }

    get isSortedByEndereco() {
        return this.sortField === 'endereco';
    }

    get isSortedByStatus() {
        return this.sortField === 'status';
    }

    get isSortedByDataProgramada() {
        return this.sortField === 'dataProgramada';
    }

    get isSortedByDataFechamento() {
        return this.sortField === 'dataFechamento';
    }

    // Classe do <th>: coluna ativa na ordenação ganha a borda laranja, igual
    // a list view nativa do Salesforce.
    get numeroThClass() {
        return this.thClass(this.isSortedByNumero);
    }

    get assuntoThClass() {
        return this.thClass(this.isSortedByAssunto);
    }

    get contatoThClass() {
        return this.thClass(this.isSortedByContato);
    }

    get usuarioThClass() {
        return this.thClass(this.isSortedByUsuario);
    }

    get enderecoThClass() {
        return this.thClass(this.isSortedByEndereco);
    }

    get statusThClass() {
        return this.thClass(this.isSortedByStatus);
    }

    get dataProgramadaThClass() {
        return this.thClass(this.isSortedByDataProgramada);
    }

    get dataFechamentoThClass() {
        return this.thClass(this.isSortedByDataFechamento);
    }

    thClass(isActive) {
        return isActive ? 'list-card__sortable-th list-card__sortable-th--active' : 'list-card__sortable-th';
    }

    // Quais colunas o modo de exibição atual mostra — replica exatamente o
    // conjunto de colunas da list view nativa equivalente na produção,
    // conferido com screenshots reais em 09/11/2026 (Todos/Devoluções/
    // Encerrados/Entregas/Suporte/Trocas; Em_andamento/Novo não têm list
    // view nativa equivalente, usam o mesmo conjunto de "Todos").
    get showAssunto() {
        return !['Entregas', 'Devolucoes', 'Trocas'].includes(this.selectedView);
    }

    get showEndereco() {
        return ['Todos', 'Em_andamento', 'Novo'].includes(this.selectedView);
    }

    get showStatus() {
        return this.selectedView !== 'Encerrados';
    }

    get showDataProgramada() {
        return this.selectedView !== 'Encerrados';
    }

    get showDataFechamento() {
        return ['Todos', 'Em_andamento', 'Novo', 'Encerrados'].includes(this.selectedView);
    }

    // Em "Trocas" a list view nativa mostra Usuário por último (depois de
    // Status/Data Programada); nas demais views ele vem logo após Contato.
    // Mesma coluna, duas posições possíveis — mutuamente exclusivas.
    get showUsuarioEarly() {
        return this.selectedView !== 'Trocas';
    }

    get showUsuarioLate() {
        return this.selectedView === 'Trocas';
    }

    get visibleColumnFields() {
        const fields = ['numero', 'contato', 'usuario'];
        if (this.showAssunto) {
            fields.push('assunto');
        }
        if (this.showEndereco) {
            fields.push('endereco');
        }
        if (this.showStatus) {
            fields.push('status');
        }
        if (this.showDataProgramada) {
            fields.push('dataProgramada');
        }
        if (this.showDataFechamento) {
            fields.push('dataFechamento');
        }
        return fields;
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

    get assuntoColStyle() {
        return this.colStyle('assunto');
    }

    get contatoColStyle() {
        return this.colStyle('contato');
    }

    get usuarioColStyle() {
        return this.colStyle('usuario');
    }

    get enderecoColStyle() {
        return this.colStyle('endereco');
    }

    get statusColStyle() {
        return this.colStyle('status');
    }

    get dataProgramadaColStyle() {
        return this.colStyle('dataProgramada');
    }

    get dataFechamentoColStyle() {
        return this.colStyle('dataFechamento');
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

    // Abre/fecha o menu "Quebrar texto / Cortar texto" da coluna clicada, sem
    // disparar a ordenação (que fica no onclick do <th> por fora).
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

    get isColumnMenuOpenAssunto() {
        return this.openColumnMenuField === 'assunto';
    }

    get isColumnMenuOpenContato() {
        return this.openColumnMenuField === 'contato';
    }

    get isColumnMenuOpenUsuario() {
        return this.openColumnMenuField === 'usuario';
    }

    get isColumnMenuOpenEndereco() {
        return this.openColumnMenuField === 'endereco';
    }

    get isColumnMenuOpenStatus() {
        return this.openColumnMenuField === 'status';
    }

    get isColumnMenuOpenDataProgramada() {
        return this.openColumnMenuField === 'dataProgramada';
    }

    get isColumnMenuOpenDataFechamento() {
        return this.openColumnMenuField === 'dataFechamento';
    }

    get numeroCellClass() {
        return this.wrapFields.has('numero') ? 'list-card__cell--wrap' : '';
    }

    get assuntoCellClass() {
        return this.wrapFields.has('assunto') ? 'list-card__cell--wrap' : '';
    }

    get contatoCellClass() {
        return this.wrapFields.has('contato') ? 'list-card__cell--wrap' : '';
    }

    get usuarioCellClass() {
        return this.wrapFields.has('usuario') ? 'list-card__cell--wrap' : '';
    }

    get enderecoCellClass() {
        return this.wrapFields.has('endereco') ? 'list-card__cell--wrap' : '';
    }

    get statusCellClass() {
        return this.wrapFields.has('status') ? 'list-card__cell--wrap' : '';
    }

    get dataProgramadaCellClass() {
        return this.wrapFields.has('dataProgramada') ? 'list-card__cell--wrap' : '';
    }

    get dataFechamentoCellClass() {
        return this.wrapFields.has('dataFechamento') ? 'list-card__cell--wrap' : '';
    }

    get displayedCasos() {
        const list = this.sortedCasos;
        const limited = this.compact && this.maxRows ? list.slice(0, this.maxRows) : list;
        return limited.map((c, idx) => ({ ...c, rowNumber: idx + 1 }));
    }

    get hasCasos() {
        return this.displayedCasos.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && !this.hasCasos && this.accountId;
    }

    get showWaitingForAccount() {
        return !this.isLoading && !this.errorMessage && !this.accountId;
    }

    get showViewAllLink() {
        return this.compact && this.hasCasos;
    }

    togglePicker() {
        this.isPickerOpen = !this.isPickerOpen;
    }

    handleViewAllClick() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'case' }
        });
    }

    handleViewSelect(event) {
        const newView = event.currentTarget.dataset.value;
        this.isPickerOpen = false;
        if (newView === this.selectedView) {
            return;
        }
        this.selectedView = newView;
        if (this.accountId) {
            this.loadCasos();
        }
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
    }

    handleRefresh() {
        if (this.accountId) {
            this.loadCasos();
        }
    }

    // Navegação SPA (sem recarregar a página) pro registro do caso, usado
    // pela tabela customizada da aba (modo não compacto).
    handleRecordClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.recordId;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: OBJECT_API_NAME, actionName: 'view' }
        });
    }

    // Navegação pros registros relacionados (Contato/Usuário/Endereço)
    // exibidos como link nas respectivas colunas.
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
