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

% Start an instance of ts_mgr for the tuple space
% with given name.
start_link(SpaceName) ->
    gen_server:start_link({local, SpaceName}, ?MODULE, SpaceName, []).

% This function must be called after a 'write_tuple' call to ts_mgr returns with {error, no_tuples},
% this function listen to all the tuples inserted in the space from now on and matches all of them
% with the given pattern; if a tuple matches or a timeout is reached this function stops listening to new
% tuples and returns the mathed.
% If timeout is set to 'infinity' or no tuple is matching this function wait indefinitly.
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

% qui eseguiamo le callbacks al gen_server 

% init/1 callback from gen_server.
init(SpaceName) ->
    process_flag(trap_exit, true),
    {ok, #tsstate{space = SpaceName}}.

% handle_call/3 callback from gen_server.
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

% handle_cast/2 callback from gen_server.
handle_cast(_Msg, _State) ->
    {noreply, _State}.

% handle_info/2 callback from gen_server.
handle_info(_Info, _State) ->
    {noreply, _State}.

% terminate/2 callback from gen_server.
terminate(_Reason, _State) ->
    ok.

% code_change/3 callback from gen_server.
code_change(_OldVsn, _State, _Extra) ->
    {ok, _State}.

%%%%%%%%%%%%%%%%%%%%
% Funzioni interne
%%%%%%%%%%%%%%%%%%%%

% Read a tuple matching given pattern.
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

% Insert the given tuple in the tuple space.
write_tuple(_, {}) -> ok;
write_tuple(Space, Tuple) -> 
    case mnesia:transaction(fun() ->
        mnesia:write({Space, tuple_size(Tuple), Tuple})
    end) of
        {atomic, _} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

% Remove the given tuple from the tuple space.
delete_tuple(_, {}) -> ok;
delete_tuple(Space, Tuple) -> 
    case mnesia:transaction(fun() ->
        % read the tuple in the db
        ReadResult = lists:filter(fun(T) -> match(Tuple, element(3,T)) end, mnesia:read({Space, tuple_size(Tuple)})),
        % if the tuple is present remove it otherwise abort the transaction and keep waiting,
        % someone else has deleted it before
        case ReadResult of
            [] -> mnesia:abort({no_tuples});
            [_] -> mnesia:delete_object({Space, tuple_size(Tuple), Tuple})
        end        
    end) of
        {atomic, _} -> ok;
        {aborted, {no_tuples}} -> {error, no_tuples};
        {aborted, Reason} -> {error, Reason}
    end.

% Given a pattern and a tuple verify that the tuple matches
% the pattern. the pattern and the tuple are both tuples, but for matching
% are converted info lists, then every element if checked recursively until
% one differs or every element equals.
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

% Given two elements, E1 an element from a pattern, E2 an element from
% a tuple, verify that the two elements match.
% If E1 is the atom 'any' the function returns true without checking
% E2, if E1 and E2 are both tuples/lists/maps their elements are checked
% recursively, otherwise it's checked the simple equality.
match_element(E1, _) when E1 == any -> true;
match_element(E1, E2) when is_tuple(E1), is_tuple(E2) -> match(E1, E2);
match_element(E1, E2) when is_list(E1), is_list(E2) -> match(E1, E2);
match_element(E1, E2) when is_map(E1), is_map(E2) -> match(maps:to_list(E1), maps:to_list(E2));
match_element(E1, E2) -> E1 == E2.