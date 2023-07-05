-module(ts_mgr).

-behaviour(gen_server).

-export([
    start_link/1,
    subscribe_for_pattern/3
]).

% gen_server callbacks.
-export([
    init/1, 
    handle_call/3, 
    handle_cast/2, 
    handle_info/2, 
    terminate/2, 
    code_change/3
]).

-record(tsstate, {space}).

% avvia un istanza di ts_mgr per lo spazio di tuple dato
start_link(TupleSpace) ->
    gen_server:start_link({local, TupleSpace}, ?MODULE, TupleSpace, []).

% Questa funzione rimane in controllo di tutte le tuple inserite nello spazio e le confronta tutte
% con il modello dato. se vi è una corrispondenza (o scade il timeout) l'ascolto viene interrotto
% e viene restituito errore o il risultato
subscribe_for_pattern(Space, Pattern, Timeout) ->
    mnesia:subscribe({table, Space, simple}),
    receive
        {mnesia_table_event, {write, {Space, Size, NewTuple}, _AId}} when Size =:= tuple_size(Pattern) ->
            mnesia:unsubscribe({table, Space, simple}),
            PtrnMatches = match(Pattern, NewTuple),
            if
                PtrnMatches -> {ok, NewTuple};
                true -> subscribe_for_pattern(Space, Pattern, Timeout)
            end
    after
        Timeout ->
            mnesia:unsubscribe({table, Space, simple}),
            {error, timeout}
    end.

% Eseguiamo le callbacks al gen_server 
init(TupleSpace) ->
    process_flag(trap_exit, true),
    {ok, #tsstate{space = TupleSpace}}.

% handle_call/3 callback al gen_server.
handle_call({read_tuple, Pattern}, _From, State) ->
    Res = read_tuple(State#tsstate.space, Pattern),
    {reply, Res, State};
handle_call({write_tuple, Tuple}, _From, State) ->
    Res = write_tuple(State#tsstate.space, Tuple),
    {reply, Res, State};
handle_call({delete_tuple, Tuple}, _From, State) ->
    Res = delete_tuple(State#tsstate.space, Tuple),
    {reply, Res, State};
handle_call(stop, _From, _State) ->
    {stop, normal, stopped, _State};
handle_call(_Request, _From, _State) ->
    {reply, {error, bad_request}, _State}.

% handle_cast/2 callback al gen_server.
handle_cast(_Msg, _State) ->
    {noreply, _State}.

% handle_info/2 callback al gen_server.
handle_info(_Info, _State) ->
    {noreply, _State}.

% terminate/2 callback al gen_server.
terminate(_Reason, _State) ->
    ok.

% code_change/3 callback al gen_server.
code_change(_OldVsn, _State, _Extra) ->
    {ok, _State}.

% Funzioni interne

% Legge dati dallo spazio di Tuple.
read_tuple(Space, Pattern) -> 
    case mnesia:transaction(fun() ->
        lists:filter(fun(T) -> 
            match(Pattern, element(3,T)) 
        end, mnesia:read({Space, tuple_size(Pattern)}))
    end) of
        {atomic, []} -> {error, no_tuples};
        {atomic, [T|_]} -> {ok, element(3,T)};
        {aborted, Reason} -> {error, Reason}
    end.

% Inserisce dati nello spazio di tuple
write_tuple(_, {}) -> ok;
write_tuple(Space, Tuple) -> 
    case mnesia:transaction(fun() ->
        mnesia:write({Space, tuple_size(Tuple), Tuple})
    end) of
        {atomic, _} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

% Rimuove i dati passati dal comando allo spazio di tuple
delete_tuple(_, {}) -> ok;
delete_tuple(Space, Tuple) -> 
    case mnesia:transaction(fun() ->
        % cerca i risultati 
        ReadResult = lists:filter(fun(T) -> match(Tuple, element(3,T)) end, mnesia:read({Space, tuple_size(Tuple)})),
        % se il pattern matching è presente rimuove i dati altrimenti rimane in attesa fino 
        case ReadResult of
            [] -> mnesia:abort({no_tuples});
            [_] -> mnesia:delete_object({Space, tuple_size(Tuple), Tuple})
        end        
    end) of
        {atomic, _} -> ok;
        {aborted, {no_tuples}} -> {error, no_tuples};
        {aborted, Reason} -> {error, Reason}
    end.
% Dato un pattern matching e una tupla verificarne la presenza all'interno di essa.
% i dati del pattern matching vengono letti come una lista all'interno della tabella, 
% ed ogni elemento è ricercato ricorsivamente in questa lista
match(Pattern, Tuple) when is_tuple(Pattern), is_tuple(Tuple) -> 
    match(tuple_to_list(Pattern), tuple_to_list(Tuple));
match([], []) -> true;
match(Pattern, Tuple) when is_list(Pattern), is_list(Tuple) ->
    if
        (length(Pattern) == 0) orelse (length(Tuple) == 0) ->
            false;
        true ->
            [PatternHd | PatternTl] = Pattern,
            [TupleHd | TupleTl] = Tuple,
            ElementMatch = match_element(PatternHd, TupleHd),
            if
                ElementMatch -> match(PatternTl, TupleTl);
                true -> false
            end
    end.

% Dati due elementi, E1 un elemento da un modello ed E2 elemento di una tupla, si verifica che i 
% due elementi corrispondono. Se E1 è l'atomo "any" la funzione restituisce vero senza controllo
% altimenti i loro elementi vengono controllati e matchati 
match_element(E1, _) when E1 == any -> true;
match_element(E1, E2) when is_tuple(E1), is_tuple(E2) -> match(E1, E2);
match_element(E1, E2) when is_list(E1), is_list(E2) -> match(E1, E2);
match_element(E1, E2) when is_map(E1), is_map(E2) -> match(maps:to_list(E1), maps:to_list(E2));
match_element(E1, E2) -> E1 == E2.