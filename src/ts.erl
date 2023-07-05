-module(ts).

-export([start/0]).

-export([in/2, in/3, new/1, out/2, rd/2, rd/3]).

-export([addNode/2, nodes/1, removeNode/2]).

% Avvia l'applicazione ts sul nodo 
start() -> 
    main_supervisor:start_link().

% Creates a new TS named with name
new(Name) -> 
    database_mgr:create_new_space(Name).

% Returns a tuple matching the pattern in the TS and deletes if from the TS
% Blocks if there is no tuple matching
in(Ts, Pattern) -> 
    in(Ts, Pattern, 'infinity').
	
% As in(TS, Pattern) but returns an errror after Timetout
in(Ts, Pattern, Timeout)-> 
    ReadResult = case gen_server:call(Ts, {read_tuple, Pattern}) of
        {error, no_tuples} -> ts_mgr:subscribe_for_pattern(Ts, Pattern, Timeout);
        Result -> Result
    end,
    case ReadResult of
        {ok, Tuple} -> 
            case gen_server:call(Ts, {delete_tuple, Tuple}) of
                {error, no_tuples} -> in(Ts, Pattern, Timeout);
                ok -> {ok, Tuple};
                Error -> Error
            end;
        Error -> Error
    end.

% % Returns a tuple matching the pattern in the TS
% The tuple remains in the TS
% Blocks if there is no tuple matching 
rd(Ts, Pattern) -> 
    rd(Ts, Pattern, 'infinity').

% As rd(TS,Pattern) but return an error after Timout
rd(Ts, Pattern, Timeout) -> 
    Res = gen_server:call(Ts, {read_tuple, Pattern}),
    case Res of
        {error, no_tuples} -> ts_mgr:subscribe_for_pattern(Ts, Pattern, Timeout);
        Result -> Result
    end.

% Puts the tuple Tuple in the TS
out(Ts, Tuple) -> 
    gen_server:call(Ts, {write_tuple, Tuple}).

% Adds the Node to the TS, so Node can access to all the tuples of TS
addNode(Ts, Node) -> 
    database_mgr:add_node_to_space(Node, Ts).

% Removes a node from the TS
removeNode(Ts, Node) -> 
    database_mgr:remove_node_from_space(Node, Ts).
 
% Tells the nodes on which the TS is visible/replicated
nodes(Ts) -> 
    database_mgr:list_nodes_in_space(Ts).

