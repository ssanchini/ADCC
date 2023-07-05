-module(ts_supervisor).

-behaviour(supervisor).

-export([
    add_space_manager/1,
    del_space_manager/1,
    start_link/0
]).

%% supervisor callbacks.
-export([init/1]).

% Avvia una nuova istanza di ts_supervisor.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

% Usato da add_node per avviare una nuova istanza di ts_mgr per lo spazio richiesto.
add_space_manager(TupleSpace) when is_atom(TupleSpace) ->
    case supervisor:start_child(?MODULE, [TupleSpace]) of
        {ok, _Child} -> ok;
        {error, Reason} -> {error, {cant_start_tsmanager, Reason}}
    end.

% Viene usato da remove_node per fermare un istanza di ts_mgr per lo spazio di tuple interessato
del_space_manager(TupleSpace) when is_atom(TupleSpace) ->
    supervisor:terminate_child(?MODULE, whereis(TupleSpace)).

% init/1 callback al supervisor.
init(_Args) ->
    Flags = #{
        strategy => simple_one_for_one,
        intensity => 0,
        period => 1
    },

    ChildSpecs = [
        #{
            id => ts_mgr,
            start => {ts_mgr, start_link, []},
            shutdown => 2000
        }
    ],

    {ok, {Flags, ChildSpecs}}.