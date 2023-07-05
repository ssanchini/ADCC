-module(main_supervisor).

-behaviour(supervisor).

-export([start_link/0]).

% supervisor callbaks.
-export([init/1]).

% Start a new instance of main_supervisor.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

% supervisor callbaks

% init/1 callback from supervisor.
init(_Args) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 1,
        period => 5},

    ChildSpecs = [
        #{
            id => ts_supervisor,
            start => {ts_supervisor, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [ts_supervisor]
        },
        #{
            id => database_mgr,
            start => {database_mgr, start_link, []},
            restart => permanent,
            shutdown => 2000,
            type => worker,
            modules => [database_mgr]
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.
