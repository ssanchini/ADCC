-module(database_mgr).

-behaviour(gen_server).

-export([
    aggiungi_nodo_a_ts/2,
    crea_nuovo_ts/1,
    lista_nodi_ts/1,
    rimuovi_nodo_da_ts/2,
    start_link/0
]).

% gen_server callbaks.
-export([
    code_change/3,
    init/1, 
    handle_call/3, 
    handle_cast/2, 
    handle_info/2, 
    terminate/2
]).

% Crea un nuovo spazio di tuple allocato in questo nodo
crea_nuovo_ts(TupleSpace) ->
    gen_server:call(?MODULE, {crea_ts, TupleSpace}).

% Aggiunge un nodo allo spazio di tuple
aggiungi_nodo_a_ts(Node, Space) -> 
    try 
        NodeInSpace = nodo_presente_nel_ts(node(), Space),
        if
            NodeInSpace ->
                gen_server:call({?MODULE, Node}, {enter_space, Space});
            true -> {error, {node_not_in_space, node(), Space}}
        end
    catch
        exit:{{nodedown,N},_} -> {error, {no_node, N}};
        _:Error -> {error, Error}
    end.

% Rimuove il nodo selezionato dallo spazio di tuple 
rimuovi_nodo_da_ts(Node, Space) when is_atom(Node), is_atom(Space) -> 
    try
        NodeInSpace = nodo_presente_nel_ts(node(), Space),
        if
            NodeInSpace ->
                gen_server:call({?MODULE, Node}, {exit_space, Space});
            true -> {error, {node_not_in_space, node(), Space}}
        end
    catch
        exit:{{nodedown,N},_} -> {error, {no_node, N}};
        _:Error -> {error, Error}
    end.

% Ritorna una lista di tutti i nodi collegati al TS
lista_nodi_ts(Space) -> 
    IsNodeInSpace = nodo_presente_nel_ts(node(), Space),
    if
        IsNodeInSpace -> gen_server:call(?MODULE, {nodi_del_ts, Space});
        true -> {error, {node_not_in_space, node(), Space}}
    end.

% Avvia un istanza del database da gen_server
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


% init/1 callback da gen_server.
init(_Args) ->
    process_flag(trap_exit, true),
    % Avvia il database mnesia con schema standard
    case init_cluster() of
        ok -> {ok, []};
        {error, Reason} -> {stop, Reason}
    end.

% handle_call/3 callback da gen_server.
handle_call({crea_ts, Name}, _From, _State) ->
    % Crea un nuovo TS con Name e avvia un nuovo ts_mgr
    Res = case crea_ts(Name) of
        ok -> ts_supervisor:add_space_manager(Name);
        Error -> Error
    end,
    {reply, Res, _State};
handle_call({enter_space, Space}, _From, _State) ->
    % Aggiunge questo nodo al TS e avvia un nuovo ts_mgr
    Res = case aggiungi_al_ts(Space) of
        ok -> ts_supervisor:add_space_manager(Space);
        Error -> Error
    end,
    {reply, Res, _State};
handle_call({exit_space, Space}, _From, _State) ->
    % Rimuove il nodo dal TS e ferma il ts_mgr
    Res = case rimuovi_dal_ts(Space) of
        ok -> ts_supervisor:del_space_manager(Space);
        Error -> Error
    end,
    {reply, Res, _State};
handle_call({nodi_del_ts, Space}, _From, _State) ->
    % Elenco di tutti i nodi collegati al TS
    Nodes = nodi_del_ts(Space),
    {reply, {ok, Nodes}, _State};
handle_call(stop, _From, _State) ->
    {stop, normal, stopped, _State};
handle_call(_Request, _From, _State) ->
    {reply, {error, bad_request}, _State}.

% handle_cast/2 callback da gen_server.
handle_cast(_Msg, _State) ->
    {noreply, _State}.

% handle_info/2 callback da gen_server.
handle_info(_Info, _State) ->
    {noreply, _State}.

% terminate/2 callback da gen_server.
terminate(_Reason, _State) ->
    ensure_stopped(),
    ok.

% code_change/3 callback da gen_server.
code_change(_OldVsn, _State, _Extra) ->
    {ok, _State}.

% Funzioni interne

% Qui ci assicuriamo che il database mnesia sia avviato correttamente
ensure_started() -> 
    mnesia:start(),
    wait_for(start).

% Qui ci assicuriamo che il database mnesia sia stato fermato
ensure_stopped() -> 
    mnesia:stop(),
    wait_for(stop).

% Attende che il db mnesia sia in start/stop 
wait_for(start) -> 
    case mnesia:system_info(is_running) of
        yes -> ok;
        no -> {error, mnesia_unexpectedly_not_running};
        stopping -> {error, mnesia_unexpectedly_stopping};
        starting -> 
            timer:sleep(1000),
            wait_for(start)
    end;
wait_for(stop) -> 
    case mnesia:system_info(is_running) of
        no -> ok;
        yes -> {error, mnesia_unexpectedly_running};
        starting -> {error, mnesia_unexpectedly_starting};
        stopping -> 
            timer:sleep(1000),
            wait_for(stop)
    end.

% Inizializza il cluster contenente tutti i nodi
init_cluster() ->
    try
        ok = ensure_started(),
        ok = sync_cluster(),
        ok = create_disc_schema(),
        ok = ensure_nodes_table(),
        ok = wait_for_tables(),
        ok = restart_space_managers(),
        ok
    catch
        error:{badmatch, {timeout, Tab}} -> {error, {cannot_find_tables, Tab}};
        error:{badmatch, Error} -> Error;
        _:Error -> {error, Error}
    end.

% Setta tutti i nodi come extra_db_nodes end se l'unione dello schema fallisce
% cancella lo schema e si sincronizza con il cluster.
sync_cluster() ->
    case mnesia:change_config(extra_db_nodes, nodes()) of
        {ok, _} -> ok;
        {error, {merge_schema_failed, _}} ->
            ok = ensure_stopped(),
            ok = mnesia:delete_schema([node()]),
            ok = ensure_started(),
            {ok, _} = mnesia:change_config(extra_db_nodes, nodes()),
            ok
    end.

% Crea uno schema mnesia come disc_copys..
create_disc_schema() -> 
    case mnesia:change_table_copy_type(schema, node(), disc_copies) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, schema, _, _}} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

% Si assicura che la tabella dei nodi sia presente nel cluster corrente
% ogni nodo deve avere questa tabella quindi se non è presente lo crea
ensure_nodes_table() ->
    Exist = lists:member(nodes, mnesia:system_info(tables)),
    if 
        Exist -> 
            % Controlla se la tabella dei nodi è un disc_copy o remoto;
            % se è remoto o ram_copies lo copia localmente
            case mnesia:table_info(nodes, storage_type) of
                disc_copies -> ok;
                _ -> 
                    case mnesia:add_table_copy(nodes, node(), disc_copies) of
                        {atomic, ok} -> ok;
                        {aborted, {already_exists, nodes, _}} -> ok;
                        {aborted, Reason} -> {error, Reason}
                    end
            end;
        true -> 
            % Crea una nuova tabella di nodi
            case mnesia:create_table(nodes, 
                [{type, bag}, {disc_copies, [node()]}]) of
                {atomic, ok} -> ok;
                {aborted, {already_exists, nodes}} -> ok;
                {aborted, Reason} -> {error, Reason}
            end
    end.

% Attende che tutte le tabelle memorizzate localmente nel nodo siano completamente 
% caricate e forza il caricamente in caso di fallimento
wait_for_tables() ->
    Tables = lists:filter(fun(Table) ->
        mnesia:table_info(Table, storage_type) =:= disc_copies
    end, mnesia:system_info(tables)),
    case mnesia:wait_for_tables(Tables, 2000) of
        ok -> ok;
        {timeout, MissingTables} -> 
            lists:foreach(fun(MissingTab) ->
                mnesia:force_load_table(MissingTab)
            end, MissingTables),
            ok
    end.

% Riavvia ts_managager per tutti gli spazi in cui si trova il nodo locale.
% Questa funzione è utile quando il nodo viene riavviato e tutti gli spazi 
% sono ancora presenti in modo che i loro ts_mgr vengano riavviati
restart_space_managers() ->
    {atomic, SpacesRecords} = mnesia:transaction(fun() ->
        mnesia:match_object({nodes, '_', node()})
    end),
    lists:foreach(fun({_,Space,_Node}) ->
        ok = ts_supervisor:add_space_manager(Space)
    end, SpacesRecords),
    ok.

% Crea una nuova TS con Name con errore se il nome esiste
crea_ts(Name) ->
    try
        {atomic, ok} = mnesia:create_table(Name, [{type, bag}, {disc_copies, [node()]}]),
        {atomic, ok} = aggiungi_nodo_a_tabella(Name),
        ok
    catch
        error:{badmatch, {aborted, Error}} -> {error, Error}
    end.

% Aggiunge il nodo alla TS con errore se già presente
aggiungi_al_ts(Space) ->
    try
        {atomic, ok} = mnesia:add_table_copy(Space, node(), disc_copies),
        {atomic, ok} = aggiungi_nodo_a_tabella(Space),
        ok
    catch
        error:{badmatch,{aborted, Error}} -> {error, Error}
    end.

% Rimuove il nodo dalla TS con errore se non presente
rimuovi_dal_ts(Space) ->
    try
        {atomic, ok} = mnesia:del_table_copy(Space, node()),
        {atomic, ok} = rimuovi_nodo_da_tabella(Space),
        ok
    catch
        error:{badmatch, {aborted, Error}} -> {error, Error}
    end.

% Mostra l'elenco di tutti i nodi della TS.
nodi_del_ts(Space) ->
    case mnesia:transaction(fun() ->
        mnesia:read(nodes, Space)
    end) of
        {atomic, Nodes} -> lists:map(fun({_,_,E}) -> E end, Nodes);
        {aborted, _} -> []
    end.

% Restituisce true se il nodo è presente nella TS altrimenti false
nodo_presente_nel_ts(Node, Space) ->
    lists:member(Node, nodi_del_ts(Space)).

% Aggiunge il nodo alla TS presente nelle tabelle
% Utilizziamo questa funzione perché restituisce unsafe_result come quelli di mnesia.
aggiungi_nodo_a_tabella(Space)->
    mnesia:transaction(fun() -> mnesia:write({nodes, Space, node()}) end).

% Rimuove il nodo corrente dalla TS data all'interno della tabella condivisa dei nodi.
rimuovi_nodo_da_tabella(Space) ->
    mnesia:transaction(fun() -> mnesia:delete_object({nodes, Space, node()}) end).
